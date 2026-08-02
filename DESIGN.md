# DESIGN — workspace architecture & the generator that builds it

**Durable design.** What the workspace model is, what this generator emits, and
which decisions are settled. It outlives any single effort.

Efforts live elsewhere: an active `PLAN.md` at the repo root, finished ones under
[`docs/plans/`](docs/plans/) with their task files. When a plan finishes, its
decisions graduate *into this file* — see [`docs/plans/README.md`](docs/plans/README.md).

Sections 1–6 are the workspace model (tier-independent). Sections 7–9 are how
`create-git-workspace` implements it. Section 10 is what is settled; §11 is what
is not.

## The one-line idea

**This workspace holds many repos. As it grows, we need one consistent way to
answer two questions: *where does each new thing live?* and *who manages it?*
The answer is a tiered, self-repeating model — and this doc is that model,
top-down.**

---

## 1. Everything is organized in tiers

A **tier** is a level that groups the things below it. There are three we care
about:

```
┌──────────────────────────────────────────────────────┐
│  PERSONAL TIER      "you, across everything"          │
│  second-brain   (captains-log)   create-* generators  │
│                                                        │
│   ┌────────────────────────────────────────────────┐  │
│   │  WORKSPACE      "one grouping of repos"          │  │
│   │  owns: membership · lifecycle · hygiene · status │  │
│   │                                                  │  │
│   │   ┌─────────┐  ┌─────────┐  ┌─────────┐         │  │
│   │   │ repo A  │  │ repo B  │  │ repo C  │  ...    │  │
│   │   └─────────┘  └─────────┘  └─────────┘         │  │
│   │      MEMBER REPOS   "one job each"               │  │
│   └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

- **Member repo** — does one job (a generator, an app, a log).
- **Workspace** — the container that *manages a set of member repos*.
- **Personal tier** — everything that spans *all* your work, above any single
  workspace.

A member checkout comes in **two forms**, and the workspace tracks which:

```
  standard   a normal clone                       .git is a DIRECTORY
  worktree   a linked worktree of another repo     .git is a FILE (a pointer)
