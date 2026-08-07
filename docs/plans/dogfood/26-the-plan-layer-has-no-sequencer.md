# 26 — the plan layer has no sequencer, so an unfinished effort blocks every other one

Status: **filed 2026-08-07**, from `mail` sitting parked behind a `dogfood` whose
scope is complete. Not started.

`docs/plans/README.md` step 1 says *one active plan at a time*, and the active
plan is the repo-root `PLAN.md`. There is exactly one slot and no queue. So an
effort that is **finished in scope but carrying follow-ups** can only be
archived — which is a lie while its follow-ups are open — or left in the slot,
where it blocks everything behind it.

That is the current state. `mail` was designed 2026-08-06 and has not started.
It is not blocked on substance: its one blocking open question (single-purpose
file versus shared manifest) was **settled 08-07** in favour of `discovery.json`,
its stated entry point (`create-project-system` task `27`) **landed 08-07**, and
its receiving surface already ships in every repo `create-project-system`
touches. It is blocked on a **slot**, which is a filesystem fact, not a plan.

## What this is not

**This does not make efforts run in parallel, and must not pretend to.**

This repo runs one effort at a time for a real reason: it has **no task system
and no worktrees**. Parallelism lives on the *task* record — `create-project-system`
puts a `Worktree` field on a user-task, validated against `worktrees.md`, so
unrelated work provably touches disjoint files and can run on parallel branches.
`create-ai-builder` runs that live today, with a bare checkout plus `main`,
`regression-infra` and `workspace-mgmt`.

This repo has none of it. It vendors the generator that provides the capability
and does not run it on itself — the same irony `create-project-system` records
about its own tasks being unreadable to the consumer asking for them.

So there are two separable problems and this task owns only the first:

| Problem | Fix | Owner |
|---|---|---|
| An unfinished effort blocks the queue | a sequencer above efforts | **this task** |
| Only one thing can be worked at a time | task system + worktrees in this repo | a separate task |

Conflating them is how this change over-scopes. A master plan with no worktrees
underneath it still runs one effort at a time — it just stops lying about why.

## The change

The repo-root `PLAN.md` stops being *an effort* and becomes **the master**: an
ordered list of efforts, each with a status and a pointer. Every effort then
lives uniformly at `docs/plans/<name>/PLAN.md` beside its task files.

This regularises more than it changes. `mail` **already** has that shape.
`dogfood` is the outlier, with its plan at the root and its tasks in
`docs/plans/dogfood/`. And `docs/plans/README.md` currently calls
`docs/plans/<name>/` the **archive** tier while two of its three directories are
not archives — `dogfood` is active, `mail` is parked. The table describes a
convention the repo already left.

The gain is that **"parked" becomes a legal state.** Today an effort is active or
archived, and there is no honest way to say "complete in scope, follow-ups open,
not being worked."

### The constraint that decides whether this works

**The master carries no state of its own.** Ordered pointers and one line of
status per effort. Nothing else — no "where I left off", no task tables, no
notes.

`docs/plans/README.md` already argues this in *"Why not keep everything in
`PLAN.md`"*: the genesis plan reached ~660 lines because two content lifetimes
accumulated in one file. The master is the most exposed document in the repo to
that failure, because unlike an effort plan it **never archives**.

This repo has been burned by duplicated state twice, both found on 2026-08-07:
`dogfood`'s own header contradicted its task table (stale "current task `21`"
against rows reading **done**), and task `24` exists precisely because the daily
plans and the commits disagree with nothing reconciling them. A master carrying
state would be the third instance, and it would be the one that never gets
archived away.

## `/wrap` is the one real breakage — and worktrees make it worse

`~/.claude/commands/wrap.md` hardcodes *"Update `PLAN.md` in the repo root"* and
rewrites `## Where I left off` there. Under this change it would write session
state into the master, which is exactly what must not happen. It is a **global**
command shared by every repo, so it cannot simply be repointed here.

Smallest fix: the master carries a single machine-findable pointer line naming
the active effort's plan, and `/wrap` follows it when present, falling back to
the repo-root file when absent. That degrades correctly in every repo that has
no master.

