# PLAN — create-git-workspace

## What we're building (one line)

**`create-git-workspace` is a generator.** A user clones it, runs `setup.sh` to
stamp out a new **git-workspace** repo (a wrapper that manages other repos and
worktrees), and runs `update.sh` to re-apply the generator's machinery to an
existing workspace later. It follows the cookiecutter pattern: a template tree +
a renderer, with a strict **machinery vs content** split so regeneration is safe.

This repo captures the hand-built wrapper we designed in
`docs/roadmap-2026-07-31.md` (scripts, allowlist `.gitignore`, `repos.yml`,
`CLAUDE.md`) under `template/`; the work now is to wrap it in `setup.sh` /
`update.sh` and test it.

---

## Key design decision: machinery lives in a hidden `.workspace/` dir

> **Decision (locked):** the generated workspace keeps all generator-owned
> machinery in a hidden directory named **`.workspace/`**, with only `CLAUDE.md`
> (+ `README.md`) at the top level. (Rejected `.git-worktree` — it names one of
> two checkout types and `.git*` invites confusion with git internals.)

Why hide it:
- The root then shows the **managed child repos** (what you actually work in) and
  `CLAUDE.md` — not plumbing. Declutters exactly the way we wanted.
- It physically reinforces the machinery/content boundary: (almost) everything
  under `.workspace/` is overwritten on update; everything outside is content.
- It's the legitimate dotdir-for-tooling pattern (`.github/`, `.husky/`).

Consequences baked into the plan:
- Scripts resolve `WORKSPACE_ROOT` **two levels up** (`.workspace/scripts/lib.sh`
  → `../..`), not one.
- `repos.yml` lives inside `.workspace/` but stays **content** (per-file class).
- `CLAUDE.md` stays at top level as the visible entry point that documents where
  the hidden machinery is (discoverability preserved for humans and agents).
- **Decided:** a top-level `Makefile` gives a visible command surface
  (`make status`, `make bootstrap`, …) so the hidden scripts aren't typed by hand.

---

## Roles: generator vs generated workspace

```
  create-git-workspace/            (the GENERATOR — what the user clones)
  ├── setup.sh                     create a new git-workspace
  ├── update.sh                    re-apply machinery to an existing one
  ├── template/                    the skeleton emitted into a workspace
  │   ├── CLAUDE.md                → top-level, {{WORKSPACE_NAME}}  (MACHINERY)
  │   ├── gitignore                → top-level .gitignore (allowlist) (MACHINERY)
  │   └── workspace/               → emitted as .workspace/
  │       ├── repos.yml            starter membership registry (CONTENT — seed only)
  │       └── scripts/             lib · bootstrap · status · guard (MACHINERY)
  ├── sandbox/                     GENERATED TEST WORKSPACES (gitignored, throwaway)
  ├── docs/                        design docs (the roadmap)
  ├── tasks/                       task tracker for building THIS generator
  ├── .gitignore                   ignores sandbox/
  └── PLAN.md                      this file

          │  setup.sh <target>
          ▼
  <target>/  (the GENERATED git-workspace — manages other repos)
  ├── CLAUDE.md              hybrid: managed block + your content   (visible)
  ├── README.md              content — links the deliverables        (visible)
  ├── summary.md             runtime deliverable                      (visible)
  ├── daily-plan-summary.md  runtime deliverable                      (visible)
  ├── Makefile               command surface (machinery)             (visible)
  ├── project/               FIRST-CLASS deliverable (create-project-system)
  │   ├── tasks/               the task-system (mount = project/tasks)
  │   ├── status/              narrative reports (status-review mtgs; optional)
  │   └── README.md            project container
  ├── .claude/skills/…       task-system skill (machinery)
  ├── .gitignore             allowlist (machinery)
  ├── .github/workflows/     auto-merge-status.yml, claude.yml (machinery)
  ├── .workspace/            hidden control plane
  │   ├── config.yml           content: name · git_author · version
  │   ├── repos.yml            content: membership
  │   ├── scripts/             machinery: lib, bootstrap, status, guard,
  │   │                          add/delete/mute-repo, sync, new-work,
  │   │                          aggregate-plans, run, daily.sh, pull.sh
  │   ├── plans/               content: <repo>/ · _workspace/
  │   ├── state/               runtime: state.json · archive/
  │   └── status-guide.md      on-demand guide (machinery)
  └── <child repos>/         ignored by the allowlist
```

