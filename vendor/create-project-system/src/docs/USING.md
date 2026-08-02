# Using the task system

Operational guide for humans and AI agents. This is the **single source of
truth** for how to work the task system — the `task-system` skill and the
`CLAUDE.md` kernel both point here rather than restating it.

For the structural reference (metadata field tables, directory format), see
[`README.md`](README.md) alongside this file.

Scripts live in `{{TASKS_REL}}/scripts/` and are run **from the repo root**.

---

## The model in one paragraph

Every task is a **directory** containing a `README.md`. Tasks live under an
**epic**, partitioned into **status folders**. Subtasks are subdirectories of
their parent. A four-digit `NNNN` in a subtask's name defines its
**implementation order**. Completed subtasks are renamed with an `X-` prefix.
All of this is maintained by the scripts — never by hand.

```
{{TASKS_REL}}/
    <epic>/
        inbox/        # raw ideas, not yet evaluated
        draft/        # being written up
        backlog/      # refined, ordered by priority — pull from here
        in-progress/  # actively being worked on
        complete/     # done and verified
        wont-do/      # explicitly decided against
```

Each status folder's `README.md` lists its tasks **in priority order** — that
list is the source of truth for ordering. To reprioritise, edit the list.

---

## Task types

**USER-TASK** — top-level, human-owned. All top-level work is a user-task. No
`Parent` field. Created with `new-user-task.sh`.

**USER-SUBTASK** — a human-owned subtask: a planning step, review, approval, or
research item. Has a `Parent`. Can nest further. Created with
`new-user-subtask.sh`.

> A third type, **PIPELINE-SUBTASK**, exists in setups that hand tasks to an
> automated build pipeline. It is not part of this installation unless the
> pipeline layer was installed.

### Naming

- Top-level: `{6-char-hex-id}-{name}` — e.g. `a3f2c1-my-task`
- Subtask: `{parent-short-id}-{NNNN}-{name}` — e.g. `a3f2c1-0001-design-review`

Always refer to a task by its **fully-qualified name**, never the hex ID alone —
`a3f2c1-my-task`, not `a3f2c1`. The name is what makes a reference legible.

### Ordering is a contract

`NNNN` defines the order subtasks are worked, ascending. It is assigned from the
parent's `Next-subtask-id` and incremented automatically. If the intended order
changes, **renumber** with `reorder-subtasks.py` (or `insert-subtask.sh`, which
shifts later subtasks up). Never work subtasks out of sequence without
renumbering first — the numbers are the contract.

### Status

Top-level tasks move between status folders. **Subtask status is binary**: `—`
(not done) or `complete`. Subtasks never move between folders.

---

## Rules

> **Use the scripts. Always.** Never hand-edit a task `README.md` to add or
> remove subtasks, and never move task directories between status folders by
> hand. The scripts keep the filesystem and the READMEs in sync; manual edits
> desynchronise them.

> **Never create task directories or READMEs directly** (`mkdir`, `cat`,
> heredocs). Use the creation scripts. Use an editor only to fill in content
> sections — Goal, Context, Notes — *after* a script has created the file.

> **Describe before you build.** Before beginning any task, state its purpose
> and list every subtask in order. If a human owns the task, wait for their
> approval before implementing.

> **Mark each subtask complete as you go** — run `complete-task.sh --parent`
> before moving to the next one. Don't batch it up at the end.

> **End every task with a documentation subtask.** Add it as the final
> NNNN-numbered subtask *before* starting implementation. A task isn't done
> until the docs it affects are updated.

> **Ask before closing.** Don't move a task or subtask to `complete/` as a side
> effect of other work. Get explicit confirmation first.

> **Keep test tasks.** When you create a task to verify a feature, complete it
> rather than deleting it — it becomes a living example of correct usage.

---

## Command reference

`--epic` defaults to the configured default epic and can usually be omitted.

### Creating

```bash
# Top-level task
{{TASKS_REL}}/scripts/new-user-task.sh --folder draft --name my-feature

# ...with topical tags and a priority. Tags are how you group tasks by SUBJECT
# (docs, video, education); they are free text and you can set them later too.
{{TASKS_REL}}/scripts/new-user-task.sh --folder draft --name my-feature \
    --tags "docs, search" --priority HIGH

# Subtask (parent is the task's full directory name)
{{TASKS_REL}}/scripts/new-user-subtask.sh --folder draft \
    --parent a3f2c1-my-feature --name design-review

# A new epic (creates all six status folders)
{{TASKS_REL}}/scripts/new-epic.sh --name main
```

