# 006 — restructure template into hidden .workspace/ dir

Status: blocked (confirm hidden-dir name first — see PLAN.md open question 1)

Move the emitted machinery under a hidden dir so the generated workspace root
shows only CLAUDE.md / README / child repos.

## Acceptance
- `template/scripts/` → `template/workspace/scripts/`.
- `template/repos.yml` → `template/workspace/repos.yml`.
- Emitted layout: `<target>/.workspace/{scripts,repos.yml}`, `CLAUDE.md` at top.
- Scripts' `WORKSPACE_ROOT` resolves **two levels up** (`../..`), verified by
  `status.sh` run from a generated workspace.
- Emitted allowlist becomes `/*` + `!/.workspace/` + `!/CLAUDE.md` + `!/README.md`.

## Notes
- Name pending: `.workspace/` (recommended) vs `.git-workspace/`. NOT `.git-worktree`.
- Blocks 001/002 finalization (they reference the emitted paths).