```

That `.git`-is-a-file detail for worktrees is load-bearing — see §7.6.

---

## 2. The one rule that decides where anything goes

> **A thing lives at the level of its *subject* — what it operates on — not at
> the highest tier available.**

That single rule settles every "where does this belong?" argument:

```
thing               what it operates on          → lives at
──────────────────────────────────────────────────────────────
project-status      this workspace's repo set    → WORKSPACE
hygiene audit       this workspace's floor        → WORKSPACE
a repo's scratch    one repo                       → inside THAT repo
captains-log*       this workspace's work          → WORKSPACE
second-brain        you, across all workspaces     → PERSONAL
```

\* *captains-log stays in the workspace only because its content is judged
workspace-specific. If its entries ever span workspaces, its subject becomes
"you," and the rule moves it up to the personal tier.*

The trap this rule avoids: "there's a higher level available, so put it there."
No — the *existence* of a higher tier doesn't pull something up. Only its
subject decides.

---

## 3. What a workspace owns (its "floor")

A workspace is responsible for the **set of repos on its floor**:

```
  MEMBERSHIP   what repos exist here        (added on create, removed on delete)
  LIFECYCLE    create / register / retire   (add-repo.py, setup.sh --create-remote)
  HYGIENE      no stray sibling repos;      (periodic audit of the floor)
               each repo keeps scratch inside its own gitignored sandbox/
  STATUS       is work actively happening   (rolls up each member's daily-plan)
```

**Membership and status are two different registries**, not a duplicated one:

```
  repos.yml         "what physically exists"   changes on clone / init / delete
  state/state.json  "what's being worked on"   changes on commit activity
```

Membership is the source of truth for *existence*; status keys off it. A hygiene
audit that reconciles both against a real filesystem scan is **not yet built**
(§11), so drift is currently undetected rather than merely tolerated.

---

## 4. Four roles — prevent, detect, remediate, explain

The same convention (e.g. "scratch lives in a gitignored `sandbox/`, never as a
sibling repo") is upheld by separate players, each with one home:

```
  PREVENT    generator (create-*)   emits the convention at birth, as machinery
                                     → re-applied on every regeneration
  DETECT     workspace audit         flags violations over time
                                     → catches whatever slips past birth
  REMEDIATE  the owning repo         fixes it, via its own task system
                                     → the workspace files the task, never the fix
  EXPLAIN    second-brain            holds the *why* (the durable rationale)
```

No central "rules engine" repo — that would just re-nest the broad concern under
a narrow one.

### The workspace detects; it does not fix

> **A workspace never edits a child repo to fix hygiene. It reports the problem,
> and the fix happens inside the repo that owns it.**

Two reasons this line sits here and not one step further:

- **Ownership.** Whether a repo keeps its scratch in a gitignored `sandbox/` is
  that *repo's* business. The workspace's business is its own floor: which repos
  are here, and whether they are accounted for.
- **Shared files.** A child's `.gitignore` belongs to everyone who works there.
  Two developers' workspaces both appending a line collide; two workspaces both
  *reporting* the same missing line do not.

Remediation therefore flows through the child's own task system: the workspace
files a task in the offending repo describing what needs fixing, and that repo
does the work on its own schedule. For a repo with no task system the verb
degrades to a message — still useful, and still not a write.

**One exception, and the test that defines it:** the workspace *does* inject the
commit-message kernel into each child's `CLAUDE.md` (§7.4). That is not hygiene —
it is the workspace's own **input**, since the rollup cannot read a history whose
messages ignore the schema. And it is built for sharing: a marker block naming no
workspace, no developer, and no version, so two people injecting it produce
identical bytes. So:

> **Write into a child only for something the workspace itself consumes, and only
> in a form two workspaces can write identically. Everything else is
> report-only.**

---

## 5. The model repeats (it's fractal)

The important part: **a workspace is just "any tier that groups repos and wants
management."** The personal tier is *also* a workspace — one whose members are
personal repos and *other workspaces*.

```
  PERSONAL workspace  ──manages──▶  its own membership · hygiene · status
      │ contains
      ▼
  DEV workspace       ──manages──▶  its own membership · hygiene · status
      │ contains
      ▼
  member repos        ──each has──▶ tasks/ + daily-plan   (via create-project-system)
```

So when something like captains-log "moves up" a tier, nothing breaks: it simply
joins the tier above, which has *its own* status scoped to *its* members. A
workspace's status correctly **never reaches across a tier** — and that refusal
is the signal that a new tier now needs its own management.

Each level gets its management machinery from the **generator for that level**:

```
  create-project-system   →  per MEMBER REPO   (tasks/ + daily-plan)
  create-git-workspace    →  per WORKSPACE     (§7 — this repo)
```

Both are *generators*, not libraries: they emit machinery a consumer owns, and
the workspace layer is its own generator rather than a mode of the repo-level one
(second-brain: `orthogonal-features-not-nesting`).

---

## 6. Conventions locked in

- **No sibling repos.** A repo's throwaway output stays in *its own* gitignored
  `sandbox/`. The workspace floor belongs to the workspace, not to the repos on
  it. (Rationale: second-brain note `scratch-lives-in-gitignored-sandbox`.)
- **Don't hide with a `.` prefix.** It overloads the "hidden config" meaning,
  doesn't actually hide from tooling (`find`/git traverse dotdirs), and fights
  editors. Use an explicit gitignored container instead. *(The generated
  workspace's `.workspace/` is the deliberate exception — see §7.1.)*
- **Golden reference ≠ scratch.** A committed known-good output a generator diffs
  against (e.g. `second-brain-test`) is real, versioned content — kept as a
  tracked peer, never buried.
- **Share the mechanism, not the concern.** Reusable helpers are *copied*
  (vendored) into each consumer until a third consumer proves the pattern (rule
  of three) — not owned by a central dependency repo.
- **Commit messages are telemetry.** `<domain>(<scope>): <summary>` plus
  `- [Context]:` / `- [Impact]:`. The rollup has no other input, so a message
  that only makes sense to someone deep in the repo today summarizes into noise
  tomorrow.

---

## 7. The generator — `create-git-workspace`

A user clones this repo, runs `setup.sh` to stamp out a **git-workspace** (a
wrapper repo that manages other repos and worktrees), and runs `update.sh` to
re-apply the machinery later. It is the cookiecutter pattern: a template tree, a
renderer, and a strict machinery/content split that makes regeneration safe
(second-brain: `cookiecutter-pattern`).

### 7.1 Machinery lives in a hidden `.workspace/`

> **Decision (locked):** the generated workspace keeps all generator-owned
> machinery in a hidden directory named **`.workspace/`**, with only `CLAUDE.md`,
> `README.md`, the deliverables, and the `Makefile` at the top level. (Rejected
> `.git-worktree` — it names one of two checkout types, and `.git*` invites
> confusion with git internals.)

Why hide it:

- The root then shows the **managed child repos** — what you actually work in —
  not plumbing.
- It physically reinforces the machinery/content boundary: almost everything
  under `.workspace/` is overwritten on update; everything outside is yours.
- It is the legitimate dotdir-for-tooling pattern (`.github/`, `.husky/`), which
  is why it overrides §6's "don't hide with a dot" for this one directory.

Consequences: scripts resolve `WORKSPACE_ROOT` **two levels up**
(`.workspace/scripts/lib.sh` → `../..`); `repos.yml` lives inside `.workspace/`
but is still *content*; a top-level `Makefile` gives the hidden scripts a visible
command surface.

### 7.2 Roles: generator vs generated workspace

```
  create-git-workspace/            (the GENERATOR — what the user clones)
  ├── setup.sh · update.sh         the two entry points
  ├── lib/generator.sh             EVERY byte of machinery is written here, so
  │                                both entry points emit identical output
  ├── template/                    the skeleton emitted into a workspace
  │   ├── CLAUDE.md                → the managed kernel block
  │   ├── gitignore                → .gitignore (dotless: inert inside here)
  │   ├── github/                  → .github/
  │   ├── claude/                  → .claude/ (the workspace-status skill)
  │   └── workspace/               → .workspace/
  ├── vendor/create-project-system copied in verbatim (generate.sh + src/)
  ├── tools/revendor.sh            refresh that copy from upstream
  ├── tests/run-tests.sh           the acceptance suite
  ├── sandbox/                     throwaway generated workspaces (gitignored)
  ├── docs/                        DESIGN.md's supporting material: plans, templates
  └── DESIGN.md                    this file

          │  setup.sh <target>
          ▼
  <target>/  (the GENERATED git-workspace — manages other repos)
  ├── CLAUDE.md              hybrid: managed kernel block + your directives
  ├── README.md              hybrid: generated roster block + your prose
  ├── summary.md             runtime deliverable (author-scoped rollup)
  ├── daily-plan-summary.md  runtime deliverable (aggregated plans)
  ├── Makefile               command surface (machinery)
  ├── project/               FIRST-CLASS deliverable (create-project-system)
  │   ├── tasks/               the task-system (mount = project/tasks)
  │   └── status/              narrative reports for status-review meetings
  ├── .claude/skills/…       workspace-status + task-system skills (machinery)
  ├── .github/workflows/     auto-merge-status.yml, claude.yml (machinery)
  ├── .workspace/            hidden control plane
  │   ├── config.yml           content: name · git_author · version · routine_url
  │   ├── repos.yml            content: membership lockfile
  │   ├── status-guide.md      machinery: the on-demand operating guide
  │   ├── scripts/             machinery: every verb
  │   ├── prompts/             machinery: the claude -p prompts
  │   ├── templates/           machinery: the child commit kernel
  │   ├── plans/               content: <repo>/ · _workspace/
  │   └── state/               runtime: state.json · archive/
  └── <child repos>/         ignored by the allowlist
```

The emitted allowlist `.gitignore` — ignore-by-default plus explicit exceptions,
so adding a child repo can never accidentally get tracked:

```
/*
!/.workspace/  !/project/  !/.claude/  !/.github/
!/CLAUDE.md  !/README.md  !/Makefile  !/.gitignore
!/summary.md  !/daily-plan-summary.md
__pycache__/  *.pyc          # re-ignored INSIDE the un-ignored dirs
```

> `docs/` is **not** emitted into a workspace. Documentation *about* the
> workspace system lives only here, in the generator.

### 7.3 The machinery / content / runtime split — the load-bearing decision

Regeneration is only safe if every emitted file is classified **once**. Class is
per-file, independent of whether it sits inside `.workspace/`. This is what lets
`update.sh` re-run over a live workspace and produce a **zero-line diff** with no
`--force`.

| File | Class | `setup.sh` | `update.sh` |
|------|-------|-----------|-------------|
| `.workspace/scripts/`, `prompts/`, `templates/`, `status-guide.md` | **machinery** | write | **overwrite** |
| `.gitignore`, `Makefile`, `.github/workflows/`, `.claude/skills/workspace-status/` | **machinery** | write | **overwrite** |
| installed task-system (via `create-project-system`) | **delegated** | install | upgrade |
| `CLAUDE.md` (managed block) | **hybrid** | create-or-inject block | **replace block only** |
| `README.md` (roster block) | **hybrid** | seed, then render block | **re-render block only** |
| `.workspace/repos.yml`, `plans/**` | **content** | seed if missing | seed if missing²; **never overwrite** |
| `.workspace/config.yml` | **content** | seed if missing | **untouched** except `generator_version`¹ |
| `summary.md`, `daily-plan-summary.md`, `.workspace/state/` | **runtime** | — | — |

The classes:

- **machinery** — the generator owns it; *always overwritten*. Users are told not
  to fork it. `.workspace/scripts/` is **mirrored**, not merely copied over: a
  script dropped from the template is deleted from the workspace and the removal
  announced, so retired machinery cannot linger.
- **content** — the *user* edits it; *created if missing, never overwritten*.
- **runtime** — the **daily status routine** writes it. It is committed (it is
  the durable record and the deliverable) but neither seeded by setup nor touched
  by update. This is the class that keeps zero-diff honest: setup/update never
  race the routine.
- **hybrid** — a generated block inside a file the user owns (§7.4).

¹ `generator_version` is canonical version telemetry, so freezing it at the
setup-time value would make it lie after every upgrade. `update.sh` rewrites
**only that line** — the hybrid rule at single-line granularity. Idempotent, so
zero-diff still holds.

² The content rule is "never overwrite", **not** "never create". `update.sh`
seeds a content slot that is *missing*, or a slot introduced by a newer generator
version could never reach an existing workspace — only `setup.sh` seeds, and it
refuses to run on a live one. Creating an absent file destroys nothing.

> **If a normal upgrade ever needs `--force`, the split is wrong — fix the split,
> not the flag.**

### 7.4 The two hybrids — marker-block injection

`CLAUDE.md` and `README.md` must both be updateable *without clobbering what the
user wrote*. So each is a generator-owned, marker-delimited block inside a
user-owned file:

```
CLAUDE.md   <!-- git-workspace:begin … end -->          the always-on kernel
README.md   <!-- git-workspace-roster:begin … end -->   the repo roster
child repo  <!-- git-workspace-commits:begin … end -->  the commit schema
```

One injection algorithm, three paths: **no file** → create it; **markers
present** → replace only between them; **no markers** (the user brought their
own) → append at the end, touching nothing. Re-injection of a current block
changes nothing, so zero-diff holds. Anything malformed — a half-open block, a
duplicated one, an end before a begin — is **refused, not guessed at**: any edit
we make there could silently destroy content.

Two deliberate asymmetries:

- A malformed `CLAUDE.md` block **aborts** the run; a malformed README roster
  block **warns and continues**. The kernel carries rules an agent must obey, so
  a mangled one is a correctness problem; the roster is a dashboard, and a stale
  dashboard must never take down a machinery upgrade.
- The child commit kernel is committed to a **shared** repo, so it names no
  workspace, no developer, and no version — several developers may track the same
  repo from their own workspaces, and anything personal in it would make them
  overwrite each other's block forever.

The README roster is rendered from `repos.yml` + `config.yml` by
`.workspace/scripts/render-readme.py`, which lives **in the workspace** so the
membership verbs, `make readme`, and both generator entry points run identical
code. The daily run deliberately does not call it: membership only changes
locally, and keeping `README.md` out of `daily.sh`'s commit set preserves the
rule that the routine and the generator never write the same file.

### 7.5 The two entry points

**`setup.sh <target> [--name] [--author] [--remote | --create-remote [--public]]
[--with-hook] [--no-tasks] [--no-commit] [--force]`** — creates the *wrapper
only*. It never clones, inits, or creates the managed children; that is
`add-repo`'s and `bootstrap.sh`'s job.

- `git init`s the target, normalizes the branch to `main`, writes machinery,
  injects the `CLAUDE.md` block, seeds content, renders the README roster,
  installs the task-system, and makes the initial commit.
- **`git_author` resolution:** `--author` → `git config user.email` → a
  placeholder plus a loud warning. *Enforced at use*: the status run hard-fails
  on the placeholder, because a wrong author silently produces a
  plausible-looking empty rollup — the worst kind of failure.
- There is **no `--no-status`**. Status is not a layer a workspace opts into; it
  *is* the workspace layer. `--no-tasks` survives because the task-system is a
  separate, delegated generator.
- `--create-remote` is **private by default** — a workspace carries your plans
  and your rollup — and pre-flights `gh`'s presence *and* auth before stamping,
  so a missing tool cannot leave a half-configured workspace.

**`update.sh <target>`** — re-applies machinery only, delegates the task-system's
upgrade to the vendored generator, re-injects both managed blocks, and touches no
content or runtime. It never commits: the whole point is to leave a reviewable
diff. **Its acceptance test is the zero-diff property.**

### 7.6 The worktree gotcha every script (and agent) must respect

```
  standard repo  →  <path>/.git is a DIRECTORY
  worktree       →  <path>/.git is a FILE (a gitdir pointer)

  detect a checkout with:   [ -e <path>/.git ]   (exists)          <- correct
  never with:               [ -d <path>/.git ]   (is-directory)    <- misses worktrees
```

`guard.sh` catches the other half of the problem: a child repo staged as a
gitlink (mode 160000), a `.git` artifact, or any path inside a managed checkout
staged into the wrapper index. It installs as a pre-commit hook via
`install-hooks.sh` — which ships *inside* the workspace, because `.git/hooks/` is
untracked and a second clone needs it re-run locally.

### 7.7 Parameterization

Placeholders are substituted with plain `sed`, no template engine:
`{{WORKSPACE_NAME}}`, `{{GENERATOR_VERSION}}`, `{{GIT_AUTHOR}}`, `{{TODAY}}`.

- Use a non-`/` `sed` delimiter (`|`) — emitted values routinely contain slashes.
- Workspace names are validated to `[A-Za-z0-9._-]`, which also removes any
  chance of a delimiter collision.
- `{{TODAY}}` is only safe in **content** templates. In machinery it would
  re-render differently tomorrow and break zero-diff.
- The version echo has exactly **two** homes: `config.yml` (canonical) and the
  `CLAUDE.md` block (derived). A third would make every version bump move an
  extra file.

### 7.8 Testing

Generation is exercised against throwaway targets — never a real repo.

- **`sandbox/`** (local, gitignored) — fast `setup`/`update`/zero-diff
  determinism tests, wiped each run. This is the workspace-hygiene rule of §6
  applied to the generator itself.
- **`git-workspace-test`** (persistent sibling + real remote) — the full remote
  round-trip an ephemeral sandbox cannot cover: a scheduled routine fires against
  a real remote, and the ff-only pull needs a persistent local checkout to land
  in. Throwaway; removed once the generator matures.
- **CI** (`.github/workflows/tests.yml`) runs the suite on every push to `main`
  and every PR, so the zero-diff invariant is protected by the repo rather than
  by remembering. It runs without `--remote` (no sibling checkout on a runner)
  and uploads `sandbox/` on failure — the generated workspaces are the evidence.
- The suite is **emitted-shell discipline applied to the harness itself**: no
  BSD-only idioms, because it must run wherever the generator is tested.
- External commands are **stubbed on `PATH`** (`claude`, `gh`) so the pipeline's
  real code path is exercised without a network call or an API charge.
- The harness is **mutation-tested**: deliberately break the generator and
  confirm the suite goes red. A test that has never failed has not been shown to
  test anything.

---

## 8. The status subsystem — the evolution of `project-status`

Each workspace intrinsically carries what `project-status` did as a standalone
repo: track its member repos via git telemetry plus daily-plans, summarize with
`claude -p`, deliver on a schedule. **`project-status` retires** (§8.7). Two
structural upgrades make it multi-developer-safe, since each developer has their
own workspace.

### 8.1 Shared vs per-developer

- **Commit telemetry** is the repo's *shared* git history → the commit kernel is
  injected into each child repo's `CLAUDE.md`.
- **Daily-plans** are *per-developer* intent → they move **up into the
  workspace** (`.workspace/daily-plans/<repo>/daily-plan.md`), private to each dev's
  workspace. No shared plan file, so no collision.

The child kernel therefore shrinks to **commit discipline only**, and a tracked
repo should have no `daily-plan.md` of its own.

### 8.2 Author-scoped summary

Every git read filters `--author` against `git_author`, so each dev's rollup
shows only their commits. **ACTIVE means "you committed", not "the repo moved":**
a repo a teammate advanced reads as INACTIVE *for you* while `state.json` still
tracks the real HEAD, so tomorrow's window stays correct.

This is required, not optional — the remote sandbox has no ambient git identity,
so the workspace must store the author.

### 8.2b Where the git history is read from

**No `tracked/` cache locally.** `project-status` kept its own clones because it
sat outside the repos it watched; a workspace *contains* them, so the run reads
the checkouts in place at the paths `repos.yml` declares. One less copy to keep
fresh, and no chance of summarizing a stale mirror.

Remotely there are no checkouts at all, so the run falls back to the platform's
**pre-cloned sources**. Cloning from inside that sandbox hits a TLS-inspecting
proxy and fails even for public repos, so the pre-cloned trees must be reused —
which is why §8.5's `sources` list is load-bearing rather than a convenience.

### 8.3 Deliverables, plans, and state

- `summary.md` — author-scoped retrospective rollup, newest day first.
- `daily-plan-summary.md` — aggregated plans behind an "At a glance" table.
- `.workspace/daily-plans/<repo>/daily-plan.md` — this dev's plan per repo.
- `.workspace/daily-plans/_workspace/daily-plan.md` — the **workspace's own** plan:
  inter-repo work belonging to no single repo. Aggregated **first**, and
  **forward-looking only** — the workspace's own commits are meta-noise.
- `.workspace/state/state.json` + `archive/YYYY-MM-DD.md`.

Deliverables sit at the **top level** (the daily dashboard); plans, prompts, and
state stay under `.workspace/`.

Two output contracts worth stating, because both were learned by breaking them:

- **An embedded plan's own headings are demoted** so they nest *under* their
  section in the aggregate rather than sitting beside it — otherwise one repo's
  `## Focus` silently becomes a peer of the repo sections themselves.
- **A failed run advances nothing.** If a model call fails, the run aborts,
  leaves `summary.md` untouched, and does **not** move the commit window in
  `state.json`. Advancing past work that was never summarized would make the next
  run skip it, and the day would vanish from the record with no error anywhere.

`project/status/` is a *different thing* and the guide must keep them apart:
hand-written periodic reports for status-review meetings, versus `summary.md`,
the automated git-telemetry rollup.

### 8.3b A plan is a report, not an act of planning

Plans are **derived deterministically from task state — no model call.**
`replan.sh` reads each task-system's own lister and projects its
in-progress / backlog / draft folders into the plan's sections, preserving
everything from `## Notes` onward.

This is a deliberate departure from `project-status`, which spent one `claude -p`
per repo. The reasoning:

- **The thinking already happened.** You decide what is in progress and what is
  next by curating tasks. The plan renders that decision; it does not make one.
- **A model can invent work you never chose.** A plausible-looking next step in a
  plan flows straight into the aggregate and reads as something you committed to.
  Determinism cannot produce that failure.
- **`replan.py`'s own behaviour concedes the point** — it defaults to re-dating
  the current plan whenever the next step is not unambiguous. That is a lot of
  model calls to mostly re-date a file.
- Free, offline, and **exactly testable**: the suite asserts byte-identical
  output for the same task state, which no model-driven version allows.

The honest cost: a repo **without** a task-system has nothing to project, so it
is skipped — loudly, never with an empty plan, because "nothing to do" and "this
repo does not track tasks here" are different claims. If a repo needs a plan, it
needs a task-system; that is the same "curate tasks, not prose" discipline
applied one level down.

### 8.4 The daily loop — push up, pull down

```
 DEV (local)                        REMOTE routine (Claude /schedule)
 ───────────                        ─────────────────────────────────
 edit plans; add/mute repos
 commit + push workspace ─────────▶ read plans + author-filtered git logs,
                                    run claude -p (per-repo + polish),
                                    write summary.md + daily-plan-summary.md,
                                    push auto/status-DATE → auto-merge → main
 morning trigger:
 git pull --ff-only      ◀───────── (aggregates now on remote main)
```

- **Push side.** The routine's GitHub App identity cannot push to the default
  branch — and the error it produces is a misleading "non-fast-forward" — so
  `daily.sh` pushes a dated side branch and `auto-merge-status.yml`
  fast-forwards it onto `main`. `daily.sh` commits **explicit paths only**, never
  `git add -A`, so it cannot sweep up your working edits.
- **Pull side.** `pull.sh` is **`--ff-only`**: it advances cleanly or it declines
  and notifies. Never merge, rebase, or force — an unattended job that resolves
  history is one that eventually destroys something at 6am. Three exit codes (0
  advanced, 1 declined, 2 misconfigured) let a trigger alert on breakage without
  nagging about unpushed work.

### 8.5 The two manual seams

The remote routine is **not self-installing**, and both gaps are silent:

1. **Creating the `/schedule` routine** is a one-time interactive step in the
   Claude app. The generator emits the workflows and `daily.sh`; you point the
   routine at it.
2. **Each tracked repo must be in the routine's `sources`** pre-clone list, or
   the remote run cannot read its git log — the sandbox has no checkouts and its
   egress proxy blocks anything not pre-declared.

These live durably in the on-demand status guide; `add-repo`'s print and the
README roster are the just-in-time nudges.

### 8.6 Membership verbs

`add-repo` (clone, register, seed the plan slot, inject the kernel, seed the
description), `delete-repo` (refuses a dirty tree, an unpushed branch, a branch
with no upstream, a stash, or a detached HEAD — reporting *every* reason at
once), `mute-repo` (`report_inactivity: false` to hide on quiet days, `--skip`
for `enabled: false`).

**`repos.yml` is a lockfile, not a config file you author.** The verbs write it
as *text*, so comments and ordering survive; `bootstrap.sh` replays it onto a new
machine. Every verb also refreshes the README roster, so it cannot drift.

### 8.7 The workspace task-system is a triage area

The workspace carries its own task-system, provided by the vendored
`create-project-system`. The need is *demonstrated, not speculative*: infra and
inter-repo tasks piled up in `captains-log` precisely because there was no
workspace to attach them to.

Work flows **downward**: an idea lands as a workspace task before it has a repo,
and **graduates** when it earns one. Anything that clearly belongs to an existing
child repo belongs *there*, not here.

### Graduation is two tasks, not a move

Following §4's rule — the workspace requests, the owning repo implements — a
workspace task is never migrated into a child. It is a **request**, and it is
complete once the request has been made:

```
  WORKSPACE task   "create repo X, then file a task in X to do Y"   → closed
  CHILD repo task  do Y                                             → the work
```

So there is **no cross-repo `move-task` to build**, here or upstream in
`create-project-system`. A move was never the right shape: the workspace should
not have owned the implementation detail in the first place.

The one wrinkle is real, though. Triage means an idea can incubate here *before*
its repo exists, so detail sometimes accumulates at the workspace level. When the
repo finally appears, the child's task **links back** to the workspace task
rather than copying it — the workspace repo is durable and closed tasks are
archived, not deleted, so the link keeps resolving. Finding yourself with a lot
to carry across usually means the implementation task was authored at the wrong
level, which is a writing mistake rather than a missing feature.

### 8.8 Vendoring `create-project-system`

`create-git-workspace` vendors a copy (`generate.sh` + `src/` only) and composes
it: a fresh clone can stamp a fully task-tracked workspace with nothing external
to fetch. Self-containment over DRY.

**Vendor the machinery, not the self-tracking.** Upstream is itself a tracked
repo carrying `daily-plan.md`, `.claude/hooks/`, `.github/`, `tests/`, `tasks/`,
and its own `ai-project-status` block. None of that is generator machinery. The
vendored copy *installs* task-systems; it is not itself tracked.

The two `CLAUDE.md` kernels are distinct blocks — `task-system:begin` (task
capture) and `git-workspace:begin` (workspace machinery) — so they coexist
without overlap. Drift is handled by a documented re-vendor step
(`tools/revendor.sh`), stamped with its source version.

### 8.9 End state: `project-status` retires by obsolescence

Once every repo lives in *some* workspace, the standalone tracker has nothing
left to track:

- **dev-workspace** tracks the dev/generator repos; **personal-workspace** tracks
  `captains-log` and other personal repos. Identical machinery; only
  `config.yml` differs.
- `captains-log` stays its own repo as a *member* — its logs are real content.
  Its misfiled inter-repo tasks migrate to the relevant workspace's `_workspace`
  task-system, so the catch-all is not merely relocated.
- `second-brain` is a **singleton service, not a member of any workspace** — an
  end product every agent references via a skill. It appears in no `repos.yml`.
- **Removing project-status from a consumer is the *last* step of onboarding it
  into its workspace, not a standalone cleanup.** Per repo: build the workspace →
  add the repo (which injects the commit kernel) → *then* strip that repo's old
  `ai-project-status` block, `daily-plan.md`, hook, and guide. Earlier leaves the
  repo's dev untracked until its workspace exists.

---

## 9. Instruction architecture — kernel, skill, guide

Agent-facing instructions are a **recurring token tax**, paid on every turn
whether or not the turn needs them (second-brain: `agent-instruction-placement`).
The generated workspace therefore splits them three ways:

| Layer | Loaded | Holds |
|---|---|---|
| `CLAUDE.md` managed block | **always** | only rules that would be *too late* if loaded on demand — `cd` into the child first, the verbs own `repos.yml`, the run owns the deliverables, machinery is overwritten. Plus one pointer. |
| `.claude/skills/workspace-status/SKILL.md` | **on demand** | orientation, the few load-bearing rules, and a pointer. Deliberately thin. |
| `.workspace/status-guide.md` | **by reference** | the procedure: layout, verbs, the daily loop, the routine seams, the file classes. |

**Single source of truth:** the guide holds the procedure; the kernel and skill
*point at it* rather than restating it. Resisting the urge to inline command
examples into the skill is the whole discipline — that duplication is precisely
what rots.

The guide is plain Markdown and therefore agent-agnostic; the skill is a
Claude-specific accelerator, never the only copy. The kernel is capped at 60
lines by a test, which fails if the mechanics creep back in.

---

## 10. Decisions locked

| # | Decision |
|---|---|
| 1 | Hidden-dir name is **`.workspace/`**. |
| 2 | `setup.sh` is local-only by default; `--remote <url>` attaches an existing remote, `--create-remote` makes one with `gh` (private unless `--public`). |
| 3 | Two test targets: ephemeral `sandbox/` for determinism, persistent `git-workspace-test` for the remote round-trip. |
| 4 | A top-level `Makefile` is the visible command surface. |
| 5 | `config.yml:generator_version` is canonical version telemetry; the `CLAUDE.md` block carries a derived echo. |
| 6 | Marker-block injection with no markers present **appends at the end**. |
| 7 | The workspace name is recovered from `config.yml`, so a directory rename never breaks regeneration. |
| 8 | Deliverables live at the **top level**; plans, prompts, and state stay under `.workspace/`. |
| 9 | Ship `pull.sh` and document cron / launchd / SessionStart; the user picks a trigger per machine. |
| 10 | `git_author` is seeded at setup and **enforced at the status run** (hard-fail on the placeholder). A list is allowed. |
| 11 | Repo lifecycle is a workspace concern: `add-repo` creates/registers, and hands scaffolding off to the chosen generator. |
| 12 | The workspace root **is a git repo**, so `CLAUDE.md`, `README.md`, and tooling are versioned — you cannot bisect a regression in unversioned docs. |
| 13 | Status is intrinsic to a workspace, not an opt-in layer — hence no `--no-status`. |
| 14 | Descriptions in `repos.yml` are **stored, not re-derived**: seeded from the repo's GitHub description, else a README scrape. |

### Triggers that would end the "one workspace" simplification

Build additional workspaces only when one actually happens: a **second
workspace** appears; a **second user**; or **captains-log / status content stops
fitting one workspace** (its subject becomes "you", pushing it to the personal
tier, which then needs its own managed workspace).

---

## 11. Open gaps — designed for, not built

> **Closed:** per-repo plan drafting. `replan.sh` now redrafts every plan — the
> workspace's, plus one per enabled repo carrying a task-system — and it does so
> **deterministically, with no model call at all**, which is a deliberate
> departure from `project-status`'s `replan.py`. See §8.3b for why.

> **Closed:** the pending sweep. `status.py` now reports *unpushed* alongside
> uncommitted — the dangerous case, since a repo you committed but never pushed
> looks perfectly clean to `git status`. The detector
> (`_status_lib.pending_findings`) is shared verbatim with `delete-repo`, so a
> report and a refusal can never disagree; the two differ only in severity, with
> deletion blocking on `local-only` and the report treating it as fact. `--all`
> extends the sweep to unregistered checkouts, and the workspace itself is a row,
> since its own uncommitted plans are the easiest of all to forget.

**Dogfooding.** No real workspace has been stamped yet — the generator is tested
but not lived in. This is the next effort, and it is mostly migration rather than
code: stamp the real workspace, move repos in one at a time in §8.9's order,
create the `/schedule` routine, then retire `project-status`. Expect it to
rewrite the requirements for everything below it; using a thing for real is what
tells you what is actually missing.

**The hygiene audit (§3, §4).** `DETECT` is the one role of §4 with no
implementation. Read-only, and narrower than it first appears — `delete-repo`
already prunes a departing repo's plan slot by default. What genuinely goes
unnoticed:

- a repo folder on the floor that was never registered;
- `state.json` entries for repos that no longer exist (nothing prunes them);
- a member repo missing §6's gitignored `sandbox/` — **reported, never fixed**,
  per §4.

Build it *after* dogfooding, when real drift has shown what is worth checking.

> **No longer a gap:** cross-repo `move-task`. §8.7's graduation is two tasks, not
> a migration, so there is nothing to move — here or upstream.

---

## Provenance

Abstract principles live in the personal second-brain — `cookiecutter-pattern`
(machinery/content split, zero-diff regeneration), `orthogonal-features-not-nesting`
(why the workspace layer is its own generator), `scratch-lives-in-gitignored-sandbox`
(the sandbox convention), and `agent-instruction-placement` (§9's kernel/skill/guide
split). This file is the workspace-specific application; the brain holds the
transferable why.

The effort that built all of this is archived at
[`docs/plans/genesis/`](docs/plans/genesis/) — 19 task files and the plan that
sequenced them.
