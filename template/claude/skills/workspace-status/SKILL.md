---
name: workspace-status
description: Operate this git-workspace — the daily status run and its rollups, the remote /schedule routine and its sources list, the morning ff-only pull, and the add/delete/mute repo verbs. Use whenever adding or removing a tracked repo, setting up or debugging the scheduled routine, running or interpreting summary.md / daily-plan-summary.md, or working out which file the generator owns.
---

# Workspace status subsystem

This repo is a **git-workspace**: a wrapper that manages the set of repos and
worktrees checked out beside it, and summarizes your activity across them.

## Before doing anything

**Read [`.workspace/status-guide.md`](../../../.workspace/status-guide.md)**
(path is relative to the workspace root) — it is the single source of truth for
this subsystem: the layout, the command surface, the repo verbs, the push/pull
daily loop, the two manual routine-setup seams, and which files are machinery,
content, or runtime. This skill deliberately does not restate it, so there is
exactly one copy to keep correct.

## The rules that matter most

- **Never hand-edit `.workspace/repos.yml`.** It is a lockfile the verbs
  (`add-repo.py` / `delete-repo.py` / `mute-repo.py`) maintain and
  `bootstrap.sh` replays onto a new machine.
- **Never hand-write `summary.md` or `daily-plan-summary.md`.** They are runtime
  files owned by the daily run; the next run overwrites the day.
- **A new tracked repo is not tracked until it is in the routine's `sources`.**
  The remote sandbox has no checkouts and cannot clone what was not pre-declared,
  so the run silently reads no git log for it. See §5.2 of the guide.
- **`cd` into the child repo before running any git or build command.** Never
  operate on a child from the wrapper root.

## Orientation

```
make status | bootstrap | guard        the checkouts
make run | run-dry | new-work | aggregate   the status pipeline
make pull                              fast-forward onto the routine's output
make add-repo|delete-repo|mute-repo ARGS="…"   membership
make inject-kernel | kernel-check      the child commit kernel
```

`make` with no target lists everything. The scripts in `.workspace/scripts/` are
the real interface and read better for anything with arguments.

If you are here to understand *what the rollup says* rather than to run it, read
`summary.md` (retrospective, author-scoped) and `daily-plan-summary.md`
(forward-looking, workspace plan first) — §6 of the guide explains how each is
produced and why a repo can look INACTIVE while its history moved.
