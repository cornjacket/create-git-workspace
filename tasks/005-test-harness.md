# 005 — test harness

Status: done (2026-08-01) — GitHub round-trip stubbed opt-in (fixture does not exist)

Exercise generation against throwaway targets only.

## Acceptance
- Generates test workspaces into `sandbox/` (gitignored) — never a real repo.
- **Zero-diff regeneration:** `setup.sh sandbox/ws1` then `update.sh sandbox/ws1`
  → `git diff` is empty.
- Asserts emitted tree + allowlist: `.workspace/scripts/*`, `.workspace/repos.yml`,
  top-level `CLAUDE.md`, `.gitignore`.
- Remote round-trip: `setup.sh sandbox/ws2 --remote git@github.com:cornjacket/git-workspace-test.git`,
  push, `bootstrap.sh` a sample `repos.yml`, `status.sh` clean.
- Teardown: wipe `sandbox/`, delete the `git-workspace-test` remote.

## Notes
- `git-workspace-test` is a disposable remote (assumption in PLAN.md, confirm).
- Applies the hygiene rule: scratch in a gitignored `sandbox/`.

## What landed — `tests/run-tests.sh` (61 assertions, 10 sections)
`./tests/run-tests.sh` · `--keep` to inspect the generated workspaces · `--remote`
for the GitHub round-trip. Assertions never abort the run, so one invocation
reports everything that broke.

1. emitted tree + allowlist (exact tracked-file set) · 2. generated scripts resolve
their root from an unrelated cwd · 3. **zero-diff regeneration** · 4. machinery
overwrite + stale pruning · 5. content and runtime preservation · 6. all CLAUDE.md
paths incl. the four malformed-marker refusals · 7. version stamp propagates then
settles · 8. refusals + rename-safety + the no-identity path · 9. push/ff-only-pull
round-trip · 10. GitHub round-trip (opt-in).

- `EXPECTED_TRACKED` at the top of the file is the emitted-tree contract. When a
  task adds an emitted file, update it deliberately — a surprise there means the
  generator started emitting something unplanned.
- Section 7 runs against a **copy** of the generator in `sandbox/gen-copy` so
  bumping `VERSION` to test propagation never dirties the repo.

## The GitHub round-trip — now live (`--remote`, 70 assertions total)
The fixture `cornjacket/git-workspace-test` + its sibling checkout were created
mid-task, so §10 became real. It stamps/updates the fixture, pushes, clones fresh
(what the remote routine's sandbox actually sees), has the "routine" write both
deliverables and land them on `main`, then `pull --ff-only`s them down. The
decline path runs in a throwaway clone: a diverged history must make `--ff-only`
**refuse**, leaving the local commit untouched. Repeatable — a second run passes.

Guards, because it touches a real checkout: it skips (never fails) when the
fixture is missing, has uncommitted changes, or origin is unreachable, and it
leaves the fixture clean and in sync.

- Section 9 keeps the same shape against a *local bare repo* — no network, no
  fixture — so the round-trip stays covered in the default run.

## Found by the round-trip: the allowlist blocked the deliverables
`summary.md` / `daily-plan-summary.md` were still ignored (those `!` lines were
deferred in `001`), so the routine could not have committed its own output. The
local bare-remote test had masked this with `git add -f`; against the real remote
the failure was obvious. Fixed in `template/gitignore`, and §10 now stages both
**without** `-f` so the regression cannot come back.

## The harness was mutation-tested
A green suite on its first run proves nothing, so each invariant was deliberately
broken and the suite confirmed to catch it:

| Injected bug | Caught by |
|---|---|
| `WORKSPACE_ROOT` resolves one level up (the 001 bug) | 2 failures in §2 |
| `repos.yml` misclassified as machinery | "repos.yml edit survives" |
| `CLAUDE.md` clobbered instead of block-injected | 8 failures across §5–6 |
| allowlist drops `!/Makefile` (the real 002 bug) | both tree assertions |
| version stamp disabled | 2 failures in §7 |
| stale-machinery pruning removed | "a script dropped ... is pruned" |
| nondeterministic machinery (timestamp in Makefile) | 7 zero-diff failures |

One mutation initially "passed" — patching `seed_content_file` to delete before
writing. That was an invalid mutation, not a gap: `update.sh` never calls that
function. Replaced with the misclassification bug above, which the suite catches.
