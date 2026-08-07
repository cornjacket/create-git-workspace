# 23 — the rollups are a wall of prose, and nothing measures whether they read well

Status: **filed 2026-08-07**, from a direct read of the 08-06 run. Not started.

Both daily artifacts have drifted from "quick summary look" into documents you
have to *study*. `summary.md` is dense, jargon-heavy paragraph-bullets;
`daily-plan-summary.md` is **607 lines**. The point of a morning rollup is that
you skim it in under a minute and know where things stand. Neither one survives
that test.

The second half of this task matters more than the first: **there is no way to
tell whether a change to either one made it better.** Both are re-generated
daily, one of them by a model, and the only quality gate is somebody eventually
noticing it has become unreadable — which is what just happened, days late. A
prompt tweak today is a guess; without a harness the next tweak is also a guess,
and the thing rots back.

## What the reader actually gets

**`summary.md`** — 6 bullets per repo, each 3-5 lines of unbroken prose, carrying
raw internals: `pipefail`/`set -e`, `t_max`, "rip-and-replace cycle", bare task
numbers, inline hash ranges. Comprehensive, and nobody scans it.

**`daily-plan-summary.md`** — the `At a glance` table at the top is *good* and is
the one part that does the job. Everything after it is 590 lines of embedded
plan. Measured on the 08-06 file:

| | lines | share |
|---|---|---|
| total | 608 | — |
| inside `### Notes` sections | 319 | **52%** |

Over half the file is the free-form `Notes` half of each repo's plan — the part
`replan` never rewrites, so it accretes — inlined verbatim, seven times over.

## The finding that decides the approach

**`template/workspace/prompts/per-repo.md` already forbids nearly everything
being complained about.** It says, in its own words:

- "Write for an outsider… does NOT follow this repo daily"
- "Spell out acronyms on first use"
- "briefly say *what it is*" rather than referencing an internal label bare
- "Prefer plain-English descriptions… over the source repo's code identifiers"
- "If a bullet would only make sense to someone who already read the source
  commit messages, rewrite it"

The 08-06 output violates every one of those. So the defect is **not a missing
instruction, and adding more prose rules will not fix it** — the rules are
unenforced assertions about quality with nothing on the other side reading the
result. That is the argument for building the judge first, and it is why this
task refuses to be just a prompt edit.

One rule is worse than unenforced — it pulls the wrong way:

> Bullet list. 1-6 bullets total. **Bias toward fewer, denser bullets** over many
> shallow ones.

Density *is* the complaint. "Fewer" and "denser" are being traded against each
other and the model is taking the second. Whatever replaces it has to bound
length in something countable, not in an adjective.

## Two artifacts, two different machines — do not conflate them

| | `summary.md` | `daily-plan-summary.md` |
|---|---|---|
| written by | `run.py` + `prompts/per-repo.md`, `prompts/polish.md` | `scripts/aggregate-plans.py` |
| non-deterministic? | **yes**, model-generated | no, pure rendering |
| why it is bad | style: dense, esoteric | structure: it embeds whole plans |
| what fixes it | prompt + a judge that can fail | a call about what gets inlined vs linked |

A judge is the right instrument for the first and the wrong one for the second —
grading a deterministic renderer teaches you nothing you could not get by reading
its code. `aggregate-plans.py`'s bloat is a **design decision to re-examine**: a
rollup that inlines every plan in full is a concatenation, not a summary. The
likely shape is that the `At a glance` table plus a short per-repo extract stays,
and the full plan becomes a link to `.workspace/daily-plans/<repo>/daily-plan.md`
— but that call belongs in this task, argued, not assumed here.

## "`project-status` did it better" — find out why before copying

The claim is worth taking seriously and worth *checking*, because the two files
are more alike than expected. Reading the archived
`cornjacket/project-status` `summary.md`, its bullets are about the same length
and carry hashes too. The visible difference is **mechanism, not style**:

- `project-status` appended a **journal**, newest first, one section per day. Each
  day's section covered one day.
- This one holds **the latest run only** (decision from `11`), and a quiet day
  **re-dates** the last real body rather than replacing it. So on 08-06 the
  reader sees a heading dated 08-06 over a body summarizing a multi-day window.

If that is the cause, the fix is about the window, not the wording — and no
amount of prompt editing reaches it. **This is the first question to put to the
harness**, because it is the one place the two systems differ structurally and
the answer changes what gets built. Do not port `project-status`'s journal shape
on nostalgia; `11` retired it for a stated reason (`git log -p summary.md` *is*
the journal) and that reason still holds.

## The harness and judge

