# 003 — implement update.sh

Status: done (2026-08-01) — both open questions resolved (below)

Create `update.sh <target-dir>` that re-applies the generator's **machinery** to
an existing git-workspace without touching user content.

## Acceptance
- Verifies `<target-dir>` is a git-workspace (`scripts/` + `repos.yml` present).
- Overwrites machinery only: `scripts/*`, `.gitignore`, re-rendered `CLAUDE.md`.
- Leaves content untouched: `repos.yml`, `README.md`.
- **Zero-diff property:** on an up-to-date workspace, `update.sh` then `git diff`
  is empty. No `--force` needed for a normal upgrade.

## Notes
- Depends on the machinery/content split in PLAN.md.
- Reuse `lib/generator.sh` verbatim (`install_machinery` + `inject_claude_block`
  + `workspace_name`); do NOT re-render anything locally, or the two scripts
  drift and zero-diff dies.
- **RESOLVED — `generator_version` staleness.** `config.yml` is content, but that
  one key is version telemetry that would lie after every upgrade. `update.sh`
  rewrites **only that line** (`stamp_generator_version`) — the CLAUDE.md hybrid
  rule applied at single-line granularity: the generator owns the key, the user
  owns every other byte. Idempotent, so zero-diff survives. `setup.sh` calls it
  too, so both paths agree.
- **RESOLVED — stale machinery.** `.workspace/scripts/` is **mirrored**: a `*.sh`
  in the workspace with no counterpart in the template is deleted and the removal
  is announced. Otherwise retired scripts linger and every workspace slowly
  accretes a different set. Scoped to `*.sh` directly in that one directory.
- `update.sh` **never commits** — it leaves a reviewable diff. Committing would
  make the acceptance test vacuous.
- If a normal upgrade ever needs `--force`, the split is wrong — fix the split.

## Verified (sandbox, then wiped)
- **Zero-diff (headline):** `setup.sh` → `update.sh` → `git diff` and
  `git status --porcelain` both empty. No `--force` anywhere.
- Machinery is restored: a vandalized `status.sh` comes back byte-exact; a
  planted `retired.sh` is pruned. Those were the *only* two paths in the diff.
- Content survives: hand-edited `repos.yml`, `README.md`, and user directives
  appended below the CLAUDE.md markers all intact.
- Runtime survives: `.workspace/state/state.json` and `summary.md` untouched.
- Version bump propagates and then settles: `VERSION` 0.1.0 → 0.2.0 moves exactly
  two lines (the `config.yml` key + the CLAUDE.md echo); the next `update.sh` is
  a zero diff.
- Rename-safe: `mv ws1 renamed-dir` then update keeps the name `ws1` recovered
  from `config.yml` — CLAUDE.md is not rewritten to the new directory name.
- Refuses a non-workspace directory (points at `setup.sh`) and a missing path.
