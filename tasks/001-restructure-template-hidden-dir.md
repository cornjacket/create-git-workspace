# 001 — restructure template into hidden .workspace/ dir

Status: done (2026-08-01) — hidden-dir name resolved to `.workspace/` (PLAN Q1)

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
- Name resolved: `.workspace/`. NOT `.git-worktree`.
- Blocked 002 finalization (it references the emitted paths).
- `lib.sh` now exports **two** roots: `WORKSPACE_DIR` (the hidden control plane,
  one up from `scripts/`) and `WORKSPACE_ROOT` (the workspace, two up).
  `REPOS_YML` hangs off `WORKSPACE_DIR`.
- Verified by hand-stamping a sandbox workspace: root resolves correctly from an
  absolute and a relative invocation, `status.sh` reports a child clean (exit 0),
  `guard.sh` passes, and `git add -A` stages only `.gitignore`, `CLAUDE.md`, and
  `.workspace/**` — the child checkout is ignored by `/*`.
- The allowlist keeps `!/.gitignore` (PLAN's layout listing omits it): `/*` matches
  the `.gitignore` itself, so without the `!` line the allowlist would never be
  committed into a fresh workspace.
