#!/usr/bin/env python3
"""Refresh the managed roster block in the workspace README.md.

    render-readme.py            rewrite the block
    render-readme.py --check    exit 1 if it is missing or stale; write nothing

README.md is a HYBRID, exactly like CLAUDE.md: the generator owns the block
between the markers, you own every other byte. That is the only way the file can
both reflect the workspace's current state and stay yours.

WHAT IT SHOWS: the tracked repos (name, one-liner, path, muted/skipped/missing),
the deliverable links, and whether the scheduled routine has been created.

WHAT IT DOES NOT SHOW: the branch — mutable, and per-checkout for worktrees, so a
value copied from the registry would eventually be a lie. Nor the last-run date,
which would make a block refreshed by the membership verbs depend on runtime
state and go quietly stale between renders.

WHO CALLS IT: setup.sh and update.sh (so an existing workspace gains the block on
upgrade), the three membership verbs, and `make readme`. Deliberately NOT the
daily run: membership only changes locally, and keeping README.md out of
daily.sh's commit set preserves the rule that the routine and the generator never
write the same file.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _status_lib import (  # noqa: E402
    ARCHIVE_DIR, CONFIG_YML, WORKSPACE_ROOT, load_config, load_repos, workspace_name,
)

README = WORKSPACE_ROOT / "README.md"
BEGIN = "<!-- git-workspace-roster:begin"
BEGIN_FULL = (BEGIN + " — managed by create-git-workspace; "
              "do not edit inside this block -->")
END = "<!-- git-workspace-roster:end -->"


class MarkerError(RuntimeError):
    """The file is in a shape where any edit could destroy content."""


def _rel(path):
    return path.relative_to(WORKSPACE_ROOT).as_posix()


def _cell(text):
    """A pipe in free text ends the table cell — descriptions are user prose, so
    escape it rather than trusting nobody writes `foo | bar`."""
    return text.replace("|", "\\|")


def roster_rows(repos):
    rows = []
    for r in repos:
        checkout = WORKSPACE_ROOT / r["path"]
        flags = []
        if not r["enabled"]:
            flags.append("**skipped**")
        elif not r["report_inactivity"]:
            flags.append("muted")
        # Worktree-safe: a linked worktree's .git is a FILE, not a directory.
        if not (checkout / ".git").exists():
            flags.append("**not checked out**")
        what = _cell(r["description"]) or "_no description — add one in `repos.yml`_"
        if flags:
            what = f"{what} <br>({', '.join(flags)})"
        where = f"`{r['path']}/`"
        if r["type"] == "worktree" and r["parent_repo_path"]:
            where += f" <br>_worktree of `{r['parent_repo_path']}/`_"
        rows.append((r["name"], what, where))
    return rows


def render_block():
    repos = load_repos()
    cfg = load_config()
    out = [BEGIN_FULL, ""]

    out.append("## Tracked repos")
    out.append("")
    if not repos:
        out.append("_No repos tracked yet._ Register the first one with")
        out.append('`make add-repo ARGS="<url>"` — it clones the repo, writes the')
        out.append("entry, seeds its plan slot, and injects the commit kernel.")
    else:
        out.append("| repo | what it is | where |")
        out.append("|---|---|---|")
        for name, what, where in roster_rows(repos):
            out.append(f"| **{name}** | {what} | {where} |")
        out.append("")
        missing = [r for r in repos
                   if not (WORKSPACE_ROOT / r["path"] / ".git").exists()]
        counts = [f"{len(repos)} tracked"]
        muted = sum(1 for r in repos if r["enabled"] and not r["report_inactivity"])
        skipped = sum(1 for r in repos if not r["enabled"])
        if muted:
            counts.append(f"{muted} muted")
        if skipped:
            counts.append(f"{skipped} skipped")
        if missing:
            counts.append(f"{len(missing)} not checked out — run `make bootstrap`")
        out.append("_" + " · ".join(counts) + "._")
    out.append("")

    out.append("## Daily dashboard")
    out.append("")
    out.append("- **[summary.md](summary.md)** — retrospective rollup of commit "
               "activity, scoped to your own commits.")
    out.append("- **[daily-plan-summary.md](daily-plan-summary.md)** — every "
               "plan in one place, workspace plan first.")
    out.append(f"- [`{_rel(ARCHIVE_DIR)}/`]({_rel(ARCHIVE_DIR)}/) — dated "
               "snapshots of each day's aggregate.")
    out.append("")
    out.append("Both are written by the daily status run and appear after its "
               "first run; do not hand-write them.")
    out.append("")

    out.append("## The scheduled routine")
    out.append("")
    url = (cfg.get("routine_url") or "").strip()
    if url:
        out.append(f"This workspace's remote routine: <{url}>")
        out.append("")
        out.append("It runs `.workspace/scripts/daily.sh` on a schedule, pushes "
                   "`auto/status-YYYY-MM-DD`, and the auto-merge workflow "
                   "fast-forwards it onto `main`. `make pull` brings it down.")
        out.append("")
        out.append("**Every repo above must also be in that routine's "
                   "`sources`** — the remote sandbox has no checkouts, so a repo "
                   "missing from the pre-clone list has no git log to read.")
    else:
        out.append("**Not set up yet.** The generator emits `daily.sh` and the "
                   "merge workflow, but creating the routine is a one-time "
                   "interactive step in the Claude app, and each tracked repo "
                   "must be added to its `sources` pre-clone list.")
        out.append("")
        out.append("See [`.workspace/status-guide.md`](.workspace/status-guide.md) "
                   "§5. Once it exists, put its URL in "
                   "`.workspace/config.yml` as `routine_url:` and re-run "
                   "`make readme` to show it here.")
    out.append("")
    out.append(END)
    return "\n".join(out)


def _span(text, what):
    """Locate the managed block, or None. Refuses to guess at anything malformed:
    a half-open or duplicated block means any edit could silently destroy
    content."""
    nbegin, nend = text.count(BEGIN), text.count(END)
    if nbegin > 1 or nend > 1:
        raise MarkerError(f"{what} contains {nbegin} begin / {nend} end roster "
                          "markers — expected at most one block.")
    i, j = text.find(BEGIN), text.find(END)
    if i >= 0 and j < 0:
        raise MarkerError(f"{what} has a roster begin marker but no end marker.")
    if j >= 0 and i < 0:
        raise MarkerError(f"{what} has a roster end marker but no begin marker.")
    if i >= 0 and j < i:
        raise MarkerError(f"{what} has its roster end marker before its begin marker.")
    return (i, j + len(END)) if i >= 0 else None


def apply(block, check=False):
    """Returns (action, changed). Never partially writes."""
    if not README.exists():
        if check:
            return "missing", True
        README.write_text(f"# {workspace_name()}\n\n{block}\n")
        return "created", True

    cur = README.read_text()
    span = _span(cur, str(README))
    if span:
        new = cur[:span[0]] + block + cur[span[1]:]
        action = "refreshed"
    else:
        # No markers: append. Least disruptive to a README the user wrote, and
        # the next run finds markers and takes the replace path.
        sep = "" if cur.endswith("\n\n") else ("\n" if cur.endswith("\n") else "\n\n")
        new = cur + sep + block + "\n"
        action = "appended"

    if new == cur:
        return "current", False
    if not check:
        README.write_text(new)
    return action, True


def main():
    check = "--check" in sys.argv[1:]
    for arg in sys.argv[1:]:
        if arg not in ("--check",):
            sys.exit(f"render-readme: unknown option: {arg}")

    try:
        action, changed = apply(render_block(), check=check)
    except MarkerError as e:
        # Exit 3 is distinct on purpose: the generator downgrades it to a warning
        # and carries on, because a mangled dashboard must not abort a machinery
        # upgrade. The CLAUDE.md kernel is the opposite case — it carries rules an
        # agent must follow, so a bad block there aborts.
        sys.stderr.write(f"render-readme: {e}\n"
                         "               Fix the markers, then re-run 'make readme'.\n")
        return 3

    rel = _rel(README)
    if check:
        if action == "missing":
            print(f"readme: {rel} does not exist — run 'make readme'")
            return 1
        if changed:
            print(f"readme: the roster block in {rel} is STALE — run 'make readme'")
            return 1
        print(f"readme: {rel} roster block is current")
        return 0

    print({
        "created":   f"[readme] created {rel} with the roster block",
        "refreshed": f"[readme] refreshed the roster block in {rel}",
        "appended":  f"[readme] appended the roster block to {rel}",
        "current":   f"[readme] {rel} roster block already current",
    }[action])
    return 0


if __name__ == "__main__":
    sys.exit(main())
