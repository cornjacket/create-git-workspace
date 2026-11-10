# 28 — rename "daily" machinery to cadence-neutral names

Status: **filed 2026-11-10**. Not started.

The routine now runs weekly, but the names still say "daily". Rename:

| Now | New |
|---|---|
| `.workspace/scripts/daily.sh` | open question — see `PLAN.md`. Not `update.sh`: that names the generator's refresh script |
| `.workspace/daily-plans/<repo>/daily-plan.md` | `.workspace/current-plans/<repo>/current-plan.md` |
| plan header `# Daily plan — YYYY-MM-DD` | `# Plan — YYYY-MM-DD` |
| `daily-plan-summary.md` | `current-plan-summary.md` |
| commit `status(<date>): daily rollup` | `status(<date>): rollup` |

Plans do **not** live in child repos. Since the per-developer move, each plan
lives in the workspace at `.workspace/daily-plans/<repo>/daily-plan.md`. No child
repo has a root `daily-plan.md`. The umbrella `CLAUDE.md` still says "each repo
keeps a root `daily-plan.md`" — that line is already wrong, before any rename.

## Risks

- **The live routine prompt names `daily.sh`, and `update.sh` deletes it.**
  `lib/generator.sh` removes every script that is not in the template. Ship
  `daily.sh` as a shim that calls the new script. Update the routine prompt (via
  `RemoteTrigger`) before any release that drops the shim reaches a workspace.
- **Plan files are user-owned, so `update.sh` will not move them.** It will also
  seed a new `.workspace/current-plans/_workspace/current-plan.md` beside the old
  directory. Each workspace needs an explicit `git mv` of `.workspace/daily-plans/`.
- **The plan header is parsed.** `aggregate-plans.py` (`PLAN_HEADER_RE`) only
  matches `# Daily plan — <date>`. A header rename without a dual-format parser
  marks every existing plan "unparseable". `replan.sh` and the seed template
  write the header too.
- **The `.gitignore` allowlist names `daily-plan-summary.md`.** Without
  `!/current-plan-summary.md`, the routine writes the new summary and git ignores it.
- **The commit kernel is in every child repo.** `commit-kernel.md` names
  `.workspace/daily-plans/<repo>/daily-plan.md`. `inject-kernel.py` writes it into
  each child's `CLAUDE.md`, so the rename lands as one commit per child repo.
- **The stale-plan flag is already wrong for weekly runs.** A plan is fresh only
  if dated on or after the most recent weekday. A weekly run flags every plan
  older than one weekday. Widen it to "on or after the previous run". Take the
  previous run from git (the last `status(...)` commit) — not from a config field.

## Steps

1. Rename in `template/`. Keep a `daily.sh` shim. Make `aggregate-plans.py` read
   both directory names and both header formats.
2. Update `.gitignore`, `Makefile`, `replan.sh`, `commit-kernel.md`,
   `status-guide.md`, the `workspace-status` skill, both READMEs, `setup.sh`,
   `update.sh` seeding, and the tests.
3. Widen the stale-plan flag to the previous run.
4. Bump `VERSION`.
5. **Update the generated workspaces:** run `update.sh` against `dev-workspace`
   and `personal-workspace`. In each, `git mv` the plan directory and files.
   Re-inject the kernel into each child repo. Fix the umbrella `CLAUDE.md`.
6. Update the routine prompt to the new script. Remove the shim in the next release.
