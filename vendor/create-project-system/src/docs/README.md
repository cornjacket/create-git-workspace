# Task Management

This directory contains all tasks for the ai-builder project, organized by
epic and status. Tasks are managed using the scripts in `scripts/` and consumed
by both human developers and AI coding agents.

---

## Task Types

There are three distinct task types. Every task README identifies its type
via a `Task-type` field in the metadata table.

### USER-TASK

Top-level task owned by the human or Oracle. All top-level work must be a
user-task. Long-lived. Captures intent, context, and decisions.

- No `Parent` field (it has no parent — it is the root)
- No pipeline sections (Components, Design, AC, Suggested Tools)
- Can contain **user-subtasks** and/or **pipeline-subtasks**
- Template: `user-task-template.md` | Script: `new-user-task.sh`

### USER-SUBTASK

Human/Oracle-owned subtask. Used for planning steps, reviews, approvals,
research — any work the human manages directly. Does not go to the pipeline.

- Has a `Parent` field
- No pipeline sections
- Can contain **user-subtasks** and/or **pipeline-subtasks**
- Template: `user-subtask-template.md` | Script: `new-user-subtask.sh`

### PIPELINE-SUBTASK

The pipeline's unit of work. A `build-N` entry point authored by the Oracle
and submitted to the orchestrator, or a pipeline-internal node (component,
integrate, test) created by the TM agent. Pipeline-owned once submitted.

- Has a `Parent` field (can point to a user-task, user-subtask, or pipeline-subtask)
- Contains pipeline sections (Components, Design, AC, Suggested Tools)
- Can only contain **pipeline-subtasks** — no human-owned children
- Template: `pipeline-build-template.md` | Script: `new-pipeline-subtask.sh`

---

## Hierarchy Rules

```
user-task
├── user-subtask          (human planning step)
│   ├── user-subtask      (can nest further)
│   └── pipeline-subtask  (build-N handed off to pipeline)
│       └── pipeline-subtask (component, integrate, test, ...)
└── pipeline-subtask      (build-N handed off to pipeline)
    └── pipeline-subtask  (component)
        └── pipeline-subtask (sub-component, if composite)
```

- All top-level work must be a **user-task**
- **user-task** can contain user-subtasks and/or pipeline-subtasks
- **user-subtask** can contain user-subtasks and/or pipeline-subtasks
- **pipeline-subtask** can only contain pipeline-subtasks
- No human-owned node may appear under a pipeline-owned node

---

## Structure

```
{{TASKS_REL}}/
    <epic>/                     # one directory per epic (e.g. main)
        README.md               # epic description and status summary
        inbox/                  # raw ideas, not yet evaluated
        draft/                  # being written up, incomplete
        backlog/                # refined, ordered by priority, ready to pull
        in-progress/            # actively being worked on
        complete/               # done and verified
        wont-do/                # explicitly decided against, kept for reference
    scripts/
        new-user-task.sh        # create a top-level user-task
        new-user-subtask.sh     # create a human-owned subtask
        new-pipeline-subtask.sh # create a pipeline entry point or internal node
        move-task.sh            # move a task to a different status folder
        complete-task.sh        # mark a task or subtask done/undone
        delete-task.sh          # soft-delete: hides directory, removes from parent README
        restore-task.sh         # reverse a soft-delete
        show-task.sh            # print a task README to stdout
        list-tasks.sh           # display the task tree
        wont-do-subtask.sh      # mark a subtask wont-do: sets Status, removes from parent list
        next-subtask.sh         # print the path of the next incomplete subtask
        task-id-helpers.sh      # shared helper: get/increment Next-subtask-id, resolve X- prefix
        user-task-template.md
        user-subtask-template.md
        pipeline-build-template.md
```

---

## Long-running Services (`project/projects/`)

For services that span multiple pipeline builds, use `project/projects/`:

```
project/projects/
    my-project/              ← USER-TASK
        README.md
        build-1/             ← PIPELINE-SUBTASK
            README.md
        build-2/             ← PIPELINE-SUBTASK
            README.md
```