Emitted allowlist `.gitignore`:

```
/*
!/.workspace/
!/project/
!/.claude/
!/.github/
!/CLAUDE.md
!/README.md
!/summary.md
!/daily-plan-summary.md
!/Makefile
```

> `docs/` is **not** emitted into a workspace. Documentation *about* the workspace
> system (the roadmap) lives only in the generator, `create-git-workspace/docs/`.

> **Reconciled (review complete).** Layout now includes `project/` (first-class
> deliverable), the top-level `summary.md` / `daily-plan-summary.md` / `Makefile`,
> `.github/workflows/`, and the full `.workspace/` control plane.

---

## The machinery / content split (the load-bearing decision)

Regeneration is only safe if every emitted file is classified **once**. There are
**three classes**, each with its own rule; class is per-file, independent of
whether it sits inside `.workspace/`. This is what lets `update.sh` re-run over a
live workspace and produce a **zero-line diff** — no `--force`.

| File | Class | `setup.sh` | `update.sh` |
|------|-------|-----------|-------------|
| `.workspace/scripts/*.sh` | **machinery** | write | **overwrite** |
| `.gitignore` (from `template/gitignore`) | **machinery** | write | **overwrite** |
| installed task-system (via `create-project-system`) | **delegated** | install | upgrade |
| `CLAUDE.md` (managed block) | **hybrid** | create-or-inject block | **replace block only** |
| `.workspace/repos.yml` | **content** | seed if missing | seed if missing²; **never overwrite** |
| `.workspace/config.yml` | **content** | seed if missing | **leave untouched** except the `generator_version` key¹ |
| `.workspace/plans/**` | **content** | seed if missing | seed if missing²; **never overwrite** |
| `README.md` | **content** | seed if missing | seed if missing²; **never overwrite** |
| `.workspace/state/state.json`, `archive/` | **runtime** | — | — |
| `summary.md`, `daily-plan-summary.md` | **runtime** | — | — |

The three classes:

- **machinery** — the generator owns it; *always overwritten*. Users are told not
  to fork it.
- **content** — the *user* edits it (repo list, identity, plans, readme); *created
  if missing, never overwritten*.
