# 001 — implement setup.sh

Status: todo

Create `setup.sh <target-dir> [--name NAME] [--remote URL]` that stamps out a new
git-workspace from `template/`.

## Acceptance
- Refuses to run over an existing workspace (points to `update.sh`) unless `--force`.
- `git init`s `<target-dir>`.
- Writes **machinery**: `scripts/*` (chmod +x), `template/gitignore` → `.gitignore`,
  rendered `CLAUDE.md` (`{{WORKSPACE_NAME}}` substituted).
- Seeds **content only if missing**: `repos.yml`, `README.md`.
- Does NOT init/create the managed child repos (that's `bootstrap.sh`).
- Prints next steps.

## Notes
- Substitution via `sed`, no template engine.
- Optional: `--remote` → `git remote add origin`.
