# 13 — mount the task-system under `.workspace/`, not on the floor

Status: **done (2026-08-04)** — generator: 344 assertions green, zero-diff holds.
`dev-workspace` migrated (`ba0f425`), pushed, `make status` clean.

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
top level for exactly that reason.

**DECIDED: `status/` moves too — one container.** The reports are read from the
repo, not from a directory listing, and keeping the vendor's single mount means
`--with-status` continues to place `status/` as a sibling for free. Splitting the
container would make the generator install two halves and force `update.sh` to
keep them apart forever.

**DECIDED: the container keeps the name `project/`** — the mount is
`.workspace/project/{tasks,status}`. The shorter `.workspace/{tasks,status}` is
tempting but puts `status/` directly beside the existing `.workspace/state/`,
and those two mean entirely different things (hand-written reports vs. the daily
run's commit-window state).

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

## Migration

**DECIDED: `update.sh` never moves content.** It stamps the new mount and leaves
the old one alone; carrying tasks across is the human's call. That much held.

The original decision went further — *no migration handling at all*, on the
grounds that there is exactly **one** workspace in existence and it is migrated
by hand here. **That half was wrong, and it bit immediately.** `update.sh` only upgrades a task-system it
finds already installed (`--no-tasks` must stay opted out). Probing the *new*
mount alone would have read every pre-move workspace as opted out and silently
stripped the subsystem — including `dev-workspace`, whose migration recipe below
assumed `update.sh` would stamp the new mount after the old one was deleted. It
would not have.

So the probe now accepts **either** mount and installs at the new one, followed
by the detection warning: if root `project/` still exists, say both are present,
say the scripts/skill/`replan` all read the new one, and print the `git rm`.
Content is never moved — the tasks are the user's, and a generator that
relocates them is one that can lose them.

That also fixes the migration ordering: **`update.sh` first, delete second.**
Deleting first leaves nothing for the probe to find.

## `dev-workspace` specifics

Zero task content to preserve: `inbox`, `draft`, `backlog`, `in-progress`,
`complete`, and `wont-do` are all empty (the one hand-filed task was removed in
`9f138f2`). Its migration is therefore:

```
cd <dev-workspace>
<create-git-workspace>/update.sh .  # stamps .workspace/project/, warns about the old mount
git rm -r --quiet project/          # scaffolding only — verify the folders are empty first
make replan                         # confirm the workspace's own plan still drafts
```

Order matters: `update.sh` needs to *see* a task-system to upgrade one.

Safe *because* nothing is at stake — which also means it does **not** exercise
the case that matters. A workspace with real tasks is the one that would prove
the migration; note that gap rather than claiming it passed.

## Outcome (2026-08-04)

Ran exactly as above. `update.sh` installed `.workspace/project/{tasks,status}`,
refreshed both `CLAUDE.md` kernels and the `task-system` skill to the new mount,
then printed the stale-mount warning; `git rm -r project/` took out 38 files of
scaffolding; `make replan` drafted from the new location and its derived-from
line names it. Committed `ba0f425` + the plan redraft, pushed, `make status`
clean. A create/delete round-trip through the moved scripts works.

**Still unproven, by construction:** a migration with real task content. Nothing
crossed here because nothing was there.

Unrelated observation while verifying: `replan` reports `create-project-system`
as "no task-system — skipped". Correct — its `tasks/` is generator *source*, not
an installed mount, so the probe rightly declines it.

## Acceptance

- A new workspace stamps with the task-system at `.workspace/project/`, and the
  root holds only `CLAUDE.md`, `README.md`, `Makefile`, the two deliverables,
  the dotfiles, and child repos.
- `make replan` still drafts the workspace's own plan from the new location.
- Zero-diff regeneration still holds; the suite is green.
- `dev-workspace` is migrated, its old `project/` is gone, and `make status` and
  `make replan` both work afterwards.
- The `status/` question above is decided and written into `DESIGN.md`.
