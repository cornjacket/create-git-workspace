# 010 — remote status routine

Status: done (2026-08-02)

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

## What landed
- `.workspace/scripts/daily.sh` — the `/schedule` entry point. Installs PyYAML
  only when missing, falls back to `config.yml`'s `git_author` when the sandbox
  has no git identity (failing at commit time, after all the work, is the worst
  moment to discover that), checks out `auto/status-YYYY-MM-DD`, runs `run.py`,
  commits, pushes.
- `template/github/workflows/{auto-merge-status,claude}.yml` → emitted as
  `.github/workflows/`. Stored without the leading dot in the generator so they
  stay inert there — the same trick as `template/gitignore`.
- Allowlist gained `!/.github/`.
- `config.yml` and the `git_author` hard-fail already landed in `008`.

### Why a side branch
The GitHub App identity a remote routine runs under cannot push to the default
branch, and the failure surfaces as a misleading "non-fast-forward" from the
local git proxy rather than a permission error. `daily.sh` pushes a dated side
branch; the workflow — running as `github-actions[bot]`, which *can* push —
fast-forwards it onto `main` and deletes it. `--ff-only` is deliberate: a merge
commit there would silently interleave a machine rollup with your own work.

### It commits explicit paths, never `git add -A`
`summary.md`, `daily-plan-summary.md`, `.workspace/state/` — and nothing else.
A routine that swept up the working tree would commit your half-finished plan
edits behind your back, on a schedule, while you were not looking. `-B` rather
than `-b` on the branch so a same-day re-run reuses it instead of dying after
the work is done.

## Found while testing: bytecode inside the tracked control plane
Running any status script creates `.workspace/scripts/__pycache__/`, which the
allowlist tracked like everything else under `.workspace/`. Every workspace would
have shown dirty after its first run, and `git add -A` would have committed
bytecode. The emitted `.gitignore` now re-ignores `__pycache__/` and `*.pyc`
*after* the `!` lines (last match wins). §8g asserts the directory exists on disk
and that git neither reports nor tracks it.

## Verified — §8g (150 local / 159 with `--remote`)
Against a local bare remote: both workflows are emitted and tracked; the run
pushes a dated side branch that reaches origin; the commit contains exactly the
four routine-owned paths; a deliberately-left uncommitted plan edit survives as a
working-tree change; the branch fast-forwards onto `main` (so the workflow's
`--ff-only` would succeed); a same-day re-run works.

## Still manual (by design — documented in the README, and in `014`)
Creating the `/schedule` routine, listing every tracked repo as a routine
`source`, and setting `CLAUDE_CODE_OAUTH_TOKEN` for `claude.yml`.
