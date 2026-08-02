# create-git-workspace

A **generator** for *git-workspaces*. Clone it, run `setup.sh`, and you get a new
repo that manages a set of other repos (standard clones and worktrees) — with a
built-in, per-developer status subsystem (the evolution of `project-status`).

- Design & rationale: [`PLAN.md`](PLAN.md)
- Workspace-architecture model: [`docs/roadmap-2026-07-31.md`](docs/roadmap-2026-07-31.md)

> **Implementation status.** This README documents the intended workspace steps as
> they are built. Today: the emitted skeleton lives in `template/` (allowlist
> `.gitignore`, `repos.yml`, `CLAUDE.md`, `bootstrap`/`status`/`guard`/`lib`
> scripts). `setup.sh`, `update.sh`, the repo verbs, and the status subsystem are
> in progress — see [`tasks/`](tasks/). Steps below are marked ✅ built / 🔧 planned.

## What it generates

A git-workspace keeps all its machinery in a hidden `.workspace/` directory and
tracks *only* that machinery via an allowlist `.gitignore`; every managed child
repo is ignored, so the wrapper can never swallow them. Only `CLAUDE.md` and the
status deliverables sit at the top level.

```
<workspace>/
├── CLAUDE.md                 managed marker-block (your directives preserved)
├── summary.md                author-scoped retrospective rollup
├── daily-plan-summary.md     aggregated per-dev plans + "At a glance"
├── .gitignore                allowlist
├── .workspace/               hidden control plane
│   ├── config.yml            name · git_author(s) · generator version
│   ├── repos.yml             membership registry (standard | worktree)
│   ├── plans/<repo>/…        this developer's daily-plans (per-dev, private)
│   ├── status/…              state.json + dated plan archive
│   └── scripts/…             the workspace verbs
└── <child repos>/            managed checkouts — git-ignored
```

## Workspace steps

### 1. Generate a workspace — `setup.sh` 🔧
```bash
git clone git@github.com:cornjacket/create-git-workspace.git
cd create-git-workspace
./setup.sh <target-dir> --name my-workspace [--remote <url>]
```
Creates the wrapper (machinery + seeded `repos.yml`/`config.yml`), `git init`s it,
and injects the managed `CLAUDE.md` block without touching any file you already had.

### 2. Add / remove / mute repos 🔧
```bash
.workspace/scripts/add-repo    <url> [--branch b] [--priority n]
.workspace/scripts/delete-repo <name>          # refuses a dirty/unpushed checkout
.workspace/scripts/mute-repo   <name> [--skip]  # hide on quiet days, or skip entirely
```
`add-repo` also injects the commit-telemetry kernel into the child repo's `CLAUDE.md`.

### 3. Materialize the working set — `bootstrap.sh` ✅ (template)
```bash
.workspace/scripts/bootstrap.sh    # clone standard repos, then git worktree add worktrees; idempotent
```

### 4. Check state — `status.sh` ✅ (template)
```bash
.workspace/scripts/status.sh       # branch + clean/dirty per managed checkout
```

### 5. Guard the index — `guard.sh` ✅ (template)
```bash
.workspace/scripts/guard.sh        # fail if a child repo/.git/worktree pointer was staged; use as pre-commit hook
```

### 6. Daily status loop — push up / pull down 🔧
Per-developer status, multi-dev-safe (plans are per-workspace; the summary is
filtered to your git author):
- **Remote routine** (Claude `/schedule`, daily): reads your plans + author-scoped
  git logs, runs `claude -p`, writes `summary.md` + `daily-plan-summary.md`, lands
  them on `main` via a side branch + auto-merge workflow.
- **Local morning trigger**: `.workspace/scripts/pull.sh` → `git pull --ff-only`
  brings the aggregates down. Fast-forwards cleanly or safely declines (never
  force). Keep it clean by pushing your workspace edits before the routine runs.

### 7. Upgrade machinery — `update.sh` 🔧
```bash
cd create-git-workspace
./update.sh <target-dir>           # re-apply machinery only; re-inject CLAUDE.md block; never touch your content
```
Zero-diff property: re-running over an up-to-date workspace produces no diff.

## Testing

```bash
./tests/run-tests.sh            # full local suite; wipes sandbox/ afterward
./tests/run-tests.sh --keep     # leave the generated workspaces for inspection
./tests/run-tests.sh --remote   # additionally run the GitHub round-trip
```

Every test generates throwaway workspaces into `sandbox/` (git-ignored) — never a
real repo. The suite covers the emitted tree and allowlist, the generated scripts,
**zero-diff regeneration**, machinery overwrite + stale pruning, content/runtime
preservation, all CLAUDE.md injection paths (including malformed markers), the
version stamp, every refusal path, and a push/ff-only-pull round-trip against a
local bare remote.

The GitHub round-trip against the disposable `cornjacket/git-workspace-test`
remote is opt-in (`--remote`) and skips cleanly when the fixture is absent; the
routine scripts it exercises land in tasks 010–011. See `PLAN.md` → "Testing".
