# 002 — implement update.sh

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
- If a normal upgrade ever needs `--force`, the split is wrong — fix the split.
