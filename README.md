# create-git-workspace

A **generator** for *git-workspaces*. Clone it, run `setup.sh`, and you get a new
repo that manages a set of other repos (standard clones and worktrees) — with a
built-in, per-developer status subsystem (the evolution of `project-status`) and
its own task-system for the work that belongs to no single repo.

- Design & rationale: [`DESIGN.md`](DESIGN.md) — the workspace model, the file
  classes, and every settled decision
- How work is planned here: [`docs/plans/README.md`](docs/plans/README.md)
- The effort that built this: [`docs/plans/genesis/`](docs/plans/genesis/)

> **Implementation status.** Every step below is built and covered by the
> acceptance suite. The `genesis` effort is closed; there is no active `PLAN.md`
> until the next one starts.

## Quick start

```bash
git clone git@github.com:cornjacket/create-git-workspace.git
cd create-git-workspace
./setup.sh ~/src/my-workspace --name my-workspace --remote git@github.com:you/my-workspace.git
cd ~/src/my-workspace && make            # lists every command
```

`setup.sh` creates the **wrapper only**. It never clones, inits, or creates the
managed child repos — that is `add-repo.py`'s and `bootstrap.sh`'s job.

## What it generates

A git-workspace keeps all its machinery in a hidden `.workspace/` directory and
tracks *only* that machinery via an allowlist `.gitignore`; every managed child
repo is ignored, so the wrapper can never swallow one.

```
<workspace>/
├── CLAUDE.md                 always-on kernel (managed marker-block) + your directives
├── README.md                 the human front door: generated roster block + your prose
├── Makefile                  visible command surface over the hidden scripts
├── summary.md                RUNTIME: author-scoped retrospective rollup
├── daily-plan-summary.md     RUNTIME: aggregated plans + "At a glance"
├── .gitignore                allowlist
├── project/                  the workspace's OWN task-system (triage) + status/
├── .claude/skills/…          workspace-status (+ task-system) on-demand skills
├── .github/workflows/…       auto-merge-status.yml · claude.yml
├── .workspace/               hidden control plane
│   ├── config.yml            name · git_author(s) · generator_version
│   ├── repos.yml             membership lockfile (standard | worktree)
│   ├── status-guide.md       the operating reference the kernel points at
│   ├── daily-plans/<repo>/…  this developer's daily plans (per-dev, private)
│   ├── prompts/…             the summariser prompts fed to `claude -p`
│   ├── templates/…           the commit kernel injected into child repos
│   ├── state/…               state.json + dated plan archive (runtime)
│   └── scripts/…             the workspace verbs
└── <child repos>/            managed checkouts — git-ignored
```

Instructions for the emitted workspace follow a three-layer split: a small
always-on `CLAUDE.md` kernel, the `workspace-status` skill for on-demand loading,
and `.workspace/status-guide.md` holding the procedure exactly once.

## Workspace steps

### 1. Generate a workspace — `setup.sh` ✅
```bash
./setup.sh <target-dir> [--name NAME] [--author EMAIL]
                        [--remote URL | --create-remote [--public]]
                        [--with-hook] [--no-tasks] [--no-commit] [--force]
```
Creates the wrapper, `git init`s it, writes the machinery, seeds the content
(`repos.yml`, `config.yml`, plans, `README.md`), injects the managed `CLAUDE.md`
block without touching any file you already had, installs the task-system, and
makes the initial commit.

`--author` seeds `git_author` in `config.yml`, falling back to
`git config user.email`; if neither resolves it writes a placeholder and warns
loudly, and the status run later **refuses to start** rather than produce an
empty rollup.

There is no `--no-status`: the status subsystem is not a layer a workspace opts
into, it *is* the workspace layer. The task-system is optional (`--no-tasks`)
because it is a separate, delegated generator.

`--remote` attaches an existing remote; `--create-remote` makes one with `gh`
(**private** unless you add `--public` — a workspace carries your plans and your
rollup). They are mutually exclusive, and both `gh`'s presence and its auth are
checked *before* anything is stamped. It creates and wires origin but does not
push; the closing print names that command.

