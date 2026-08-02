# 007 — workspace task-system + daily-plan

Status: done (2026-08-01) — "aggregated first" is a contract for `008` to honor

Give the workspace its own task-system and daily-plan for inter-repo / workspace
tasks — the triage area for portfolio work with no repo home yet. See PLAN.md
"Workspace task-system — the triage area".

## Acceptance
- Workspace task-system provided by vendored **create-project-system** (task 006),
  installed into the workspace — same task-system as a tracked repo.
- Plan slot `.workspace/plans/_workspace/daily-plan.md`, derived from that task
  state (same replan mechanism as per-repo plans).
- Aggregated **first** — top row of "At a glance", first section of
  `daily-plan-summary.md`.
- Forward-looking only: no retrospective git-log summary for the workspace itself.

## Triage lifecycle
- An idea lands as a workspace task before it has a repo home.
- A workspace task may spawn a child repo (subtask = "create repo X" → `add-repo`),
  then **graduate**: remaining work migrates into that child's task-system.
- Cross-boundary task move (workspace → child) is manual initially
  (recreate-in-child + close-in-workspace); a helper is a later nice-to-have.

## Notes
- Need is demonstrated (infra tasks accumulated in captains-log), not speculative.
- Ties to the project-status retirement end state (PLAN.md).

## What landed
- The task-system itself came with `006` (vendored create-project-system at
  `project/tasks`), so `007` is the **plan half** plus the triage semantics.
- `.workspace/plans/_workspace/daily-plan.md` — seeded content slot, dated header
  `# Daily plan — YYYY-MM-DD` (the project-status convention the aggregator reads).
- `.workspace/scripts/replan.sh` (machinery) + `make replan` — redrafts the plan
  from `project/tasks` via the task-system's own `list-tasks.sh`, so the folder
  layout stays that generator's business.
  - **Draft-only**: writes the file and stops. Never stages, never commits. Git is
    the review surface (project-status's replan invariant, kept).
  - **Derived, not invented**: in-progress → *In progress*, backlog → *Next up*,
    inbox+draft → *Triage*. It reads task state and never edits it.
  - **Section ownership**: everything from `## Notes` onward is the human's and is
    preserved verbatim — the same "generator owns a region" rule as the CLAUDE.md
    block and the `generator_version` key.
  - Idempotent (a second run reports "already current"), `--date YYYY-MM-DD`,
    and it refuses rather than guessing when there is no task-system.
- `{{TODAY}}` added to `render()` — safe **only** in content templates; in a
  machinery file it would re-render tomorrow and break zero-diff (noted in code).
- CLAUDE.md block now explains the triage area, the graduate flow, why plans live
  in the workspace (per-developer intent → no shared-plan collisions), and why the
  workspace plan is forward-looking only.

## Found by the suite: content slots could never reach an existing workspace
Adding the first new content file since `002` exposed it — the upgraded remote
fixture silently lacked the plan slot. Only `setup.sh` seeded content, and
`setup.sh` refuses to run on a live workspace, so **no content file added by a
future version could ever arrive**. `update.sh` now seeds *missing* content and
still never overwrites what exists; PLAN's split table carries the amendment.
Zero-diff is unaffected: on a current workspace every slot exists, so nothing is
written.

## Deferred to 008 (by design)
"Aggregated first — top row of At a glance, first section of
`daily-plan-summary.md`" is an **ordering contract**, and the aggregator that
must honor it (`aggregate-plans`) is `008`. Building half an aggregator here
would have duplicated it. Per-repo plan slots (`.workspace/plans/<repo>/`) land
there too; `replan.sh` is written to grow a `--repo` flag.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `007` — workspace task-system + `_workspace/daily-plan.md` (aggregated first); triage/graduate flow. *(plan slot + `replan.sh` + triage docs landed; "aggregated first" is an ordering contract the aggregator in `008` implements.)*
