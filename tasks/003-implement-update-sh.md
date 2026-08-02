# 003 — implement update.sh

Status: todo

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
- **Open (raised in 002):** `generator_version` lives in `.workspace/config.yml`,
  which is *content* ("leave untouched"), so after an update the canonical stamp
  lies. Proposed fix: `update.sh` rewrites that one generator-owned key in place
  — the CLAUDE.md hybrid pattern applied to a single line. Idempotent, so
  zero-diff survives. Decide before implementing.
- **Also open:** stale machinery. If a script is dropped from the template, a
  copy-each-file update leaves the old one behind. Mirror `.workspace/scripts/`
  (delete extras) or accept the drift.
- If a normal upgrade ever needs `--force`, the split is wrong — fix the split.
