# PLAN — rollups

**Make the daily artifacts readable and trustworthy — and build the thing that
can tell whether a change to them helped.**

Started 2026-08-07, from three tasks that accumulated in `dogfood` without
belonging to it. Task files: `docs/plans/rollups/`. Durable design lives in
`DESIGN.md`; this file is only this effort.

## Where I left off

_Rewritten wholesale by `/wrap` at the end of each session — state, not a log.
Never append a new dated entry; overwrite._

- **current task** — none in flight. Effort still not started.
  Last session (11-12) was off-effort: `dogfood` [`31`](../dogfood/31-marker-is-an-external-contract.md), done and closed.
- **next concrete step** — **`23`**, *judge* half first, before any prompt edit.
  Create the rubric file + frozen fixture set from `git log -p summary.md`;
  freeze the 08-06 run as the known-bad case. Not `24` — it adds ungraded output.
- **files mid-edit** — none.
- **uncommitted / unpushed** — none. Checked 2026-11-12: clean tree, `main` = `origin/main` @ `2467c1f`.
- **open questions** — all four of `23`'s are still open and one of them gates
  the rubric: **who is the reader?** `summary.md` is author-scoped, so if the
  real reader is the author a week later then "outsider" is the wrong target and
  some of the esoterica is legitimate shorthand. Settle it before writing the
  rubric — it decides what *plain* means and it is the one dimension the rubric
  cannot be neutral about.

## Why these three are one effort

Each one is a different way the daily output fails its reader, and they share a
single missing capability: **nothing measures whether any of it is any good.**

- **`18`** — the rollup never says what a repo *is*, so a reader without the
  context cannot use it.
- **`23`** — both artifacts are a wall of prose, and no harness can tell an
  improvement from a regression.
- **`24`** — the plans and the commits disagree, and nothing reconciles them, so
  a reader following the plan redoes finished work.

Fixing any one without the judge from `23` is a guess, and a guess that rots
back. That is the argument for grouping them rather than working them wherever
they happen to sit.

## Scope

**In:** the rubric and its thresholds; the frozen fixture set; the `make` verb
that runs the harness; the `prompts/per-repo.md` rewrite justified by a measured
before/after; the structural call on `daily-plan-summary.md`; the `/whats-next`
skill and the `template/claude/skills/` generalisation it needs; projecting
`repos.yml` descriptions into the rollup.

**Out:** anything that changes *what is collected*. This effort is about the
artifacts' readability and their agreement with reality, not about adding new
telemetry. A new data source is a different effort.

**Out:** grading the daily run in production. `23` leans toward on-demand and CI
over frozen fixtures — the daily run should not pay to grade itself.

## Decisions already made

- **Numbers are inherited from `dogfood`, deliberately not renumbered.** `24`
  references `23` and `18` by number, and so do a `dev-workspace` task and a
  second-brain note written the same day. Inherited numbering is ugly once; a
  broken cross-reference is ugly forever.
- **`18` lands inside `23`'s restructure, not before it.** Recorded in `dogfood`
  before the move and carried here unchanged: adding a per-repo blurb to a file
  whose complaint is that it is too long, before deciding its structure, makes
  the measured problem worse.
- **`24` was built ahead of the judge, knowingly.** The cost is written into
  `24` itself along with two obligations — `23`'s harness must cover the skill's
  output, and until it does the one-line-per-repo budget is the only measurable
  property the skill has.

## Tasks

| # | Task | Status |
|---|---|---|
| 23 | the rollups are a wall of prose, and nothing measures them — [`23`](23-rollups-are-unreadable-and-unmeasured.md) | **filed 08-07** — judge before prompt edit; sequences ahead of `18` |
| 24 | nothing reconciles the plans against the commits — [`24`](24-whats-next-reconciles-plan-against-reality.md) | **filed 08-07** — `/whats-next` skill; ships ungraded by decision |
| 18 | `daily-plan-summary.md` never says what a repo *is* — [`18`](18-newcomer-blurb-in-plan-summary.md) | **filed** — land it *inside* `23`'s restructure |