### 2. Add / remove / mute repos ✅
```bash
python3 .workspace/scripts/add-repo.py    <url> [--name N] [--branch B] [--priority N]
python3 .workspace/scripts/delete-repo.py <name>            # refuses a dirty/unpushed checkout
python3 .workspace/scripts/mute-repo.py   <name> [--skip]   # hide on quiet days, or skip entirely
```
Or `make add-repo ARGS="<url>"`. `add-repo` clones *before* registering (a bad
URL leaves the registry untouched), seeds the repo's plan slot, and injects the
commit-telemetry kernel into the child's `CLAUDE.md` — without committing inside
the child, so the change lands with your identity and that repo's hooks.

`delete-repo` refuses a dirty tree, an unpushed branch, a branch with no
upstream, a stash, or a detached HEAD — and reports every reason at once.

**`repos.yml` is a lockfile, not a config file you author.** The verbs write it
as *text*, so its comments and ordering survive; `bootstrap.sh` replays it.

Each verb also refreshes the workspace `README.md`'s **roster block** — the
tracked repos with a one-line description each, their paths, and whether they are
muted, skipped, or not checked out on this machine, plus the deliverable links
and the scheduled routine's status. `add-repo` seeds a repo's description from
the best available source — `--description`, else the repo's own **GitHub
description** (`gh repo view`), else the first prose paragraph of its
`README.md`/`CLAUDE.md` with badges and headings skipped — and stores it in
`repos.yml`, where you can correct it. `make readme` re-renders by hand, `make readme-check` reports staleness.
There is no branch column on purpose: a branch is mutable and per-checkout for
worktrees, so a registry copy of it would drift into a lie.

### 3. Materialize the working set — `bootstrap.sh` ✅
```bash
make bootstrap    # clone standard repos, then git worktree add worktrees; idempotent
```

### 4. Check state — `status.py` ✅
```bash
make status       # branch + uncommitted/unpushed per checkout
make status ARGS="--all"   # also sweep unregistered checkouts on the floor
```

### 5. Guard the index — `guard.sh` ✅
```bash
make guard        # fail if a child repo / .git dir / worktree pointer was staged
make hook         # install it as this clone's pre-commit hook (hook-check reports status)
```
`setup.sh --with-hook` does the same at stamp time. It is **per-clone** — git
does not track `.git/hooks/`, which is why the installer ships inside the
workspace rather than being something only the generator can do. It refuses to
overwrite or remove a pre-commit hook it did not write.

### 6. Daily status loop — push up / pull down ✅
Per-developer status, multi-dev-safe: plans live per-workspace, and every git
read is filtered to your `git_author`, so ACTIVE means "*you* committed".

- **Locally:** `make run` (or `make run-dry` for a deterministic, LLM-free pass)
  summarizes → aggregates → advances state.
- **Remote routine** (Claude `/schedule`, daily) runs `.workspace/scripts/daily.sh`:
  reads your plans + author-scoped git logs, runs `claude -p`, writes
  `summary.md` + `daily-plan-summary.md`, and lands them on `main` via a dated
  side branch plus the auto-merge workflow (the routine's GitHub App identity
  cannot push to the default branch).
- **Local morning trigger:** `make pull` → `git pull --ff-only`. It advances or
  it declines and tells you which — never merges, rebases, or forces. Exit 1 is
  "you are ahead or diverged", exit 2 is "misconfigured", so a trigger can alert
  on breakage without nagging about unpushed work.

Two steps the generator cannot install for you — creating the `/schedule`
routine, and adding each tracked repo to its `sources` pre-clone list — are
documented in the emitted `.workspace/status-guide.md` (§5).

### 7. Upgrade machinery — `update.sh` ✅
```bash
./update.sh <target-dir>    # machinery only; re-injects the CLAUDE.md block; never commits
```
**Zero-diff property:** re-running over an up-to-date workspace produces no diff,
with no `--force`. It also delegates to the vendored `create-project-system` so
the installed task-system upgrades in step, and mirrors its own directories — a
script dropped from the template is deleted from the workspace and the removal
announced, so retired machinery cannot linger.

