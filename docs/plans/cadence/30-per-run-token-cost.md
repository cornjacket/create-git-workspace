# 30 — record the token cost of each status run

Status: **filed 2026-11-10**. Not started.

The account moved to the $20 Pro plan. The routine is the one recurring cost, and nothing measures it.

## What to build

1. `run.py`'s `claude_p()` calls plain `claude -p` and returns stdout. Switch it to `--output-format json`. Parse the result text and the `usage` / cost fields.
2. Add up input, output and cache tokens, and cost, per run. Record them per repo and in total.
3. Write the totals to `.workspace/state/` and print one line in `summary.md`, for example: `run cost: 41k in / 3k out · haiku`.
4. Optional: let `config.yml` set the model for the `claude -p` summaries (`--model`).

## Notes

- The cost line goes into `summary.md`, which `rollups` `23` restructures. Build
  this after `23` settles that file's structure, or put the line where `23` can move it.
- The routine's own wrapper turn (Haiku) is not a `claude -p` call. This task
  measures the per-repo summaries only. Say so in the cost line.
- The routine's wrapper model moved from Sonnet to Haiku on 2026-11-10, before this task. There is no Sonnet baseline, so compare Haiku runs against each other, not against Sonnet.

## Steps

1. Build in `template/` with a test that uses a canned JSON response.
2. Bump `VERSION`.
3. **Update the generated workspaces:** run `update.sh` against `dev-workspace` and `personal-workspace`.
