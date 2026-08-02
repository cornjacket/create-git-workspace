# 005 — test harness

Status: todo

Exercise generation against throwaway targets only.

## Acceptance
- Generates test workspaces into `sandbox/` (gitignored) — never a real repo.
- **Zero-diff regeneration:** `setup.sh sandbox/ws1` then `update.sh sandbox/ws1`
  → `git diff` is empty.
- Asserts emitted tree + allowlist: `.workspace/scripts/*`, `.workspace/repos.yml`,
  top-level `CLAUDE.md`, `.gitignore`.
- Remote round-trip: `setup.sh sandbox/ws2 --remote git@github.com:cornjacket/git-workspace-test.git`,
  push, `bootstrap.sh` a sample `repos.yml`, `status.sh` clean.
- Teardown: wipe `sandbox/`, delete the `git-workspace-test` remote.

## Notes
- `git-workspace-test` is a disposable remote (assumption in PLAN.md, confirm).
- Applies the hygiene rule: scratch in a gitignored `sandbox/`.
