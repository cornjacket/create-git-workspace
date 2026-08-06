# Workspace guide — {{WORKSPACE_NAME}}

<!--
  MACHINERY: written and overwritten by create-git-workspace on every update.sh.
  Local edits are lost. To change it, edit template/workspace/status-guide.md in
  the generator and re-run update.sh.

  This file is the REFERENCE half of a kernel-plus-guide split. The hard rules —
  the ones that would be too late if they loaded on demand — live in the managed
  block of CLAUDE.md, which is always in context. Everything here is the
  procedure, the mechanics, and the why: read it while doing the thing, not
  before every conversation.
-->

Operating reference for this workspace: how the daily status run works, how to
set up the parts the generator cannot install for you, and what each verb does.
The `workspace-status` skill points here; so does `CLAUDE.md`. Read it when you
are wiring up the routine, adding or removing a repo, or trying to work out why
the rollup says what it says.

## 1. What this repo is

A **git-workspace**: a wrapper that manages a *set* of other repos and worktrees
checked out beside it. It does not edit their contents — you do that from inside
the owning repo. Machinery lives in a hidden `.workspace/` directory; an
allowlist `.gitignore` tracks only that machinery and ignores every managed
child, so the wrapper can never accidentally swallow one.

```
{{WORKSPACE_NAME}}/
├── CLAUDE.md              always-on kernel (managed block) + your own directives
├── README.md              the human front door + daily dashboard links
├── Makefile               visible command surface: make status | run | pull | …
├── .gitignore             allowlist: tracks the machinery, ignores the children
├── summary.md             RUNTIME: retrospective rollup, newest day first
├── daily-plan-summary.md  RUNTIME: forward-looking plans, workspace plan first
├── .claude/skills/        on-demand skills: workspace-status, task-system
├── .github/workflows/     auto-merge-status.yml, claude.yml
├── .workspace/            the control plane (hidden)
│   ├── config.yml         identity: name · git_author · generator_version
│   ├── repos.yml          membership lockfile — written by the verbs, not by you
│   ├── status-guide.md    this file
│   ├── project/           the workspace's OWN task-system (triage — §8) + status/
│   ├── plans/             per-developer daily plans, one dir per repo
│   │   └── _workspace/    the workspace's own forward-looking plan
│   ├── prompts/           the summariser prompts the run feeds to `claude -p`
│   ├── scripts/           every verb (§2)
│   ├── templates/         the commit kernel injected into child repos (§7)
│   └── state/             runtime: state.json (the commit window)
└── <child repos>/         managed checkouts — ignored by git
```

Two checkout kinds are declared in `repos.yml`: **standard** (a normal clone) and
**worktree** (a linked worktree; `parent_repo_path` names the repo it hangs off).
A worktree's `.git` is a **file**, not a directory — test `[ -e <path>/.git ]`,
never `[ -d ... ]`, or every worktree silently disappears from your loop.

## 2. Command surface

`make` is the visible surface; the scripts under `.workspace/scripts/` are the
real interface and read better for anything with arguments.

