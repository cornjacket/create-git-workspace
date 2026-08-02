# 011 — local morning pull trigger

Status: todo

Bring the remote-generated aggregates down to the local workspace each morning.
The mirror of the remote push routine — closes the push-up / pull-down loop.

## Acceptance
- `.workspace/scripts/pull.sh` — `git pull --ff-only` on the workspace repo.
  - Fast-forward → advance silently.
  - Diverged → **notify and stop** (never force, never auto-merge/rebase).
  - Optional: chain `bootstrap.sh` to materialize any repo added remotely.
- Trigger wiring documented for cron / macOS launchd / Claude Code SessionStart
  hook (ship the script; let the user pick the trigger — PLAN Q9).

## Notes
- `--ff-only` is deliberate: safe for unattended runs. The dev keeps ff clean by
  pushing workspace edits (plans, repos.yml) before the remote routine runs.
