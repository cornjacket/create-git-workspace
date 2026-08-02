# 009 — add-repo / delete-repo / mute-repo

Status: todo

Workspace verbs that edit `.workspace/repos.yml`, under `.workspace/scripts/`.

## Acceptance
- `add-repo <url> [--branch b] [--priority n]` — append entry; clone into the
  workspace; inject the commit kernel into the child's `CLAUDE.md` (task 012).
- `delete-repo <name>` — remove the entry; if it also removes the checkout, it
  **refuses on a dirty or unpushed child** (reuse `status.sh`/`guard.sh`).
- `mute-repo <name> [--skip]` — default sets `report_inactivity: false` (keep
  tracked, hide on quiet days); `--skip` sets `enabled: false` (skip entirely).
- All three preserve YAML comments/ordering as much as practical.

## Notes
- Schema gains `priority`, `enabled`, `report_inactivity` (from project-status).
