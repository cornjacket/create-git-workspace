# 008 — status subsystem core

Status: todo

Fold project-status's tracking engine into the workspace machinery. See PLAN.md
"Status subsystem".

## Acceptance
- `sync` (local: no-op — children already present; remote routine: pre-cloned sources),
  `new-work` (classify ACTIVE/INACTIVE, git telemetry slices), `aggregate-plans`,
  `run` orchestrator — under `.workspace/scripts/`.
- **Author-scoped:** `git log --author=<git_author>` from `.workspace/config.yml`.
- Plans read from `.workspace/plans/<repo>/daily-plan.md` (per-dev, in the workspace).
- `claude -p` prompts `per-repo` + `polish` shipped as machinery.
- Deliverables: `summary.md` (author-scoped retro) + `daily-plan-summary.md`
  (aggregated plans + "At a glance"); state in `.workspace/state/state.json`;
  archive under `.workspace/state/archive/`.

## Notes
- Reuse project-status's proven code where it transfers; drop the `tracked/` cache
  locally (children are present) but keep the remote sources/pre-clone path.