**Do not design this from scratch — it is already sketched.**
`customer-req-responder/eval-skill-sketch.md` (132 lines, captured 2026-05-29,
status *deferred*) specifies an LLM-as-judge harness: fixtures → pipeline → judge
grades against a rubric → pass-rate you can track across prompt changes. It
carries the directory shape, the judge-call contract (strict JSON verdicts,
per-dimension PASS/FAIL), the fixture format, and the guardrails. Read it first.
Two of its decisions need revisiting rather than inheriting: it predates this
workspace, and its "lives in a new `ai-skills` repo" placement call refers to a
repo that does not exist on any floor.

What this task supplies is the ~30% the sketch says each project owns:

- **Rubric dimensions.** From the complaint, in priority order: *skimmable*
  (can you get the state in under a minute), *plain* (no unexplained internal
  term, acronym, or bare task/phase number), *length* (a countable budget — words
  per bullet, bullets per repo, lines per file), *faithful* (nothing asserted
  that is not in the input slice — a readability push must not buy brevity with
  invention).
- **Fixtures, and they are free.** Every run ever written is already in
  `git log -p summary.md` and `git log -p daily-plan-summary.md` in each
  workspace — real inputs with real outputs, including the ones that read badly.
  Freeze a set, and keep the 08-06 file in it as a known-bad case.
- **Wiring** to `run.py`'s per-repo/polish calls.

### The judge must be able to fail

A judge that grades everything a pass is worse than no judge, because it launders
the guess into a number. This is [[tests-that-cannot-fail]]'s shape exactly, and
it gets that note's remedy — **break it on purpose**:

- Feed it the 08-06 `summary.md` and a hand-written good version of the same day.
  If it does not separate them, the judge is what is broken. Fix it before
  trusting a single aggregate.
- Hand-check ~20% of verdicts before the pass-rate is used to justify anything
  (the sketch's own guardrail — judges drift and are sycophantic).
- Freeze the fixtures. Changing them invalidates the trend, which is the only
  reason the number exists.

## Sequencing against `18`

[`18`](18-newcomer-blurb-in-plan-summary.md) adds a "What this repo is" line to
every section of `daily-plan-summary.md`. Both tasks are right and they push
opposite ways: `18` makes the file longer, `23` sets the budget `18` spends into.
Doing `18` first means writing the line, then re-deciding where it goes once
sections are restructured. **Do `23`'s structural call for
`daily-plan-summary.md` first**, then land `18` inside the shape that results —
`18`'s own reasoning (project the stored `repos.yml` field, one source of truth)
is unaffected either way.

## Acceptance

- The rubric exists as a checked-in file with its dimensions and thresholds
  stated, including at least one **countable** length budget rather than an
  adjective.
- A frozen fixture set is checked in, drawn from real `git log -p` history, and
  includes the 08-06 run as a known-bad case.
- `make` grows a verb that runs the harness over the fixtures and prints a
  per-dimension pass-rate plus the failing cases.
- **Mutation check, recorded in this file:** the judge scores the 08-06
  `summary.md` below a hand-written good version of the same day. A run where it
  does not is a blocked task, not a passing one.
- ~20% of verdicts hand-checked once, with the disagreement rate written down.
- `prompts/per-repo.md` loses "denser" and gains the countable budget; the
  rewrite is justified by a measured before/after on the fixtures, not by taste.
- `daily-plan-summary.md`'s structural call is made and argued in this file, and
  the resulting file is materially shorter than 607 lines on the same input.
- Dogfooded into `dev-workspace` via `update.sh`, then the real thing read cold
  the next morning. This task is done only if the rollup is genuinely skimmed
  rather than skipped.

## Open questions

- **Where does the harness live?** In this repo (it grades this repo's prompts,
  and `tests/run-tests.sh` is here), or in the shared skill the sketch imagined?
  The sketch's `ai-skills` repo does not exist. Leaning: build it here against
  these two artifacts, and extract it only if a second caller appears — the
  generator that installs workspaces is a defensible home for the thing that
  checks their output. Note the tension with `docs/plans/mail`, which is also
  workspace-scoped: two efforts wanting a home for cross-cutting tooling is
  itself evidence about where it belongs.
- **When does it run?** Every status run costs judge calls on top of summary
  calls. Leaning: on demand and in CI over frozen fixtures, never in the daily
  run — the daily run should not pay to grade itself.
- **Who is the reader?** The prompt says "an outsider", but `summary.md` is
  author-scoped — it is one developer's own work, read mostly by them. If the
  real reader is the author a week later, "outsider" is the wrong target and some
  of the esoterica is legitimate shorthand. Settle this before writing the
  rubric; it decides what *plain* means and it is the one dimension the rubric
  cannot be neutral about.
- **Does the judge grade a whole file or a bullet?** Whole-file catches "too
  long"; per-bullet catches "unexplained term" and localizes the fix. Probably
  both, at different dimensions.
