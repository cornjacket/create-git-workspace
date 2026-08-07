# docs/plans — how work is planned here

Four documents, four lifetimes. Keeping them apart is the whole point: the
thing that changes hourly must not live in the thing that outlives the project.

| Doc | Lifetime | Holds |
|---|---|---|
| `DESIGN.md` (repo root) | **durable** | the model, the settled decisions, why things are the way they are |
| `PLAN.md` (repo root) | **permanent** | the **master** — which effort is active, which are queued, in what order. No state of its own |
| `docs/plans/<name>/PLAN.md` | **one effort** | where I left off, the ordered task list, decisions still in flight |
| `docs/plans/<name>/NNN-*.md` | **one task** | the substance and canonical status of a single task |

There are **two sequencing layers**, and they answer different questions.

- A **task system** tracks the *set* of work and its status. It does not say what
  order to do it in.
- An **effort's `PLAN.md`** orders tasks within one effort and defines what "done
  with this effort" means.
- The **master `PLAN.md`** orders the efforts themselves, and lets an effort rest
  in a state that is neither active nor finished.

> **The master holds no state.** Ordered pointers and one line of status per
> effort — no "where I left off", no task tables, no notes. It is the only plan
> document that never archives, which makes it the most exposed to the failure
> described in *"Why not keep everything in `PLAN.md`"* below. Duplicating an
> effort's state here creates a second copy that will disagree with the first.

## Effort states

| State | Means | Lives |
|---|---|---|
| **active** | being worked now. Exactly one at a time | `docs/plans/<name>/` |
| **parked** | complete-in-scope or deliberately deferred, with open follow-ups | `docs/plans/<name>/` |
| **queued** | designed, not started | `docs/plans/<name>/` |
| **archived** | finished, nothing points at it any more | `docs/plans/<name>/` |

Every effort lives in the same place regardless of state. **State is a field the
master owns, not a filesystem location** — moving files to signal status is how
a directory called `archive/` ends up holding two things that are not archives.

**Parking is honest; archiving is final.** Archive only when the scope is met
*and* no open task still names the effort. An effort with live follow-ups that
gets archived is a lie, and one left active to avoid the lie blocks everything
behind it.

## The cycle

1. **Start an effort.** Copy [`../templates/PLAN.md.template`](../templates/PLAN.md.template)
   to `docs/plans/<name>/PLAN.md` and name the effort. Add a row to the master
   and make it the active one. One active effort at a time — the master
   sequences, it does not parallelise.
2. **Write tasks.** Either create `docs/plans/<name>/NNN-slug.md` up front and
   point the plan at them, or draft tasks inline in `PLAN.md` and extract them
   into files once they stop moving. Inline-first is fine for a small effort; a
   task that has grown acceptance criteria and notes wants its own file.
3. **Work it.** `PLAN.md` carries the order and the current state; the task files
   carry the substance and the canonical status. The plan should reference a task
   by number and one line of intent — **not restate it**. Two copies of "done"
   is one too many.
4. **Wrap each session.** `/wrap` rewrites `## Where I left off` — current task,
   next concrete step, files mid-edit, uncommitted work, open questions. It
   writes to the **active effort's** plan, named on the master's
   `**Active effort:**` line — never to the master itself. A repo with no master
   has no such line, and `/wrap` falls back to the repo-root `PLAN.md` as before.
5. **Park or resume.** Change the status in the master's table. Nothing moves on
   disk. Park when the scope is met but follow-ups remain, or when something
   more urgent takes the active slot; note *why* in one line, since a parked
   effort with no stated reason reads as abandoned.
6. **Finish.** Review every task file against `DESIGN.md` and **graduate the
   durable conclusions into it** — what was decided, what it rules out, why. A
   decision left only in a task file is a decision the next effort will
   re-litigate.
7. **Archive.** Slim the effort's `PLAN.md` down to pointers and set its master
   row to `archived`. The files stay where they are; only the status changes.

## What graduates, and where

- **Durable and repo-specific** (a convention, an invariant, a rejected
  alternative) → `DESIGN.md`.
- **Durable and transferable across projects** (a lesson that would help in a
  different repo in six months) → the personal second-brain, as a well-abstracted
  note. Link to the evidence; do not copy it.
- **Execution detail** (what broke, which commit, the exact command) → stays in
  the task file. That is what the archive is for.

## Why not keep everything in `PLAN.md`

Because it accumulates two kinds of content with opposite lifetimes. The genesis
plan reached ~660 lines, most of it settled architecture that had nothing to do
with what to do next — and meanwhile the doc that *should* have held it, a
date-stamped `docs/roadmap-2026-07-31.md`, read as a frozen snapshot nobody
updated. Splitting them is what stops the effort doc from silently becoming the
design doc.

The same argument is why the master holds no state. It is permanent, so it has
no archive event to flush it — anything that accretes there stays forever.

## Efforts

The master [`PLAN.md`](../../PLAN.md) is the live list. This is the directory
index.

- [`rollups/`](rollups/) — readable, trustworthy daily artifacts (2026-08-07 → ).
- [`dogfood/`](dogfood/) — stood up the first workspace, retired `project-status`
  (2026-08-02 → 08-06, parked with follow-ons).
- [`mail/`](mail/) — cross-repo task hand-off (designed 2026-08-06, queued).
- [`genesis/`](genesis/) — built the generator itself (2026-07-31 → 2026-08-02,
  archived).