- **runtime** — the **daily status routine** writes it, not `setup`/`update`. It is
  committed (it's the durable record + the deliverables) but neither seeded by
  setup nor touched by update — the routine owns it. This is the class that keeps
  the zero-diff property honest: setup/update never race the routine's files.

¹ *Amended in task `003`.* `generator_version` is canonical version telemetry, so
freezing it at the setup-time value makes it lie after every upgrade. `update.sh`
rewrites **only that line** — the same hybrid rule as `CLAUDE.md`, applied at
single-line instead of block granularity: the generator owns the key, the user
owns every other byte of the file. Idempotent, so zero-diff still holds.

² *Amended in task `007`.* The content rule is "never overwrite", **not** "never
create". `update.sh` seeds a content slot that is *missing* — otherwise a slot
introduced by a newer generator version could never reach an existing workspace,
because only `setup.sh` seeds and it refuses to run on a live one. (Found the
moment `_workspace/daily-plan.md` was added: the upgraded test fixture silently
lacked it.) Creating an absent file destroys nothing, and zero-diff is unaffected
— on a current workspace every slot already exists, so nothing is written.

Also decided in `003`: `.workspace/scripts/` is **mirrored**, not merely copied
over — a script dropped from the template is deleted from the workspace (and the
removal announced), so retired machinery cannot linger.

`CLAUDE.md` is the one **hybrid** — a machinery block inside a content file (§5).
The task-system the vendored `create-project-system` installs follows *its own*
machinery/content split, delegated to that generator.

---

## `CLAUDE.md`: marker-block injection (not overwrite)

`CLAUDE.md` must be **updateable without clobbering the user's own directives**.
So it is neither pure machinery nor pure content: the generator owns a
**marker-delimited managed block**, and everything outside the markers is the
user's, preserved verbatim across updates. (Same convention as the `cornjacket`
umbrella `CLAUDE.md`'s `project-status:begin/end` block.)

Markers:

```
<!-- git-workspace:begin — managed by create-git-workspace; do not edit inside this block -->
   ... generated workspace directives ...
<!-- git-workspace:end -->
```

Injection algorithm (used by both `setup.sh` and `update.sh`):

1. **No `CLAUDE.md`** → create it: `# CLAUDE.md — <name>` + the managed block.
2. **Has `CLAUDE.md` with markers** → replace only the text between the markers.
3. **Has `CLAUDE.md`, no markers** (user brought their own) → **append** the block
   at the end, without touching their content (least disruptive to their framing).

The zero-diff property still holds: if the block already matches the current
template, re-injection changes nothing. The block content is rendered from
`template/CLAUDE.md` (the region between its markers), with `{{WORKSPACE_NAME}}`
substituted.

---

## `setup.sh` — create a new git-workspace

**Usage (proposed):** `./setup.sh <target-dir> [--name NAME] [--author EMAIL] [--remote URL] [--no-tasks] [--no-status]`
(Full-featured by default; `--no-tasks` / `--no-status` opt out. `--with-tasks`
runs the vendored `create-project-system`.)

1. Resolve `<target-dir>`; refuse if it already looks like a workspace (has
   `.workspace/`) unless `--force` — point at `update.sh` instead.
2. `mkdir -p <target>` and `git init` it.
3. **Machinery:** copy `template/workspace/scripts/` → `<target>/.workspace/scripts/`
   (chmod +x); copy `template/gitignore` → `<target>/.gitignore`.
4. **`CLAUDE.md` (managed block):** create-or-inject per the injection algorithm
   above, `{{WORKSPACE_NAME}}` substituted — never overwrite a user's file.
5. **Content (seed if missing):** `template/workspace/repos.yml` →
   `<target>/.workspace/repos.yml`; seed `.workspace/config.yml` (name +
   `git_author`); generate a starter `README.md` that **links `summary.md` /
   `daily-plan-summary.md`** at the top (like project-status) and names the two
   manual routine-setup steps.
   - **`git_author` resolution:** `--author EMAIL` → else `git config user.email`
     → else a **placeholder + loud warning** (setup still succeeds). *Enforced at
     use*: the status run (local + remote) **hard-fails** on an unresolved/placeholder
     author — a wrong/empty author silently corrupts the author-scoped summary, and
     the remote has no ambient identity to fall back on.
6. Optionally `git remote add origin <URL>` if `--remote`.
7. Optionally install `.workspace/scripts/guard.sh` as the pre-commit hook.
8. Print next steps (edit `.workspace/repos.yml`, run `.workspace/scripts/bootstrap.sh`).

**Do NOT** init or create GitHub repos for the *managed children* — that's
`bootstrap.sh`'s / the user's job. `setup.sh` only creates the wrapper.

---

## `update.sh` — re-apply machinery to an existing workspace

**Usage (proposed):** `./update.sh <target-dir>`

- Verify `<target-dir>` is a git-workspace (has `.workspace/`).
- Overwrite **machinery only**: `.workspace/scripts/*`, `.gitignore`, the vendored
  `create-project-system/`.
- **Delegate to the vendored `create-project-system`'s update path** so the
  installed task-system machinery upgrades too (it overwrites its own machinery
  and preserves task content — its own machinery/content split).
- **Re-inject the `CLAUDE.md` managed block only** (between the markers); recover
  `{{WORKSPACE_NAME}}` from `.workspace/config.yml`. User directives outside the
  block are preserved.
- Touch **no content or runtime**: `.workspace/repos.yml`, `config.yml`, `plans/`,
  `README.md`, and the routine-owned `state.json` / deliverables stay untouched.
- Success criterion: on an up-to-date workspace, `update.sh` + `git diff` = empty.
  That zero-diff property is the acceptance test — build it in from the start.
- If a normal upgrade ever needs `--force`, the split is wrong — fix the split.

---

## Testing

Generation is exercised against throwaway targets — never against a real repo.

- **`sandbox/` (local, gitignored):** `setup.sh` generates test workspaces into
  `create-git-workspace/sandbox/`. This is the workspace-hygiene rule applied to
  the generator itself — scratch lives in a gitignored `sandbox/` inside the repo
  that produces it, never as a sibling. `create-git-workspace/.gitignore` ignores it.
- **`git-workspace-test` (persistent sibling + remote):** a real repo
  `cornjacket/git-workspace-test` with a **local sibling checkout** next to
  `create-git-workspace` — the analog of `second-brain-test` for
  `second-brain-devkit`. It's the fixture for the **full remote round-trip** an
  ephemeral sandbox can't cover: a scheduled routine fires against a real remote,
  and the ff-only pull needs a persistent local checkout to land in. Deliberately
  clutters the workspace root; **throwaway — removed once the generator matures.**

> **Two test targets, two jobs:** `sandbox/` (ephemeral, gitignored) covers fast
> `setup`/`update`/zero-diff determinism tests, wiped each run. `git-workspace-test`
> (persistent sibling + remote) covers the **remote round-trip** — a scheduled
> routine + ff-only pull can only run against a real, persistent remote.

### Continuous integration (task `017`)

`.github/workflows/tests.yml` runs `./tests/run-tests.sh` on every push to `main`
and on every PR, so the zero-diff invariant is protected by the repo rather than
by remembering to run the suite. It installs PyYAML (the emitted workspace's only
third-party dependency), configures a git identity — without one `setup.sh` takes
its "stage but do not commit" path and every git-reading assertion fails — and
runs **without** `--remote`, since the `git-workspace-test` sibling checkout does
not exist on a runner; that section skips itself with a reason. A failed run
keeps `sandbox/` and uploads it as an artifact, because the generated workspaces
are the evidence.

> Adding CI surfaced that the suite was macOS-only (`sed -i ''`, `shasum`). Both
> are now portable. Worth remembering: the suite is *emitted-shell* discipline
> applied to the harness itself — it must run wherever the generator is tested.

Test flow (acceptance harness, task `005`):
1. `./setup.sh sandbox/ws1 --name ws1` → assert the emitted tree + allowlist.
2. `./update.sh sandbox/ws1` → assert **zero git diff** (the regeneration test).
3. Against persistent `../git-workspace-test` (+ remote): `setup.sh`, push,
   run the routine, `pull.sh` → assert the aggregates land locally.
4. Tear down: wipe `sandbox/` (ephemeral). `git-workspace-test` persists across
   runs; removed only when the generator matures.

---

## Status subsystem — the evolution of project-status

Each workspace intrinsically carries what `project-status` did as a standalone
repo: track its member repos via git telemetry + daily-plans, summarize via
`claude -p`, deliver on a schedule. **`project-status` retires.** Two structural
upgrades make it multi-developer-safe (each developer has their own workspace):

**1. Shared vs per-developer split.**
- **Commit telemetry** (structured `[Context]`/`[Impact]` messages) is the repo's
  *shared* git history → the **commit kernel is still injected into each child
  repo's `CLAUDE.md`** (marker block, same pattern as this generator's own
  injection).
