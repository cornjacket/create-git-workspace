# PLAN — cadence

**Make the status run cadence-neutral and cheap: weekly by default, honest names, a visible schedule, a measured cost.**

Started 2026-11-10. Task files: `docs/plans/cadence/`.
Durable design lives in `DESIGN.md`; this file is only this effort.

## Where I left off

_Rewritten wholesale by `/wrap` at the end of each session — state, not a log.
Never append a new dated entry; overwrite._

- **current task** — none started.
- **next concrete step** — `28`: settle the script name, then rename.
- **files mid-edit** — none.
- **uncommitted / unpushed** — none.
- **open questions** — see below.

## Scope

**In:** renames away from "daily"; the routine schedule in the README roster; the token cost of each run.

**Out:** a `cadence:` config field. The schedule lives in the routine, so a repo copy would drift (the `routine_registered` lesson, task `20`).

## Tasks

| # | Task | Status |
|---|---|---|
| [28](28-cadence-neutral-names.md) | rename `daily.sh` and `daily-plan*.md` to cadence-neutral names | todo |
| [29](29-routine-schedule-in-readme.md) | `routine-sync.py` saves the schedule; `render-readme.py` shows it | todo |
| [30](30-per-run-token-cost.md) | `run.py` records the token cost of each run. Its `summary.md` line waits on `rollups` `23` | todo |

## Decisions

- 2026-11-10 — The dev-workspace routine moved to weekly (`43 12 * * 1`) and to `claude-haiku-5-5`, done by hand via `RemoteTrigger`. No code change: the run window is commit-based (`last_commit..HEAD`), so a weekly run covers the whole week.
- 2026-11-10 — No `cadence:` field in `config.yml`. The live routine is the only source of truth for the schedule.

## Open questions

- `28`: what replaces `daily.sh`? `update.sh` is out — it names the generator's refresh script. Candidates: `summarize.sh`, `routine.sh` (the entry point the routine calls; `run.py` does the summarizing, this script branches, commits and pushes).

## Done when

`dev-workspace` and `personal-workspace` run on the renamed machinery after `update.sh`. The README shows the checked schedule. The rollup reports the run's token cost.
