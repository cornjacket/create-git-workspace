# 013 — status-pipeline tests

Status: done (2026-08-02)

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

## Most of the acceptance already existed
Classification, author-scoped `git log`, aggregation + "At a glance" ordering,
`state.json` advance, and summary insertion landed with `008` (§8d/§8e), and
`pull.sh`'s ff-only behavior with `011` (§8h). What none of them touched is the
code path `--dry-run` *skips*: prompt rendering and the decision to call the
model at all. That is what `013` adds.

## §8j — a stub `claude` first on PATH
The stub records every prompt it is handed and answers deterministically, so the
real `run.py` path runs end to end with no network and no non-determinism.
`CLAUDE_STUB_FAIL=1` makes it exit non-zero on demand.

- **Prompt boundary:** no `{{PLACEHOLDER}}` survives into any prompt; the slice
  carries real commit telemetry including the `[Context]`/`[Impact]` lines; the
  polish prompt gets the workspace name.
- **Author scoping holds at the prompt boundary** — a teammate's commit must
  never be handed to the model as this developer's work. §8d proved it in the
  report; this proves it in what actually reaches the LLM.
- **The polish call is conditional:** two active repos → 3 calls (2 per-repo +
  polish); one active repo → 1 call, because there is nothing cross-repo to
  merge and a second call would be waste. `--dry-run` → 0 calls.
- **An idle repo costs nothing:** the "No updates" block is deterministic, with
  no model call.
- **Failure is atomic-ish:** a failing model call aborts the run, leaves
  `summary.md` untouched, and — the part that matters — does **not** advance the
  commit window. State advancing past work that was never summarized would make
  the next run skip it, and that day would vanish from the record silently. A
  retry after the failure picks the same work back up.

## Out of scope, as planned
The live `claude -p` prose. It is non-deterministic and asserting on it would
buy noise. The remote routine end-to-end stays a manual exercise against
`git-workspace-test` (§10).

## Verified — 195 local / 204 with `--remote`

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `013` — status-pipeline tests (`claude -p` stubbed). *(§8j drives the real prompt path with a stub `claude` on PATH — the code `--dry-run` skips.)*