- **Daily-plans** are *per-developer* intent → they move **up into the
  workspace** (`.workspace/plans/<repo>/daily-plan.md`), private to each dev's
  workspace. No shared `daily-plan.md` → no collision. (This supersedes
  project-status's proposed `status/<username>/` mitigation more cleanly.)

**2. Author-scoped summary.** The retrospective summary filters `git log
--author=<email>`, so each dev's rollup shows only their commits. This is
**required, not optional**: the remote sandbox has no ambient identity, so the
workspace must store the author.

### `.workspace/config.yml` (new)

```
name: {{WORKSPACE_NAME}}
git_author:               # one or more; filters git log --author
  - dev@example.com
generator_version: X.Y.Z
```

Also resolves earlier open questions: how `update.sh` recovers the name, and
where version telemetry lives.

### Deliverables, plans & state

- `summary.md` — author-scoped retrospective rollup (top-level, visible).
- `daily-plan-summary.md` — aggregated per-dev plans + "At a glance" table (top-level).
- `.workspace/plans/<repo>/daily-plan.md` — this dev's plan per repo.
- `.workspace/plans/_workspace/daily-plan.md` — the **workspace's own** plan:
  inter-repo / workspace-scoped tasks that belong to no single repo (the middle
  tier of "stuff to do"). Aggregated **first** — top of "At a glance" and the
  summary. **Forward-looking only** (no retrospective git summary; the workspace's
  own commits are meta-noise). Derived from the workspace **task-system** (see
  below) — same replan mechanism as per-repo plans.
- `.workspace/state/state.json` — per-repo last-seen commit (per-dev).
- `.workspace/state/archive/YYYY-MM-DD.md` — dated plan snapshots.

> This gives homeless inter-repo work a proper home, so a personal catch-all repo
> (e.g. `captains-log`) stops absorbing workspace-scoped tasks.

**Decided:** deliverables live at the **top level** (the daily dashboard) — needs
allowlist `!/summary.md` + `!/daily-plan-summary.md`; plans/state/prompts stay
under `.workspace/`. The generated `README.md` **links to them** at the top —
`[summary.md](summary.md)` / `[daily-plan-summary.md](daily-plan-summary.md)` —
exactly like project-status's README.

`.workspace/repos.yml` gains project-status's flags: `priority`, `enabled`,
`report_inactivity`.

### The daily loop — push up, pull down

```
 DEV (local)                        REMOTE routine (Claude /schedule)
 ───────────                        ─────────────────────────────────
 edit plans; add/mute repos
 commit + push workspace ─────────▶ read plans + git logs (author-filtered),
                                    run claude -p (per-repo + polish),
                                    write summary.md + daily-plan-summary.md,
                                    push auto/status-DATE → auto-merge → main
 morning trigger:
 git pull --ff-only      ◀───────── (aggregates now on remote main)
```

- **Remote (push side)** — as in project-status: `daily.sh` → side branch →
  `auto-merge-status.yml` (works around "GitHub App can't push to the default
  branch"). Still needs the children pre-cloned as routine `sources` — the
  sandbox lacks your checkouts. So the "`tracked/` collapses" simplification is
  **local-only**; remotely the routine still fetches the repos to read their
  logs. Plans need no fetch — they live in the workspace repo the routine has.
- **Local (pull side)** — a morning trigger (cron/launchd, or a SessionStart
  hook) runs `.workspace/scripts/pull.sh` → `git pull --ff-only`, bringing the
  aggregates down. `--ff-only` is the correct unattended choice: advance cleanly
  or **safely decline** — never clobber, never auto-merge. On decline (local
  diverged) it **notifies**; the dev reconciles by hand. Keep ff clean by pushing
  workspace edits before the routine runs (remote main = your commits + aggregates
  on top = a fast-forward). Optionally chain `bootstrap.sh` after the pull to
  materialize any repo added remotely.

### Known manual steps (seams)

The remote routine is **not fully self-installing** — two steps `setup.sh` can't
automate (inherited from project-status), to be named in the generated `README.md`:

1. **Creating the Claude `/schedule` routine** is a one-time interactive step in the
   Claude app. `setup.sh` emits the workflows + `daily.sh` + `pull.sh`; *you* create
   the routine and point it at `daily.sh`.
2. **Each tracked repo must be added to the routine's `sources`** (the sandbox
   pre-clone list) or the remote run can't fetch its git log — `add-repo` prints
   this reminder.

These directions live **durably in an on-demand workspace status guide/skill**
(project-status's kernel-+-guide split; create-project-system's on-demand skill
pattern). The always-on `CLAUDE.md` block carries only a **one-line pointer** to
it, keeping the kernel small; the `add-repo` print and the README are the
just-in-time nudges, the guide/skill is the canonical home.

### New workspace verbs (edit `.workspace/repos.yml`)

- `add-repo <url> [--branch b]` — append entry; clone; inject the commit kernel
  into the child's `CLAUDE.md` (project-status's `setup-new-repo.sh`, folded in);
  **print a reminder to add the repo to the remote routine's `sources`** (the
  sandbox pre-clone list — else the remote run can't fetch its git log).
