"""Shared helpers for the workspace status subsystem.

Ported from project-status's tools/_lib.py, with three structural changes that
come from the work living *inside* a workspace instead of in a standalone
tracker repo:

  * **No `tracked/` cache locally.** The child repos are already checked out
    beside the workspace at the paths `repos.yml` declares, so the local run
    reads them in place. The remote routine still has no checkouts of its own,
    so it falls back to the platform's pre-cloned sources.
  * **Plans moved up into the workspace.** A plan is *per-developer* intent, so
    it lives at `.workspace/daily-plans/<repo>/daily-plan.md` — in this developer's own
    workspace — not in the shared child repo where two developers would collide.
  * **Author-scoped telemetry.** Every git-log read filters `--author`, so each
    developer's rollup shows only their own commits. Required, not optional: the
    remote sandbox has no ambient git identity to fall back on.
"""
import json
import os
import subprocess
import sys
from datetime import date as _date
from pathlib import Path

import yaml

# .workspace/scripts/_status_lib.py -> .workspace -> the workspace root.
WORKSPACE_DIR = Path(__file__).resolve().parent.parent
WORKSPACE_ROOT = WORKSPACE_DIR.parent

REPOS_YML = WORKSPACE_DIR / "repos.yml"
CONFIG_YML = WORKSPACE_DIR / "config.yml"
STATE_DIR = WORKSPACE_DIR / "state"
STATE_JSON = STATE_DIR / "state.json"
ARCHIVE_DIR = STATE_DIR / "archive"
DAILY_PLANS_DIR = WORKSPACE_DIR / "daily-plans"
PROMPTS_DIR = WORKSPACE_DIR / "prompts"

# Top-level deliverables — the daily dashboard.
SUMMARY_MD = WORKSPACE_ROOT / "summary.md"
DAILY_PLAN_SUMMARY_MD = WORKSPACE_ROOT / "daily-plan-summary.md"

# The workspace's own plan slot. Aggregated FIRST: inter-repo work outranks any
# single repo's, and it is the tier that otherwise has nowhere to be seen.
WORKSPACE_PLAN_KEY = "_workspace"

# In a Claude remote routine the platform pre-clones every declared `source` at
# /home/user/<name> through an authenticated proxy. Direct clones from inside
# that sandbox hit a TLS-inspecting proxy and 401 even for public repos, so the
# pre-cloned trees MUST be reused.
PREBUILT_SOURCE_ROOT = Path("/home/user")

# Well-known SHA-1 of git's empty tree — the baseline range on a first run.
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

DEFAULT_PRIORITY = 3

# The placeholder setup.sh writes when it cannot resolve an author. Reaching a
# status run with this still in place means the summary would be scoped to
# nobody, so the run refuses rather than emitting a silently-empty rollup.
AUTHOR_PLACEHOLDER = "CHANGEME@example.invalid"


class StatusError(RuntimeError):
    """A misconfiguration the operator must fix — reported, never worked around."""


# ---------------------------------------------------------------------------
# Config and membership
# ---------------------------------------------------------------------------
def load_config():
    if not CONFIG_YML.exists():
        raise StatusError(f"missing {CONFIG_YML} — is this a git-workspace?")
    with open(CONFIG_YML) as f:
        return yaml.safe_load(f) or {}


def workspace_name():
    return (load_config().get("name") or WORKSPACE_ROOT.name).strip()


def git_authors():
    """The emails the summary is scoped to. Hard-fails on an unresolved author.

    A wrong or empty author does not fail loudly on its own — it silently
    produces an empty rollup that looks like "you did nothing today". That is
    the failure mode worth refusing outright.
    """
    raw = load_config().get("git_author")
    authors = [raw] if isinstance(raw, str) else list(raw or [])
    authors = [str(a).strip() for a in authors if str(a).strip()]
    if not authors:
        raise StatusError(
            f"no git_author in {CONFIG_YML}. The summary is author-scoped, so "
            "the workspace must name whose commits to report."
        )
    if any(a == AUTHOR_PLACEHOLDER for a in authors):
        raise StatusError(
            f"git_author in {CONFIG_YML} is still the placeholder "
            f"'{AUTHOR_PLACEHOLDER}'. Replace it with your git email — otherwise "
            "the rollup would be scoped to nobody and silently come back empty."
        )
    return authors


