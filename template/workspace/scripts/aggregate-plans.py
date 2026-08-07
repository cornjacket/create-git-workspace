#!/usr/bin/env python3
"""Aggregate the workspace's daily plans into daily-plan-summary.md.

Plans live in THIS workspace, one per tracked repo:

    .workspace/daily-plans/_workspace/daily-plan.md    the workspace's own (see below)
    .workspace/daily-plans/<repo>/daily-plan.md        one per tracked repo

They are per-developer intent, which is why they sit here rather than in the
shared child repos — two developers each keep their own and never collide.

The `_workspace` plan is aggregated FIRST — top row of "At a glance", first
section of the body — and is exempt from the priority sort. Inter-repo work
outranks any single repo's, and it is the tier that otherwise has nowhere to be
seen. It is forward-looking only: the workspace's own commits are meta-noise, so
it never appears in the retrospective summary.md.

Each plan declares its date on the first line:

    # Daily plan — YYYY-MM-DD

Freshness is weekend-tolerant: a plan is fresh iff its date is on or after the
most recent weekday. Output overwrites daily-plan-summary.md — and only that.
The day-by-day history is `git log -p daily-plan-summary.md`, which every run
already writes; a second dated copy on disk was a duplicate that grew forever.

The output opens with a banner when any repo's routine registration is still
outstanding (see `_status_lib.routine_pending`) — those repos are silently
absent from the rollup, so the warning belongs above the content it invalidates.
"""
import os
import re
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _status_lib import (  # noqa: E402
    DAILY_PLAN_SUMMARY_MD, DAILY_PLANS_DIR, WORKSPACE_PLAN_KEY,
    StatusError, enabled_repos, git, normalize_remote, repo_dir, routine_pending,
    workspace_name,
)

PLAN_HEADER_RE = re.compile(r"^#\s+Daily plan\s+[—\-]\s+(\d{4}-\d{2}-\d{2})\s*$", re.M)
# The first bullet under this heading is the day's headline. `replan.sh` writes
# "In progress"; hand-written plans often use "Focus / plan".
FOCUS_HEADING_RE = re.compile(r"^#{2,3}\s*(In progress|Focus\s*/\s*plan):?\s*$", re.M | re.I)
BULLET_RE = re.compile(r"^\s*[-*]\s+(?:\[[ xX]\]\s+)?(.+?)\s*$")
# The table is meant to be scanned; a wrapping row defeats that.
MAX_FOCUS_CHARS = 64


# Moved into _status_lib so `routine-sync.py` compares against the identical
# normalization; kept under the old name here because this module's readers know
# it by that name and the roster link is what it means locally.
remote_to_url = normalize_remote


def most_recent_weekday(today):
    """today if Mon-Fri, else the previous Friday."""
    return today if today.weekday() < 5 else today - timedelta(days=today.weekday() - 4)


def parse_plan(text):
    m = PLAN_HEADER_RE.search(text)
    if not m:
        return None, text.strip()
    try:
        plan_date = date.fromisoformat(m.group(1))
    except ValueError:
        return None, text.strip()
    return plan_date, (text[:m.start()] + text[m.end():]).strip()


def extract_focus(body):
    """First bullet under the focus heading, else the first bullet anywhere."""
    m = FOCUS_HEADING_RE.search(body)
    region = body[m.end():] if m else body
    for line in region.splitlines():
        if line.lstrip().startswith("#"):
            break
        b = BULLET_RE.match(line)
        if b and not b.group(1).startswith("_"):
            return b.group(1)
    return None


def plan_path(key):
    return DAILY_PLANS_DIR / key / "daily-plan.md"


def plan_state(path, today):
    """(state, plan_date, body); state ∈ fresh|stale|missing|unparseable.

    One source of truth for freshness, shared by the table and the sections so
    the two cannot disagree.
    """
    if not path.exists():
        return "missing", None, ""
    plan_date, body = parse_plan(path.read_text())
    if plan_date is None:
        return "unparseable", None, body
    return ("stale" if plan_date < most_recent_weekday(today) else "fresh"), plan_date, body


def days_since_commit(repo, today):
    """Days since the newest commit in the checkout, or None.

    Read from git, not state.json: aggregation runs BEFORE state advances, so
    state.json is always a run behind and would report today's work as idle.
    """
    d = repo_dir(repo)
    if d is None:
        return None
    out = git(["log", "-1", "--format=%cs"], cwd=d, check=False).stdout.strip()
    try:
        return (today - date.fromisoformat(out)).days
    except ValueError:
        return None


def _cell(text, limit=MAX_FOCUS_CHARS):
    one_line = " ".join(text.split())
    if len(one_line) > limit:
        one_line = one_line[:limit].rsplit(" ", 1)[0].rstrip(" ,;:—-") + "…"
    return one_line.replace("|", "\\|")


def workspace_row(today):
    state, plan_date, body = plan_state(plan_path(WORKSPACE_PLAN_KEY), today)
    return {
        "key": WORKSPACE_PLAN_KEY,
        "label": f"{workspace_name()} (workspace)",
        "url": None,
        "priority": None,
        "state": state,
        "plan_date": plan_date,
        "focus": extract_focus(body) if body else None,
        "idle": None,
        "body": body,
    }


def repo_row(repo, today):
    state, plan_date, body = plan_state(plan_path(repo["name"]), today)
    return {
        "key": repo["name"],
        "label": repo["name"],
        "url": remote_to_url(repo.get("url")),
        "priority": repo["priority"],
        "state": state,
        "plan_date": plan_date,
        "focus": extract_focus(body) if body else None,
        "idle": days_since_commit(repo, today),
        "body": body,
    }