- `delete-repo <name>` — unregister; **refuse to remove a dirty/unpushed
  checkout** (reuse `status.sh`/`guard.sh` logic).
- `mute-repo <name>` — two flavors: `report_inactivity: false` (keep tracked,
  hide on quiet days) or `enabled: false` (skip entirely).

### What shrinks

The child injection loses its daily-plan half (plans moved up): the child kernel
becomes **commit-discipline only**, and the stale-plan `SessionStart` nag moves
to the workspace.

### Workspace task-system — the triage area

The workspace carries its own **task-system**, not just a freeform plan — provided
by **`create-project-system`, which `create-git-workspace` vendors** (see below).
The need is *demonstrated, not speculative*: infra/inter-repo tasks piled up in
`captains-log` precisely because there was no workspace to attach them to. The
workspace task-system is the portfolio-level **incubator / triage**:

- An idea lands as a workspace task **before it has a repo home** — potentially
  before that repo even exists.
- A workspace task can **spawn a child repo**: a subtask is literally "create repo
  X" (runs `add-repo` / `setup`), after which the task **graduates** — its
  remaining work migrates into that new child repo's own task-system.
- So work flows *down*: triage at the workspace → resolve as inter-repo work, or
  move into a (possibly new) child repo once it has a home.

Migration note: moving a task **across a boundary** (workspace task-system → child
repo task-system) is a cross-repo operation `move-task` doesn't do today —
initially recreate-in-child + close-in-workspace; worth a helper later.

