# list-tasks.sh

Lists tasks in an epic, grouped by status folder. Reads task ordering and
completion state from each `README.md` so the output matches the same
convention as the on-disk task system. Top-level tasks are always shown;
checked-off subtask entries (`[x]`) are hidden by default and surfaced
with `--all`.

---

## CLI Flags

| Flag | Description |
|------|-------------|
| `--epic <name>` | Epic to list (default: `main`). |
| `--folder <status>` | Limit output to a single status folder (`inbox`, `draft`, `backlog`, `in-progress`, `complete`, `wont-do`). Omit to show all. |
| `--depth <n>` | Recursion depth for subtasks (default: `1` — top-level tasks only). |
| `--root <path>` | Traverse from a specific path instead of an epic. Path is relative to `{{TASKS_REL}}/`. |
| `--all` | Include completed `[x]` subtask entries in subtask listings. |
| `--tag <tag>` | Filter to tasks whose `Tags` field contains the given value (case-insensitive). This is the **topical** filter — `docs`, `video`, `education`. |
| `--worktree <branch>` | Filter to tasks whose `Worktree` field equals the given branch (e.g. `task-tooling`). Use `unclassified` to match tasks with `Worktree: —` or no Worktree field. |
| `--group-by-worktree` | Within each status folder, group tasks under `[<worktree>]` sub-headings in declaration order. The `unclassified` group always trails. |
| `--sort-priority` | Order tasks `HIGH → MED → LOW → unset` within each folder (or each worktree group, when combined with `--group-by-worktree`). |

`--worktree` and `--group-by-worktree` apply only at the top-level
(depth-1) layer — subtasks inherit the worktree from their parent and
don't carry the field themselves.

`--category` and `--group-by-category` are deprecated aliases for the two
worktree flags. They still work and warn; the field was renamed because
`Category` reads as topical grouping, which is what `Tags` is for.

---

## Worktree Order

When grouping is enabled, worktrees are listed in the order they are
declared in [`{{TASKS_REL}}/worktrees.md`](../worktrees.md), with
`unclassified` always last.

The order is **read at runtime** into `WORKTREE_ORDER` — reordering or
adding a worktree in `worktrees.md` is picked up with no script change.
When the worktrees layer is not installed, the order collapses to just
`unclassified` and grouping degrades to a single group.

Installs generated before the rename declare their worktrees in
`classes.md`; the script falls back to that name when `worktrees.md` is
absent.

---

## Examples

```bash
# Outstanding work, all folders
list-tasks.sh --epic main --folder draft --depth 2
list-tasks.sh --epic main --folder backlog --depth 2
list-tasks.sh --epic main --folder in-progress --depth 2

# Priority-ordered backlog
list-tasks.sh --epic main --folder backlog --sort-priority

# What's next per worktree — global view
list-tasks.sh --epic main --folder backlog --group-by-worktree --sort-priority

# What's next for a specific worktree
list-tasks.sh --epic main --folder backlog --worktree task-tooling --sort-priority

# Tasks missing a Worktree field
list-tasks.sh --epic main --folder backlog --worktree unclassified

# Everything about a topic, regardless of which worktree it lands in
list-tasks.sh --epic main --folder backlog --tag docs
```

---

## Implementation Notes

- `get_priority` and `get_worktree` parse the task's `README.md` table
  with line-anchored `grep` patterns (`^| Priority`, `^| Worktree`).
- `get_worktree` falls back to `^| Category` for tasks created before the
  rename. Task READMEs are content the generator never rewrites, so this
  fallback is permanent and a repo may hold a mix of both rows.
- The worktree filter is applied in both `print_status_tasks` (for the
  default depth-1 view) and `print_dir_tasks` (only when `current_depth`
  is 1, so deeper recursion never re-applies the filter).
- Group rendering iterates `WORKTREE_ORDER` outer and `task_dirs` inner.
  Per-task printing is duplicated between the grouped and ungrouped
  branches; this is deliberate to keep the indentation logic obvious.
- Tests live alongside the generated subsystem (see the target repo test suite).
