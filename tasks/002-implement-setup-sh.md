# 002 — implement setup.sh

Status: todo

Create `setup.sh <target-dir> [--name NAME] [--author EMAIL] [--remote URL] [--no-tasks] [--no-status]`
that stamps out a new git-workspace from `template/`. Full-featured by default.

## Acceptance
- Refuses to run over an existing workspace (has `.workspace/`) unless `--force`
  (points to `update.sh`).
- `git init`s `<target-dir>`.
- **Machinery:** `template/workspace/scripts/` → `.workspace/scripts/` (chmod +x);
  `template/gitignore` → `.gitignore`; emit the `Makefile` command surface.
- **CLAUDE.md:** create-or-inject the managed block (`{{WORKSPACE_NAME}}` substituted);
  never overwrite a user's file (append if no markers).
- **Content (seed if missing):** `.workspace/repos.yml`; `.workspace/config.yml`
  (name + `git_author`, resolved `--author` → `git config user.email` →
  placeholder + warn); a starter `README.md` linking `summary.md` /
  `daily-plan-summary.md`.
- **Tasks (default):** run the vendored `create-project-system`
  (`--tasks-dir project/tasks --with-skill --with-status`) unless `--no-tasks`.
- `--remote` → `git remote add origin`. Does NOT init/create child repos
  (that's `bootstrap.sh`).
- Prints next steps + the two manual routine-setup reminders.

## Notes
- Plain copy + `sed`; use a **non-`/` delimiter** for values that contain `/`
  (e.g. a remote URL).