### Vendoring `create-project-system`

`create-git-workspace` **vendors a copy** of `create-project-system` (e.g.
`vendor/create-project-system/`) and *composes* it — generating a workspace can
also run it to install the task-system. This is the cookiecutter "vendor a copy
for self-containment" trade: a fresh `create-git-workspace` clone can stamp a
fully task-tracked workspace with no external generator to fetch.

- **`setup.sh --with-tasks` (default on; `--no-tasks` to skip)** runs the vendored
  `create-project-system` against the new workspace with
  `--tasks-dir project/tasks --with-skill --with-status`, stamping the **full
  `project/`** deliverable (tasks + status + docs). `project/tasks` feeds
  `_workspace/daily-plan.md`.
- **Child repos** get the same treatment via `add-repo` — project-status's
  per-repo instrumentation is just this same vendored generator applied to a child.
- **Vendor the machinery, not the self-tracking.** Copy only `generate.sh` + `src/`.
  Leave behind create-project-system's own dev scaffolding — `daily-plan.md`,
  `.claude/hooks/`, `.github/`, `tests/`, `tasks/`, its `ai-project-status` block.
  The vendored copy *installs* task-systems; it is **not itself a tracked repo**,
  so it carries no project-status instrumentation.
- **Drift:** a vendored copy can lag upstream; refresh with a documented re-vendor
  step (copy latest `generate.sh`+`src/` in), stamped with its source version.
  Self-containment over DRY.
- **Boundary (confirmed by inspection).** create-project-system injects a
  *task-tracking* kernel (`task-system:begin`) and installs `tasks/` — **task
  capture only**. The commit-telemetry kernel (`ai-project-status:begin`),
  daily-plan discipline, and aggregation are the **status subsystem** (project-status
  lineage). The two CLAUDE.md kernels are distinct blocks (captains-log carries
  both), so no overlap. **`--with-status` IS enabled** (full `project/` stamp), but
  it's a *distinct, optional* surface: `project/status/` is hand-written periodic
  reports for **status-review meetings**, whereas the top-level `summary.md` is the
  **automated git-telemetry rollup**. May go unused in a workspace; the status-guide
  (task 014) must spell out which is which so the two aren't confused.