def load_repos():
    """Normalized repo dicts from .workspace/repos.yml, in file order.

    The membership schema (name/url/path/type/branch/parent_repo_path) is the
    workspace's; the status flags (enabled/priority/report_inactivity) are
    project-status's, folded in here.
    """
    if not REPOS_YML.exists():
        return []
    with open(REPOS_YML) as f:
        data = yaml.safe_load(f) or {}
    out = []
    for r in data.get("repos") or []:
        name = r.get("name")
        if not name:
            continue
        out.append({
            "name": name,
            "url": r.get("url", ""),
            "path": r.get("path", name),
            "type": r.get("type", "standard"),
            "branch": r.get("branch", "main"),
            "parent_repo_path": r.get("parent_repo_path", ""),
            # One line of "what is this repo", seeded at registration and then
            # yours. Stored rather than re-scraped so a render is stable and a
            # bad guess can be corrected by hand.
            "description": (r.get("description") or "").strip(),
            "enabled": r.get("enabled", True),
            "report_inactivity": r.get("report_inactivity", True),
            # Phase two of registration — see routine_registered() below. ABSENT
            # MEANS INCOMPLETE: the default is False, not True, so a repo
            # registered before this field existed reads as outstanding (which
            # it is) instead of silently claiming to be done.
            "routine_registered": bool(r.get("routine_registered", False)),
            # Band, not a rank: ties are expected and fall back to repos.yml
            # order. Lower = more important; unset sorts last rather than
            # silently claiming the top band.
            "priority": int(r.get("priority", DEFAULT_PRIORITY)),
        })
    return out


def enabled_repos():
    return [r for r in load_repos() if r["enabled"]]


# ---------------------------------------------------------------------------
# Routine registration — the second, un-automatable half of `add-repo`
#
# Registering a repo is TWO phases and only the first can be automated:
#
#   1. `add-repo` writes repos.yml, clones, injects the kernel  — automatic
#   2. the repo is added to the scheduled routine's `sources`   — by hand, in
#      the Claude app, because neither setup.sh (no session) nor add-repo (no
#      API handle) can edit a routine
#
# Phase two is what makes the repo readable to the remote run: the sandbox has
# no checkouts and its egress proxy blocks anything not pre-declared. Skip it
# and the run does not fail — it reports the repo as unreadable and quietly
# omits it from the rollup (guide §5.2). A printed reminder does not survive a
# scrollback, so the outstanding state lives in repos.yml, where bootstrap
# replays it onto the next machine.
#
# ONE SOURCE OF TRUTH, RENDERED TWICE: the flag is authoritative; the `status`
# row and the `daily-plan-summary.md` banner are projections recomputed on every
# run. `routine-registered.py` is the only writer of a `true`.
# ---------------------------------------------------------------------------
ROUTINE_FLAG = "routine_registered"


def routine_pending(repos=None):
    """Enabled repos whose phase-two registration is still outstanding.

    Scoped to *enabled* repos: a repo with `enabled: false` is out of the run
    entirely, so it cannot be silently omitted from a rollup it never joins.
    Re-enabling it brings the flag back into view, because this is recomputed
    rather than stored.
    """
    repos = enabled_repos() if repos is None else repos
    return [r for r in repos if not r.get(ROUTINE_FLAG)]


def routine_hint(name):
    """The one wording of "here is how to clear it", shared by every reporter."""
    return (f"add '{name}' to the scheduled routine's `sources` "
            f"(.workspace/status-guide.md §5.2), then run: "
            f"make routine-registered ARGS=\"{name}\"")