### Viewing

```bash
# Outstanding work in one status folder, with subtasks
{{TASKS_REL}}/scripts/list-tasks.sh --folder backlog --depth 2

# Order by priority: HIGH → MED → LOW → unset
{{TASKS_REL}}/scripts/list-tasks.sh --folder backlog --sort-priority

# Filter by topic — matches against the Tags field
{{TASKS_REL}}/scripts/list-tasks.sh --folder backlog --tag docs

# Everything including completed
{{TASKS_REL}}/scripts/list-tasks.sh --all

# One task's README
{{TASKS_REL}}/scripts/show-task.sh --folder in-progress --name a3f2c1-my-feature

# Path of the next incomplete subtask (exit 1 if all done)
{{TASKS_REL}}/scripts/next-subtask.sh --folder in-progress --parent a3f2c1-my-feature
```

> Don't run `list-tasks.sh` without `--folder` when asked for *outstanding*
> work — it includes `complete/`, which is noise.

### Progressing

```bash
# Start work: move to in-progress
{{TASKS_REL}}/scripts/move-task.sh --name a3f2c1-my-feature --from backlog --to in-progress

# Finish a subtask (marks [x], renames dir with X-)
{{TASKS_REL}}/scripts/complete-task.sh --folder in-progress \
    --parent a3f2c1-my-feature --name a3f2c1-0000-design-review

# Finish the task itself (moves it to complete/)
{{TASKS_REL}}/scripts/complete-task.sh --folder in-progress --name a3f2c1-my-feature

# Undo either
{{TASKS_REL}}/scripts/complete-task.sh --folder in-progress --name a3f2c1-my-feature --undo
```

### Editing metadata

`Tags` and `Priority` can be changed after creation — you do not have to
delete and recreate a task (which would destroy its subtasks), and you must not
hand-edit the metadata table.

```bash
# Retag an existing task (Tags is free text; this is the TOPICAL grouping)
{{TASKS_REL}}/scripts/set-field.sh --folder backlog --name a3f2c1-my-feature \
    --field Tags --value "docs, search"

# Re-prioritise
{{TASKS_REL}}/scripts/set-field.sh --folder backlog --name a3f2c1-my-feature \
    --field Priority --value HIGH

# Clear a field
{{TASKS_REL}}/scripts/set-field.sh --folder backlog --name a3f2c1-my-feature \
    --field Tags --value "—"
```

Only `Tags` and `Priority` are settable this way — they mirror nothing on the
filesystem. `Status` and a task's location are owned by `move-task.sh` and
`complete-task.sh`.

### Restructuring

```bash
# Insert a subtask at position 0003, shifting later ones up
{{TASKS_REL}}/scripts/insert-subtask.sh --folder in-progress \
    --parent a3f2c1-my-feature --at 0003 --name new-step

# Renumber a subtask
{{TASKS_REL}}/scripts/rename-subtask.sh --folder in-progress \
    --parent a3f2c1-my-feature --name a3f2c1-0003-my-sub --new-id 0005

# Reorder wholesale (pass base names in the desired order)
python3 {{TASKS_REL}}/scripts/reorder-subtasks.py --task-dir <path> --apply name-a name-b ...
```

### Removing

```bash
# Soft-delete (hides the directory, drops it from the parent list)
{{TASKS_REL}}/scripts/delete-task.sh --folder draft --name a3f2c1-my-feature
{{TASKS_REL}}/scripts/restore-task.sh --folder draft --name a3f2c1-my-feature

# Decided against, but keep it for the record
{{TASKS_REL}}/scripts/wont-do-subtask.sh --folder in-progress \
    --parent a3f2c1-my-feature --name a3f2c1-0002-abandoned-idea
```

---

## Lifecycle walkthrough