| Command | Script | What it does |
|---|---|---|
| `make status` | `status.py` | branch + **uncommitted and unpushed** work for every managed checkout, and for the workspace itself, plus any repo missing from the routine's `sources` (§5.2). `ARGS="--all"` also sweeps unregistered checkouts; `-v` lists each finding |
| `make bootstrap` | `bootstrap.sh` | replay `repos.yml` onto this machine: clone every `standard` repo, `git worktree add` every `worktree`. Idempotent |
| `make guard` | `guard.sh` | fail if a child repo, a `.git` dir, or a worktree `.git` pointer was staged into the wrapper index |
| `make hook` | `install-hooks.sh` | install `guard.sh` as this clone's pre-commit hook (`hook-check` reports status; `--uninstall` removes it) |
| `make readme` | `render-readme.py` | refresh `README.md`'s roster block from `repos.yml` + `config.yml` (`readme-check` reports staleness) |
| `make replan` | `replan.sh` | redraft every daily plan from task state — the workspace's, plus one per enabled repo that has a task-system. **No model calls**; **draft-only**, it writes and stops. `ARGS="--repo NAME"` for one, `--date` for another day |
| `make new-work` | `new-work.py` | what *you* committed per repo since the last run |
| `make run` | `run.py` | the daily run: summarize → aggregate → advance state, via `claude -p` |
| `make run-dry` | `run.py --dry-run` | the same pipeline with no LLM calls — deterministic placeholders |
| `make aggregate` | `aggregate-plans.py` | rebuild `daily-plan-summary.md` from `.workspace/daily-plans/` |
| `make pull` | `pull.sh` | the morning trigger (§4) |
| `make routine-registered` | `routine-registered.py` | record that a repo is now in the routine's `sources` (§5.2). `ARGS="<name>"`, `--all`, or `--unset` |
| `make routine-check` | `routine-registered.py --check` | list the repos whose registration is still outstanding |
| `make inject-kernel` | `inject-kernel.py --all` | refresh the commit kernel in every tracked repo (§7) |
| `make kernel-check` | `inject-kernel.py --check` | report stale/missing kernels without writing |
| — | `sync.py` | report which repos are readable. Read-only; it never clones |
| — | `daily.sh` | the scheduled REMOTE routine's entry point (§4) |
| — | `lib.sh`, `_status_lib.py`, `_repos_edit.py` | shared helpers, not run directly |

**The pre-commit hook is per-clone.** Git does not track `.git/hooks/`, so a
workspace cloned onto a second machine arrives without it — run `make hook`
there. It refuses to overwrite (or remove) a pre-commit hook it did not write;
`--force` overrides, or chain it from your own hook with
`.workspace/scripts/guard.sh || exit 1`.

## 3. Membership: the repo verbs

**Never hand-edit `.workspace/repos.yml`.** It is a lockfile the verbs maintain,
and `bootstrap.sh` replays it onto a fresh machine. The verbs edit it as *text*,
so its comments and ordering survive.

- **`add-repo.py <url> [--name N] [--branch B] [--priority N]`** — clone it,
  register it, seed its plan slot, and inject the commit kernel into the child's
  `CLAUDE.md`. It clones *before* writing the entry, so a bad URL leaves the
  registry untouched. It prints two follow-ups: commit the kernel from inside the
  child repo, and **add the repo to the routine's `sources`** (§5.2).

  **Re-running it is a reconcile, not an error.** Over an already-registered repo
  it back-fills whatever is missing — an absent `routine_registered` flag, a
  deleted plan slot, a stale kernel — and writes nothing when nothing is missing.
  It refuses only to *repoint* an entry: a different `url` or `--path` under a
  name already in the lockfile is a re-registration, so use `delete-repo
  --keep-checkout` and add it again.
- **`routine-registered.py <name>…`** — record phase two of registration (§5.2).
  `--all` after one bulk edit of `sources`, `--unset` to reverse it, `--check` to
  list what is outstanding. The only writer of a `true`.
- **`delete-repo.py <name>`** — unregister and remove the checkout. It **refuses**
  a dirty tree, an unpushed branch, a branch with *no* upstream, a stash, or a
  detached HEAD — and reports every reason at once rather than one per run.
  `--keep-checkout` unregisters without touching disk.
- **`mute-repo.py <name>`** — two flavors of quiet:
  `report_inactivity: false` (default: stays tracked, just stops appearing on
  days it did not move) and `--skip`, which sets `enabled: false` and drops it
  from the run entirely. `--unmute` restores both.

`repos.yml` entries also carry `priority`, which orders the "At a glance" table
in `daily-plan-summary.md`, and `description` — one line of "what is this repo",
seeded at registration and shown in `README.md`'s roster. Three sources, best
first: `add-repo --description "…"`; the repo's own **GitHub description** via
`gh repo view` (the one field a human already wrote *as* a one-liner); then the
first prose paragraph of its `README.md`/`CLAUDE.md`, which is a guess. No `gh`,
not GitHub, or no description set simply falls through.