# ---------------------------------------------------------------------------
# Descriptions
#
# A repo's one-liner is seeded once, at registration, by reading the child's own
# prose — and then STORED in repos.yml. Re-scraping on every render would make
# the README change under you whenever a child edits its README, and would fail
# outright for a repo that is registered but not checked out on this machine.
# ---------------------------------------------------------------------------
DESCRIPTION_MAX = 160
# Below this a single sentence has usually said nothing ("`foo` is a generator.")
# — pull in the next one rather than storing a line that carries no signal.
DESCRIPTION_MIN = 60


def summarize_text(text, limit=DESCRIPTION_MAX, floor=DESCRIPTION_MIN):
    """Leading sentence(s) of `text`, capped at `limit`, cut on a word boundary."""
    import re

    text = " ".join((text or "").split())
    if not text:
        return ""
    out = ""
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        candidate = f"{out} {sentence}".strip()
        if len(candidate) > limit:
            if len(out) >= floor:
                return out
            cut = candidate[:limit].rsplit(" ", 1)[0]
            return cut.rstrip(" ,;:—-") + "…"
        out = candidate
        if len(out) >= floor:
            break
    return out


def _is_decoration(line):
    """True for a badge row: images and links with no prose of their own.

    Badges are the common false positive — `[![build](img)](link)` starts with
    '[', not '!', so a simple prefix test walks straight past the filter and
    stores markup as the repo's description. Strip the image/link syntax and ask
    whether any words survive.
    """
    import re

    stripped = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", line)          # ![alt](src)
    stripped = re.sub(r"\[\s*\]\([^)]*\)", "", stripped)          # []() leftovers
    return not re.search(r"[A-Za-z]{2}", stripped)


def _prose_paragraph(md):
    """First real prose paragraph of a Markdown doc: no heading, badge, comment,
    code fence, list, quote, or table row. Those are decoration; we want a
    sentence a human wrote about the project."""
    para = []
    in_fence = in_comment = False
    for raw in md.splitlines():
        line = raw.strip()
        if in_comment:
            if "-->" in line:
                in_comment = False
            continue
        if line.startswith("<!--"):
            in_comment = "-->" not in line
            continue
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if not line:
            if para:
                break
            continue
        if line.startswith(("#", ">", "-", "*", "|", "!", "=")) or _is_decoration(line):
            if para:
                break
            continue
        para.append(line)
    return " ".join(para)


def refresh_readme():
    """Re-render README.md's roster block after a membership change.

    Every verb that writes repos.yml calls this, so the README cannot drift from
    the registry — a roster you have to remember to refresh is one that is
    wrong. Failures are reported but never fatal: the membership edit already
    succeeded and must not be rolled back over a dashboard.
    """
    script = Path(__file__).resolve().parent / "render-readme.py"
    if not script.exists():
        return
    r = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.stderr.write("       (the membership change itself was written)\n")


