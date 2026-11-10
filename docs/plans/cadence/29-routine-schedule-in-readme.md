# 29 — show the routine's checked schedule in the README roster

Status: **filed 2026-11-10**. Not started.

The README says the routine runs "on a schedule" but never says when. The only way to know is to ask Claude to check the live routine.

## What to build

1. `routine-sync.py --check` already reads the live routine. Also save `cron_expression`, `enabled`, `model` and `next_run_at` into `.workspace/state/routine-check.json`, with the check time.
2. `render-readme.py` prints one line from that cache in the roster block, for example:
   `Mondays 12:43 UTC · haiku · next run 2026-11-17 · checked 2026-11-10`
3. A cron that does not map to a plain phrase prints raw. A disabled routine prints **disabled**. No cache prints "schedule not checked yet".

No hand-typed `schedule:` field: a stored claim is not a checked state (task `20`).

## Steps

1. Extend `routine-sync.py` and `render-readme.py` in `template/`, with tests.
2. Bump `VERSION`.
3. **Update the generated workspaces:** run `update.sh` against `dev-workspace` and `personal-workspace`. Then run `make routine-check` and `make readme` in `dev-workspace`.
