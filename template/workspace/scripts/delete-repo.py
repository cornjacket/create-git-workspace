#!/usr/bin/env python3
"""Unregister a repo from this workspace, and remove its checkout.

    delete-repo.py <name> [--keep-checkout] [--keep-plan] [--force]

Removing a checkout destroys anything that only exists there, so this refuses
unless the working copy is provably reproducible from its remote. Three ways it
can fail that test, all reported together so one run tells you everything:

  * dirty     — uncommitted changes or untracked files
  * unpushed  — a branch ahead of its upstream, or with no upstream at all
  * stashed   — stash entries live nowhere but this checkout

A branch with NO upstream is treated as unpushed on purpose: it is the most
common shape of "work that exists only here", and calling it safe because there
is nothing to compare against would delete exactly the work worth protecting.
"""
import argparse
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _repos_edit as R  # noqa: E402
from _status_lib import (  # noqa: E402
    REPOS_YML, WORKSPACE_DIR, WORKSPACE_ROOT, git, load_repos, pending_findings,
    refresh_readme,
)


def unsafe_reasons(d):
    """Every reason this checkout must not be deleted, as human-readable lines.

    Deletion blocks on **every** finding, including `local-only` — a repo that
    exists nowhere else is precisely the one whose removal cannot be undone.
    `status.py` shares the detector but treats that kind as informational.
    """
    return [message for _kind, message in pending_findings(d)]


def remove_checkout(repo, d):
    """Delete the working copy, using git's own removal for a linked worktree."""
    if repo.get("type") == "worktree":
        parent = WORKSPACE_ROOT / (repo.get("parent_repo_path") or "")
        if (parent / ".git").exists():
            r = git(["worktree", "remove", str(d)], cwd=parent, check=False)
            if r.returncode != 0:
                return f"git worktree remove failed: {r.stderr.strip()}"
            return None
        return (f"parent repo '{repo.get('parent_repo_path')}' is not present, so the "
                "worktree cannot be removed cleanly — remove it by hand")
    shutil.rmtree(d)
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name")
    ap.add_argument("--keep-checkout", action="store_true",
                    help="unregister only; leave the working copy on disk")
    ap.add_argument("--keep-plan", action="store_true",
                    help="keep .workspace/daily-plans/<name>/ (default: remove it)")
    ap.add_argument("--force", action="store_true",
                    help="delete the checkout even when it is dirty or unpushed")
    args = ap.parse_args()

    text = REPOS_YML.read_text() if REPOS_YML.exists() else "repos: []\n"
    if args.name not in R.names(text):
        known = ", ".join(R.names(text)) or "(none)"
        sys.exit(f"delete-repo: no repo named '{args.name}'. Registered: {known}")

    repo = next((r for r in load_repos() if r["name"] == args.name), None)
    d = WORKSPACE_ROOT / (repo["path"] if repo else args.name)
    present = (d / ".git").exists()

    if present and not args.keep_checkout:
        reasons = unsafe_reasons(d)
        if reasons and not args.force:
            print(f"delete-repo: refusing to remove {d} —", file=sys.stderr)
            for r in reasons:
                print(f"  * {r}", file=sys.stderr)
            print("\nPush or discard that work first. To unregister without touching the",
                  file=sys.stderr)
            print("checkout, use --keep-checkout; to delete it anyway, --force.", file=sys.stderr)
            return 1
        if reasons:
            print(f"[delete-repo] --force: removing {d} despite "
                  f"{len(reasons)} unsafe condition(s)")

    new_text = R.remove_entry(text, args.name)
    R.validate(new_text)
    REPOS_YML.write_text(new_text)
    print(f"[delete-repo] unregistered '{args.name}' from .workspace/repos.yml")

    if present and not args.keep_checkout:
        err = remove_checkout(repo or {}, d)
        if err:
            print(f"[delete-repo] {err}", file=sys.stderr)
            return 1
        print(f"[delete-repo] removed the checkout at {d.relative_to(WORKSPACE_ROOT)}")
    elif args.keep_checkout and present:
        print(f"[delete-repo] left the checkout at {d.relative_to(WORKSPACE_ROOT)} "
              "(now untracked by the workspace)")

    plan_dir = WORKSPACE_DIR / "daily-plans" / args.name
    if plan_dir.exists() and not args.keep_plan:
        shutil.rmtree(plan_dir)
        print(f"[delete-repo] removed .workspace/daily-plans/{args.name}/")
    elif plan_dir.exists():
        print(f"[delete-repo] kept .workspace/daily-plans/{args.name}/ — it is no longer "
              "aggregated, since only registered repos are")

    refresh_readme()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except R.RepoEditError as e:
        sys.exit(f"delete-repo: {e}")