It is **stored, not re-derived**: a render stays stable when a child edits its
README, still works for a repo that is registered but not checked out here, and
a bad guess is fixed by editing that one line.

### The README roster

`README.md` is a **hybrid**, like `CLAUDE.md`: everything outside the
`git-workspace-roster` markers is yours, and the block between them is generated
from `repos.yml` + `config.yml`. It lists every tracked repo with its
description, path, and whether it is muted, skipped, or not checked out on this
machine; links the deliverables; and reports the scheduled routine.

All three verbs refresh it, so it cannot drift from the registry — a roster you
have to remember to update is one that is wrong. `make readme` refreshes it by
hand (after a `routine_url` change, or a `repos.yml` you edited despite the
warnings), and `update.sh` back-fills the block into a workspace stamped before
it existed.

It deliberately shows **no branch column**: a branch is mutable and, for a
worktree, per-checkout — a value copied from the registry would drift into a
lie. Use `make status` for the live answer.

## 4. The daily loop — push up, pull down

```
 YOU (local)                        THE ROUTINE (remote, Claude /schedule)
 ───────────                        ──────────────────────────────────────
 edit plans; add/mute repos
 commit + push the workspace ─────▶ read plans + author-filtered git logs,
                                    run claude -p per repo, then polish,
                                    write summary.md + daily-plan-summary.md,
                                    push auto/status-DATE → auto-merge → main
 morning:
 make pull  (ff-only)     ◀──────── the aggregates are now on remote main
```

### The push side — `daily.sh`

The routine cannot commit to `main` directly: the GitHub App identity it runs
under is blocked from pushing to the default branch, and the error it produces is
a misleading "non-fast-forward". So `daily.sh` pushes a dated side branch
`auto/status-YYYY-MM-DD`, and `.github/workflows/auto-merge-status.yml`
fast-forwards that onto `main` and deletes it.

`daily.sh` commits **explicit paths only** — `summary.md`,
`daily-plan-summary.md`, and `.workspace/state/` — never `git add -A`. Your
plans, your `repos.yml`, and any in-progress edit stay exactly where you left
them.

Keep the fast-forward clean by pushing your own workspace edits *before* the
routine runs, so remote `main` is your commits with the rollup on top.

### The pull side — `pull.sh`

`make pull` fast-forwards this workspace onto whatever the routine landed. It is
**`--ff-only`**: it advances cleanly or it declines and tells you why. It never
merges, rebases, or forces — an unattended job that resolves history is one that
eventually destroys something at 6am.

| Exit | Meaning |
|---|---|
| 0 | up to date, or fast-forwarded |
| 1 | declined — you are ahead or diverged; it names which, and the fix |
| 2 | misconfigured — no origin, detached HEAD, or origin unreachable |

The split matters for automation: a trigger can alert on **2** (something is
broken) without nagging you about **1** (you simply have unpushed work).
`--bootstrap` also clones any repo you registered from another machine;
`--quiet` suits an unattended run.

Pick **one** trigger — the script ships, the wiring is yours:

**cron** (weekdays at 08:00)
```cron
0 8 * * 1-5 cd /path/to/{{WORKSPACE_NAME}} && .workspace/scripts/pull.sh --quiet >> /tmp/workspace-pull.log 2>&1
```

**macOS launchd** — `~/Library/LaunchAgents/com.you.workspace-pull.plist`, then
`launchctl load` it. Preferred over cron on a laptop: launchd runs the job when
the machine wakes; cron silently skips it if you were asleep at 08:00.
```xml
<dict>
  <key>Label</key><string>com.you.workspace-pull</string>
  <key>ProgramArguments</key>
  <array>
    <string>/path/to/{{WORKSPACE_NAME}}/.workspace/scripts/pull.sh</string>
    <string>--quiet</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>8</integer></dict>
</dict>
```

**Claude Code SessionStart hook** — pulls whenever you start working here, which
matches the real trigger (you sitting down) better than a clock does. In
`.claude/settings.json`:
```json
{"hooks": {"SessionStart": [{"hooks": [
  {"type": "command", "command": ".workspace/scripts/pull.sh --quiet", "timeout": 30}
]}]}}
```