def sort_rows(rows):
    """Workspace first, then fresh plans, then priority band, then repos.yml order.

    Freshness leads the repo rows because the table answers "what is live today"
    before "what matters most" — a stale P1 has nothing to say about today.
    Python's sort is stable, so equal keys keep their repos.yml position.
    """
    return [r for _, r in sorted(
        enumerate(rows),
        key=lambda pair: (
            0 if pair[1]["key"] == WORKSPACE_PLAN_KEY else 1,
            0 if pair[1]["state"] == "fresh" else 1,
            pair[1]["priority"] if pair[1]["priority"] is not None else -1,
            pair[0],
        ),
    )]


def render_banner(repos):
    """A blockquote naming every repo whose routine registration is outstanding.

    The flag lives in repos.yml and `make status` enforces it; this is the
    *second projection* of the same field, and it is here because this file is
    what actually gets read each morning. A flag nobody looks at is not tracking.
    """
    pending = routine_pending(repos)
    if not pending:
        return ""
    names = ", ".join(f"`{r['name']}`" for r in pending)
    return (
        f"> **⚠ Routine registration incomplete — {names}**\n"
        "> \n"
        "> Registered in `.workspace/repos.yml` but not confirmed in the scheduled\n"
        "> routine's `sources`, so the remote run cannot read their git logs and\n"
        "> **silently omits them** from the rollup — it does not fail.\n"
        "> \n"
        "> Add them to the routine's `sources` (`.workspace/status-guide.md` §5.2),\n"
        "> then record it: `make routine-registered ARGS=\"<name>\"`.\n"
    )


def render_overview(rows):
    if not rows:
        return ""
    lines = [
        "## At a glance",
        "",
        "<!-- Workspace plan first, then fresh plans, then by priority band "
        "(P1 = highest, set in .workspace/repos.yml). Idle = days since the "
        "newest commit. -->",
        "",
        "| Repo | Pri | Plan | Focus | Idle |",
        "| --- | --- | --- | --- | --- |",
    ]
    for r in rows:
        label = f"[{r['label']}]({r['url']})" if r["url"] else r["label"]
        plan_cell = {
            "fresh": r["plan_date"].isoformat() if r["plan_date"] else "—",
            "stale": f"**STALE** {r['plan_date'].isoformat()}" if r["plan_date"] else "**STALE**",
            "missing": "**none**",
            "unparseable": "**bad header**",
        }[r["state"]]
        pri = "—" if r["priority"] is None else f"P{r['priority']}"
        focus = _cell(r["focus"]) if r["focus"] else "—"
        idle = "—" if r["idle"] is None else ("today" if r["idle"] == 0 else f"{r['idle']}d")
        lines.append(f"| {label} | {pri} | {plan_cell} | {focus} | {idle} |")
    return "\n".join(lines) + "\n"


def demote_headings(body):
    """Push every heading in an embedded plan down one level.

    A plan's own `## In progress` would otherwise sit at the same level as the
    aggregator's `## <repo>` section heading, flattening the document so the
    sections no longer nest under the repo they belong to. Capped at h6, which
    is as deep as Markdown goes.
    """
    out = []
    for line in body.splitlines():
        m = re.match(r"^(#{1,6})(\s+\S)", line)
        out.append(f"#{line}" if m and len(m.group(1)) < 6 else line)
    return "\n".join(out)


def render_section(r):
    label = f"[{r['label']}]({r['url']})" if r["url"] else r["label"]
    if r["state"] == "missing":
        return f"## {label} — no plan\n\n> No `{plan_path(r['key']).name}` in " \
               f"`.workspace/daily-plans/{r['key']}/`.\n"
    if r["state"] == "unparseable":
        return (f"## {label} — plan present but unparseable\n\n"
                "> Could not read a `# Daily plan — YYYY-MM-DD` header.\n")
    if r["state"] == "stale":
        header = f"## {label} — STALE (last plan: {r['plan_date'].isoformat()})"
    else:
        header = f"## {label} — plan for {r['plan_date'].isoformat()}"
    if not r["body"]:
        return f"{header}\n\n> Plan file has no body content.\n"
    return f"{header}\n\n{demote_headings(r['body'])}\n"


def build_summary(today=None, repos=None):
    today = today or date.today()
    repos = repos if repos is not None else enabled_repos()
    rows = sort_rows([workspace_row(today)] + [repo_row(r, today) for r in repos])
    banner = render_banner(repos)
    return (
        f"# Daily plan summary — {today.isoformat()}\n\n"
        "<!-- Auto-aggregated by .workspace/scripts/aggregate-plans.py from the "
        "plans in .workspace/daily-plans/. Overwritten on every run. -->\n\n"
        # Above the table on purpose: a repo missing from `sources` is missing
        # from everything below, so it has to be read before the content it
        # invalidates.
        + (f"{banner}\n" if banner else "")
        + f"{render_overview(rows)}\n"
        + "\n".join(render_section(r) for r in rows)
    )


def main():
    # ONE FILE, REWRITTEN. There is deliberately no dated snapshot alongside it:
    # every run commits daily-plan-summary.md, so `git log -p` on it already IS
    # the day-by-day history — versioned, diffable, and free. A parallel
    # archive/ directory was a second copy of that same history which grew
    # without bound, and which nothing ever read. Same argument that made
    # summary.md a dashboard rather than a journal.
    today = date.today()
    summary = build_summary(today=today)
    DAILY_PLAN_SUMMARY_MD.write_text(summary)
    print(f"[aggregate-plans] wrote {DAILY_PLAN_SUMMARY_MD.name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except StatusError as e:
        print(f"[aggregate-plans] {e}", file=sys.stderr)
        sys.exit(2)
