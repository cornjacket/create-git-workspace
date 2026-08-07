#!/usr/bin/env python3
"""Branch and pending-work state for every managed checkout. Read-only.

    status.py           the registered repos, plus this workspace itself
    status.py --all     also every unregistered git checkout on the floor

Two kinds of pending work, and reporting only the first is how work goes
missing:

  * **uncommitted** — staged, unstaged, or untracked changes. `git status` in
    that repo would show you these.
  * **unpushed** — commits the remote does not have. A repo you committed but
    never pushed looks perfectly *clean* to `git status`, which is exactly why
    it needs a sweep at this level.

Plus one piece of pending *setup*: a repo registered here but never added to the
scheduled routine's `sources` reads `routine not registered`. That is a debt the
tool knows about with certainty, and this gate is its whole enforcement — see
`_status_lib.routine_pending`. It is reported here but is NOT a git finding, so
`delete-repo` does not refuse over it: nothing is at risk of being lost.

Exits non-zero if anything is missing or pending, so it works as a pre-flight
check before you close the laptop.

WHY PYTHON, when bootstrap and guard are shell: the unpushed detector is shared
verbatim with `delete-repo.py` (`_status_lib.pending_findings`). Two copies of a
safety check drift, and the day they disagree you get "status says clean" and
"delete-repo refuses" in the same minute.

**This workspace is a row too.** Its own uncommitted plans and unpushed commits
are the easiest of all to forget, and the routine's fast-forward depends on you
having pushed them.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _status_lib import (  # noqa: E402
    LOCAL_ONLY, ROUTINE_CHECK_TTL_H, WORKSPACE_ROOT, load_repos,
    pending_findings, routine_basis, routine_check_age_hours,
    routine_check_fresh, routine_configured, routine_hint, routine_pending,
)

# Reported alongside the git findings, but produced here rather than by
# pending_findings(): that detector is shared verbatim with delete-repo, and an
# unregistered routine is not a reason to refuse a deletion.
ROUTINE = "routine"

WORKSPACE_LABEL = "(this workspace)"


def refresh_routine_check(force=False, quiet=False):
    """Re-verify the routine's real `sources` if the cached verdict has aged out.

    THE ONE NETWORK CALL IN AN OTHERWISE LOCAL COMMAND, and it is rationed. The
    honest gate is the one that asks the routine, but asking costs a `claude -p`
    round-trip and this command is meant to be instant, so the verdict is cached
    for `ROUTINE_CHECK_TTL_H` hours and only re-taken when it expires (or on
    `--all`, the deliberate deep sweep).

    A FAILED REFRESH IS REPORTED, NEVER SWALLOWED. Offline, no `claude` on PATH,
    a changed API shape — each leaves the gate standing on the old
    `routine_registered` flag, which is a weaker fact than it looks. Saying so
    is the §5.2 rule the rollup already follows for an unreadable repo: a thing
    you could not check is not a thing that passed.
    """
    if not routine_configured():
        return None
    # Two places must never make this call: CI and the remote sandbox. Neither
    # has an interactive Claude session to borrow a token from, so the attempt
    # can only ever time out slowly and then fall back. CLAUDE_CODE_REMOTE is
    # already the sandbox's tell (see sync.py); WORKSPACE_NO_VERIFY is the
    # explicit off switch the acceptance suite sets.
    if os.environ.get("WORKSPACE_NO_VERIFY") or os.environ.get("CLAUDE_CODE_REMOTE"):
        return None
    if not force and routine_check_fresh():
        return None

    script = Path(__file__).resolve().parent / "routine-sync.py"
    try:
        r = subprocess.run([sys.executable, str(script), "--check", "--json"],
                           capture_output=True, text=True, timeout=200)
    except (OSError, subprocess.TimeoutExpired) as e:
        r = None
        err = str(e)
    else:
        err = (r.stderr or "").strip()

    # 0 = verified in sync, 1 = verified and drifted. Both wrote a fresh verdict,
    # so both are a successful refresh. Only 2 (could not verify) is a failure.
    if r is not None and r.returncode in (0, 1):
        return True
    if not quiet:
        age = routine_check_age_hours()
        stale = f"last verified {age:.0f}h ago" if age is not None else "never verified"
        print(f"[status] could not verify the routine's `sources` ({stale}); "
              f"falling back to the recorded flag.", file=sys.stderr)
        for line in (err or "no detail").splitlines()[:4]:
            print(f"         {line}", file=sys.stderr)
        print("", file=sys.stderr)
    return False


def colours(stream):
    if not stream.isatty():
        return {k: "" for k in ("B", "D", "G", "Y", "R", "X")}
    return {"B": "\033[1m", "D": "\033[2m", "G": "\033[32m",
            "Y": "\033[33m", "R": "\033[31m", "X": "\033[0m"}


def is_checkout(d):
    # Worktree-safe: a linked worktree's .git is a FILE, not a directory.
    return (d / ".git").exists()


def current_branch(d):
    from _status_lib import git
    r = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd=d, check=False)
    return r.stdout.strip() or "?"


def summarize(findings):
    """(state string, is_pending). Counts per kind, worst-first."""
    if not findings:
        return "clean", False
    kinds = {}
    for kind, _ in findings:
        kinds[kind] = kinds.get(kind, 0) + 1

    # local-only on its own is a statement of fact, not a warning — and the tree
    # is still clean, so say so. Dropping the word "clean" here would make a
    # perfectly tidy repo with no remote look like it needed attention.
    real = {k: v for k, v in kinds.items() if k != LOCAL_ONLY}
    if not real:
        return "clean (local-only)", False

    parts = []
    for kind in ("dirty", "stashed", "ahead", "no-upstream", "detached", ROUTINE):
        if kind in real:
            label = {"ahead": "unpushed", "no-upstream": "no upstream",
                     ROUTINE: "routine not registered"}.get(kind, kind)
            parts.append(f"{label} ({real[kind]})" if real[kind] > 1 else label)
    return ", ".join(parts), True


def rows(include_all):
    """(name, type, branch, findings-or-None) per checkout. None = missing."""
    out = [(WORKSPACE_LABEL, "workspace", current_branch(WORKSPACE_ROOT),
            pending_findings(WORKSPACE_ROOT))]

    registered_paths = set()
    # ONE ANSWER, ASKED ONCE. This used to re-derive the condition inline
    # (`repo["enabled"] and not repo["routine_registered"]`) while the
    # daily-plan-summary banner asked `routine_pending()`. Two readers of one
    # fact drift: a workspace with no routine at all was silenced in the banner
    # and still red here. The enabled/flag scoping and the "no routine means no
    # phase two" rule both live in that function now.
    pending_names = {r["name"] for r in routine_pending()}

    for repo in load_repos():
        d = WORKSPACE_ROOT / repo["path"]
        registered_paths.add(repo["path"].strip("/"))
        findings = pending_findings(d) if is_checkout(d) else None
        if findings is not None and repo["name"] in pending_names:
            findings = findings + [(ROUTINE, f"routine not registered — "
                                             f"{routine_hint(repo['name'])}")]
        out.append((repo["name"], repo["type"], current_branch(d) if is_checkout(d) else "-",
                    findings))

    if include_all:
        # Only the workspace's own floor — depth 1. Anything nested deeper
        # belongs to a checkout that is already accounted for.
        for d in sorted(p for p in WORKSPACE_ROOT.iterdir() if p.is_dir()):
            if d.name.startswith(".") or d.name in registered_paths:
                continue
            if is_checkout(d):
                out.append((d.name, "unregistered", current_branch(d), pending_findings(d)))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true",
                    help="also report git checkouts that are not in repos.yml")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="list every pending finding, not just the counts")
    ap.add_argument("--no-verify", action="store_true",
                    help="never call the routine; answer from the cached verdict "
                         "or the recorded flag (keeps this command fully offline)")
    args = ap.parse_args()

    if not args.no_verify:
        # --all is the deliberate deep sweep, so it always re-verifies; a plain
        # run only does when the cached verdict has aged out.
        refresh_routine_check(force=args.all)

    c = colours(sys.stdout)
    table = rows(args.all)
    width = max([len(r[0]) for r in table] + [20])

    print(f"{c['B']}{'NAME':<{width}} {'TYPE':<13} {'BRANCH':<20} STATE{c['X']}")
    rc = 0
    for name, kind, branch, findings in table:
        if findings is None:
            print(f"{name:<{width}} {kind:<13} {'-':<20} {c['R']}missing{c['X']}")
            rc = 1
            continue
        state, pending = summarize(findings)
        colour = c["Y"] if pending else (c["D"] if state == "local-only" else c["G"])
        print(f"{name:<{width}} {kind:<13} {branch:<20} {colour}{state}{c['X']}")
        if pending:
            rc = 1
        if args.verbose:
            for _k, message in findings:
                print(f"{'':<{width}} {c['D']}· {message}{c['X']}")

    # SAY WHICH FACT THE ROUTINE COLUMN IS STANDING ON. "registered" derived from
    # a checked `sources` list and "registered" derived from a flag somebody set
    # by hand look identical in the table, and they are not the same claim.
    basis = routine_basis()
    if basis == "verified":
        age = routine_check_age_hours()
        when = "just now" if age is not None and age < 0.05 else f"{age:.0f}h ago"
        print(f"\n{c['D']}Routine `sources` verified {when} "
              f"(re-checked every {ROUTINE_CHECK_TTL_H}h; `make routine-check` "
              f"forces it).{c['X']}")
    elif basis == "flag":
        print(f"\n{c['Y']}Routine `sources` NOT verified{c['X']}{c['D']} — the column above "
              f"is the recorded flag, which asserts the edit was made rather than "
              f"checking it. Run `make routine-check`.{c['X']}")

    if rc and not args.verbose:
        print(f"\n{c['D']}Pending work above. Re-run with -v for the detail.{c['X']}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