## 5. Setting up the routine — the two manual seams

The generator emits every piece of machinery, but the remote routine is **not
self-installing**. Two steps are yours, and the run is silently useless without
them.

### 5.1 Create the `/schedule` routine and point it at `daily.sh`

A one-time interactive step in the Claude app: create a scheduled routine whose
working repo is *this* workspace and whose instruction is to run
`.workspace/scripts/daily.sh`. There is no API-free way for `setup.sh` to do this
— it has no session to create the routine in.

Give it a daily schedule that lands *before* your morning pull, so `make pull`
has something to fast-forward onto.

### 5.2 Add every tracked repo to the routine's `sources`

The remote sandbox has none of your checkouts, and its egress proxy blocks
cloning anything not pre-declared. So every repo in `repos.yml` must also appear
in the routine's `sources` (the pre-clone list) or the run **cannot read its git
log** — it reports the repo as unreadable and moves on. The failure is silent:
the run does not fail, it quietly omits that repo from the rollup.

Update the routine's `sources` by sending back the **entire** job config with the
new `{"git_repository": {"url": "https://github.com/<owner>/<repo>"}}` appended —
do not rely on partial-merge semantics, which can drop the fields you omit.

Then **record it**, because a printed reminder scrolls away:

```
make routine-registered ARGS="<name>"     # or --all after one bulk edit
```

That sets `routine_registered: true` on the entry in `repos.yml` — the lockfile
`bootstrap.sh` replays, so the state survives a fresh clone on another machine.
Until it is set (and **absent counts as unset**), two projections of that one
field keep the debt visible:

- `make status` reports `routine not registered` and **exits non-zero**, exactly
  as it does for unpushed work. This is the enforcement; there is no second copy
  to reconcile, and no task to remember to close.
- `daily-plan-summary.md` opens with a banner naming every repo still
  outstanding — that file is what actually gets read each morning.

Both are recomputed on every run, and `routine-registered.py` is the only writer.
So the flag is never hand-edited, and the two renderings cannot disagree with it
— both ask `_status_lib.routine_pending()`, which is the single answer to "is
anything outstanding?"

**A workspace with no routine at all reports nothing here.** If `routine_url` is
unset in `config.yml`, there is no phase two to complete, so no repo is
outstanding and `make status` stays green. That is a supported configuration —
a personal workspace whose repos should never enter a remote run is the obvious
case — not an unfinished setup. Add a `routine_url` later and every repo's
registration reappears immediately, because nothing is stored.

For the same reason `make routine-registered` **refuses** to set the flag in a
workspace with no routine: `true` would assert membership of a `sources` list
that does not exist. `--unset` is still allowed, since clearing a flag claims
nothing.

Skip this step only if you run the pipeline locally (`make run`) and never
remotely.

### 5.3 Optional: the `@claude` workflow secret

`.github/workflows/claude.yml` lets you mention `@claude` on issues and PRs in
*this* repo. It needs a `CLAUDE_CODE_OAUTH_TOKEN` repository secret. The daily
routine does **not** need it — `auto-merge-status.yml` runs on the default
`GITHUB_TOKEN`.

## 6. Who writes what

Three classes plus a hybrid, and the boundary is what keeps regeneration safe:

- **machinery** — `.workspace/scripts/`, `.workspace/prompts/`,
  `.workspace/templates/`, this guide, the `workspace-status` skill,
  `.github/workflows/`, `.gitignore`, `Makefile`. The generator overwrites all of
  it on `update.sh`; edits are lost.
- **content** — `.workspace/repos.yml`, `.workspace/config.yml`,
  `.workspace/daily-plans/**`, your tasks. Created if missing, never overwritten.
- **runtime** — `summary.md`, `daily-plan-summary.md`, `.workspace/state/`. The
  daily run owns them. They are committed (they are the durable record), but
  `setup.sh` and `update.sh` never touch them, so a regeneration can never race
  the routine.
- **hybrid** — `CLAUDE.md` and `README.md`: a generated block inside a file you
  own. The generator rewrites only what is between the markers
  (`git-workspace` / `git-workspace-roster`); every other byte is yours and
  survives every update.

