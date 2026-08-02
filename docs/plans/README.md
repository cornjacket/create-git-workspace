# docs/plans — how work is planned here

Three documents, three lifetimes. Keeping them apart is the whole point: the
thing that changes hourly must not live in the thing that outlives the project.

| Doc | Lifetime | Holds |
|---|---|---|
| `DESIGN.md` (repo root) | **durable** | the model, the settled decisions, why things are the way they are |
| `PLAN.md` (repo root) | **one effort** | where I left off, the ordered task list, decisions still in flight |
| `docs/plans/<name>/` | **archive** | a finished plan plus its task files |

`PLAN.md` is the **sequencing layer**. A task system tracks the *set* of work and
its status; it does not say what order to do it in, or what "done with this
effort" means. That is this file's job.

## The cycle

1. **Start an effort.** Copy [`../templates/PLAN.md.template`](../templates/PLAN.md.template)
   to `PLAN.md` at the repo root and name the effort. One active plan at a time.
2. **Write tasks.** Either create `docs/plans/<name>/NNN-slug.md` up front and
   point the plan at them, or draft tasks inline in `PLAN.md` and extract them
   into files once they stop moving. Inline-first is fine for a small effort; a
   task that has grown acceptance criteria and notes wants its own file.
3. **Work it.** `PLAN.md` carries the order and the current state; the task files
   carry the substance and the canonical status. The plan should reference a task
   by number and one line of intent — **not restate it**. Two copies of "done"
   is one too many.
4. **Wrap each session.** `/wrap` rewrites `## Where I left off` — current task,
   next concrete step, files mid-edit, uncommitted work, open questions.
5. **Finish.** Review every task file against `DESIGN.md` and **graduate the
   durable conclusions into it** — what was decided, what it rules out, why. A
   decision left only in a task file is a decision the next effort will
   re-litigate.
6. **Archive.** Slim `PLAN.md` down to pointers and move it into
   `docs/plans/<name>/` beside its tasks. The repo root has no `PLAN.md` again
   until the next effort starts.

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

## Archives

- [`genesis/`](genesis/) — built the generator itself (2026-07-31 → 2026-08-02).