## The machinery / content / runtime split

Regeneration is only safe because every emitted file is classified once. Class is
per-file and independent of whether it sits inside `.workspace/`.

| Class | Examples | `setup.sh` | `update.sh` |
|---|---|---|---|
| **machinery** | `.workspace/scripts/`, `prompts/`, `templates/`, `status-guide.md`, `.claude/skills/workspace-status/`, `.github/workflows/`, `.gitignore`, `Makefile` | write | **overwrite** |
| **content** | `repos.yml`, `config.yml`, `plans/**`, `README.md`, your tasks | seed if missing | seed if missing; **never overwrite** |
| **runtime** | `summary.md`, `daily-plan-summary.md`, `.workspace/state/` | — | — |
| **hybrid** | the `CLAUDE.md` managed block, `README.md`'s roster block | create-or-inject | replace the block only |
| **delegated** | the installed task-system | install | upgrade (its own split) |

The runtime class is what keeps zero-diff honest: `setup`/`update` never race the
daily routine's files. `config.yml` is content except for the one
`generator_version` key the generator owns — the same hybrid rule at single-line
granularity, so version telemetry cannot go stale.

## Inside this repo

```
DESIGN.md                the durable design: the model, the file classes,
                         every settled decision
docs/plans/              finished efforts + their task files; README.md there
                         describes the plan → tasks → graduate-to-DESIGN cycle
docs/templates/          PLAN.md.template, copied to the root to start an effort
setup.sh · update.sh     the two entry points
lib/generator.sh         every byte of machinery is written here, so both
                         entry points emit identical output (this is what
                         makes zero-diff hold)
template/                the skeleton that gets emitted
  ├── CLAUDE.md          the managed block (kernel)
  ├── gitignore          → .gitignore (dotless so it stays inert here)
  ├── github/            → .github/
  ├── claude/            → .claude/ (the workspace-status skill)
  └── workspace/         → .workspace/
vendor/                  create-project-system, copied in verbatim
tools/revendor.sh        refresh that copy from an upstream checkout
tests/run-tests.sh       the acceptance suite
sandbox/                 throwaway generated workspaces (git-ignored)
```

## Testing

```bash
./tests/run-tests.sh            # full local suite; wipes sandbox/ afterward
./tests/run-tests.sh --keep     # leave the generated workspaces for inspection
./tests/run-tests.sh --remote   # additionally run the GitHub round-trip
```

276 local assertions. Every test generates throwaway workspaces into `sandbox/`
(git-ignored) — never a real repo. The suite covers the emitted tree and
allowlist, the generated scripts, **zero-diff regeneration**, machinery overwrite
+ stale pruning, content/runtime preservation, all `CLAUDE.md` injection paths
(including four malformed-marker shapes), the version stamp, every refusal path,
the task-system delegation, the status pipeline against a stubbed `claude` on
`PATH`, the repo verbs, the kernel/guide/skill split, the opt-in extras
(including a real blocked commit through the installed hook), the living README
roster, and a push + ff-only-pull round-trip against a local bare remote.

CI (`.github/workflows/tests.yml`) runs the suite on every push to `main` and
every PR, so the zero-diff invariant is protected by the repo rather than by
remembering. A failed run uploads `sandbox/` as an artifact — the generated
workspaces are the evidence.

The GitHub round-trip against the disposable `cornjacket/git-workspace-test`
remote is opt-in (`--remote`) and skips cleanly when the fixture is absent, since
that sibling checkout does not exist on a runner. See [`DESIGN.md`](DESIGN.md) §7.8.

## Vendoring

`vendor/create-project-system/` is a verbatim copy of the task-system generator
(`generate.sh` + `src/` only), so a fresh clone can stamp a fully task-tracked
workspace with nothing external to fetch — self-containment over DRY. Refresh it
with `./tools/revendor.sh [path-to-create-project-system]`, which re-stamps the
version and leaves the diff for review. See [`vendor/README.md`](vendor/README.md).
