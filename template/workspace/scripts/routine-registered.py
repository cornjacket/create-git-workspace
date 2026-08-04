#!/usr/bin/env python3
"""Record that a repo now appears in the scheduled routine's `sources`.

    routine-registered.py <name>...       mark phase two done
    routine-registered.py --all           mark every registered repo
    routine-registered.py --unset <name>  put it back to outstanding
    routine-registered.py --check         list what is still outstanding

Registering a repo is two phases and only the first is automatable: `add-repo`
writes `repos.yml`, clones, and injects the kernel — then the repo must *also*
be added to the remote routine's pre-clone `sources`, by hand, in the Claude app
(guide §5.2). Miss that and the run does not fail; it reports the repo as
unreadable and quietly omits it from the rollup.

So the outstanding state is recorded in `repos.yml` — the lockfile `bootstrap`
replays — rather than in a line of terminal output that scrolls away. `make
status` gates on it and `daily-plan-summary.md` banners it; both are projections
of this one field.

**This is the only writer of a `true`.** `add-repo` writes `false` (and
back-fills a missing field as `false`), because an absent flag means the work is
outstanding, never that it is done. Run this once you have actually edited the
routine — it records a fact about the world it cannot verify for you.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _repos_edit as R  # noqa: E402
from _status_lib import (  # noqa: E402
    REPOS_YML, ROUTINE_FLAG, load_repos, routine_hint, routine_pending,
)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="repo names from repos.yml")
    ap.add_argument("--all", action="store_true",
                    help="every registered repo — the one-shot after populating `sources`")
    ap.add_argument("--unset", action="store_true",
                    help="mark them outstanding again (a repo dropped from `sources`)")
    ap.add_argument("--check", action="store_true",
                    help="report what is outstanding and write nothing; exit 1 if any")
    args = ap.parse_args()

    if not REPOS_YML.exists():
        sys.exit("routine-registered: no .workspace/repos.yml")
    text = REPOS_YML.read_text()
    known = R.names(text)

    if args.check:
        pending = routine_pending()
        if not pending:
            print("[routine-registered] every enabled repo is in the routine's `sources`")
            return 0
        print("[routine-registered] registration incomplete:", file=sys.stderr)
        for r in pending:
            print(f"  * {r['name']} — {routine_hint(r['name'])}", file=sys.stderr)
        return 1

    if args.all:
        if args.names:
            ap.error("--all takes no names")
        names = known
    elif args.names:
        missing = [n for n in args.names if n not in known]
        if missing:
            sys.exit(f"routine-registered: not registered: {', '.join(missing)}. "
                     f"Registered: {', '.join(known) or '(none)'}")
        names = args.names
    else:
        ap.error("name a repo, or pass --all (or --check)")

    if not names:
        print("[routine-registered] no repos are registered — nothing to mark")
        return 0

    value = "false" if args.unset else "true"
    before = {r["name"]: r[ROUTINE_FLAG] for r in load_repos()}
    for name in names:
        text = R.set_field(text, name, ROUTINE_FLAG, value)
    R.validate(text)
    REPOS_YML.write_text(text)

    for name in names:
        was = before.get(name)
        state = "outstanding" if args.unset else "registered"
        if was == (not args.unset):
            print(f"[routine-registered] {name}: already {state}")
        else:
            print(f"[routine-registered] {name}: {state} in the routine's `sources`")

    # The README roster is deliberately NOT refreshed: it does not render this
    # flag. Two projections were chosen on purpose (the status row and the
    # summary banner) — a third copy is a third thing that can disagree.
    if not args.unset:
        print("\nCommit .workspace/repos.yml so the record survives a fresh clone.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except R.RepoEditError as e:
        sys.exit(f"routine-registered: {e}")
