# 25 — `status` measures a worktree against its remote, never against `main`

Status: **filed 2026-08-07**, from a real integration on `create-ai-workspace`'s
`create-ai-builder`.

`pending_findings()` answers exactly one question: *does this checkout differ
from its own upstream?* Its kinds are `dirty`, `stashed`, `ahead`,
`no-upstream`, `detached`, plus the routine gate. Every one of them compares a
checkout to **its remote**.

For a `type: worktree` entry that is the wrong axis. A worktree exists to carry
a branch that will eventually land on `main`, and the debt that actually hurts
is **how far that branch has drifted from the branch it must land on** — which
`status` cannot currently see, and which can therefore grow without limit while
every row reads `clean`.

## The concrete case

`create-ai-builder` runs three long-lived worktrees. On 2026-08-07, before any
integration:

```
main              — 6 commits the feature branches do not have
workspace-mgmt    — 15 commits ahead of main,  6 behind
regression-infra  —  4 commits ahead of main,  6 behind
```

`make status` reported `unpushed` on two rows and nothing else. Both branches
were, by its measure, healthy. The real state was a three-way divergence that
had been widening since merge-base `26840b8`.

**What the divergence had already cost, invisibly:**

- `workspace-mgmt` and `regression-infra` had independently made **the same
  change to the same five files** — the `project-status` un-bootstrap, committed
  as `a0d1f2a`/`331c61e` on one branch and `886b039`/`50e7794` on the other. Two
  people-hours of the same work, and a guaranteed rebase conflict.
- The two branches overlapped on **8 files** total, including `CLAUDE.md`,
  `.claude/settings.json`, and `.claude/hooks/check-daily-plan.py`.

That last point is the one that matters for the design. The owner's mental model
was *"my worktrees are orthogonal — they touch different features, so they will
not collide."* The measurement says otherwise, and it says so for a structural
reason: **cross-cutting chores defeat feature-orthogonality.** Retiring a
tracker, editing `CLAUDE.md`, changing a hook — these land on every branch by
nature, no matter how cleanly the *features* are partitioned.

Nobody could have known this without the number. That is the argument for
measuring it.

## Why this is a workspace concern and not the repo's own problem

`repos.yml` already holds everything needed, and holds it *only* here:

```yaml
type:             worktree
parent_repo_path: <the repo the worktree hangs off>
branch:           <the branch it carries>
```

The workspace is the only layer that knows a given checkout is a worktree, which
repo it belongs to, and therefore what its integration branch is. A repo looking
at itself sees a branch; the workspace sees a *set* of branches that must
eventually reconcile onto one trunk. Divergence between them is a property of
the set.

It is also the layer that already iterates the roster every day.

## The fix, in two phases that must not be merged

**Phase 1 — measure. Safe, and the whole value.**

A new finding kind, produced only for `type: worktree` rows:

```python
# in _status_lib.pending_findings(), or a sibling that status.py folds in
ahead, behind = git_rev_list_left_right(f"{integration_branch}...HEAD", cwd=d)
if ahead + behind >= divergence_threshold:
    findings.append(("diverged", f"{ahead} ahead, {behind} behind {integration_branch}"))
```

- Threshold in `config.yml`, workspace-level, one number
  (`worktree_divergence_threshold:`), defaulting to something deliberately low —
  **10 total commits**. The point is to fire early, while a rebase is still
  cheap.
- Below the threshold, report the counts as *fact*, not as a finding, the way
  `local-only` is reported: a `2 ahead, 0 behind` row is healthy and should not
  turn `make status` red.
- Compare against `parent_repo_path`'s **local** integration branch, not
  `origin/main`. The trunk you must land on is the one on disk.
- Resolve the integration branch rather than hardcoding `main` — read the parent
  repo's default branch. This workspace has no `master`, but a managed repo
  might.

**Phase 2 — remediate. A verb the operator types, never the routine.**

