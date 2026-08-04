# 12 — how a git-worktree layout is tracked by a workspace

Status: **near-term step done (2026-08-04); full design still deferred** — see
DECIDED below, then "What happened".

A repo checked out as **bare + linked worktrees** has no verb that registers it.
`repos.yml` can *describe* one and `bootstrap.sh` can *replay* one, but nothing
writes those entries, so the only way in is hand-editing the lockfile that every
other rule forbids. That is why `create-ai-builder` was held back from task `04`
rather than migrated with the others.

## The concrete case

`cornjacket/create-ai-builder` is not a repo directory — it is a container:

```
create-ai-builder/
├── .bare/                 the real git dir (bare clone)
├── main/                  worktree, branch main              84c13bc
├── regression-infra/      worktree, branch regression-infra  cf5f1e9
├── workspace-mgmt/        worktree, branch workspace-mgmt    904c4a3
└── README.md              (container-level, untracked by any of them)
```

All three worktrees are clean and pushed. This idiom is why the umbrella
`CLAUDE.md` points at `./create-ai-builder/main` rather than at the directory —
the directory itself is not something you can `cd` into and run git in.

## What already works, and what is missing

**The data model exists.** `repos.yml` has a first-class `type: worktree` with
`parent_repo_path`; `bootstrap.sh` replays it with `git worktree add`;
`guard.sh` and `status.py` are worktree-safe (they test `[ -e <path>/.git ]`,
because a linked worktree's `.git` is a *file*); `delete-repo.py` removes one
with `git worktree remove` run from the parent, and refuses when the parent is
absent because the removal could not then be clean.

**The write path does not.** `add-repo.py` only ever emits `type: standard`, and
its flow is `git clone <url> <path>` — it cannot produce a bare clone, and it
writes exactly one entry per invocation. So the entries this model was designed
for can only be created by hand.

## What breaks if you just register three worktree entries

Worth writing down, because "the schema supports it" hides three real problems:

1. **The remote run cannot see them.** `_status_lib.repo_dir()` resolves a
   remote checkout via `prebuilt_source_path(name)` → `/home/user/<name>`, and
   the platform pre-clones `sources` **by repository**, naming the directory
   after the repo. A worktree entry named `create-ai-builder-main` has no
   `/home/user/create-ai-builder-main`, so it falls through to a workspace-root
   path that does not exist in the sandbox and the entry is reported
   `UNAVAILABLE` — the silent-omission failure of §5.2, permanently, by
   construction.
2. **Task `10`'s flag has no honest value for them.** `routine_registered` asks
   "is this in the routine's `sources`?" — but `sources` is a list of *repo
   URLs*. Three worktrees of one repo are one source. So either the flag lies
   for two of the three, or the gate stays red forever on entries that can never
   be satisfied.
3. **The first run triple-counts.** State is keyed by entry name, so three
   entries are three independent commit windows over one history. Each starts at
   `EMPTY_TREE..HEAD` and each summarizes its whole branch, so shared history is
   reported once per worktree. The rollup would open with the same work three
   times, in three sections, as if it were three repos.

The root asymmetry underneath all three: **the rollup is inherently per-repo**
(one history, one remote, one author window, one `sources` entry) while
**`status` is inherently per-worktree** (three working trees that can each be
dirty, ahead, or detached independently). Any design that ignores that split
will be wrong at one end.

## DECIDED (2026-08-03)

**The worktrees are long-lived parallel workstreams**, not short-lived branch
checkouts. That settles the shape:

1. **Each branch is its own `repos.yml` entry.** Per-worktree granularity is
   real granularity here — three independent workstreams that can each be dirty,
   ahead, or idle. Registering only `main` would hide two thirds of the work.
2. **A branch whose HEAD matches `main` is not summarized** — it has been
   fast-forwarded, so its commits are already reported under `main`. Report it as
   `same as main`. This is what kills the triple-counting in problem 3 above:
   shared history is attributed once, to the branch that owns it.
3. **Worktree lifecycle is the workspace's job, not the repo's.** Creating and
   removing a worktree is a membership operation, same rule as `add-repo`: the
   workspace owns the *set*, the child owns its *contents*. So the verb lives in
   `.workspace/scripts/`, and a child repo never learns it is checked out this
   way.
4. **A worktree entry resolves remotely through its parent.** This is the fix for
   problem 1: instead of looking for `/home/user/<worktree-name>`, a worktree
   entry reads the **parent's pre-cloned source** and that branch's ref. The
   pre-clone carries every ref, so `regression-infra` is readable from it without
   a second source. One `sources` line covers the whole repo.
5. **`routine_registered` is inherited from the parent**, not stored per
   worktree. That is problem 2 dissolved: three worktrees are one `sources`
   entry, so one flag is the honest representation.

**Deferred.** None of this is built yet. The near-term step is (6) below.

6. **Support the `main` worktree now.** Register `create-ai-builder/main` as a
   single standard entry so the repo is tracked at all, and leave
   `regression-infra` and `workspace-mgmt` unregistered until the above lands.
   Be explicit that this is partial: work on the other two branches is **not** in
   the rollup, and that is a known omission rather than a silent one.

## Options considered

**(a) Teach `add-repo` a `--worktree` mode.** `add-repo <url> --worktrees
main,regression-infra` clones bare into `<path>/.bare` and adds one worktree per
branch, writing a container entry plus N worktree entries. Fits the declared
model. Costs: the first verb that writes *several* entries from one invocation,
and every other verb (`delete-repo`, `routine-registered`, `replan`, the plan
slots) then has to reason about a group rather than a row.

**(b) A separate `add-worktree <parent> <branch>` verb.** `add-repo` stays
one-repo-one-entry; worktrees are added incrementally afterwards. Simpler verbs,
and it matches how worktrees actually appear (you add one when you start a
branch). Leaves the bare-clone bootstrap unowned — something still has to create
`.bare` and the first worktree.

**(c) Register the container as ONE repo; worktrees stay invisible to the
registry.** One entry, one plan slot, one `sources` line, one commit window —
which is correct for the rollup, since three worktrees share one history. The
cost is the thing you'd most want: `make status` stops seeing per-worktree dirt,
and unpushed work in `regression-infra` becomes exactly the invisible state the
pending sweep (task `01`) was built to catch.

**(d) Split by concern — (c) for the registry, plus per-worktree expansion in
`status` only.** The registry stays one-entry-per-repo; `status.py` discovers
worktrees at runtime via `git worktree list` from the container and prints a row
per worktree. Nothing is stored, so nothing can drift, and each end gets the
granularity it actually needs. Costs a runtime `git worktree list` per repo and
means a `status` row that no `repos.yml` entry corresponds to — which needs
saying out loud in the output, or it reads as an unregistered checkout.

**Outcome: (a), scoped.** The decision above is option (a) — per-worktree
entries — with the two things that made it look expensive removed: the remote
resolution goes through the parent, and the flag is inherited rather than
duplicated. `bootstrap.sh`'s existing `parent_repo_path` replay is therefore
kept, not deleted; it becomes the replay half of a write path that finally
exists.

## What happened (2026-08-04) — the near-term step

`create-ai-builder` was **moved** into `dev-workspace/create-ai-builder/`
(container and all), and `create-ai-builder/main` registered as one standard
entry named `create-ai-builder`. Child commits `56c68d5` (kernel) and `cdd3104`
(task `07` strip), workspace commit `6fd35b4`. All three worktrees came through
at their pre-move HEADs — `84c13bc` / `cf5f1e9` / `904c4a3`.

Three things the move taught, none of them predicted above:

1. **A moved worktree layout needs `git worktree repair`.** The pointers are
   absolute *in both directions* — each worktree's `.git` file holds an absolute
   path to `.bare/worktrees/<name>`, and each `.bare/worktrees/<name>/gitdir`
   holds an absolute path back to the worktree's `.git`. After the `mv`, all
   three read `prunable` and `git worktree list` still named the old location.
   `git worktree repair main regression-infra workspace-mgmt`, run from the
   container, fixed both directions at once. **Whatever verb eventually creates
   or relocates this layout has to run `repair`** — a plain `mv` leaves a repo
   that looks fine until you touch it.
2. **The entry name is load-bearing for the remote run.** It is `create-ai-builder`
   (not `create-ai-builder-main`) precisely because problem 1 above resolves a
   remote checkout as `/home/user/<name>` and the platform pre-clones by *repo*.
   The name matching the repo is what makes the one registered worktree readable
   in the sandbox — and it is the same trick decision 4 generalizes.
3. **The `--all` sweep now reports a false clean.** See below.

## Two more findings worth keeping

- **The container has a `.git` after all — and that is worse than none.**
  Corrects the original claim here. `create-ai-builder/.git` is a *file* reading
  `gitdir: ./.bare`, so `[ -e <path>/.git ]` says checkout and the depth-1
  `status --all` sweep picks the container up as `unregistered … clean`. That
  `clean` is **not a finding, it is the absence of one**: a bare repo has no
  working tree, so nothing can ever be reported dirty there. Worse, the two
  unregistered worktrees sit at depth *2* and the sweep is depth 1, so unpushed
  work on `regression-infra` or `workspace-mgmt` is invisible to the exact
  command task `01` built to catch it. The full design must make a container
  either skipped-and-said-so or expanded into its worktrees; reporting it clean
  is the one option that misleads. (It also produces two rows named
  `create-ai-builder`, which reads as a duplicate rather than a container.)
- **The rollup's window is per-HEAD, not per-repo.** `gather_report` reads
  `last..HEAD` in one directory. This is why registering only `main` loses the
  other branches' work — and why per-branch entries are the fix rather than a
  nicety.

## Open questions

- **Does the container's own `README.md` belong to anything?** It sits outside
  every worktree and is tracked by no repo. Same class of artifact as the
  umbrella `CLAUDE.md` that task `08` deletes.
- **What creates the bare clone?** `add-repo` runs `git clone <url> <path>`;
  a worktree layout needs `git clone --bare` into `<path>/.bare` and then a
  worktree per branch. That is the new write path, and it is the part with no
  existing code to lean on.
- **How does a branch get added or removed later?** A long-lived workstream ends;
  its worktree and its `repos.yml` entry should go together. That is the lifecycle
  verb from decision 3, and it is the natural sibling of `delete-repo`.

## Acceptance

**Near-term (do now):** — **met in full, 2026-08-04.**
- ✅ `create-ai-builder` is in `dev-workspace` with `main` registered as a
  standard entry, and the partial coverage stated out loud — the other two
  branches are not in the rollup. Recorded in the workspace's plan slot for the
  repo, not only here, so it is visible from where the work happens.
- ✅ It is **moved**, not re-cloned.
- ✅ `make status` green — five clean rows, exit 0, after the manual half of
  registration (`sources`) and `make routine-registered` (`cd84b06`).

**Full (deferred):**
- A verb creates the layout (bare clone + a worktree per branch) and writes the
  container plus per-branch entries. `repos.yml` is never hand-edited to achieve
  it.
- A worktree entry resolves remotely via its parent's pre-cloned source and that
  branch's ref; one `sources` line covers the repo.
- `routine_registered` is inherited from the parent, not stored per worktree.
- A branch fast-forwarded to `main` reports `same as main` and is not
  re-summarized; the rollup attributes shared history once.
- A lifecycle verb removes a worktree and its entry together.
- The decision is graduated into `DESIGN.md` (§8.6 owns membership verbs; §7.6
  owns the worktree gotcha).