**The worktree half is unsolved and should not be guessed at.** `/wrap` today
assumes one repo, one root, one `PLAN.md`. Under worktrees:

- **"Repo root" becomes ambiguous.** `git rev-parse --show-toplevel` returns the
  *worktree's* root, which is right for an effort plan living on that branch and
  wrong for a master that must be global.
- **A wholesale-rewritten shared file is the worst possible file to branch.**
  `/wrap` overwrites `## Where I left off` every session by design. Two branches
  doing that to one file conflict on every merge.
- **This repo already knows the answer one level up.** `CLAUDE.md` forbids a
  `daily-plan.md` here: *"Plans are per-developer intent... A shared plan file in
  a shared repo is a file two people overwrite."* The generalisation is that a
  plan file shared across **parallel units of work** is a file those units
  overwrite — and worktrees are parallel units, exactly as developers are.

That points at a split worth considering rather than adopting blind: the master
is global, single-writer, and edited only from the primary checkout; an effort
plan is local to the branch doing the effort and merges back when it lands. The
cost is a dangling pointer — the master on `main` naming a plan that only exists
on a branch until merge.

An alternative worth weighing before choosing: **derive the master instead of
writing it.** `aggregate-plans.py` already builds `daily-plan-summary.md` from
per-repo plans one level up, and a derived file cannot drift or conflict. The
ordering is the one part that is a genuine input and cannot be derived, so the
hand-owned surface would shrink to a short ordered list. That may be the better
end state; it is more than this task needs.

**Decide the `/wrap` pointer now. Leave the worktree model open** — it is not
blocking, because this repo has no worktrees yet, and settling it properly
belongs with the task that introduces them.

## The `18`/`23`/`24` regrouping

`dogfood` is acting as a holding pen. Its own header concedes the remaining
items are *"follow-on defects, not scope this plan set out with"*, and three of
them are one coherent effort about whether the daily artifacts are readable and
trustworthy:

- **`18`** — the rollup never says what a repo *is*
- **`23`** — both rollups are a wall of prose, and nothing measures them
- **`24`** — nothing reconciles the plans against the commits

They move to a new effort, `rollups`. `17` (commit-schema blank line) and `20`'s
open writer half stay in `dogfood`, which can then close honestly when they land.

**Do not renumber the moved tasks.** `24` references `23` and `18` by number, and
so do a `dev-workspace` task and a second-brain note written the same day.
Inherited numbering is ugly exactly once; a broken cross-reference is ugly
forever.

## Acceptance

- Root `PLAN.md` is the master: efforts, order, status, pointers. **No
  `## Where I left off`, no task table, no notes.** A reviewer can state the
  active effort and the queue in one screen.
- `dogfood`'s plan lives at `docs/plans/dogfood/PLAN.md` beside its task files;
  every effort has the same shape regardless of state.
- `docs/plans/README.md`'s three-lifetime table and cycle are rewritten: the
  third tier is *effort (active | parked | archived)*, not *archive*, and the
  cycle gains park/resume alongside start/finish.
- `docs/plans/rollups/PLAN.md` exists carrying `18`, `23`, `24` at their original
  numbers; `dogfood`'s table no longer claims them.
- `DESIGN.md:6` still describes the layout correctly after the change.
- The master names exactly **one** active effort. If it ever names two, this task
  failed — that is the parallelism it explicitly does not deliver.
- `/wrap`'s pointer convention is written down where a reader of the master will
  find it.

## Open questions

- **Does the master eventually become derived?** See above. Deciding "yes,
  later" is fine; deciding nothing means it accretes by default.
- **Where do loose defects live** that belong to no effort? A master-level queue
  is the obvious home and is also how a master starts growing state. Leaning: an
  effort named for the theme, always — if a defect has no theme, it is not ready
  to be worked.
- **Does this repo adopt its own task system?** Out of scope, but this task is
  the second piece of evidence for it in a week. Without it the master sequences
  efforts that each contain an unordered pile.
