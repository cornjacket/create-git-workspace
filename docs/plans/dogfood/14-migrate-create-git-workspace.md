# 14 — move `create-git-workspace` into `dev-workspace`

Status: **done (2026-08-04)** — all seven steps, acceptance verified.

The generator itself becomes a tracked child of the workspace it generates. It
is part of task `04`, but it has its own file because the ordinary "clone, then
delete the old checkout" recipe **cannot be run end-to-end from one session**.

## The hazard

A working session on this repo is rooted at
`~/src/github.com/cornjacket/create-git-workspace`. Every command resolves from
there. The last step of a migration deletes that directory — so a session doing
its own migration destroys the ground it is standing on, and every command after
that point fails in a confusing way.

**Split it across two sessions.** Steps 1–6 in the current session, step 7 only
after re-rooting.

## Procedure

From a session rooted at the *old* checkout:

1. Verify clean and pushed — `git status -sb`, `git stash list`, one branch
   tracking origin. (No local-only work: cloning cannot carry what is not on a
   remote.)
2. From `dev-workspace`:
   `python3 .workspace/scripts/add-repo.py git@github.com:cornjacket/create-git-workspace.git`
3. Confirm the fresh clone's HEAD matches the old checkout's exactly.
4. Commit the injected kernel **inside the new clone** and push it.
5. Add `https://github.com/cornjacket/create-git-workspace` to the routine's
   `sources` — send the **entire** job config back, never a partial merge.
6. `make routine-registered ARGS="create-git-workspace"`, then commit and push
   the workspace.

**Stop. Re-root a session at `dev-workspace/create-git-workspace`.** Then:

7. Delete the old checkout at `cornjacket/create-git-workspace`.

## Notes

- **No task `07` needed.** This repo was never a `project-status` target — that
  is exactly what the SessionStart nag has been reporting. It gains the commit
  kernel and nothing is stripped.
- **The generator becomes a child of its own output.** Harmless: `update.sh`
  takes an absolute target, so regenerating `dev-workspace` from inside
  `dev-workspace/create-git-workspace` works. Worth knowing rather than
  discovering.
- **This repo generates repos.** Its `sandbox/` creates throwaway git checkouts
  during the test suite, which would then sit two levels inside the workspace.
  `status --all` sweeps only depth 1 and the allowlist ignores everything under a
  child, so neither should notice them — but this is the first tracked repo that
  creates repos, so **check after landing** rather than assuming.
- **Ordering.** Do this *after* task `13`, so the generator work happens before
  the generator moves. Doing it earlier is not wrong; it just means `13` gets
  implemented from the new location after a session restart.

## What happened (2026-08-04)

Steps 1-6 ran from the old checkout, clean:

- Old checkout was clean, pushed, one branch, no stashes. `add-repo` cloned to
  the same HEAD, `a43950c`, verified by `rev-parse` on both.
- The kernel **created** `CLAUDE.md` rather than editing one — this repo had none
  at the root; the umbrella `CLAUDE.md` a level up belonged to `project-status`,
  which is being retired. Committed and pushed as `00e9562`.
- The routine's `sources` went from three URLs to four (whole job config sent
  back, not a merge), then `make routine-registered`. `make status` shows four
  clean rows with no registration finding.
- Workspace committed and pushed.

Both open questions from the notes below are now answered, not assumed:

- **The suite passes from the new location** — 344 assertions. `sandbox/` turns
  out to be **empty** afterwards: the harness cleans up its throwaway checkouts,
  so there is nothing persistent for `status --all` to trip over. Even mid-run
  they sit at depth 2, and the sweep is depth 1. Confirmed green.
- **Regenerating the workspace from inside itself works** — `./create-git-workspace/update.sh .`
  run from `dev-workspace` reports zero diff.

**Step 7 (2026-08-04).** The old checkout was `rm -rf`'d from a session rooted at
the new one — the split worked exactly as designed, and the two-session shape is
the transferable part: *any* repo that a session is normally rooted in needs its
final deletion done from somewhere else.

Re-verified after the deletion, from the new location: `make status` lists four
clean rows including `create-git-workspace`, and `make status ARGS="--all"`
returns the same four — no stray checkout on the floor, and nothing from
`sandbox/`.

## Acceptance

- `dev-workspace/create-git-workspace` exists at the same HEAD the old checkout
  had, with the kernel committed and pushed.
- It is in the routine's `sources` and `routine_registered: true`.
- `make status` is green with the repo listed.
- The old checkout is gone, deleted from a session not rooted in it.
- The test suite still passes from the new location, and `sandbox/` checkouts do
  not appear in `make status --all`.
