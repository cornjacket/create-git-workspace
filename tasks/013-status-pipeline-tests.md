# 013 — status-pipeline tests

Status: todo

Test the deterministic status layer, not just the wrapper mechanics. Mirrors
project-status's approach: stub the `claude -p` calls, assert on everything
around them.

## Acceptance
- `claude -p` **stubbed** (deterministic placeholders, à la project-status `--dry-run`).
- Covers: repo classification (ACTIVE/INACTIVE/…), **author-scoped** `git log
  --author`, plan aggregation + "At a glance" ordering, `state.json` advance,
  summary insertion.
- `pull.sh` ff-only behavior: fast-forwards when clean; **notifies and stops** on
  divergence (never force).
- Runs against `sandbox/` fixtures (ephemeral); the live `claude -p` prose is out
  of scope (non-deterministic, not worth asserting).

## Notes
- Complements task 005 (wrapper determinism + remote round-trip). This task is the
  status-subsystem's deterministic-layer coverage.
- The remote routine end-to-end is exercised manually against `git-workspace-test`.
