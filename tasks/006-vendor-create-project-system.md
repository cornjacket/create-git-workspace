# 006 — vendor create-project-system

Status: done (2026-08-01)

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

## What landed
- `vendor/create-project-system/` — `generate.sh` + `src/` only (42 files),
  byte-identical to upstream `v0.1.0-2-gaa757cf`. No `daily-plan.md`,
  `.claude/hooks/`, `.github/`, `tests/`, or `tasks/` came across.
- `vendor/README.md` — the stamp (source, version, SHA, date), why only those two
  paths, the kernel boundary, and the re-vendor step.
- `tools/revendor.sh` — copies the two paths and rewrites the stamp. **Refuses a
  dirty source checkout**: a stamp naming a commit that does not describe what was
  copied defeats the only thing the stamp is for. (Confirmed live — it declined
  the upstream checkout, which has uncommitted work.)
- `install_task_system` in `lib/generator.sh`, called by BOTH setup and update, so
  the delegated generator is invoked identically from either path. Runs
  `--tasks-dir project/tasks --with-skill --with-status --inject-claude-md`.
- Allowlist gained `!/project/` and `!/.claude/` — without them the whole
  task-system installed but was invisible to git.
- **Interface correction:** the calls stubbed in 002/003 used a positional target;
  `generate.sh` takes `--target-repo <path>`. They would have failed on contact.

## Two bugs the suite caught
- **`install_task_system` returning 1 when the vendor is missing aborted
  `setup.sh` mid-stamp** (callers run under `set -e`), leaving a half-built
  workspace with no initial commit. A missing vendor means "no task-system",
  which `--no-tasks` produces legitimately — so it warns and returns 0.
- The harness's tree assertions compared against a raw `git ls-files`, which now
  includes 39 delegated files. Added `ours()`, which filters `project/`,
  `.claude/`, and the runtime deliverables: pinning upstream's exact file list
  would turn a re-vendor into a spurious regression.

## Verified — §8b of the suite (77 local / 86 with `--remote`)
- `project/` + `project/tasks` + `project/status` + `.claude/skills/task-system`
  all installed and tracked; nothing left untracked.
- **Zero-diff holds WITH the task-system installed** — the delegation risk.
- Both CLAUDE.md kernels coexist, exactly once each, before and after update.
- A real task created via `new-user-task.sh` survives `update.sh`.
- `--no-tasks` installs nothing, and `update.sh` does not add it later — update
  upgrades what is installed, it never adds a subsystem the user declined.
