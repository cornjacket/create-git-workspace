# 009 — add-repo / delete-repo / mute-repo

Status: done (2026-08-01) — commit-kernel injection stays in `012`

Workspace verbs that edit `.workspace/repos.yml`, under `.workspace/scripts/`.

## Acceptance
- `add-repo <url> [--branch b] [--priority n]` — append entry; clone into the
  workspace; inject the commit kernel into the child's `CLAUDE.md` (task 012).
- `delete-repo <name>` — remove the entry; if it also removes the checkout, it
  **refuses on a dirty or unpushed child** (reuse `status.sh`/`guard.sh`).
- `mute-repo <name> [--skip]` — default sets `report_inactivity: false` (keep
  tracked, hide on quiet days); `--skip` sets `enabled: false` (skip entirely).
- All three preserve YAML comments/ordering as much as practical.

## Notes
- Schema gains `priority`, `enabled`, `report_inactivity` (from project-status).

## What landed
Three Python verbs under `.workspace/scripts/`, plus `_repos_edit.py`. Reachable
as `make add-repo ARGS="..."` etc., but the scripts are the real interface —
`make` reads bare words as extra goals, so arguments have to be tunnelled
through a variable, which is worse than just calling the script.

- **`add-repo.py <url>`** — clones, registers, seeds `.workspace/plans/<name>/`.
  Clones *before* writing the entry: a bad URL or a network failure must leave
  `repos.yml` untouched, so a retry is clean rather than a half-registered repo.
  Also refuses a duplicate name and a path already claimed by another entry.
- **`delete-repo.py <name>`** — unregisters and removes the checkout.
- **`mute-repo.py <name>`** — `report_inactivity: false` by default, `--skip`
  for `enabled: false`, `--unmute` to restore both.

### repos.yml is edited as TEXT, not round-tripped
`yaml.safe_load` → `yaml.safe_dump` would silently delete the file's 57-line
explanatory header and every per-entry comment, reflow quoting, and reorder
keys. `_repos_edit.py` does line-level edits and only parses YAML to *validate*
the result before writing — an edit that produced invalid YAML must never reach
disk, because the next reader is a status run that would fail far from the cause.
An emptied list is rewritten as `repos: []`, since a bare `repos:` parses as
None and would need a special case in every reader.

### "Unpushed" is defined generously, on purpose
`delete-repo` destroys a working copy, so it refuses unless the tree is provably
reproducible from its remote, reporting **every** reason at once:
- dirty (uncommitted *or* untracked files)
- a branch ahead of its upstream
- **a branch with no upstream at all** — the most common shape of "work that
  exists only here". Treating it as safe because there is nothing to compare
  against would delete exactly the work worth protecting.
- a stash (lives nowhere but this checkout)
- a detached HEAD on no remote branch

`--keep-checkout` unregisters without touching disk; `--force` overrides. A
linked worktree is removed with `git worktree remove`, not `rm -rf`.

## Verified — §8f (138 local / 147 with `--remote`)
Against a real bare-repo remote: add clones+registers+seeds a plan; the header
comments survive the edit; a duplicate name is refused; **a failed clone
registers nothing**; all three mute flavors write the right key; each of the four
refusal paths blocks deletion and the checkout survives all of them; the clean
path removes entry, checkout, and plan slot and restores `repos: []`;
`--keep-checkout` unregisters while leaving a dirty tree alone.

## Not in scope (stays in 012)
Injecting the commit-telemetry kernel into the child's `CLAUDE.md`. `add-repo`
prints the routine-`sources` reminder; the kernel injection is task 012's.
