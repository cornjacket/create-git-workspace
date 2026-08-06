#!/usr/bin/env python3
"""The daily status run — one entry point for the whole cycle.

  1. sync        — report which repos are readable (local: they already are)
  2. gather      — classify each repo against YOUR commit window
  3. per repo    — `claude -p` summarises each ACTIVE repo's telemetry
  4. inactive    — deterministic one-liners, no LLM
  5. polish      — with >=2 ACTIVE repos, `claude -p` merges cross-repo themes
  6. summary.md  — REPLACE its one section with this run's
  7. aggregate   — rebuild daily-plan-summary.md (always, even with no commits)
  8. advance     — move state.json's window forward

SUMMARY.MD HOLDS ONE RUN, NOT A JOURNAL. It is a dashboard — "what is the state
of my work" — so it is windowed and its size is bounded, rather than growing by
a section a day forever. A run with no new commits does not overwrite the last
real activity with an empty "No updates" list: it keeps that body verbatim and
re-dates the heading to today, which is the useful reading of a quiet day (the
status is current; the work is still the work). The heading then names both
dates, so a re-dated section can never be mistaken for work done today.

The journal did not disappear, it moved to where journals belong: every run
commits summary.md, so `git log -p summary.md` is the full day-by-day history.

The LLM steps (3 and 5) are skipped by `--dry-run`, which emits deterministic
placeholders instead — that is what makes the pipeline testable offline.

This writes files and stops. It never commits: on the remote side daily.sh owns
the branch-and-push, and locally the diff is the review surface.
"""
import argparse
import functools
import os
import re
import subprocess
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _status_lib import (  # noqa: E402
    PROMPTS_DIR, SUMMARY_MD, StatusError, advance_state, format_telemetry,
    gather_report, git_authors, workspace_name,
)

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

# `## <status date>` or `## <status date> — no new work since <activity date>`.
# The second form is what a quiet day writes, and parsing it back is what stops
# the activity date from creeping forward one quiet day at a time.
SECTION_RE = re.compile(
    r"^##\s+(\d{4}-\d{2}-\d{2})(?:\s+—\s+no new work since\s+(\d{4}-\d{2}-\d{2}))?\s*$",
    re.M,
)

# The step scripts run as subprocesses and write straight to the terminal, so
# this process's own progress lines must not sit in a pipe buffer — otherwise
# the log reads out of order (aggregate's output appearing before "[run] ...").
print = functools.partial(print, flush=True)  # noqa: A001


def claude_p(prompt):
    """Invoke `claude -p`, piping the prompt on stdin (safer for large inputs)."""
    r = subprocess.run(["claude", "-p"], input=prompt, check=True,
                       capture_output=True, text=True)
    return r.stdout.strip()


def format_slice(e):
    return (
        f"Range: {e['last_commit'][:8]}..{e['head'][:8]}\n\n"
        f"## commit telemetry\n{format_telemetry(e['commit_telemetry'])}\n\n"
        f"## file stat\n{e['file_stat'] or '(none)'}\n\n"
        f"## commits\n{e['commit_list'] or '(none)'}\n"
    )


def render_per_repo(e, dry_run):
    if dry_run:
        return (f"### {e['name']}\n- (dry-run placeholder for "
                f"{e['last_commit'][:8]}..{e['head'][:8]}, "
                f"{len(e['commit_telemetry'])} commit(s))")
    template = (PROMPTS_DIR / "per-repo.md").read_text()
    return claude_p(template
                    .replace("{{REPO_NAME}}", e["name"])
                    .replace("{{REPO_SLICE}}", format_slice(e)))


def render_inactive_bullet(e):
    if e["last_activity_date"]:
        return f"- {e['name']} (for {e['days_inactive']} days)"
    return f"- {e['name']} (no activity recorded yet)"


def render_inactives_block(entries):
    if not entries:
        return ""
    return "### No updates\n" + "\n".join(render_inactive_bullet(e) for e in entries)


# A repo the run could not READ is a different fact from a repo that did
# nothing, and the deliverable has to carry both. This heading is matched when
# carrying a section forward, so keep the two in step.
UNAVAILABLE_HEADING = "### Not read this run"


def render_unavailable_block(entries):
    """Repos that are tracked but whose git history could not be read.

    THE WHOLE POINT OF THIS BLOCK: without it the run skipped them with a
    warning on stderr, which on a scheduled remote run goes to a job log nobody
    opens — so the committed rollup showed no trace and "absent" read as
    "nothing to report". A repo that is tracked and was not read must say so in
    the file people actually read.

    It is deliberately NOT suppressible by `report_inactivity: false`. That flag
    opts a repo out of the quiet-day list, which is a claim about the *repo*;
    being unreadable is a claim about the *run*. Letting the flag hide it would
    rebuild the original bug behind a config field.
    """
    if not entries:
        return ""
    bullets = "\n".join(
        f"- {e['name']} — no readable checkout "
        f"(is it in the routine's `sources` pre-clone list?)"
        for e in entries)
    return (f"{UNAVAILABLE_HEADING}\n{bullets}\n"
            "\nThese repos are tracked but were not summarized, so this rollup "
            "does not cover them.")


def strip_unavailable(body):
    """Remove a previous run's unavailable block from a carried-forward body.

    A quiet day re-uses the last real section (see the `previous` branch in
    main). Without this, yesterday's notice would ride along and read as
    current — and re-running would stack duplicates. The notice always
    describes THIS run.
    """
    out, skipping = [], False
    for line in body.splitlines():
        if line.startswith(UNAVAILABLE_HEADING):
            skipping = True
            continue
        if skipping:
            # The block runs until the next heading.
            if line.startswith("#"):
                skipping = False
            else:
                continue
        out.append(line)
    return "\n".join(out).strip()