### The rollup is author-scoped

Every git read filters `--author` against `git_author` in `.workspace/config.yml`,
so the summary shows **only your own commits**. A repo a teammate advanced reads
as INACTIVE *for you*, while `state.json` still tracks the real HEAD so tomorrow's
window stays correct. ACTIVE means "you committed", not "the repo moved".

This is why the run **hard-fails** on an unresolved `git_author`: a wrong one
produces a plausible-looking empty rollup instead of an error, which is the worst
kind of failure. If setup could not resolve your email it wrote a placeholder and
warned; fix it in `config.yml` before the first run.

### `summary.md` is not `.workspace/project/status/`

Two different artifacts, easy to confuse:

- **`summary.md`** (top level) — the **automated** git-telemetry rollup the daily
  run writes. Machine-generated and author-scoped. Never hand-write it; every run
  rewrites the file.

  It holds **one section: the latest run**, so it stays a fixed-size dashboard
  rather than growing a section a day. On a day with no new commits it keeps the
  last real work and just re-dates the heading, which then names both dates —
  `## 2026-08-10 — no new work since 2026-08-04` means "this status is current;
  the work it describes is from the 4th". For the day-by-day history, the file is
  committed on every run: `git log -p summary.md`.
- **`.workspace/project/status/`** — **hand-written** periodic status reports, the kind you
  bring to a status-review meeting. Installed by the vendored
  `create-project-system`, entirely optional, and many workspaces never use it.

`daily-plan-summary.md` is the forward-looking twin of `summary.md`: every
`.workspace/daily-plans/*/daily-plan.md` aggregated behind an "At a glance" table, with
the `_workspace` plan first and stale plans flagged.

**Neither deliverable is archived.** Both are rewritten in place, and the
day-by-day history of each is `git log -p <file>` — every run commits them, so
that history is written for free, diffable, and impossible to get out of sync.
There used to be a dated snapshot of `daily-plan-summary.md` under
`.workspace/state/archive/`; it was removed, because it was a second copy of a
history git already had, it grew without bound, and nothing read it.

## 7. The child commit kernel

Each tracked repo carries a `git-workspace-commits` block in its own `CLAUDE.md`
holding the commit schema this workspace parses:

```
<domain>(<scope>): <high-level functional summary>
- [Context]: why this was done / what was learned
- [Impact]: how it alters the project or system behavior
```

That is telemetry, not decoration — it is the only input the rollup has, so
titles are written for a reader who has never seen the repo.

The block is **committed to a shared repo**, so it names no workspace, no
developer, and no version: several developers may track the same repo from their
own workspaces, and anything personal in it would make them overwrite each
other's block forever. It is commit-discipline **only** — plans live
per-developer under `.workspace/daily-plans/`, so a tracked repo should have no
`daily-plan.md` of its own.

`inject-kernel.py` never commits inside a child repo. You `cd` there and commit,
so the change lands with your identity and that repo's hooks.

## 8. The workspace task-system is a triage area

`.workspace/project/tasks/` tracks work that belongs to **no single child repo** —
inter-repo chores, infrastructure, and ideas that have no repo home yet. Work
flows *downward*:

- An idea lands as a workspace task **before** it has a repo.
- A workspace task **graduates** when it earns one: add a subtask "create repo X",
  run `add-repo.py`, then migrate the remaining work into that child repo's own
  task-system. Cross-boundary moves are manual today — recreate in the child,
  close in the workspace.
- Anything that clearly belongs to an **existing** child repo belongs in *that
  repo's* task-system, not here. This one is for the homeless work.

`.workspace/daily-plans/_workspace/daily-plan.md` is that task state rendered as a
plan, redrafted by `make replan`. It is **forward-looking only** — the
workspace's own commits are meta-noise, so unlike a child repo's plan it carries
no retrospective git summary.

Plans live in the workspace rather than in the child repos because they are
*per-developer intent*: each developer's own workspace holds their own plans, so
two developers never collide over one shared plan file.