def describe_remote(url):
    """GitHub's own one-line description for `url`, or "".

    Preferred over scraping prose, because it is the one field a human already
    wrote *as* a one-liner — the exact shape the roster wants — instead of a
    heuristic guess at which paragraph of a README is the summary.

    Returns "" for anything that is not a reachable GitHub repo: no `gh`, not
    authenticated, not GitHub, or simply no description set. All fall through to
    the README scrape; none is an error worth interrupting a clone over.
    """
    import shutil

    if not url or not shutil.which("gh"):
        return ""
    try:
        r = subprocess.run(
            ["gh", "repo", "view", url, "--json", "description", "-q", ".description"],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if r.returncode != 0:
        return ""
    return summarize_text(r.stdout.strip())


def describe_checkout(path):
    """A one-line description scraped from a checked-out repo, or "".

    README.md first, then CLAUDE.md — README is written for a newcomer, which is
    exactly the audience of the roster line.
    """
    path = Path(path)
    for candidate in ("README.md", "readme.md", "CLAUDE.md"):
        f = path / candidate
        if not f.is_file():
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        summary = summarize_text(_prose_paragraph(text))
        if summary:
            return summary
    return ""


def prebuilt_source_path(name):
    """The platform's pre-cloned checkout for `name`, or None (remote only)."""
    if not os.environ.get("CLAUDE_CODE_REMOTE"):
        return None
    p = PREBUILT_SOURCE_ROOT / name
    return p if (p / ".git").exists() else None


def repo_dir(repo):
    """Where this repo's git history actually is, or None if unavailable.

    Locally that is the checkout sitting beside the workspace — no `tracked/`
    cache, because the working copies are right there. Remotely it is the
    pre-cloned source.
    """
    prebuilt = prebuilt_source_path(repo["name"])
    if prebuilt:
        return prebuilt
    d = WORKSPACE_ROOT / repo["path"]
    # Worktree-safe: a linked worktree's .git is a FILE, not a directory.
    return d if (d / ".git").exists() else None


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
def load_state():
    if not STATE_JSON.exists():
        return {}
    with open(STATE_JSON) as f:
        return json.load(f)


def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(STATE_JSON, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")


# ---------------------------------------------------------------------------
# Git
# ---------------------------------------------------------------------------
def git(args, cwd=None, check=True):
    return subprocess.run(
        ["git"] + args,
        cwd=str(cwd) if cwd else None,
        check=check,
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Pending work — the shared detector
#
# ONE implementation, two callers with different severities:
#
#   status.py     reports it. "Did I forget to push?" — the question a working
#                 tree cannot answer, because a repo you committed but never
#                 pushed looks perfectly clean to `git status`.
#   delete-repo   refuses on it. Removing a checkout destroys anything that
#                 exists only there.
#
# They must never disagree. A second copy of this logic — in bash, say — is how
# you get "status says clean" and "delete-repo refuses" in the same minute.
# ---------------------------------------------------------------------------

# A repo with NO remotes at all is a different animal from a repo whose branch
# forgot its upstream: the first is local by design, the second is work you meant
# to push. status.py ignores LOCAL_ONLY; delete-repo blocks on it, because
# "exists nowhere else" is exactly what makes a deletion unrecoverable.
LOCAL_ONLY = "local-only"


def pending_findings(d):
    """Everything about checkout `d` that is not safely on a remote.

    Returns a list of (kind, message). Kinds: dirty, stashed, ahead,
    no-upstream, detached, local-only. Messages are human-facing and are the
    strings delete-repo prints, so they read as refusal reasons.
    """
    findings = []

    porcelain = git(["status", "--porcelain"], cwd=d, check=False).stdout.strip()
    if porcelain:
        n = len(porcelain.splitlines())
        findings.append(("dirty", f"dirty — {n} uncommitted or untracked file(s)"))

    stashes = git(["stash", "list"], cwd=d, check=False).stdout.strip()
    if stashes:
        n = len(stashes.splitlines())
        findings.append(("stashed",
                         f"stashed — {n} stash entr{'y' if n == 1 else 'ies'} "
                         f"exist{'s' if n == 1 else ''} only in this checkout"))

    has_remote = bool(git(["remote"], cwd=d, check=False).stdout.strip())

    branches = [b.strip() for b in git(
        ["for-each-ref", "--format=%(refname:short)", "refs/heads/"], cwd=d, check=False
    ).stdout.splitlines() if b.strip()]

    for b in branches:
        up = git(["rev-parse", "--abbrev-ref", f"{b}@{{upstream}}"], cwd=d, check=False)
        if up.returncode != 0 or not up.stdout.strip():
            kind = "no-upstream" if has_remote else LOCAL_ONLY
            findings.append((kind, f"unpushed — branch '{b}' has no upstream"))
            continue
        ahead = git(["rev-list", "--count", f"{up.stdout.strip()}..{b}"],
                    cwd=d, check=False).stdout.strip()
        if ahead and ahead != "0":
            findings.append(("ahead",
                             f"unpushed — branch '{b}' is {ahead} commit(s) ahead of "
                             f"{up.stdout.strip()}"))

    # Detached HEAD: commits reachable only from here are just as lost.
    if git(["symbolic-ref", "-q", "HEAD"], cwd=d, check=False).returncode != 0:
        if not git(["branch", "-r", "--contains", "HEAD"], cwd=d, check=False).stdout.strip():
            findings.append(("detached", "unpushed — detached HEAD is on no remote branch"))

    return findings


def author_args(authors):
    """`--author` flags. git ORs repeated --author, which is what we want for a
    developer who commits under more than one email."""
    return [f"--author={a}" for a in authors]


def head_commit(d):
    return git(["rev-parse", "HEAD"], cwd=d, check=False).stdout.strip()


# ASCII control chars as git-log delimiters. Commit bodies are multi-line, so
# "%s%n%b" is unparseable across records; these never occur in real text.
_RECORD_SEP = "\x1e"
_UNIT_SEP = "\x1f"


def _parse_message(raw):
    """Split a raw commit message into (title, context, impact, body).

    Parsing the raw message ourselves rather than leaning on git's %s/%b is
    deliberate: git treats the whole first paragraph as the subject, so a commit
    written WITHOUT a blank line after the title would swallow [Context]/[Impact]
    into %s and leave %b empty.
    """
    lines = raw.splitlines()
    title = ""
    rest_start = 0
    for i, ln in enumerate(lines):
        if ln.strip():
            title = ln.strip()
            rest_start = i + 1
            break
    context_lines, impact_lines = [], []
    current = None
    for raw_line in lines[rest_start:]:
        line = raw_line.strip()
        low = line.lower()
        if low.startswith("- [context]:"):
            current = context_lines
            current.append(line.split(":", 1)[1].strip())
        elif low.startswith("- [impact]:"):
            current = impact_lines
            current.append(line.split(":", 1)[1].strip())
        elif not line:
            current = None
        elif current is not None:
            current.append(line)
    return (
        title,
        " ".join(p for p in context_lines if p).strip(),
        " ".join(p for p in impact_lines if p).strip(),
        raw.strip("\n"),
    )


def git_telemetry(d, rev_range, authors):
    """Author-scoped commit telemetry for `rev_range`, newest first.

    Reads the structured commit schema each tracked repo is held to:
        <domain>(<scope>): <high-level functional summary>
        - [Context]: why this was done / what was learned
        - [Impact]: how it alters the project or system behavior
    """
    fmt = f"{_RECORD_SEP}%h{_UNIT_SEP}%B"
    out = git(["log", f"--pretty=format:{fmt}", *author_args(authors), rev_range],
              cwd=d, check=False).stdout
    commits = []
    for record in out.split(_RECORD_SEP):
        if not record.strip():
            continue
        parts = record.split(_UNIT_SEP, 1)
        title, context, impact, body = _parse_message(parts[1] if len(parts) > 1 else "")
        commits.append({
            "hash": parts[0].strip(),
            "title": title,
            "context": context,
            "impact": impact,
            "body": body,
        })
    return commits


def author_file_stat(d, rev_range, authors):
    """Per-file +/- totals across the author's commits in `rev_range`.

    `git diff --stat <range>` cannot be author-filtered — it would report every
    developer's changes — so the numbers are summed from `git log --numstat`
    over the author's commits only.
    """
    out = git(["log", "--numstat", "--pretty=format:", *author_args(authors), rev_range],
              cwd=d, check=False).stdout
    files = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        added, removed, path = parts
        if added == "-" or removed == "-":       # binary file
            continue
        a, r = files.get(path, (0, 0))
        files[path] = (a + int(added), r + int(removed))
    if not files:
        return ""
    rows = sorted(files.items(), key=lambda kv: -(kv[1][0] + kv[1][1]))
    width = max(len(p) for p, _ in rows)
    lines = [f" {p.ljust(width)} | {a + r:>4} +{a} -{r}" for p, (a, r) in rows]
    total_a = sum(a for _, (a, _) in rows)
    total_r = sum(r for _, (_, r) in rows)
    n = len(rows)
    lines.append(f" {n} file{'' if n == 1 else 's'} changed, "
                 f"{total_a} insertion{'' if total_a == 1 else 's'}(+), "
                 f"{total_r} deletion{'' if total_r == 1 else 's'}(-)")
    return "\n".join(lines)


def days_between(iso_a, iso_b):
    return (_date.fromisoformat(iso_b) - _date.fromisoformat(iso_a)).days


def format_telemetry(commits):
    """Render git_telemetry() output for a human or an LLM prompt."""
    if not commits:
        return "(none)"
    blocks = []
    for c in commits:
        lines = [f"- {c['hash']} {c['title']}"]
        if c["context"]:
            lines.append(f"    [Context]: {c['context']}")
        if c["impact"]:
            lines.append(f"    [Impact]: {c['impact']}")
        blocks.append("\n".join(lines))
    return "\n".join(blocks)


# ---------------------------------------------------------------------------
# The report
# ---------------------------------------------------------------------------
def gather_report(today=None, since=None, authors=None):
    """One dict per enabled repo, in repos.yml order.

    status ∈ {ACTIVE, INACTIVE, INACTIVE_SUPPRESSED, UNAVAILABLE}

    ACTIVE means "this developer committed here in the window" — not "the repo
    moved". A repo advanced entirely by a teammate has nothing to say in *your*
    author-scoped rollup, so it reads as INACTIVE for you while state.json still
    tracks the real HEAD, keeping the window correct for the next run.

    The window is the durable `last_commit..HEAD` from state.json, which
    preserves catch-up after a missed day. `since` (e.g. "24 hours ago") is an
    ad-hoc override that ignores state entirely.
    """
    today = today or _date.today().isoformat()
    authors = authors or git_authors()
    state = load_state()
    out = []
    for r in enabled_repos():
        name = r["name"]
        s = state.get(name, {})
        last = s.get("last_commit") or EMPTY_TREE
        last_act = s.get("last_activity_date")
        entry = {
            "name": name,
            "path": r["path"],
            "url": r["url"],
            "priority": r["priority"],
            "status": None,
            "last_commit": last,
            "head": None,
            "last_activity_date": last_act,
            "days_inactive": days_between(last_act, today) if last_act else None,
            "commit_telemetry": None,
            "file_stat": None,
            "commit_list": None,
            "report_inactivity": r["report_inactivity"],
        }
        d = repo_dir(r)
        if d is None:
            entry["status"] = "UNAVAILABLE"
            out.append(entry)
            continue
        entry["head"] = head_commit(d)
        if since:
            base = git(["rev-list", "-1", f"--before={since}", "HEAD"],
                       cwd=d, check=False).stdout.strip() or EMPTY_TREE
            rev_range = f"{base}..HEAD"
        else:
            rev_range = f"{last}..HEAD"
        telemetry = git_telemetry(d, rev_range, authors)
        if not telemetry:
            entry["status"] = "INACTIVE" if r["report_inactivity"] else "INACTIVE_SUPPRESSED"
        else:
            entry["status"] = "ACTIVE"
            entry["commit_telemetry"] = telemetry
            entry["file_stat"] = author_file_stat(d, rev_range, authors)
            entry["commit_list"] = git(
                ["log", "--oneline", *author_args(authors), rev_range], cwd=d, check=False
            ).stdout
        out.append(entry)
    return out


def advance_state(today=None):
    """Move each repo's window forward to its current HEAD.

    HEAD is stored unfiltered even though the report is author-scoped: the
    window must not re-offer a teammate's commits tomorrow just because they
    were not yours today.
    """
    today = today or _date.today().isoformat()
    state = load_state()
    for r in enabled_repos():
        d = repo_dir(r)
        if d is None:
            continue
        head = head_commit(d)
        prev = state.get(r["name"], {})
        moved = prev.get("last_commit") != head
        state[r["name"]] = {
            "last_commit": head,
            "last_synced": today,
            "last_activity_date": today if moved else prev.get("last_activity_date"),
        }
    save_state(state)
    return state
