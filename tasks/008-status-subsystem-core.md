# 008 — status subsystem core

Status: done (2026-08-01)

Fold project-status's tracking engine into the workspace machinery. See PLAN.md
"Status subsystem".

## Acceptance
- `sync` (local: no-op — children already present; remote routine: pre-cloned sources),
  `new-work` (classify ACTIVE/INACTIVE, git telemetry slices), `aggregate-plans`,
  `run` orchestrator — under `.workspace/scripts/`.
- **Author-scoped:** `git log --author=<git_author>` from `.workspace/config.yml`.
- Plans read from `.workspace/plans/<repo>/daily-plan.md` (per-dev, in the workspace).
- `claude -p` prompts `per-repo` + `polish` shipped as machinery.
- Deliverables: `summary.md` (author-scoped retro) + `daily-plan-summary.md`
  (aggregated plans + "At a glance"); state in `.workspace/state/state.json`;
  archive under `.workspace/state/archive/`.

## Notes
- Reuse project-status's proven code where it transfers; drop the `tracked/` cache
  locally (children are present) but keep the remote sources/pre-clone path.

## What landed — `.workspace/scripts/*.py` + `.workspace/prompts/`
Ported from project-status's `tools/`, not rewritten: the commit-message parser,
the telemetry format, the freshness rules, and the "At a glance" table are proven
and came across close to verbatim.

- `_status_lib.py` — config, membership, state, git telemetry, `gather_report`.
- `sync.py` · `new-work.py` · `aggregate-plans.py` · `run.py` (orchestrator).
- `prompts/per-repo.md` + `prompts/polish.md` — machinery: the prompt wording is
  the generator's and must upgrade with the code that fills it in.
- `make new-work | run | run-dry | aggregate`; `repos.yml` documents the three
  status flags (`enabled`, `report_inactivity`, `priority`).

### Four structural changes from project-status
1. **No `tracked/` cache locally.** The children are already checked out beside
   the workspace, so the run reads them in place. The `tracked/` clone existed
   only because project-status had no checkouts of its own. The remote path is
   unchanged — the sandbox still uses the platform's pre-cloned `sources`.
2. **Author-scoped everything.** Every git read filters `--author` from
   `config.yml`. `git diff --stat` cannot be author-filtered at all, so file
   stats are summed from `git log --numstat` over your commits only.
3. **ACTIVE means "you committed", not "the repo moved".** A repo a teammate
   advanced reads INACTIVE *for you*, while `state.json` still stores the real
   HEAD so tomorrow's window stays correct.
4. **Plans read from `.workspace/plans/`**, and `_workspace` is aggregated first,
   exempt from the priority sort — honoring `007`'s ordering contract.

### Hard-fail on an unresolved author (by design)
A placeholder `git_author` produces a *plausible-looking empty* rollup rather
than an error — "you did nothing today" instead of "this is misconfigured". The
run refuses to start instead, at the very top of `main()` before any work.

### Two bugs found by running it
- **Embedded plan headings collided with the aggregator's own.** A plan's
  `## In progress` sat beside the `## <repo>` section instead of under it,
  flattening the document. Bodies are now demoted one level on embed (capped h6).
- `install_machinery` only copied `*.sh`, so no `.py` would have shipped. It now
  mirrors the whole scripts tree plus `prompts/`, pruning stale files in both.

## Verified — §8d + §8e (117 local / 126 with `--remote`)
Fixture: a child repo with two commits by the test author and one by a teammate.
- The teammate's commit **and** the file it touched are absent from the report.
- `[Context]`/`[Impact]` telemetry is parsed; `run --dry-run` writes both
  deliverables, the archive snapshot, and advances `state.json`; the window then
  reports INACTIVE, and a teammate's later commit does not revive it.
- Placeholder author hard-fails; `enabled: false` drops the repo.
- Aggregation: workspace row and section first, focus bullet and linkified URL in
  the table, embedded headings demoted, stale flagged, missing reported.
- The deliverables are **runtime**: `update.sh` leaves them untouched.
