# 010 — remote status routine

Status: todo

The push side of the daily loop — the Claude `/schedule` routine that generates
the aggregates on a schedule. Folded from project-status.

## Acceptance
- Emit `.workspace/scripts/daily.sh` (side-branch push: `auto/status-YYYY-MM-DD`
  → `run` → push).
- Emit `.github/workflows/auto-merge-status.yml` (ff-merge the side branch to main
  — works around "GitHub App can't push to the default branch") + `claude.yml`.
- Emit `.workspace/config.yml` (name, git_author, generator_version).
- `git_author` enforced at run (hard-fail on placeholder).

## Manual step (documented in the status guide, task 014)
- Create the `/schedule` routine pointing at `daily.sh`; declare every tracked
  repo as a routine `source` (sandbox pre-clone).

## Notes
- Remote sandbox still fetches children via `sources`; local runs skip that
  (children already present).
