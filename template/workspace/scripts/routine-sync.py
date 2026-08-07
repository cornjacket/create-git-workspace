#!/usr/bin/env python3
"""Reconcile the scheduled routine's `sources` pre-clone list against repos.yml.

    routine-sync.py --check                verify the LIVE routine; exit 1 on drift
    routine-sync.py --check --from-file F  verify against a saved job config
    routine-sync.py --check --json         machine-readable verdict
    routine-sync.py --show-expected        what `sources` should contain, and stop

Phase two of registration is "the repo is in the routine's `sources`". Until now
that fact was *asserted* by a hand-set `routine_registered` flag in repos.yml,
and the assertion has already been wrong in production: the flag read `true` for
`create-ai-builder` while `sources` did not contain it, so the repo was silently
omitted from three days of rollups. A stored claim is not a checked state.

This script checks the state. `--check` reads the routine's real config and
diffs it, so the gate stops trusting what somebody once typed.

WHY THIS IS BUILDABLE NOW. `DESIGN.md` §8.5 files routine editing as a manual
seam "only a human can take in the Claude app". That premise was false, and this
effort believed it for two weeks: the belief came from checking `CronList`, which
only lists crons created in the *current session* and therefore cannot see a
cloud routine. One tool answered "no" to a different question and the answer was
generalized. The `RemoteTrigger` tool reads and writes routine config fine.

THE TRANSPORT, AND WHY IT IS A SUBPROCESS. `RemoteTrigger` is an in-session tool
whose OAuth token is deliberately never exposed to the environment, so a plain
script cannot call the API — there is no CLI and no token to borrow. It is
reached by shelling out to `claude -p` with the tool allowed, exactly as `run.py`
already shells out for summaries. Two paths were considered and rejected:

  * **curl with a scraped token.** The token lives in the macOS keychain, which
    makes the script macOS-only while the remote routine's sandbox is Linux, and
    it breaks silently whenever the token rotates. The tool's own contract says
    to use it *instead of* curl.
  * **Letting the model do the diff.** The model is a transport here and nothing
    more. Every comparison below is ordinary Python over parsed JSON, because a
    reconcile that a model performs is a reconcile nobody can test.

WHAT THIS DOES NOT DO YET: write. Sending a reconciled config back is the other
half of task `20`, and it is the dangerous half — `RemoteTrigger update` is
documented as a *partial* update, so anything omitted is dropped, and the
job_config carries the run prompt, the model, and the allowed-tools list. Read
first, and land the writer behind a round-trip verification.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _status_lib import (  # noqa: E402
    ROUTINE_CHECK_JSON, STATE_DIR, StatusError, expected_sources, git,
    load_config, normalize_remote, routine_configured, workspace_origin_url,
)

# `claude -p` spawns a whole model turn to make two HTTP calls, so it is slow in
# the way a network call is slow, not in the way a model is slow. Long enough to
# absorb a cold start; short enough that a wedged call does not hang `make
# status` forever.
FETCH_TIMEOUT_S = 180

TRIGGER_ID_RE = re.compile(r"(trig_[A-Za-z0-9_-]+)")

FETCH_PROMPT = (
    "Call the RemoteTrigger tool with action=get and trigger_id={tid}. "
    "Output ONLY the raw JSON response body, with no prose, no explanation, "
    "and no markdown code fence."
)


class VerifyError(RuntimeError):
    """The routine's real state could not be established.

    Distinct from "drift found" ON PURPOSE, and the distinction is the whole
    safety property of this script. A check that reports "clean" when it could
    not reach the thing it checks is worse than no check — it converts an
    unknown into a false all-clear, which is exactly how the flag this replaces
    went wrong. Every failure path below raises this, and it exits 2.
    """


# ---------------------------------------------------------------------------
# Transport — the only impure part
# ---------------------------------------------------------------------------
def trigger_id(url=None):
    """The `trig_...` id out of config.yml's `routine_url`.

    Stored as a browsable URL rather than a bare id because that is what the
    operator is given when the routine is created, and asking them to dissect it
    is how a config field acquires a wrong value.
    """
    if url is None:
        url = (load_config().get("routine_url") or "").strip()
    if not url:
        return None
    m = TRIGGER_ID_RE.search(url)
    if not m:
        raise VerifyError(
            f"routine_url in .workspace/config.yml does not contain a trigger id: {url!r}\n"
            "  Expected something like https://claude.ai/code/routines/trig_XXXXXXXX"
        )
    return m.group(1)


def extract_json(text):
    """The first complete JSON object in `text`.

    The transport is a model, so the response may arrive fenced, prefaced, or
    both no matter how firmly the prompt says otherwise. Scanning for a balanced
    object is more durable than trusting the instruction — but it deliberately
    does NOT fall back to "no JSON means empty": that returns a VerifyError, so
    an unparseable answer can never be read as an empty `sources` list.
    """
    start = text.find("{")
    if start < 0:
        raise VerifyError(f"no JSON object in the fetch response:\n{text[:500]}")
    depth, in_str, esc = 0, False, False
    for i, ch in enumerate(text[start:], start):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                blob = text[start:i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError as e:
                    raise VerifyError(f"fetch response was not valid JSON: {e}")
    raise VerifyError(f"unterminated JSON object in the fetch response:\n{text[:500]}")


def fetch_trigger(tid):
    """The routine's full API record, via `claude -p`."""
    if not _have("claude"):
        raise VerifyError(
            "`claude` is not on PATH, so the routine's real state cannot be read.\n"
            "  This check needs a Claude Code session to reach the RemoteTrigger API."
        )
    try:
        r = subprocess.run(
            ["claude", "-p", FETCH_PROMPT.format(tid=tid), "--allowedTools", "RemoteTrigger"],
            capture_output=True, text=True, timeout=FETCH_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        raise VerifyError(f"timed out after {FETCH_TIMEOUT_S}s reading the routine")
    if r.returncode != 0:
        raise VerifyError(
            f"`claude -p` exited {r.returncode} while reading the routine:\n"
            f"{(r.stderr or r.stdout or '').strip()[:500]}"
        )
    return extract_json(r.stdout)


def _have(cmd):
    from shutil import which
    return which(cmd) is not None


# ---------------------------------------------------------------------------
# Pure core — everything below is ordinary data, and is what the tests drive
# ---------------------------------------------------------------------------
def actual_sources(trigger):
    """Normalized repo URLs in the routine's pre-clone list.

    Walked field by field rather than with a chain of `.get(...)` defaults: a
    missing `sources` key and an empty `sources` list mean opposite things here.
    Empty is a routine that pre-clones nothing; missing is a payload we do not
    understand, and guessing "empty" would report every repo as drifted — a
    check that cries wolf gets ignored, which costs as much as one that never
    fires.
    """
    node = trigger.get("trigger", trigger)
    for key in ("job_config", "ccr", "session_context"):
        if not isinstance(node, dict) or key not in node:
            raise VerifyError(
                f"the routine payload has no `{key}` — cannot tell what it pre-clones. "
                "The API shape may have changed; refusing to guess."
            )
        node = node[key]
    if "sources" not in node:
        raise VerifyError(
            "the routine's session_context has no `sources` key — refusing to "
            "treat an unknown payload as an empty pre-clone list."
        )
    out = []
    for entry in node["sources"] or []:
        url = ((entry or {}).get("git_repository") or {}).get("url")
        if url:
            out.append(normalize_remote(url))
    return out


def diff_sources(expected, actual, workspace_url=None):
    """What is registered but not pre-cloned, and vice versa.

    `expected` and `actual` are already normalized. Order is not compared: the
    platform does not care, and a diff that reports reordering as drift would
    make a no-op run look like work.
    """
    exp, act = set(expected), set(actual)
    missing = sorted(exp - act)
    extra = sorted(act - exp)
    # The workspace's own repo is a legitimate source and is NOT in repos.yml —
    # it is the checkout the run writes its rollup into. Counting it as `extra`
    # would make a correctly-configured routine report drift forever.
    if workspace_url:
        extra = [u for u in extra if u != workspace_url]
    return missing, extra


def verdict(trigger, repos=None):
    """The whole comparison, as data. No I/O beyond reading repos.yml."""
    ws_url = workspace_origin_url()
    expected = expected_sources(repos)
    actual = actual_sources(trigger)
    missing, extra = diff_sources(expected, actual, ws_url)
    return {
        "checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "trigger_id": (trigger.get("trigger", trigger) or {}).get("id"),
        "workspace_url": ws_url,
        "expected": sorted(set(expected)),
        "actual": sorted(set(actual)),
        "missing": missing,
        "extra": extra,
        "in_sync": not missing and not extra,
    }


# ---------------------------------------------------------------------------
# Cache
#
# `make status` is local and instant, and this check is a network round-trip, so
# the verdict is cached with a staleness window rather than recomputed per
# invocation. This IS a cache of a fact — the thing task `20` argues against —
# with one difference that makes it defensible: it has a timestamp and a real
# source, so it expires and re-derives. The `routine_registered` flag it
# replaces had neither; it recorded that a human said they had done something,
# and nothing ever asked again.
# ---------------------------------------------------------------------------
def write_cache(v):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = ROUTINE_CHECK_JSON.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(v, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, ROUTINE_CHECK_JSON)
    return ROUTINE_CHECK_JSON


# ---------------------------------------------------------------------------
def report(v, stream=sys.stdout):
    tag = "[routine-sync]"
    if v["in_sync"]:
        n = len(v["expected"])
        print(f"{tag} in sync — the routine pre-clones all {n} enabled "
              f"{'repo' if n == 1 else 'repos'}", file=stream)
        return
    print(f"{tag} the routine's `sources` does not match repos.yml:", file=stream)
    for url in v["missing"]:
        print(f"  MISSING  {url}", file=stream)
        print("           registered here, not pre-cloned — the run reports it "
              "UNAVAILABLE and leaves it out of the rollup", file=stream)
    for url in v["extra"]:
        print(f"  EXTRA    {url}", file=stream)
        print("           pre-cloned by the routine, not in repos.yml — "
              "harmless, but it is cloned on every run", file=stream)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="verify the routine's real `sources`; exit 1 if it drifted")
    ap.add_argument("--from-file", metavar="F",
                    help="read the job config from F instead of the API "
                         "(what the tests drive; also useful offline)")
    ap.add_argument("--json", action="store_true",
                    help="emit the verdict as JSON instead of prose")
    ap.add_argument("--show-expected", action="store_true",
                    help="print what `sources` should contain, and make no network call")
    ap.add_argument("--no-cache", action="store_true",
                    help="do not write .workspace/state/routine-check.json")
    args = ap.parse_args()

    if args.show_expected:
        for url in sorted(set(expected_sources())):
            print(url)
        ws = workspace_origin_url()
        if ws:
            print(ws)
        return 0

    if not args.check:
        ap.error("nothing to do — pass --check (the writer half is not built yet)")

    # A workspace with no routine has no `sources` to drift from. Clean no-op,
    # never an error: a routine-free workspace is a supported configuration
    # (task 21), and failing here would make `setup.sh` depend on a routine
    # existing before the first status run.
    if not args.from_file and not routine_configured():
        print("[routine-sync] this workspace has no routine — nothing to reconcile")
        return 0

    if args.from_file:
        trigger = json.loads(Path(args.from_file).read_text())
    else:
        trigger = fetch_trigger(trigger_id())

    v = verdict(trigger)
    if not args.no_cache and not args.from_file:
        write_cache(v)

    if args.json:
        print(json.dumps(v, indent=2, sort_keys=True))
    else:
        report(v, sys.stdout if v["in_sync"] else sys.stderr)
    return 0 if v["in_sync"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except VerifyError as e:
        # EXIT 2, NOT 1. `1` means "verified, and it drifted"; `2` means "could
        # not verify". A caller that collapses them turns an outage into a false
        # all-clear or a false alarm, and both teach the operator to ignore it.
        print(f"routine-sync: could not verify the routine's state:\n{e}", file=sys.stderr)
        sys.exit(2)
    except StatusError as e:
        print(f"routine-sync: {e}", file=sys.stderr)
        sys.exit(2)