`make integrate REPO=<name>`, which does exactly what was done by hand today:

```
git rebase <integration-branch>          # in the worktree
git merge --ff-only <worktree-branch>    # in the parent repo
```

`--ff-only` is the load-bearing flag: it *refuses* rather than silently
producing a merge commit, so the linear history is enforced by git rather than
by discipline.

## Why phase 2 must not be automatic — the correction to the original idea

The request this task came from was: *if past threshold, perform a rebase
followed by a fast-forward.* **The measurement should be automatic. The rebase
must not be.** Three reasons, in increasing order of severity:

1. **A rebase can conflict.** An unattended rebase that hits a conflict leaves
   the worktree in a mid-rebase state with a detached HEAD and a half-applied
   patch series. That is strictly worse than the divergence it was fixing, and
   the daily routine would have done it to you overnight, on every diverged
   repo, in parallel. In the concrete case above, conflicts across those 8
   shared files were **certain**.
2. **Rebase rewrites published history.** All three branches on
   `create-ai-builder` are on `origin`. Rebasing rewrites commits the remote
   already has, so it forces a `--force-with-lease` push to reconcile. A daily
   job that force-pushes branches is a different category of tool than a status
   reporter, and not one this workspace should quietly become.
3. **It breaks the read-only contract.** `status` is a reporting pipeline;
   `guard.sh` exists precisely to stop the machinery from mutating managed
   checkouts. Making the daily run rewrite history inverts that guarantee, and
   every future reader of `status.py` would have to know it.

The honest split: **automate the thing that is always safe and always right
(counting), and make the dangerous thing one keystroke away (`make integrate`).**
That achieves the actual goal — *do not allow long-lived divergence* — because
what prevents drift is knowing about it early, not repairing it unattended.

`make integrate` should additionally: refuse on a dirty tree, abort the rebase
cleanly on conflict and say so, and **never push**. Pushing stays the operator's.

## Where to implement — not in `dev-workspace`

`template/workspace/scripts/status.py` in this generator is **byte-identical**
to `dev-workspace/.workspace/scripts/status.py` (verified 2026-08-07). That
directory is managed machinery: `update.sh` overwrites it, so a fix authored in
`dev-workspace` is destroyed by the next update.

Prototype there if it is faster to iterate against a live roster with real
worktrees — but the change lands **here**, in `template/workspace/scripts/`, and
reaches `dev-workspace` through `update.sh`. Nothing in `.workspace/scripts/`
is a source file.

## What this does NOT cover, deliberately

- **Choosing an integration strategy per repo.** This assumes rebase + ff-only,
  because that is what the one real user wants and what `--ff-only` can enforce.
  A repo that prefers merge commits has no user yet; a `strategy:` field in
  `repos.yml` would be declaring something no one has asked for.
- **Anything about pushing.** Divergence from `main` and divergence from
  `origin` are different debts; `ahead` already covers the second one.
- **The `create-ai-builder` case's own cleanup.** Its `CLAUDE.md` documents
  *ephemeral* worktrees torn down by `remove-worktree.sh` after a merged PR,
  which contradicts the long-lived model that produced this divergence. That is
  that repo's task, not this one's.

## Acceptance

- ✅ A `type: worktree` row past the threshold reports
  `diverged (15 ahead, 6 behind main)` and `make status` exits non-zero.
- ✅ A worktree below the threshold reports its counts without turning the run
  red.
- ✅ A `type: standard` row is unaffected — no divergence finding, no new git
  calls.
- ✅ The integration branch is resolved from the parent repo, not hardcoded.
- ✅ The daily routine never rebases, never force-pushes, and `guard.sh`'s
  read-only contract still holds.
- ✅ `make integrate` refuses a dirty tree, aborts cleanly on conflict, and does
  not push.
- ✅ A test covers a workspace with a diverged worktree, using the
  `git-workspace-test` fixture.
