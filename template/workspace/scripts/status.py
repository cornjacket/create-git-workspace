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
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _status_lib import (  # noqa: E402
    LOCAL_ONLY, WORKSPACE_ROOT, load_repos, pending_findings,
)

WORKSPACE_LABEL = "(this workspace)"


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
    for kind in ("dirty", "stashed", "ahead", "no-upstream", "detached"):
        if kind in real:
            label = {"ahead": "unpushed", "no-upstream": "no upstream"}.get(kind, kind)
            parts.append(f"{label} ({real[kind]})" if real[kind] > 1 else label)
    return ", ".join(parts), True


def rows(include_all):
    """(name, type, branch, findings-or-None) per checkout. None = missing."""
    out = [(WORKSPACE_LABEL, "workspace", current_branch(WORKSPACE_ROOT),
            pending_findings(WORKSPACE_ROOT))]

    registered_paths = set()
    for repo in load_repos():
        d = WORKSPACE_ROOT / repo["path"]
        registered_paths.add(repo["path"].strip("/"))
        out.append((repo["name"], repo["type"], current_branch(d) if is_checkout(d) else "-",
                    pending_findings(d) if is_checkout(d) else None))

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
    args = ap.parse_args()

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

    if rc and not args.verbose:
        print(f"\n{c['D']}Pending work above. Re-run with -v for the detail.{c['X']}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
