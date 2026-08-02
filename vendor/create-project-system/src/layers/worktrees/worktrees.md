# Worktree Definitions

Each task has a `Worktree:` field assigning it to one of the worktrees below.
Tasks in the same worktree touch the same files and should be worked in the same
branch. Tasks in different worktrees can run in parallel with minimal merge
conflicts.

This field is about **parallel-work isolation, not topic.** To group tasks by
what they are *about* — `docs`, `video`, `education` — use `Tags` instead
(`new-user-task.sh --tags`, `set-field.sh --field Tags`, `list-tasks.sh --tag`).

**This is a starter file — replace the example worktree with your own.**

## How it is used

- `new-user-task.sh --worktree <name>` validates `<name>` against the
  **Worktree branch** values declared here. The literal `unclassified` is
  always accepted, for tasks that fit no worktree.
- `list-tasks.sh --worktree <name>` filters by it; `--group-by-worktree` groups
  output in the order worktrees are declared in this file.

## Adding a worktree

Copy the block below. The `**Worktree branch:**` line is the parsed one — its
backticked value is the worktree name. Everything else is prose for humans.

---

## Worktree 1 — General

**Worktree branch:** `general`
**Core files:** _list the files this worktree typically touches_

Starter worktree so `--worktree` works out of the box. Replace this with
worktrees that reflect how your repo actually partitions — group tasks that
touch the same files, so different worktrees can be worked in parallel without
conflicting.

**Tasks:** _optional: list task IDs assigned to this worktree_

---

## Conflict hotspots & merge order

_Once you have several worktrees, note here which files are touched by more than
one worktree, and the recommended merge order._
