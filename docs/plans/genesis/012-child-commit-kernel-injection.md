# 012 — child commit-kernel injection

Status: done (2026-08-02)

Inject the commit-telemetry kernel into each tracked child repo's `CLAUDE.md`, so
git history carries the structured `[Context]`/`[Impact]` telemetry the summary
reads. Folded from project-status's `setup-new-repo.sh` — the **commit half only**.

## Acceptance
- Marker block (`ai-project-status:begin/end` style) injected into the child's
  `CLAUDE.md` via `add-repo` (task 009); idempotent, preserves user content.
- **Commit-discipline only — drop the daily-plan half** (plans live in the
  workspace now).
- The stale-plan `SessionStart` nag moves to the workspace, not the child.

## Notes
- Distinct from the task-tracking kernel `create-project-system` injects (task 006).

## What landed
- `.workspace/templates/commit-kernel.md` (machinery) — the block itself.
- `.workspace/scripts/inject-kernel.py` — `<name>...` / `--all` / `--check`,
  plus `make inject-kernel` and `make kernel-check`.
- `add-repo` injects it at registration, so a repo's history is readable as
  telemetry from its first day rather than whenever someone remembers.
- Marker: `git-workspace-commits:begin/end` — deliberately NOT project-status's
  `ai-project-status`, so that during migration a repo can carry both and the
  old block can be stripped as its own step (PLAN's retirement sequence).

## The kernel is workspace-agnostic, and that is load-bearing
The block is **committed to the shared child repo**, and several developers may
each track that repo from their own workspace. So it contains no workspace name,
no developer email, and no version stamp — any of those would make two
developers overwrite each other's block on every injection, forever. It is
copied verbatim by `install_machinery`, never rendered. Two tests assert the
emitted block contains neither the workspace name nor the author.

## It never commits inside a child repo
The workspace edits the file and stops. You `cd` into the repo and commit there,
so the change lands with your identity, your review, and that repo's hooks —
the same rule the workspace CLAUDE.md states for all child-repo work. The script
prints the exact `cd … && git commit` for each repo it touched.

## Commit-discipline only
The daily-plan half of project-status's kernel is gone: plans moved up into each
developer's workspace. The block now says explicitly *do not create a
`daily-plan.md` here*, because a shared plan file in a shared repo is a file two
people overwrite. `--check` gives the drift detection project-status did in
`target_drift`, without needing the tracker.

## A test this broke, correctly
§8f's clean-path `delete-repo` started failing: `add-repo` now leaves the child
dirty (the uncommitted kernel), so deletion rightly refused. The fix was in the
test — commit and push the kernel the way a user would. Worth knowing as
behavior: immediately after `add-repo`, the child has an uncommitted CLAUDE.md.

## Verified — §8i (178 local / 187 with `--remote`)
Kernel injected on `add-repo` with the repo's own content preserved; no
workspace/developer name in the block; left uncommitted in the child, which
still has only its own commit; re-injection byte-identical; `--check` passes when
current and fails on drift; `--all` refreshes a mangled block while keeping the
repo's own text.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `012` — child commit-kernel injection (commit-discipline only). *(marker `git-workspace-commits`, distinct from project-status's block so both can coexist during migration; the kernel names no workspace or developer, since it is committed to a shared repo.)*
