# 014 — vendor create-project-system

Status: todo

`create-git-workspace` vendors `create-project-system` and composes it, so a
generated workspace can get a task-system with no external generator to fetch.
See PLAN.md "Vendoring create-project-system".

## Acceptance
- Vendored copy under `create-git-workspace/vendor/create-project-system/` —
  **`generate.sh` + `src/` only**. Strip create-project-system's self-tracking
  scaffolding (`daily-plan.md`, `.claude/hooks/`, `.github/`, `tests/`, `tasks/`,
  its `ai-project-status` block): the vendored copy is inert machinery, not a
  tracked repo.
- `setup.sh --with-tasks` (default; `--no-tasks` opts out) runs
  `generate.sh --target-repo <workspace> --tasks-dir project/tasks --with-skill --with-status`
  — stamping the **full `project/`** deliverable. `project/tasks` feeds
  `_workspace/daily-plan.md`; `project/status/` is optional narrative reports
  (status-review meetings), distinct from the automated `summary.md`.
- `add-repo` can run the same vendored generator against a new child repo (task
  capture); the commit-telemetry kernel is injected separately (task 012).
- Documented **re-vendor** step (copy latest `generate.sh`+`src/` in), stamped with
  source version.

## Boundary (confirmed)
- create-project-system = task capture (`task-system:begin` kernel + `tasks/`).
- status subsystem = commit telemetry (`ai-project-status:begin`) + daily-plan +
  aggregation. Distinct CLAUDE.md blocks — no overlap.

## Notes
- Cookiecutter "vendor a copy for self-containment" over DRY (second-brain:
  cookiecutter-pattern). Composition of generators: create-git-workspace ∘ create-project-system.
