# PLAN — master

**The sequencer for this repo's efforts. Which one is active, which are queued,
and in what order.**

<!-- This file holds NO state. No "where I left off", no task tables, no notes.
     Each effort's own PLAN.md is the single place its state lives; duplicating
     any of it here creates a second copy that will disagree. See
     docs/plans/README.md, and task 26 for why this file exists. -->

**Active effort:** [`docs/plans/dispatch/PLAN.md`](docs/plans/dispatch/PLAN.md)

<!-- /wrap: write session state to the plan named on the "Active effort" line
     above, never to this file. Repos with no master have no such line, and
     /wrap falls back to the repo-root PLAN.md as before. -->

## Efforts

One active at a time. `parked` means complete-in-scope or deliberately deferred,
not abandoned — it is a legal resting state, which is the whole reason this file
exists.

| Effort | Status | What it is |
|---|---|---|
| [`rollups`](docs/plans/rollups/PLAN.md) | **parked** | make the daily artifacts readable and trustworthy — tasks `18`, `23`, `24`. Parked 2026-11-12: never started, and `23`'s rubric waits on "who is the reader?" |
| [`dogfood`](docs/plans/dogfood/PLAN.md) | **parked** | stood up the first workspace and retired `project-status`. Scope met 08-06; `17`, `20`-writer, `26` remain as follow-ons. `12` and `25` are driven under `dispatch` |
| [`cadence`](docs/plans/cadence/PLAN.md) | **queued** | weekly cadence on the $20 plan: cadence-neutral names, schedule in the README, per-run token cost — tasks `28`, `29`, `30` |
| [`proposals`](docs/plans/proposals/PLAN.md) | **queued** | the workspace leader keeps ideas as proposals and hands a ready one to the target repo, which creates its own task |
| [`dispatch`](docs/plans/dispatch/PLAN.md) | **active** | the leader starts a background agent on a task in a registered worktree and relays its status and questions. Drives `dogfood` `12` and `25` first; task `006` still needs `proposals` |
| [`mail`](docs/plans/mail/PLAN.md) | superseded | one repo files a task into another repo's inbox. Superseded 2026-10-22 by [`proposals`](docs/plans/proposals/PLAN.md) and [`dispatch`](docs/plans/dispatch/PLAN.md) |
| [`genesis`](docs/plans/genesis/PLAN.md) | archived | built the generator itself (2026-07-31 → 08-02) |

## Order, and why

1. **`dispatch`** — active, promoted 2026-11-12. It opens on `dogfood` `12` (the
   worktree lifecycle verb) and `25` phase 1 (divergence measurement), both
   pulled into this effort on the same day. Neither needs `proposals`, so the
   effort has real work from the first session.
2. **`proposals`** — before `dispatch`'s `006`, not before the effort. Hand-over
   ships the leader skill that work start joins, so `006` cannot close until it
   lands. It needs nothing from `dogfood` and gates neither `12` nor `25`.
3. **`rollups`** — parked, not abandoned. It owns the judge that grades
   model-generated daily output, so everything downstream of it stays
   unmeasurable until it lands, and it already carries a task (`24`) built ahead
   of that judge. Resume it once `23`'s reader question has an answer.
4. **`dogfood`'s remainder** — `17` is one edit across four copies of the commit
   schema and can be taken at any time. `20`'s writer half and `26` are larger
   and unsequenced against each other. `12` and `25` have left this bucket.

## Rules

- **One active effort.** This file sequences; it does not parallelise. Working
  two efforts at once needs a task system with a `Worktree` field and worktrees
  to back it, which this repo does not have — see task `26`, "What this is not".
- **Parking is honest, archiving is final.** Archive only when a plan's scope is
  met *and* nothing is left pointing at it. `dogfood` is parked, not archived,
  because open tasks still live in it — `17`, `20`'s writer half and `26`, plus
  `12` and `25`, whose files stay here while `dispatch` drives them.
- **State lives in the effort, never here.** Adding a status line to this table
  is fine. Adding a sentence about what happened is how this file starts
  becoming the thing `docs/plans/README.md` warns about.
