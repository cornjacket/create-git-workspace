# 24 — `/whats-next`: nothing reconciles what was planned against what happened

Status: **filed 2026-08-07**, from a session that did the reconciliation by hand.
Not started.

The workspace emits two daily artifacts and they answer two different questions.
`summary.md` says **what happened** — commits, per repo, interpreted.
`daily-plan-summary.md` says **what was intended** — each repo's plan, aggregated.
Both are generated fresh every morning. **Nothing compares them**, and the
comparison is where the answer lives.

## The evidence, from the day this was filed

The 2026-08-07 plans were redrafted in `a92f0c4` and named two things as the
work that mattered most: agree `discovery.json` between `create-project-system`
`28` and `create-context-hygiene` `13`, and `/wrap` this repo's `PLAN.md`
because its header contradicted its own task table.

Both landed the same day. The `discovery.json` design was settled across three
repos; `PLAN.md` was reconciled in `63af017`. `create-project-system` also cut
`v0.2.0`, closing a plan item carried since 08-02.

**Every one of those plan files still said to do them.** A reader who opened
`daily-plan-summary.md` the next morning and worked top-down would have started
by redoing finished work — not because any artifact was wrong, but because plans
are written in the morning, work happens after, and no artifact closes the loop.

This is not a prose problem. Making both files perfectly skimmable (task `23`)
would not have caught a single one of those three staleness cases. It is a
missing comparison, and it is the third instance of this repo's recurring shape:
the system drops something and still looks successful.

## Why a skill and not a `make` verb

`make new-work` already shows new commits per repo since the last status run.
It cannot do this job, and no deterministic verb can.

Deciding that a plan item is *satisfied* by a commit is a judgment call. "Design
`27` and `28` in one sitting" is discharged by commits titled `tasks(27): capture
the machine-readable task interface downstream is asking for` and
`tasks(28): the manifest is shared — own your keys, never the file`. No string
match connects those. Reading the plan's intent against the commit's claim is
exactly the work a model does and a script cannot, which is why this ships as a
skill rather than a target.

The corollary is that the output is **model-generated prose**, with everything
that implies — see "The cost we are accepting" below.

## What it emits

Two sections, in this order, plus a flag.

1. **What moved** — per repo, what actually landed since the plans were written.
   Sourced from `summary.md` where a run exists, so improvements to that file
   flow through instead of being re-derived in a second place.
2. **Revised next task per project** — one line per repo. The repo's own next
   action, restated in light of what moved. Explicitly *revised*: where the
   plan's answer still stands, say so and say it is unchanged.
3. **Stale-plan flag** — name every plan whose stated next action already
   landed. This is the finding that justifies the whole skill; it must be
   impossible to miss, not buried in a per-repo line.

One line per repo in section 2 is a hard budget, not a target. The failure mode
this skill exists to fix is a reader who does not finish the document.

## Where it ships

`template/claude/skills/whats-next/SKILL.md`, installed into every generated
workspace at `.claude/skills/whats-next/` — the same path and mechanism as
`workspace-status`.

**This needs a generalization first.** `lib/generator.sh:162-178` hardcodes
`workspace-status` in three places: the `mkdir -p`, the render loop, and the
stale-file prune that deletes anything in the target not present in the template.
Adding a second skill by copying that block gives two near-identical blocks that
will drift. Loop over `template/claude/skills/*/` instead, and keep the prune
semantics per-skill — a skill directory removed from the template should still
disappear from targets.

Because it is generated into *every* workspace, the skill must be
**workspace-agnostic**: it may not name a repo, a developer, or a generator
version. Same constraint the commit kernel carries, for the same reason.

## The cost we are accepting

This was filed with a decision already made: **build it ahead of `23`, not after.**

Task `23`'s second half establishes that nothing measures whether either rollup
reads well, and that a model-generated daily artifact rots back without a
harness. This skill is a third model-generated artifact and inherits that problem
whole. Building it first means shipping something with no way to tell whether a
prompt change improved or degraded it — the exact position `23` was filed to end.

That is the accepted trade, recorded here so it is a decision rather than an
oversight. Two consequences follow, and they are obligations, not suggestions:

- **`23`'s harness must cover this skill's output when it is built.** Not a
  fourth bespoke checker. Add its fixtures to the same frozen set.
- **Until then, the one-line-per-repo budget in section 2 is the only
  measurable property this thing has.** Keep it countable and enforce it by
  reading the output, because nothing else will.

The related failure is written up in the second-brain as `tests-that-cannot-fail`
— an artifact nobody can grade and a test that cannot go red are the same shape.

## Acceptance

- `template/claude/skills/whats-next/SKILL.md` exists and renders into a target
  workspace through `generate.sh`.
- `lib/generator.sh` installs skills by **looping over `template/claude/skills/*/`**,
  with no skill named literally in the install or prune paths. Verified by adding
  a throwaway second skill directory and confirming it installs and then prunes
  when removed.
- The golden test covers a workspace with two skills installed.
- Output holds to **one line per repo** in the revised-next-task section, on a
  roster of at least seven.
- **Replays the 2026-08-07 case.** Run against that day's plans and commits, it
  flags `create-project-system`, `create-git-workspace` and
  `create-context-hygiene` as having stale next-actions. A run that misses any of
  the three is a blocked task, not a passing one — this is the case the skill was
  filed from and the closest thing to a mutation check available before `23`.
- Dogfooded into `dev-workspace` via `update.sh` and read cold the following
  morning.

## Open questions

- **Does it read `summary.md`, or `git log` directly?** Reading the rollup keeps
  one interpretation of the day and inherits `23`'s improvements. Reading git
  directly makes the skill work when the routine has not run, on demand, mid-day
  — which is when a reconciliation is most useful. Leaning: git directly for
  *what moved*, with `summary.md` as prose input where it exists. Decide before
  writing the prompt; it changes what the skill can promise.
- **What is "since"?** Since the plan was written, since the last status run, or
  since the last time this skill ran. These differ, and the third needs state
  this skill does not have. Leaning: since the plan's own date, since that is
  what makes the staleness claim well-defined.
- **Does it write a file or only speak?** A file is diffable and reviewable and
  becomes a third artifact to maintain and grade. Speaking-only keeps it a
  reading aid with no upkeep. Leaning: speak only, at least until `23` lands —
  fewer ungraded generated files is the whole point of the paragraph above.
- **Does it supersede part of `18`?** `18` projects the `repos.yml` description
  into the rollup so a newcomer learns what a repo *is*. This skill has the same
  newcomer problem in its per-repo lines. Check before building `18` separately.
- **Should it cover every workspace or one?** A developer with `dev-workspace`
  and `personal-workspace` wants one read, not two. Out of scope here, but the
  skill should not make it harder.