### End state: project-status retires

Once every repo lives in *some* workspace, project-status has nothing left to
track and retires — by obsolescence, not amputation:

- **dev-workspace** tracks the dev/generator repos; **personal-workspace** tracks
  `captains-log` + other personal repos. Each has its own intrinsic remote
  daily-plan/status (identical machinery; only `.workspace/config.yml` differs).
- `captains-log` stays its own repo, as a **member** of the personal-workspace
  (its logs + personal tasks are real content). The workspace *tracks* it; it is
  not absorbed. Its misfiled inter-repo tasks migrate to the relevant workspace's
  `_workspace` task-system, so the catch-all isn't merely relocated.
- A standalone tracked repo with no workspace was the *only* reason an external
  tracker existed. Remove the orphan and the tracker's job is gone.
- `second-brain` is a **singleton service, not a member of any workspace** — an
  end product (git is incidental storage; its pre-commit hook just makes it
  convenient infra) that every AI agent references via the `second-brain` skill.
  No workspace tracks or manages it; it appears in no `repos.yml`.
- **Removing project-status from each consumer is the *last* step of onboarding it
  into its workspace, not a standalone cleanup.** Sequence per repo: build the
  workspace → add the repo as a member (workspace injects the commit kernel) →
  *then* strip that repo's old `ai-project-status` block, `daily-plan.md`, hook,
  and `project-status-guide.md`. Doing it earlier leaves the repo's dev untracked
  until its workspace exists. The whole sweep (create-project-system, captains-log,
  …) is one **workspace-level "mothball project-status" epic** — itself a poster
  child for the `_workspace` triage plan. (Vendoring is unaffected either way: it
  copies only `generate.sh` + `src/`, which never held the project-status scaffolding.)

---

## Parameterization & templating

- Placeholders: `{{WORKSPACE_NAME}}` (extend later: `{{REMOTE_URL}}`,
  `{{GENERATOR_VERSION}}`). Plain copy + `sed`, no template engine.
- Store the workspace `.gitignore` as `template/gitignore` (no leading dot) so it
  is inert inside the generator, then rename on emit.
- Stamp emitted `CLAUDE.md` with the generator version — a **derived echo** of
  `.workspace/config.yml:generator_version`, which is the canonical source.
- Use a non-`/` `sed` delimiter when substituting values that may contain `/`
  (e.g. a remote URL) — avoids silent delimiter collisions.

---

## Open questions

1. ✅ **RESOLVED — Hidden-dir name** = `.workspace/`.
2. ✅ **RESOLVED — setup.sh remote creation** = local-only default + `--remote <url>`
   to attach an existing remote; `gh repo create` is an opt-in extra (task 016).
3. ✅ **RESOLVED — git-workspace-test** = persistent local sibling checkout + remote
   (like `second-brain-test`); throwaway, removed when mature. `sandbox/` stays for
   ephemeral determinism tests.
4. ✅ **RESOLVED — Command visibility** = ship a top-level `Makefile`.
5. ✅ **RESOLVED — Version telemetry** = `.workspace/config.yml:generator_version`
   is canonical; the `CLAUDE.md` block carries a derived human-visible echo.
6. ✅ **RESOLVED — CLAUDE.md injection position (no-marker case)** = append at end.
7. ✅ **RESOLVED — `{{WORKSPACE_NAME}}` source on update** = read from
   `.workspace/config.yml` (survives a dir rename).
8. ✅ **RESOLVED — Status deliverable layout** = top-level `summary.md` /
   `daily-plan-summary.md` (allowlist `!` lines added); README links to them.
9. ✅ **RESOLVED — Morning-trigger** = ship `pull.sh`; document cron / launchd /
   SessionStart; user picks per machine.
