# Optional layers

Each directory here is a self-contained layer the generator emits **only** when
its flag is passed. The human core (`src/scripts`, `src/templates`, `src/docs`)
works fully without any of them.

Design rule followed throughout: **prefer runtime gating over file variants.**
Where the core can detect a layer's presence at runtime (e.g. "does `worktrees.md`
exist?"), there is one script that works both ways, rather than two variants the
generator has to choose between.

---

## `worktrees/` — `--with-worktrees` (parallel-work isolation)

**Emits:** `worktrees.md` → `<tasks-root>/worktrees.md` (a starter with one
example worktree, so `--worktree` works immediately).

The field names which files a task touches, so unrelated work can run in
parallel branches. It is **not** topical grouping — that is `Tags`, which is
free text and settable at any time via `set-field.sh`. The field was called
`Category` through v0.1.0 and renamed in v0.2.0 precisely because the old name
pulled operators toward it when they wanted `Tags` (task 19).

**Core behavior when absent (already implemented, no file swap needed):**
- `new-user-task.sh` — `--worktree` is optional; it validates against
  `worktrees.md` *only if that file exists*, otherwise skips validation. Unset
  worktree is recorded as `—`.
- `list-tasks.sh` — builds `WORKTREE_ORDER` at runtime from `worktrees.md`
  (declaration order), falling back to just `unclassified`. `--worktree` and
  `--group-by-worktree` remain present and harmless either way.

**Generator emit rule:** when `--with-worktrees` is **not** passed, strip the
`| Worktree | … |` row from the emitted `user-task-template.md` so repos
without the layer don't carry a permanently-empty field. (Implemented in
`generate.sh`, task 04.)

**Backward compatibility (task 19).** Both the metadata row and the definitions
file are CONTENT, which the generator never rewrites — so pre-rename installs
are supported by the *readers*, permanently, rather than by a migration:
- `list-tasks.sh` reads `| Worktree |`, then falls back to `| Category |`.
- Both scripts read `worktrees.md`, then fall back to `classes.md`.
- `generate.sh` seeds `worktrees.md` only when **neither** name is present, so
  regenerating over a pre-rename install never leaves a fresh empty file
  shadowing the operator's real definitions.
- `--category` / `--group-by-category` warn and still work. `--with-classes`
  errors out: generate-time flags are typed once during a deliberate upgrade,
  and v0.1.0 remains pinnable.

---

## `projects/` — `--with-projects` (long-running services)

**Emits:** `scripts/new-project.sh`, `scripts/list-projects.sh` →
`<tasks-root>/scripts/`, and sets `PROJECTS_REL` in the generated
`task-config.sh`.

**Mount:** `PROJECTS_REL` is a sibling of the tasks mount. If unset,
`task-env.sh` derives it:

| `TASKS_REL` | derived `PROJECTS_REL` |
|---|---|
| `tasks` | `projects` |
| `project/tasks` | `project/projects` |

`task-env.sh` also exports `PROJECTS_ROOT="$REPO_ROOT/$PROJECTS_REL"`.
`new-epic.sh --project <name>` uses it (core script, works whether or not the
layer's scripts are installed).

---

## `status/` — `--with-status` (project workspace: status reports)

**Emits (both CONTENT — seeded, never clobbered):**
- `README.md` → `<status-mount>/README.md` — a thin log-table stub. The
  authoritative "write a status report" workflow lives in `docs/USING.md`
  (machinery), so this stub stays single-source and doesn't drift.
- `container-README.md` → `<container>/README.md` — overview of the `project/`
  workspace (tasks + status). **Emitted only when the tasks mount sits inside a
  container dir**; at the repo root there is no container to document (and
  writing the repo's own `README.md` would clobber it).

**Mount:** `STATUS_REL` is a sibling of the tasks mount, mirroring `projects`:

| `TASKS_REL` | derived `STATUS_REL` | container README |
|---|---|---|
| `tasks` | `status` | *(skipped — no container)* |
| `project/tasks` | `project/status` | `project/README.md` |

This is the canonical **option-B** layout: mount at `project/tasks --with-status`
so the target grows a `project/` workspace with `tasks/` + `status/` siblings.

Unlike the other layers, this one ships **no scripts** — a status report is a
convention + an agent workflow (documented in `USING.md` and mirrored in the
skill), not a command. `reviews/` and the empty `project/scripts/` from the
original ai-builder workspace are intentionally **not** extracted (reviews was
never fully designed; the scripts dir held nothing).

---

## `worktree-guard/` — `--with-worktree-guard`

**Emits:** `check-task-complete.py` → the target's bootstrap/hook location.

Blocks worktree removal until a task and all its subtasks are complete. Already
mount-agnostic — it takes its search root as an argument, so no refactor was
required.

**⚠️ Generator wiring trap.** The first argument is the **epic directory**, not
the tasks mount — it looks for the status folders (`draft/`, `in-progress/`,
`complete/`, …) *directly* beneath it:

```
correct:  check-task-complete.py <tasks-mount>/<epic> <branch>   # e.g. tasks/main
wrong:    check-task-complete.py <tasks-mount>        <branch>   # finds nothing, exits 2
```

The upstream argument was named `<tasks-root>`, which invites exactly this
mistake; the emitted copy renames it to `<epic-root>` and documents both forms.
`generate.sh` must pass `$TASKS_REL/$DEFAULT_EPIC`.

**Exit codes:** `0` complete · `1` incomplete (blocks) · `2` no matching task
(warns, allows removal). Note it requires **both** that the task sits in
`complete/` **and** that every subtask carries the `X-` prefix.