Use `new-user-task.sh` for the service directory, `new-pipeline-subtask.sh`
for each build.

---

## Task Format

Each task is a **directory** containing a `README.md` that describes the task.

**Top-level task** directory names are `{6-char-hex-id}-{name}` (e.g. `a3f2c1-my-task`).

**Subtask** directory names are `{parent-short-id}-{NNNN}-{name}` where `{NNNN}` is a
zero-padded 4-digit counter (e.g. `a3f2c1-0001-design-review`). The parent's
`Next-subtask-id` field is incremented automatically by `new-user-subtask.sh` and
`new-pipeline-subtask.sh`. When a subtask is marked complete, its directory is renamed
with an `X-` prefix (e.g. `X-a3f2c1-0001-design-review`) to signal completion at the
filesystem level.

**USER-TASK header:**
```markdown
| Field           | Value       |
|-----------------|-------------|
| Task-type       | USER-TASK   |
| Status          | draft       |
| Epic            | main        |
| Tags            | —           |
| Priority        | HIGH        |
| Created         | 2026-04-02  |
| Completed       | —           |
| Next-subtask-id | 0000        |
```

**USER-SUBTASK header:**
```markdown
| Field           | Value          |
|-----------------|----------------|
| Task-type       | USER-SUBTASK   |
| Status          | —              |
| Epic            | main           |
| Tags            | —              |
| Parent          | my-parent-task |
| Priority        | —              |
| Created         | 2026-04-02     |
| Completed       | —              |
| Next-subtask-id | 0000           |
```

**PIPELINE-SUBTASK header:**
```markdown
| Field           | Value              |
|-----------------|--------------------|
| Task-type       | PIPELINE-SUBTASK   |
| Status          | —                  |
| Epic            | main               |
| Tags            | —                  |
| Parent          | my-parent-task     |
| Priority        | —                  |
| Next-subtask-id | 0000               |
| Complexity      | —                  |
| Stop-after      | false              |
| Last-task       | false              |
```

Pipeline subtask timestamps are stored in `task.json` (not the README, which is
prose-only): `created_at` (ISO 8601 date string) is set at creation;
`completed_at` (ISO 8601 date string, or `null`) is set by `complete-task.sh`.

Valid Priority values: `CRITICAL`, `HIGH`, `MED`, `LOW`, `—` (unset).

**Subtask Status is binary.** Subtasks don't move between status folders — their
`Status` field has only two valid values:

| Value | Meaning |
|---|---|
| `—` | Not yet done |
| `complete` | Done |

Use `complete-task.sh --parent` to mark a subtask done; this updates both the
`Status` field and the `[x]` checkbox in the parent README.

---

## Workflow Rules

**Before beginning any task or subtask:** describe its purpose and list all
subtasks in order. If the task manager is human, wait for their approval
before starting any implementation work.

**When picking up work:** pull from `backlog/` in top-to-bottom order.
**When starting a task:** move it to `in-progress/` using `move-task.sh`.
**When done:** run `complete-task.sh` — no `--parent` for top-level tasks,
add `--parent` for subtasks.

---

## Status Directories

Each status directory contains a `README.md` that lists its tasks in priority
order (top = highest priority). This ordered list is the single source of truth
for task ordering — to reprioritise, edit the list directly.

| Status | Meaning |
|---|---|
| `inbox` | Raw idea, captured as-is. Not yet evaluated. |
| `draft` | Being written up. Description is incomplete. |
| `backlog` | Refined and ready to pull. Ordered by priority. |
| `in-progress` | Actively being worked on. |
| `complete` | Done and verified. |
| `wont-do` | Explicitly decided against. Kept for reference. |

---

## Scripts

All scripts are in `{{TASKS_REL}}/scripts/` and should be run from the
**repo root**.