```bash
# 1. Create the task
{{TASKS_REL}}/scripts/new-user-task.sh --folder draft --name add-search
#    -> {{TASKS_REL}}/main/draft/7f21ab-add-search/

# 2. Fill in Goal and Context (edit the README's prose sections only)

# 3. Plan subtasks in order — last one is always docs
{{TASKS_REL}}/scripts/new-user-subtask.sh --folder draft --parent 7f21ab-add-search --name design-index
{{TASKS_REL}}/scripts/new-user-subtask.sh --folder draft --parent 7f21ab-add-search --name implement-query
{{TASKS_REL}}/scripts/new-user-subtask.sh --folder draft --parent 7f21ab-add-search --name update-docs

# 4. Get approval on the plan, then start
{{TASKS_REL}}/scripts/move-task.sh --name 7f21ab-add-search --from draft --to in-progress

# 5. Work subtasks in NNNN order, completing each before the next
{{TASKS_REL}}/scripts/complete-task.sh --folder in-progress \
    --parent 7f21ab-add-search --name 7f21ab-0000-design-index

# 6. When all subtasks are [x], confirm with the owner, then close
{{TASKS_REL}}/scripts/complete-task.sh --folder in-progress --name 7f21ab-add-search
```

---

## Optional layers

These commands exist only if the corresponding layer was installed.

### Worktrees (`worktrees.md`)

Groups tasks that touch the same files, so different groups can be worked in
parallel branches without conflicting. Valid values are the **Worktree branch**
names declared in `{{TASKS_REL}}/worktrees.md`; `unclassified` is always
accepted.

> **This is about isolation, not topic.** `Worktree` answers "which files does
> this touch, and what can run beside it" — not "what is this about". For
> subject-matter grouping (`docs`, `video`, `education`) use **`Tags`**, which
> is free text and settable at any time with `set-field.sh`.

```bash
{{TASKS_REL}}/scripts/new-user-task.sh --folder draft --name my-feature --worktree docs
{{TASKS_REL}}/scripts/list-tasks.sh --folder backlog --worktree docs
{{TASKS_REL}}/scripts/list-tasks.sh --folder backlog --group-by-worktree --sort-priority
```

If this layer is installed, set a task's worktree at creation; don't leave it `—`.

> Installs generated before this field was renamed carry it as `Category`, in a
> `classes.md`. Both spellings are read for as long as they exist — those are
> content files the generator never rewrites — so no migration is needed. The
> `--category` and `--group-by-category` flags still work, with a warning.

### Long-running projects

For services spanning many pieces of work, each with its own epic:

```bash
{{TASKS_REL}}/scripts/new-project.sh --name my-service
{{TASKS_REL}}/scripts/list-projects.sh
```

### Status reports

Installed with `--with-status`. A `status/` sibling of the tasks mount holds
periodic **delta** reports — each a narrative synthesis of what shipped since
the previous report, not a daily log and not tied to session boundaries.

**At the start of a session, read the most recent report** (`{{STATUS_REL}}/`)
to see where things left off.

**Writing one.** When the operator says **"write a status report"** (or a
variant: "status report", "draft a status report", "write status", "write up
the period"):

1. Identify the period since the most recent report in `{{STATUS_REL}}/`.
2. Synthesize what shipped during that period — drawing on the git history and
   completed tasks, but as a narrative of themes and outcomes, *not* a line-by-line
   replay of `git log`.
3. Write it to `{{STATUS_REL}}/YYYY-MM-DD.md` (the date is the report's as-of
   date), with these sections:
   - **Work Completed** — what shipped, as narrative.
   - **Work In Progress** — what is open and where it stands.
   - **Next Up** — what comes after, and why.
   - **Key Decisions** — non-obvious decisions worth carrying forward.
4. Add a row to the top of the log table in `{{STATUS_REL}}/README.md`.
5. Commit if requested.

Reports are produced on operator request, not at session end — cadence is
flexible (weekly, twice-weekly, daily). In a worktree layout, write them from
the primary worktree only; they are a coordination artifact, not per-worktree state.

### Worktree completion guard

Blocks worktree removal until a task and all its subtasks are complete:

```bash
python3 check-task-complete.py {{TASKS_REL}}/<epic> <branch-name>
```

Exit `0` complete · `1` incomplete (blocks) · `2` no matching task (allows).
Note the first argument is the **epic** directory, not the mount.
