# CLAUDE.md — {{WORKSPACE_NAME}}

<!-- Anything you write OUTSIDE the managed block below is yours and is preserved
     across updates. create-git-workspace regenerates ONLY the block between the
     two git-workspace markers. Put your own directives above or below it. -->

<!-- git-workspace:begin — managed by create-git-workspace; do not edit inside this block -->

## Workspace machinery (managed)

<!--
  This block is a KERNEL: only the rules that would be too late if they loaded on
  demand. The layout, the command surface, the repo verbs, the daily push/pull
  loop, the routine-setup seams, and the machinery/content/runtime split all live
  in the on-demand guide named below. Do not restate them here.
-->

This repo (`{{WORKSPACE_NAME}}`) is a **git-workspace**: a wrapper that manages
a *set* of other repos and worktrees checked out beside it, and summarizes your
activity across them. Its machinery is hidden in `.workspace/`; an allowlist
`.gitignore` keeps every managed child out of the wrapper's index.

**Full procedure:** the `workspace-status` skill, or
[`.workspace/status-guide.md`](.workspace/status-guide.md) — consult it before
adding or removing a repo, setting up or debugging the scheduled routine, or
running the status pipeline.

- **`cd` into the target child repo/worktree first.** Run every git/build command
  from *inside* `<path>`, never from the wrapper root — otherwise you risk hitting
  the wrong repo or staging a child into the wrapper index (what `guard.sh`
  catches). Do real code work in the owning child repo, from a session rooted
  there; this wrapper manages the *set* of repos, not their contents.
- **Never hand-edit `.workspace/repos.yml`.** It is a lockfile maintained by
  `add-repo.py` / `delete-repo.py` / `mute-repo.py` / `routine-registered.py`
  and replayed by `bootstrap.sh`. `make` (no target) lists every verb.
- **Never hand-write `summary.md`, `daily-plan-summary.md`, or
  `.workspace/state/`.** They are *runtime* files owned by the daily status run,
  which overwrites the day.
- **`.workspace/scripts/`, `.workspace/prompts/`, `.workspace/templates/`,
  `.workspace/status-guide.md`, `.github/workflows/`, `.gitignore`, `Makefile`,
  and this block are machinery** — `update.sh` overwrites them, so edits are lost.
  `repos.yml`, `config.yml`, `.workspace/daily-plans/`, and anything outside these
  markers are yours and are never overwritten. `README.md` is the same deal one
  level down: its `git-workspace-roster` block is regenerated from `repos.yml`,
  every other byte is yours.
- **`.workspace/project/tasks/` is the workspace's triage area** — inter-repo work and ideas
  with no repo home yet. Work that clearly belongs to an existing child repo goes
  in *that repo's* task-system.
- **A worktree's `.git` is a FILE, not a directory.** Test `[ -e <path>/.git ]`,
  never `[ -d <path>/.git ]` — the `-d` form silently misses every worktree.

_Managed block from create-git-workspace v{{GENERATOR_VERSION}}; canonical version
lives in `.workspace/config.yml`. Refresh with the generator's `update.sh`._

<!-- git-workspace:end -->
