# PLAN — master

**The sequencer for this repo's efforts. Which one is active, which are queued,
and in what order.**

<!-- This file holds NO state. No "where I left off", no task tables, no notes.
     Each effort's own PLAN.md is the single place its state lives; duplicating
     any of it here creates a second copy that will disagree. See
     docs/plans/README.md, and task 26 for why this file exists. -->

**Active effort:** [`docs/plans/rollups/PLAN.md`](docs/plans/rollups/PLAN.md)

<!-- /wrap: write session state to the plan named on the "Active effort" line
     above, never to this file. Repos with no master have no such line, and
     /wrap falls back to the repo-root PLAN.md as before. -->

## Efforts

One active at a time. `parked` means complete-in-scope or deliberately deferred,
not abandoned — it is a legal resting state, which is the whole reason this file
exists.

| Effort | Status | What it is |
|---|---|---|
| [`rollups`](docs/plans/rollups/PLAN.md) | **active** | make the daily artifacts readable and trustworthy — tasks `18`, `23`, `24` |
| [`dogfood`](docs/plans/dogfood/PLAN.md) | **parked** | stood up the first workspace and retired `project-status`. Scope met 08-06; `17`, `20`-writer, `25`, `26` remain as follow-ons |
| [`mail`](docs/plans/mail/PLAN.md) | **queued** | one repo files a task into another repo's inbox. Unblocked in substance since 08-07 — was waiting only on a slot |
| [`genesis`](docs/plans/genesis/PLAN.md) | archived | built the generator itself (2026-07-31 → 08-02) |

## Order, and why

1. **`rollups`** — active. It owns the judge that grades model-generated daily
   output. Everything downstream of it stays unmeasurable until it lands, and it
   is already carrying a task (`24`) built ahead of that judge.
2. **`mail`** — next. Cross-repo hand-offs are currently done by hand and by
   memory; its blocking design question was settled 08-07 and its entry point
   (`create-project-system` `27`) landed the same day.
3. **`dogfood`'s remainder** — `17` is one edit across four copies of the commit
   schema and can be taken at any time. `20`'s writer half, `25` and `26` are
   larger and unsequenced against each other.

## Rules

- **One active effort.** This file sequences; it does not parallelise. Working
  two efforts at once needs a task system with a `Worktree` field and worktrees
  to back it, which this repo does not have — see task `26`, "What this is not".
- **Parking is honest, archiving is final.** Archive only when a plan's scope is
  met *and* nothing is left pointing at it. `dogfood` is parked, not archived,
  because four tasks still name it.
- **State lives in the effort, never here.** Adding a status line to this table
  is fine. Adding a sentence about what happened is how this file starts
  becoming the thing `docs/plans/README.md` warns about.