10. ✅ **RESOLVED — git_author** — seeded from `--author` / `git config user.email`
    at setup (placeholder + warn if unset); **enforced at status-run** (hard-fail on
    placeholder). A list is allowed for multiple emails.

---

## Task breakdown (see `tasks/`)

Numbered in **build order** — `001` first, `016` last; `017`+ are additions
discovered during the build rather than planned up front. The generator skeleton
(001–005) comes first; the status subsystem (006–016) builds on the proven base.

- [x] `001` — restructure `template/` into `template/workspace/` (hidden `.workspace/`
      layout); fix script `WORKSPACE_ROOT` to `../..`.
- [x] `002` — implement `setup.sh` (create wrapper: machinery, CLAUDE.md block,
      `config.yml`, `Makefile`; seed content; run tasks by default).
      *(task-system install deferred to `006`; setup warns and skips.)*
- [x] `003` — implement `update.sh` (machinery-only + delegate to create-project-system;
      **zero-diff** regeneration test). *(delegation wired but inert until `006`.)*
- [x] `004` — `CLAUDE.md` marker-block injection (append when no markers; version echo).
- [x] `005` — test harness: `sandbox/` determinism + zero-diff + `git-workspace-test`
      round-trip + teardown. *(`tests/run-tests.sh` — 61 local assertions, 70
      with `--remote`. The GitHub round-trip against `git-workspace-test` is
      live: push → routine writes the aggregates → `pull --ff-only` lands them,
      plus the diverged-history decline path.)*
- [x] `006` — vendor `create-project-system`; wire `setup.sh --with-tasks` (default)
      + `add-repo`; document re-vendor. *(`add-repo` half deferred to `009`,
      which is where that verb is built.)*
- [x] `007` — workspace task-system + `_workspace/daily-plan.md` (aggregated first);
      triage/graduate flow. *(plan slot + `replan.sh` + triage docs landed;
      "aggregated first" is an ordering contract the aggregator in `008`
      implements.)*
- [x] `008` — status core: `sync`/`new-work`/`aggregate`/`run`, author-scoped `git log`,
      `claude -p` prompts; plans under `.workspace/plans/`. *(ACTIVE now means
      "you committed", not "the repo moved"; `_workspace` aggregates first.)*
- [x] `009` — `add-repo` / `delete-repo` (refuses dirty) / `mute-repo` verbs.
      *(`delete-repo` also refuses unpushed branches, no-upstream branches,
      stashes, and a detached HEAD; `repos.yml` is edited as text so its
      comments survive.)*
- [x] `010` — remote routine: `daily.sh` + `auto-merge-status.yml` + `claude.yml`
      + `.workspace/config.yml`. *(`daily.sh` commits explicit routine-owned
      paths, never `git add -A`, so it cannot sweep up your working edits.)*
- [x] `011` — local morning trigger: `pull.sh` (ff-only, notify-on-decline) + wiring.
      *(three exit codes — 0 advanced, 1 declined, 2 misconfigured — so a trigger
      can alert on breakage without nagging about unpushed work.)*
- [ ] `012` — child commit-kernel injection (commit-discipline only).
- [ ] `013` — status-pipeline tests (`claude -p` stubbed).
- [ ] `014` — on-demand status guide/skill (durable home for routine-setup directions).
- [ ] `015` — generator `README.md` (keep in sync as steps land).
- [ ] `016` — optional extras: `gh repo create`, guard pre-commit hook.
- [x] `017` — **CI**: run the acceptance suite on push/PR (`tests.yml`). *(Not in
      the original breakdown — added once it was clear commits were landing on
      `main` with no automated verification.)*

---

## Provenance & rationale

Abstract principles live in the personal second-brain — `cookiecutter-pattern`
(machinery/content split, zero-diff regeneration, collision policy),
`orthogonal-features-not-nesting` (why the workspace layer is its own generator),
and `scratch-lives-in-gitignored-sandbox` (the `sandbox/` testing convention and
the hygiene rule the workspace enforces). The workspace-architecture model this
generator implements is in `docs/roadmap-2026-07-31.md`. This PLAN.md is the
build plan; the brain holds the transferable why.