def polish(today, drafts_text, dry_run):
    if dry_run:
        return f"## {today}\n\n{drafts_text}"
    template = (PROMPTS_DIR / "polish.md").read_text()
    return claude_p(template
                    .replace("{{TODAY}}", today)
                    .replace("{{WORKSPACE_NAME}}", workspace_name())
                    .replace("{{DRAFTS}}", drafts_text))


def previous_section():
    """(activity_date, body) of the section already in summary.md, or None.

    `activity_date` is when the work actually happened, which is NOT the
    heading's own date once a section has been re-dated: a carried-forward
    heading names both, and this reads the original through any number of quiet
    days rather than letting it creep forward one day at a time.

    Tolerant of a pre-windowing summary.md that stacked many day sections: the
    first one is the newest, and everything below it is history git already has.
    """
    if not SUMMARY_MD.exists():
        return None
    text = SUMMARY_MD.read_text()
    m = SECTION_RE.search(text)
    if not m:
        return None
    body = text[m.end():].lstrip("\n")
    older = SECTION_RE.search(body)
    if older:
        body = body[:older.start()]
    return (m.group(2) or m.group(1)), body.rstrip("\n")


def write_summary(section):
    """Rewrite summary.md around exactly one section — the newest run's."""
    SUMMARY_MD.write_text(
        f"# Summary — {workspace_name()}\n\n"
        "<!-- Author-scoped retrospective rollup. Holds ONE run: the most\n"
        "     recent. A run with no new commits keeps this body and re-dates the\n"
        "     heading, so the date says when the status was taken, not when the\n"
        "     work happened. Day-by-day history: `git log -p summary.md`.\n"
        "     Written by .workspace/scripts/run.py — never hand-edit it. -->\n\n"
        f"{section.rstrip()}\n"
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="skip `claude -p`; emit deterministic placeholders")
    ap.add_argument("--skip-sync", action="store_true")
    ap.add_argument("--skip-plans", action="store_true",
                    help="skip the aggregate-plans step")
    ap.add_argument("--skip-state", action="store_true",
                    help="do not advance state.json (re-runnable window)")
    ap.add_argument("--since", "--window", dest="since", metavar="WHEN",
                    help="ad-hoc window override (e.g. '24 hours ago')")
    args = ap.parse_args()

    # Resolve the author FIRST: everything downstream is scoped to it, and a
    # placeholder would produce a plausible-looking but empty rollup.
    authors = git_authors()
    print(f"[run] workspace '{workspace_name()}' — scoped to {', '.join(authors)}")

    if not args.skip_sync:
        subprocess.run([sys.executable, os.path.join(SCRIPTS_DIR, "sync.py")], check=True)

    today = date.today().isoformat()
    report = gather_report(today=today, since=args.since, authors=authors)

    drafts, inactive_entries, unavailable_entries, active_count = [], [], [], 0
    for e in report:
        # UNAVAILABLE is checked FIRST and reported, never merely skipped. It is
        # also above INACTIVE_SUPPRESSED on purpose: "could not read this repo"
        # must not be silenceable by a flag about quiet days.
        if e["status"] == "UNAVAILABLE":
            print(f"[run] WARNING: {e['name']} has no readable checkout; "
                  "reporting it in the rollup", file=sys.stderr)
            unavailable_entries.append(e)
            continue
        if e["status"] == "INACTIVE_SUPPRESSED":
            continue
        if e["status"] == "INACTIVE":
            inactive_entries.append(e)
            continue
        print(f"[run] summarizing {e['name']}...")
        drafts.append(render_per_repo(e, args.dry_run))
        active_count += 1

    inactives = render_inactives_block(inactive_entries)
    if inactives:
        drafts.append(inactives)
    unavailable = render_unavailable_block(unavailable_entries)
    if unavailable:
        drafts.append(unavailable)

    previous = previous_section()
    if active_count:
        drafts_text = "\n\n".join(drafts)
        if active_count >= 2:
            print("[run] polishing cross-repo section...")
            section = polish(today, drafts_text, args.dry_run)
        else:
            section = f"## {today}\n\n{drafts_text}"
        write_summary(section)
        print(f"[run] summary.md now holds the {today} run")
    elif previous:
        # A quiet day must not replace real work with an empty "No updates"
        # list — that reads as "nothing has happened", when what is true is
        # "nothing has happened *since*". Keep the body, move the date, and say
        # both in the heading so the two can never be confused.
        activity, body = previous
        header = f"## {today}" if activity == today \
            else f"## {today} — no new work since {activity}"
        # Carry the work forward, but re-state unreadability from THIS run:
        # drop any stale notice, then append the current one. A quiet day is
        # exactly when an unreadable repo would otherwise vanish, since the
        # whole body is inherited.
        body = strip_unavailable(body)
        if unavailable:
            body = f"{body}\n\n{unavailable}"
        write_summary(f"{header}\n\n{body}")
        print(f"[run] no new commits — re-dated summary.md to {today} "
              f"(work unchanged since {activity})")
    elif drafts:
        # No prior section to carry: the inactivity report IS the whole story.
        write_summary(f"## {today}\n\n" + "\n\n".join(drafts))
        print(f"[run] summary.md now holds the {today} run")
    else:
        print("[run] nothing to report; summary.md untouched")

    # Plans aggregate even on a zero-commit day — the forward-looking half is
    # the point of the dashboard, and it is independent of git activity.
    if not args.skip_plans:
        subprocess.run([sys.executable, os.path.join(SCRIPTS_DIR, "aggregate-plans.py")],
                       check=True)

    if not args.skip_state:
        advance_state(today=today)
        print("[run] advanced state.json")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except StatusError as e:
        print(f"[run] {e}", file=sys.stderr)
        sys.exit(2)
