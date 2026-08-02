# 007 — workspace task-system + daily-plan

Status: todo

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
