---
name: task-system
description: Create, plan, progress, or close tasks and subtasks in this repo's Markdown task system. Use whenever work is being tracked as a task — creating a task or subtask, listing what's outstanding or next, marking something complete, reordering subtasks, or moving a task between status folders (draft/backlog/in-progress/complete).
---

# Task system

This repo tracks work in a filesystem-native Markdown task system: every task is
a directory with a `README.md`, managed **only** through the scripts in
`{{TASKS_REL}}/scripts/` (run from the repo root).

## Before doing anything

**Read `{{TASKS_REL}}/docs/USING.md`** (path is relative to the repo root) — it
is the single source of truth for this system: task types, the `NNNN` ordering
contract, the status model, the full command reference, and the operating rules.
This skill deliberately does not restate it, so there is exactly one copy to keep
correct.

## The one rule that matters most

**Use the scripts. Never hand-edit task `README.md` files to add or remove
subtasks, never create task directories with `mkdir`/`cat`/heredocs, and never
move task directories between status folders by hand.** The scripts keep the
filesystem and the READMEs in sync — manual edits silently desynchronise them.
Use an editor only to fill in prose sections (Goal, Context, Notes) *after* a
script has created the file.

## Orientation

```
{{TASKS_REL}}/
    <epic>/{inbox,draft,backlog,in-progress,complete,wont-do}/
    scripts/     # all task management commands
    docs/        # USING.md (how to operate) + README.md (format reference)
```

Start with `list-tasks.sh --folder <status> --depth 2` to see where things stand,
then consult `USING.md` for the command you need.

If a `status/` sibling exists, this repo also keeps periodic status reports; read
the most recent one to pick up context, and see the **Status reports** section of
`USING.md` for the "write a status report" workflow.