```bash
# Create a new top-level user-task. --worktree must match a worktree branch
# name in worktrees.md (or `unclassified`). Use --tags for topical grouping.
{{TASKS_REL}}/scripts/new-user-task.sh --epic main --folder draft \
    --name my-project --worktree task-tooling --tags "docs, search"

# Create a human-owned subtask (review, planning step, etc.)
{{TASKS_REL}}/scripts/new-user-subtask.sh --epic main --folder in-progress \
    --parent my-project --name design-review

# Create a pipeline entry point (build-N)
{{TASKS_REL}}/scripts/new-pipeline-subtask.sh --epic main --folder in-progress \
    --parent my-project --name build-1

# Move a task (and all its subtasks) to a different status
{{TASKS_REL}}/scripts/move-task.sh --epic main --name my-task \
    --from draft --to backlog

# Mark a top-level task complete (moves to complete/)
{{TASKS_REL}}/scripts/complete-task.sh --epic main --folder in-progress --name my-task

# Mark a subtask complete (updates checkbox and Status field)
{{TASKS_REL}}/scripts/complete-task.sh --epic main --folder in-progress \
    --parent my-task --name my-subtask

# Undo either
{{TASKS_REL}}/scripts/complete-task.sh --epic main --folder in-progress --name my-task --undo
{{TASKS_REL}}/scripts/complete-task.sh --epic main --folder in-progress \
    --parent my-task --name my-subtask --undo

# Print a task's README to stdout
{{TASKS_REL}}/scripts/show-task.sh --epic main --folder in-progress --name my-task

# Change Tags or Priority on an existing task (never hand-edit the table)
{{TASKS_REL}}/scripts/set-field.sh --epic main --folder backlog --name my-task \
    --field Tags --value "docs, search"
{{TASKS_REL}}/scripts/set-field.sh --epic main --folder backlog --name my-task \
    --field Priority --value HIGH

# Soft-delete a task (hides directory, removes from parent README)
{{TASKS_REL}}/scripts/delete-task.sh --epic main --folder draft --name my-task

# Restore a soft-deleted task
{{TASKS_REL}}/scripts/restore-task.sh --epic main --folder draft --name my-task

# Mark a subtask as wont-do (sets Status, removes from parent list, keeps directory)
{{TASKS_REL}}/scripts/wont-do-subtask.sh --epic main --folder in-progress \
    --parent my-task --name my-subtask

# List incomplete tasks in an epic
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --folder draft
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --folder backlog
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --folder in-progress

# List all tasks including completed
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --all

# List tasks with subtask depth
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --folder in-progress --depth 2

# Filter by tag
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --tag backend --depth 2 --all

# Filter by Worktree (which files a task touches — see worktrees.md)
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --folder backlog --worktree task-tooling

# Group output by Worktree for a per-worktree breakdown
{{TASKS_REL}}/scripts/list-tasks.sh --epic main --folder backlog \
    --group-by-worktree --sort-priority

# List tasks rooted at a specific directory
{{TASKS_REL}}/scripts/list-tasks.sh --root main/in-progress/my-task --depth 3

# Get the next incomplete subtask (prints absolute path to README, exit 1 if all done)
{{TASKS_REL}}/scripts/next-subtask.sh --epic main --folder in-progress \
    --parent my-task

# Write the absolute path of a task README to current-job.txt (for pipeline use)
{{TASKS_REL}}/scripts/set-current-job.sh \
    --output-dir <pipeline-output-dir> \
    <path-to-task-README.md>

# Check whether a task is the last (integration) subtask (exit 0 = yes, 1 = no)
{{TASKS_REL}}/scripts/is-last-task.sh <path-to-task-README.md>

# Rename a subtask's NNNN position ID (also bumps Next-subtask-id if needed)
{{TASKS_REL}}/scripts/rename-subtask.sh --epic main --folder in-progress \
    --parent my-task --name a3f2c1-0003-my-sub --new-id 0005

# Insert a new subtask at position NNNN, shifting later subtasks up by one
{{TASKS_REL}}/scripts/insert-subtask.sh --epic main --folder in-progress \
    --parent my-task --at 0003 --name new-step
# With pipeline type:
{{TASKS_REL}}/scripts/insert-subtask.sh --epic main --folder in-progress \
    --parent my-task --at 0003 --name new-step --type pipeline
```

---

## Epics

| Epic | Description |
|---|---|
| `main` | Default epic. Core ai-builder platform work. |
