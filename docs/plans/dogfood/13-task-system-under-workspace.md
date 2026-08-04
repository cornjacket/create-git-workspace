# 13 — mount the task-system under `.workspace/`, not on the floor

Status: open

The vendored task-system installs at `project/` in the workspace **root**, which
is the one directory that is supposed to hold child repos and nothing else. A
workspace's floor should read as "these are the repos I manage"; today it reads
as "these are the repos I manage, plus a directory called project that is not
one of them".

Move the mount to `.workspace/project/`, so everything the workspace owns lives
in the control plane and the floor is exclusively children.

## Why this is the right split

Every other workspace-owned artifact is already under `.workspace/` —
`config.yml` and `repos.yml` (content you edit), `daily-plans/` (content you
edit *daily*), `prompts/`, `templates/`, `state/`. The task-system is the same
class of thing as `daily-plans/`: workspace-owned content, not a child repo. It
is the only one that sits outside.

It also removes a special case from the allowlist. `.gitignore` currently needs
`!/project/` to un-ignore a directory sitting among ignored children; under
`.workspace/` it is covered by the existing `!/.workspace/` line and the rule
becomes "the floor is ignored, full stop".

## The counter-argument, recorded because it is real

`.workspace/` is documented as the **hidden** control plane, and this moves
human-edited content into a dotdir — harder to find, harder to open in an
editor, invisible to `ls`. Two things blunt it: `daily-plans/` already set that
precedent and has not hurt, and the `Makefile` plus the `task-system` skill are
how anyone actually reaches the task-system, neither of which cares where it
sits.

The sharper edge is **`project/status/`** — hand-written periodic status reports,
the kind you bring to a review meeting. That is an audience-facing deliverable,
and the other two (`summary.md`, `daily-plan-summary.md`) deliberately sit at the
top level for exactly that reason. Moving it into a hidden directory is a real
demotion. Options: accept it (the reports are read from the repo, not the
filesystem), or split the container and leave `status/` at root — which costs the
"one container" property the vendor's `--with-status` gives for free.

**Decide this before implementing.** Splitting them later is worse than choosing
now.

## What it touches

The vendor is already parameterized — this is a flag change, not a fork:

- **`lib/generator.sh`** — `install_task_system` passes `--tasks-dir
  project/tasks`; make it `.workspace/project/tasks`. `--with-status` creates
  `status/` as a **sibling of the tasks mount**, so it follows automatically.
- **`replan.sh`** — probes `$WORKSPACE_ROOT/project/tasks` for the workspace's
  *own* plan (line ~145). Note the child-repo probe (`project/tasks`, then
  `tasks/`) must NOT change: that is about other repos' layouts, not ours.
- **`.gitignore`** — drop `!/project/`. `!/.claude/` stays: Claude requires
  skills at `.claude/skills/`, so that one cannot move and the split is not
  total.
- **`CLAUDE.md` kernel** — the "`project/tasks/` is the workspace's triage area"
  rule, plus the task-system block the vendor injects (it renders the mount, so
  re-running should fix it — verify rather than assume).
- **The emitted `task-system` skill** — vendor-owned and mount-aware; confirm it
  renders the new path rather than a hardcoded `project/tasks/`.
- **Docs** — `DESIGN.md` §8.7 (triage area), §8.8 (vendoring), and the tree
  diagrams in `DESIGN.md`, `README.md`, and `status-guide.md` §1.
- **Tests** — `ours()` filters `^project/`; `test_task_system` asserts the mount
  by contract; `EXPECTED_TRACKED` excludes the delegated tree. All three need the
  new path, and the zero-diff invariant must still hold.

## Migration is the hard part

An existing workspace was stamped with `project/` at the root. `update.sh` has to
do something about it, and every option has a cost:

- **(a) Auto-migrate**: if root `project/` exists and `.workspace/project/` does
  not, `git mv` it and report. Cleanest result — but it is the **first time
  `update.sh` moves user content**, and the machinery/content split has held
  precisely because regeneration never touches content. A `git mv` of a
  directory holding real tasks is not a regeneration; it is a data migration
  wearing one's clothes.
- **(b) Detect and instruct**: warn loudly, print the exact `git mv`, refuse to
  install a second task-system until the old one is gone. Keeps the split
  honest at the cost of a manual step.
- **(c) New workspaces only**: leave stamped workspaces alone. Cheapest, and
  guarantees two layouts in the wild forever — the thing `update.sh` exists to
  prevent.

Lean: **(b)**, with the instruction precise enough to paste. The split is worth
more than the convenience, and this is a one-time step per workspace.

Whatever is chosen, the failure to avoid is **two task-systems coexisting** — a
populated `project/` on the floor and an empty `.workspace/project/` — because
the scripts, the skill, and `replan` would each pick one and they would not agree.

## `dev-workspace` specifics

Zero task content to preserve: `inbox`, `draft`, `backlog`, `in-progress`,
`complete`, and `wont-do` are all empty (the one hand-filed task was removed in
`9f138f2`). So its migration is a `git mv` of scaffolding plus a regeneration,
and it is a safe first subject *because* nothing is at stake — which also means
it does **not** exercise the case that matters. A workspace with real tasks is
the one that proves the migration; note that gap rather than claiming it passed.

## Acceptance

- A new workspace stamps with the task-system at `.workspace/project/`, and the
  root holds only `CLAUDE.md`, `README.md`, `Makefile`, the two deliverables,
  the dotfiles, and child repos.
- `make replan` still drafts the workspace's own plan from the new location.
- Zero-diff regeneration still holds; the suite is green.
- `dev-workspace` is migrated, its old `project/` is gone, and `make status` and
  `make replan` both work afterwards.
- The `status/` question above is decided and written into `DESIGN.md`.
