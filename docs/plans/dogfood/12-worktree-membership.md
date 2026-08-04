# 12 — how a git-worktree layout is tracked by a workspace

Status: open — **blocks bringing `create-ai-builder` into `dev-workspace`**

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

## Options

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

## Lean

**(d)**, on the strength of the asymmetry argument: it is the only option where
neither end is wrong, and it stores nothing that could disagree with reality.
**(c)** is the fallback if runtime discovery proves noisy — it is strictly
better than (a)/(b) for the rollup, and its only loss is per-worktree dirt,
which `make status --all` on the floor still catches today.

Not (a) or (b) until there is a second worktree repo: one instance is not enough
to justify a group-aware write path across five verbs.

## Open questions

- **How are those three worktrees actually used day to day?** If they are
  long-lived parallel workstreams, per-worktree status matters and (d) wins. If
  they are short-lived branch checkouts, (c) is enough and the whole thing is
  simpler.
- **Does the container's own `README.md` belong to anything?** It sits outside
  every worktree and is tracked by no repo. It is the same class of artifact as
  the umbrella `CLAUDE.md` that task `08` deletes.
- **Should `bootstrap.sh`'s existing worktree replay survive at all** if the
  registry stops declaring worktrees? It is currently the only consumer of
  `parent_repo_path`. Removing an unused code path is cheaper than keeping one
  that nothing can produce — but it is also the only thing that would let a
  hand-written entry work.

## Acceptance

- A decision recorded here and graduated into `DESIGN.md` (§8.6 owns the
  membership verbs; the worktree gotcha is §7.6).
- `create-ai-builder` is registered in `dev-workspace` under that decision, with
  all three worktrees present and `make status` green.
- The rollup reports its history **once**, not once per worktree.
- Whatever the decision, `repos.yml` is not hand-edited to achieve it — either a
  verb writes it, or the schema stops claiming to support what nothing writes.
