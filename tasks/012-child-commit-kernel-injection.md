# 012 — child commit-kernel injection

Status: todo

Inject the commit-telemetry kernel into each tracked child repo's `CLAUDE.md`, so
git history carries the structured `[Context]`/`[Impact]` telemetry the summary
reads. Folded from project-status's `setup-new-repo.sh` — the **commit half only**.

## Acceptance
- Marker block (`ai-project-status:begin/end` style) injected into the child's
  `CLAUDE.md` via `add-repo` (task 009); idempotent, preserves user content.
- **Commit-discipline only — drop the daily-plan half** (plans live in the
  workspace now).
- The stale-plan `SessionStart` nag moves to the workspace, not the child.

## Notes
- Distinct from the task-tracking kernel `create-project-system` injects (task 006).
