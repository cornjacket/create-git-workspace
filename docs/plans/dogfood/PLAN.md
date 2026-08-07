# PLAN — dogfood

**Stand up the first real git-workspace (`dev-workspace`), move repos into it,
and retire `project-status`.**

Started 2026-08-02. Task files: this directory (drafted inline below until
they stop moving). Durable design lives in `DESIGN.md`; this file is only this
effort.

<!-- PARKED 2026-08-07: scope met on 08-06. Not archived, because `17`, `20`'s
     writer half, `25` and `26` still name this effort. Sequenced from the
     master plan at the repo root; see task 26 for why parking is now a legal
     state. Tasks `18`, `23` and `24` moved to `docs/plans/rollups/`. -->

**Status: parked.** Scope met 2026-08-06 — `01`–`15` all landed and `08`
mothballed `project-status`. What remains is follow-on defects, not scope this
plan set out with.

## Where I left off

- **current task** — none in flight; this effort is **parked**. Stated goal met:
  `01`-`15` all landed, `08` mothballed `project-status` 08-06. Remaining `17`,
  `20`-writer, `25` and `26` are defects dogfooding exposed, not scope this plan
  set out with. `18`, `23` and `24` were the same kind of orphan and moved to
  the `rollups` effort on 08-07.
- **next concrete step** — **`20`** — `sources` becomes a verb. On 08-07 the
  whole algorithm was executed **by hand** to register `create-context-hygiene`:
  read `routine_url` from `config.yml`, `RemoteTrigger get`, diff against
  `repos.yml`, resend the entire config. That is steps 1-4 of `20`'s own spec,
  proven end to end against the live routine. Third hand-edit of this seam; the
  script is now transcription, not design.
  Start: `.workspace/scripts/routine-sync.py` with `--check` for `status.py` to
  call, so the gate verifies the **actual** remote state instead of trusting a
  flag that asserts it.
  (`17` remains the cheapest item — one edit, four copies of the commit schema —
  but it is not what today made ready.)
- **files mid-edit** — none.
- **uncommitted / unpushed** — none. Verified `git status` + `git log @{u}..`,
  both empty. Whole `dev-workspace` floor clean except `create-context-hygiene`,
  which reads `routine not registered` after being unmuted 08-07.
- **open questions** — `discovery.json`'s filename and merge rule must be agreed
  between `create-project-system` `28` and `create-context-hygiene` `13` before
  either writes code; two generators writing one file under different names is a
  silent mutual overwrite. Whether this repo vendors `create-context-hygiene`
  (leaning yes) and whether it then checks its own *template* in CI — a
  workspace's `CLAUDE.md` is machinery, so an over-budget block is fixable only
  here, and one bad template edit fails CI in every workspace at once.

### Queued, not started

_Effort-level sequencing moved to the master plan at the repo root on 08-07 —
this list is no longer the queue, and `mail` is no longer blocked by this file._

- **`docs/plans/mail/PLAN.md`** — 9 tasks. Entry point: read
  `create-project-system` `27` first — it **landed 08-07**, so this is now a
  read, not a wait.
- **`create-project-system`** `27` (`--json` lister) and `28` (`discovery.json`
  keys) — design together, one sitting.
- **`create-context-hygiene`** `13` (CI is the gate) — unparked 08-07,
  `sources` edit outstanding.

## Scope

**In:** the two commands that block retirement; creating `dev-workspace` inside
`cornjacket/`; moving a first few repos into it; the `/schedule` routine; winding
down `project-status`, its umbrella `CLAUDE.md`, and its SessionStart hook.

**Out:** the hygiene audit (build it after living in this — `DESIGN.md` §11);
anything about the generator's own features that dogfooding does not force.

**Moved IN on 2026-08-04:** a second workspace. `personal-workspace` was "out,
deliberately later" on the grounds that the trigger had not fired — but the
roster decision *is* that trigger: `foa`, `ymca-basketball`, and `dotfiles` have
no dev home and §10 says build the second workspace when one actually happens.
It has now happened. Task [`15`](15-personal-workspace.md).

## Decisions already made

- **`cornjacket/` is not a workspace.** It is the parent GitHub directory. The
  workspace is `cornjacket/dev-workspace/`, and member repos live *inside* it.
- **One workspace to start.** A second (personal) comes later, once the first is
  proven.
- **The unpushed sweep folds into `make status`** rather than being a new
  command, and takes `--all` to sweep every git repo on the floor, not just
  registered ones.
- **Delete the generated `cornjacket/CLAUDE.md`.** It is unversioned, which
  `DESIGN.md` §10 #12 already rules against, and both of its jobs move into
  `dev-workspace`. Replace with at most a hand-written signpost carrying no
  roster, and retire `gen-umbrella-claude.py` with it.
- **`.project-status-ignore` in `dev-workspace`** as the interim fix for the
  SessionStart nag; the hook itself is removed in the last task.
- **One session drives both repos, for this effort only — a deliberate,
  expiring exception.** `dev-workspace/CLAUDE.md` says to run its commands from
  a session rooted there. During dogfooding they run from here instead, because
  the plan and the migrations feed each other: tasks `12`, `16`, `19` and `20`
  were all found *while* migrating, and `16` specifically by reading a rollup
  mid-migration — a session that only did membership work would not have looked.

  **This is not a licence to be sloppy.** Every git command is explicitly
  `cd`-ed or `git -C`-ed into its target, which is the only reason nothing has
  landed in the wrong index; `guard.sh` has passed on every workspace commit,
  and today's logs are a clean split (generator: `PLAN.md`, `DESIGN.md`,
  `docs/plans/`; workspace: `repos.yml`, `daily-plans/`, `README.md`). Note the
  extra wrinkle since `14`: this repo is now a *child of* `dev-workspace`, so
  the session sits inside the workspace it is driving.

  **Expires when this effort closes.** At that point membership work moves to a
  `dev-workspace`-rooted session and this repo goes back to generator work only.
  Recorded here so a later reader sees a decision rather than a violation to
  "correct".

## Tasks

In order. Acceptance is one line each until these are extracted into files.

| # | Task | Status |
|---|---|---|
| 01 | `make status` also reports unpushed work; `--all` mode | **done** |
| 02 | per-repo replan — deterministic, no model calls | **done** |
| 03 | create `dev-workspace` locally, push it to a new remote | **done** |
| 04 | move the first repos in and register them | **done** — all 7 in and registered; `create-context-hygiene` unmuted 08-07, `sources` edit outstanding |
| 15 | stand up `personal-workspace` — [`15`](15-personal-workspace.md) | **built** — 2 repos in; routine outstanding |
| 16 | an UNAVAILABLE repo vanishes from the rollup — [`16`](16-unavailable-is-a-silent-omission.md) | **done** — 369 assertions; reported, not skipped |
| 17 | the injected kernel omits the blank line after the commit title | **filed** — all four copies of the schema, see `04` notes |
| 19 | confirm the `sources` fix on the 08-05 run — [`19`](19-confirm-the-sources-fix.md) | **done** — 08-05 and 08-06 runs both carry all three repos; `state.json` has a key for each |
| 20 | `sources` should be a verb, not a manual seam — [`20`](20-sources-should-be-a-verb.md) | **reader done 08-07** — `routine-sync.py --check`, 394 assertions, live; the writer stays open behind a round-trip verification |
| 21 | a workspace with no routine should not nag — [`21`](21-no-routine-no-nag.md) | **done** — 362 assertions; `personal-workspace` green |
| 22 | `replan` crashes and truncates the roster — [`22`](22-replan-crashes-and-truncates.md) | **done** — 353 assertions, dogfooded into both workspaces |
| 25 | `status` measures a worktree against its remote, never against `main` — [`25`](25-worktree-divergence-is-invisible-debt.md) | **filed 08-07** — filed from a live three-worktree integration |
| 26 | the plan layer has no sequencer — [`26`](26-the-plan-layer-has-no-sequencer.md) | **filed 08-07** — master plan at the root; this effort parked rather than archived |
| 10 | track incomplete routine registration; make `add-repo` idempotent | **done**, dogfooded into `dev-workspace` |
| 05 | create the `/schedule` routine, add every repo to `sources` | **done** for the current roster |
| 06 | run a full day: routine writes, `make pull` lands it | **done** — passed first try |
| 11 | `summary.md` holds the latest run only, not a growing journal | **done** |
| 12 | how a git-worktree layout is tracked — [`12`](12-worktree-membership.md) | near-term step **done** (`main` registered); full build still deferred |
| 13 | mount the task-system under `.workspace/` — [`13`](13-task-system-under-workspace.md) | **done**, dogfooded into `dev-workspace` |
| 14 | move `create-git-workspace` into `dev-workspace` — [`14`](14-migrate-create-git-workspace.md) | **done** — acceptance verified from the new location |
| 07 | strip `project-status` from each migrated repo — [`07`](07-strip-project-status.md) | **done** — every repo clean, incl. the two worktree branches |
| 08 | retire `project-status`: hook, umbrella `CLAUDE.md`, the repo | **done 2026-08-06** — remote archived read-only |
| 09 | discuss whether `.project-status-ignore` was needed at all | **moot** — the hook is gone; files are inert litter |

**01 — done.** `unsafe_reasons()` became `_status_lib.pending_findings()`,
shared verbatim with `delete-repo` so a report and a refusal cannot disagree.
`status.sh` was rewritten as `status.py` rather than duplicating the detector in
bash. Three judgement calls worth keeping: a repo with **no remote at all** reads
`clean (local-only)` rather than "unpushed", because local-by-design is not
forgotten work — while `delete-repo` still blocks on it, since "exists nowhere
else" is what makes a deletion unrecoverable; the **workspace itself is a row**,
as its own uncommitted plans are the easiest to forget and the routine's
fast-forward depends on them being pushed; and `--all` sweeps unregistered
checkouts with no ignore-file yet (see the open question). §8n, 291 assertions.

**02 — done.** Shape **A**: a plan is a *report* of decisions already made, so
`replan.sh` projects task state into plan files with no model call. It now covers
every enabled repo carrying a task-system plus the workspace's own, with `--repo`
to target one. Notable calls: the child's task-system is **probed**
(`project/tasks`, then `tasks/`) rather than configured, so there is no field to
keep true; a repo with no task-system is skipped **loudly** rather than given an
empty plan, since "nothing to do" and "does not track tasks here" are different
claims; `enabled: false` repos are skipped, which needed a new
`parse_enabled_repos` in `lib.sh` (`bootstrap`/`guard` still want every repo);
and `add-repo`'s seeded plan now matches the shape `replan` writes, so the first
redraft preserves the human half instead of eating it. A test puts a failing stub
`claude` on `PATH` to prove no model is ever called. §8o, 307 assertions.

**03 — done, not yet pushed.** Stamped with `--create-remote --with-hook`;
`cornjacket/dev-workspace` exists and is **private**, origin is wired, nothing
pushed. `git_author` resolved from git config. First real proof of task `01`:
`make status` reports `no upstream` — a remote exists and the branch has never
been pushed, which is exactly the state it was built to catch.

`.project-status-ignore` is present but **deliberately untracked** — the
allowlist ignores it, and force-adding it (or adding a `!` line to the emitted
allowlist) would put a transitional artifact of a *retiring* system into the
generator's machinery. It only has to exist locally to silence the hook, and it
dies with the hook at task `08`. Verified: the nag is now silent.

**04 — in progress; the method changed from `mv` to CLONE.** The original plan
moved each checkout in so local branches, stashes, and worktrees survived. The
clone path is the better test — it proves `repos.yml` reconstitutes a workspace
from nothing, which an `mv` never exercises — and the pending sweep (`01`) is
what makes it safe: it is run first, and a repo with nothing local-only to lose
can be reproduced exactly from its remote. The old checkout is then removed.

Per repo: verify clean → `add-repo <url>` clones and registers → commit the
kernel inside the child → add to the routine's `sources` → `routine-registered`
→ commit the workspace → remove the old checkout.

- `captains-log` — done earlier, by `mv` (before the method changed).
- `create-project-system` — **done by clone.** Fresh clone came back at the same
  HEAD (`322924c`) as the checkout it replaced; kernel committed inside the child
  (`701f502`); old checkout removed.
- `create-ai-builder` — **done by MOVE**, per `12`'s near-term step. Bare +
  three worktrees is a shape no verb can reproduce, so this is the one repo the
  clone path could not take: the container was moved whole, `git worktree
  repair` fixed the absolute gitdir pointers the `mv` broke in both directions,
  and only `main` is registered. Coverage is knowingly partial — the other two
  branches are outside the rollup, and the bare container reports a **false
  clean** in the `--all` sweep. Both recorded in `12`.
- `create-git-workspace` — decided in, **with a session hazard**: it is the repo
  a working session is normally rooted in, so cloning it into `dev-workspace` and
  deleting the old checkout removes the directory that session is standing in.
  Do the clone and registration, then re-root the session at the new path
  *before* deleting the old one. **Done** — see [`14`](14-migrate-create-git-workspace.md).
- **the rest — DECIDED 2026-08-04.** Three repos join, three classes stay out.

  **In:** `second-brain-devkit` (248 commits, the most active repo on the
  floor), `create-context-hygiene` (a generator, quiet since 07-26 but in by the
  same rule), `customer-req-responder` (an app, not checked out anywhere — it
  joins by clone, which is the path `04` already prefers).

  **Out, as fixtures:** `second-brain-test`, `git-workspace-test`,
  `tasks-test`, `tasks-test-wt`. Graduated to `DESIGN.md` §8.9.

  **Refined the same day: a fixture lives ON the floor, it is just not a
  member.** Not a compromise — `second-brain-devkit` addresses its golden as
  `../second-brain-test/` in eleven files, so migrating the devkit while
  leaving the golden outside would have broken the devkit's own documented
  prototyping loop. Physical adjacency is a real requirement; membership is a
  separate question, and the answer to it is still no. `second-brain-test` was
  moved in and is deliberately unregistered.

  What saved this from being a live breakage: OQ-1 in the devkit resolved to
  **vendoring** the golden at `tests/golden/` (109 files), so CI never reaches
  outside the repo. Only the human prototyping loop and the doc links depend on
  the sibling path.

  **Out, to `personal-workspace`:** `foa`, `ymca-basketball` — done, see task
  [`15`](15-personal-workspace.md).

  **Out, to no workspace at all: `dotfiles`.** Revised 2026-08-04, having been
  listed for `personal-workspace` and then briefly for `dev-workspace`. It is
  **config, not a project** — consumed by every session in every repo, a member
  of none, which is §8.9's `second-brain` argument applied to config. The
  hazard settles it: its files are symlinked into live locations by absolute
  path, so any migration silently breaks them, and the one live link is
  `~/.claude/CLAUDE.md` — the global instructions. Nothing errors; sessions just
  quietly stop following rules you believe are loaded. Graduated to §8.9 and
  written into the repo's own README, so the next person to eye it as a
  migration candidate is warned by the repo rather than by luck.

  **Out, nothing to track:** `create-repo-mail` has **zero commits**. Not a
  judgement about the repo; there is literally no history for a rollup to read.
  Revisit when it has one.

  **Resolved 2026-08-06 — it never will.** The revisit trigger cannot fire: the
  repo was to be a generator installing an inter-repo mailbox, and that job is
  now a **workspace feature**, planned here as
  [`docs/plans/mail/PLAN.md`](../mail/PLAN.md) — addressing, delivery
  and notification are all workspace-scoped because only the workspace holds the
  roster, so there is nothing left for a separate generator to install. It has
  no checkout on any floor. What survives is an empty public GitHub repo,
  `cornjacket/create-repo-mail`, which wants archiving or deleting; that is a
  remote-side chore for whoever does the next roster pass, not a membership
  question.

  What unlocked it: `DESIGN.md` §8.9's `second-brain` exemption is about the
  **vault**, not `second-brain-devkit`. The vault is a singleton *product* and
  not a repo on any floor; the devkit is a generator whose subject is its own
  code, which §2 places like every other generator. That conflation is the whole
  reason this read as undecidable — the fix is in §8.9 so it cannot recur.

**10 — done in the generator.** Registration is two-phase and only phase one is
automatable, so the in-between state is now **recorded rather than printed**:
`routine_registered` in `repos.yml`, where **absent means outstanding**, so every
repo registered before the field existed reads as the debt it actually is.
`routine-registered.py` (`make routine-registered ARGS="<name>"`, plus `--all`,
`--unset`, `--check`) is the only writer of a `true` — without a verb, the only
exit from the state would be hand-editing the lockfile every other rule forbids.
`make status` gates on it (`routine not registered`, non-zero) and
`aggregate-plans.py` banners it above the "At a glance" table. Two projections of
one field, recomputed every run; the durable half is in `DESIGN.md` §8.5.

Judgement calls worth keeping: the flag is reported by `status` but is **not a
git finding**, so `delete-repo` does not refuse over it — nothing is at risk of
being lost, and folding it into the shared detector would have made a
housekeeping debt block a deletion. A repo with `enabled: false` is **exempt**:
it is out of the run entirely, so it cannot be silently omitted from a rollup it
never joins — and re-enabling brings the debt straight back, because nothing is
stored. And **no tracking task**: that would be a third copy of one fact,
hand-closable and therefore driftable (`dev-workspace`'s hand-filed
`446273-captains-log-routine-sources-registration` is superseded by this).

`add-repo` is now **idempotent**: re-running it over a registered repo reconciles
— back-fills a missing flag, re-seeds a deleted plan slot, re-injects a stale
kernel — and writes nothing when nothing is missing. It refuses only to *repoint*
an entry (a different `url` or `--path` under an existing name), since that is a
re-registration and would leave the manifest and the checkout describing two
different repos. That is what makes the mechanism provable against `captains-log`
without unregistering it first. §8p, 334 assertions.

**Still to dogfood.** `update.sh` into `dev-workspace`, re-run
`add-repo captains-log` to back-fill the flag, then add it to `sources` and clear
it. `05` then populates `sources` once from a complete `repos.yml` instead of six
manual edits.

**05 — done, and deliberately moved ahead of the rest of `04`.** The routine is
`trig_01TA28JDCMTd8Em8sceLpxEC`, `43 12 * * *` (12:43 UTC daily), sources
`dev-workspace` + `captains-log`, running `daily.sh` with a terse "just run the
script" prompt modelled on `project-status`'s. It sits 30 minutes behind that
routine's 12:13 UTC so the two do not overlap while both exist; `08` retires the
other. `routine_url` is in `config.yml` and the README roster links it.

**Why the resequence.** The original order held `05` until the roster was
complete, so `sources` could be populated in one edit instead of six. Two things
outweighed that: `10`'s gate had **no honest exit** — a flag that cannot be
cleared until a routine exists is a permanent red `status` — and `06` is the
first genuine end-to-end proof, which is worth having on *one* repo before
multiplying the setup by six. Same argument `04` already made for moving one
low-stakes repo first. **The cost is real and accepted:** each remaining repo now
needs its own `sources` edit as it lands, rather than one bulk edit at the end.
`routine-registered --all` still clears the flags in one go.

**06 — done, passed on the first run.** Triggered by hand rather than waiting
for 12:43 UTC. `auto/status-2026-08-04` was pushed within ~20s, auto-merged onto
`main` and deleted, and `make pull` brought down `a0a0bd4` — four files, exactly
the routine-owned set. **Both sandbox unknowns cleared:** `claude -p` *is* on
`PATH` in the CCR container (the rollup is real prose, not dry-run placeholders)
and `daily.sh`'s PyYAML install worked. `daily-plan-summary.md` came back with no
banner, which proves the `10` projection renders remotely too — had the flag been
cleared before the routine existed, `captains-log` would have been silently
absent instead.

What it exposed: the first run's window is `EMPTY_TREE..HEAD`, so the section
covered `captains-log`'s entire history — which is what made the growth problem
in `11` obvious.

**11 — `summary.md` is a dashboard, not a journal.** It held one dated section
per run, prepended forever, so it grew without bound and the first run's
whole-history section sat at the top of it. Now the file holds **exactly one
section — the latest run** — and is rewritten rather than appended to.

The quiet-day rule is the part worth keeping: a run with no new commits does
**not** replace real work with an empty "No updates" list, because that reads as
*nothing has happened* when the truth is *nothing has happened since*. It keeps
the body verbatim and re-dates the heading, which then names both dates
(`## 2026-08-10 — no new work since 2026-08-04`). The activity date is parsed
back out of that heading rather than re-derived, or a run of quiet days would
creep it forward a day at a time and quietly claim the work was recent.

Deliberately **not** archived like `daily-plan-summary.md` is: every run commits
the file, so `git log -p summary.md` already is the day-by-day journal, and a
second copy under `.workspace/state/archive/` would reintroduce the growth this
removed. Documented in `DESIGN.md` §8.3 as the third output contract. Note this
also fixed a doc bug next door — the guide claimed dated snapshots of *both*
deliverables land in the archive, which was never true.

**Deferred, and worth a decision later:** the gather window itself is untouched.
`state.json`'s `last_commit..HEAD` still preserves catch-up after a missed day —
capping it would bound the *content* too, but would silently drop work done on a
day the routine did not run. Bounding the file solved the growth; bounding the
window would trade correctness for it.

**12 — the worktree membership gap.** Full analysis in
[`docs/plans/dogfood/12-worktree-membership.md`](12-worktree-membership.md)
— the first task in this effort to earn its own file. In short: `repos.yml` can
*describe* a worktree layout and `bootstrap.sh` can *replay* one, but `add-repo`
only ever writes `type: standard`, so nothing can create the entries the schema
declares — and hand-editing the lockfile is what every other rule here forbids.

Registering three worktree entries by hand is worse than it looks: they are
`UNAVAILABLE` to the remote run *by construction* (the platform pre-clones
`sources` by repo, so `/home/user/<worktree-name>` never exists), `10`'s flag has
no honest value for them (three worktrees are one `sources` entry), and the first
run reports one shared history once per worktree. The asymmetry that should
decide the design: **the rollup is per-repo; `status` is per-worktree.** Lean is
to keep the registry per-repo and expand worktrees at runtime in `status` only.

**13 — the task-system sits on the floor.** Full analysis in
[`docs/plans/dogfood/13-task-system-under-workspace.md`](13-task-system-under-workspace.md).
`project/` installs in the workspace **root**, the one directory that should hold
child repos and nothing else, while every other workspace-owned artifact —
including `daily-plans/`, which is human-edited content too — already lives under
`.workspace/`. The vendor is parameterized (`--tasks-dir`), so the emit side is a
flag change; `--with-status` moves `status/` along with it.

Both open questions settled the way the lean pointed. **`status/` follows** —
the vendor derives it as a sibling of the tasks mount, so one flag places both,
and splitting the container would make `update.sh` keep two halves apart forever.
**`update.sh` detects and instructs, never moves** — it now accepts either mount,
installs at the new one, and prints the old one plus the `git rm`. That last part
was not optional after all: probing only the new mount would have read every
pre-move workspace as `--no-tasks` and silently stripped the subsystem.

`dev-workspace` has **zero** tasks, so its own migration is scaffolding only —
safe to do first, and precisely for that reason it does not exercise the case
that matters.

**07** — per `DESIGN.md` §8.9 this is the *last* step per repo, not a separate
cleanup: remove that repo's `ai-project-status` block, root `daily-plan.md`,
`check-daily-plan.py` hook, and `project-status-guide.md`. First candidate was
`create-project-system`, which carried both instrumentation blocks — **done**.
The other two migrated repos need nothing and it is worth saying why rather than
rechecking later: `captains-log` carries only a `.project-status-ignore` and no
instrumentation, and `create-git-workspace` was never a target at all — which is
precisely what its SessionStart nag has been reporting. So `07` is idle until the
next repo lands.

**08 — DONE 2026-08-06.** `project-status` is mothballed. Verified rather than
assumed: the GitHub remote is `isArchived: true` and read-only, its description
records the supersession, the local checkout is gone from the floor, and
`~/.claude/settings.json` no longer carries the SessionStart hook. The umbrella
`cornjacket/CLAUDE.md` survives but is now **hand-owned** — the plan had it
deleted outright, and keeping a hand-written signpost with no roster is the
milder option the Decisions section already allowed for.

**The repo was archived, not deleted.** It still holds the historical
cross-repo activity record (`summary.md`, `daily-plan-archive/`), which is the
one thing the new system genuinely does not carry forward: this workspace's own
history starts at its first run.

**07 — DONE.** Re-checked on 08-06: `second-brain-test` and both
`create-ai-builder` worktree branches (`regression-infra`, `workspace-mgmt`) are
now clean of the old instrumentation, closing the inventory below. Nothing on
the floor carries a hook pointing at an archived repo.

**09 — moot, and worth recording as such rather than answered.** The question
was whether `.project-status-ignore` was worth creating given `08` would delete
the hook anyway. `08` has now happened, so the files are inert: seven remain
scattered (`dotfiles`, `tasks-test`, `tasks-test-wt/main`, `dev-workspace`,
`captains-log`, `second-brain-test`, `ymca-basketball`). None is read by
anything. They are litter, not debt — sweep them whenever, or never.

The lesson the question was really asking about: **a transitional artifact
created to silence a system you are retiring will outlive the system.** It cost
nothing here because the file is inert; it would have cost something if it had
been wired into behaviour.

**Inventory: who still carries the old instrumentation (surveyed 2026-08-04).**
`07` only ever runs on a member's default branch, so the leftovers are exactly
the places membership does not reach. This list is `08`'s precondition — a hook
pointing at an archived repo is the failure `07`'s closing note warns about.

| still instrumented | why `07` missed it |
|---|---|
| `second-brain-test` | a fixture, never a member — hook, plan, guide, block |
| `create-ai-builder/regression-infra` | a non-default branch of a member |
| `create-ai-builder/workspace-mgmt` | same |
| `customer-req-responder` | not migrated yet; `07` runs as its last step |

**Clean, and worth recording so nobody re-checks:** `git-workspace-test`,
`tasks-test`, `tasks-test-wt` were never `project-status` targets at all — the
"fixtures carry stale hooks" worry turned out to be true of exactly one fixture,
not the class.

**`second-brain-test` is not a plain `07`.** Its `CLAUDE.md` is vendored into
the devkit at `tests/golden/CLAUDE.md` and flows from there toward emitted
brains, so stripping it is a devkit operation (prototype → `vendor_golden.py` →
commit), not a workspace edit. State the requirement here; the devkit does the
work — and see its `#41`, which is the same swap seen from the other side.

**09** — `dev-workspace` got a `.project-status-ignore` to silence the
SessionStart nag. Question the premise: the hook is deleted in `08` anyway, so
the file may buy a few days of quiet in exchange for an artifact to remember to
remove. Alternatives: delete the hook now and skip `08`'s half; or leave the nag
and let it die with the hook. Decide before `08`, and if the file stays, note
that it is untracked by design.

## Open questions

**Per-repo replan couples to the child's task-system internals (revisits `02`).**
`replan.sh` probes the layout, calls `list-tasks.sh`, **scrapes its human output
with `sed`**, and assumes the folder vocabulary. There is no `--json`. For the
workspace's *own* plan that is fine — it vendored and installed that task-system
and knows its version. For a *child* it is over-reach, and the failure is silent:
if the output format changes, the scrape matches nothing and the plan reads
`_Nothing in progress._`, which is a plausible wrong answer rather than an error.

Options: **(a)** the child advertises a machine-readable interface — file
`list-tasks.sh --json` upstream against `create-project-system`, per §4's rule
that the workspace states the problem and the owning repo does the work;
**(b)** declare the flavour+version in `repos.yml` and only trust known ones;
**(c)** drop per-repo replan and keep those plans hand-written; **(d)** an AI
pass for repos with no task-system at all; **(e)** verify the interface before
trusting it, and skip loudly when it does not match.

Lean: **(e) now** to close the silent-failure hole, **(a)** as the real fix, and
let dogfooding decide whether **(c)** was right all along. Not **(d)** until a
real repo without a task-system exists.

**Precedent for (c):** under `project-status` every repo's `daily-plan.md` was
**hand-written**, and that worked. The aggregator only ever needed a plan file to
exist, not a tool to generate it. Deferred by agreement — revisit after `04`,
with real repos in the workspace.

**Should `--all` honour an ignore file? — now concrete.** `project-status`'s
sweep skips repos carrying `.project-status-ignore`. The workspace sweep has no
opt-out, on the grounds that an unregistered checkout is exactly what you want
flagged. The fixture decision put two deliberate non-members on the floor
(`second-brain-test`, plus the `create-ai-builder` container), so `--all` now
reports rows that are correct-but-expected.

**A reading worth considering before building anything:** this may already be
right. Plain `make status` shows only members, so a fixture's status is *already*
untracked in the default view. `--all` is an explicit sweep-everything mode, and
a fixture with unpushed work in it is genuinely worth knowing about — that is
task `01`'s whole purpose. The gap is presentation, not policy: `unregistered`
reads as "you forgot to register this" when the truth is "deliberately not a
member". A third state, or a marker file that changes the *label* rather than
hiding the row, may be the whole fix.

**Membership: ~~TBD~~ decided 2026-08-04** — see `04` above. `DESIGN.md` §1 files
`create-*` generators under the personal tier, but while they are under **active
development** they are dev work, so they are in `dev-workspace`. Revisit the tier
question once the generators stop changing daily. `second-brain` — the **vault**
— joins no workspace either way (§8.9); its devkit does.

**What happens to `project-status/tracked/`?** It holds clones of every tracked
repo. Deleting it is presumably right once nothing reads it, but confirm no
unpushed work is sitting in one of those clones first — which is exactly what
`01` is for.

## Decisions

- Plans are a **report**, not an act of planning → deterministic replan, no model
  call. Rules out inventing work that was never chosen (task `02`, DESIGN §8.3b).
- `status.py` replaces `status.sh` → one shared pending-detector with
  `delete-repo`. Rules out a bash copy that could disagree with a refusal (`01`).
- A repo with no remote reads `clean (local-only)`, not "unpushed" — local by
  design is not forgotten work. `delete-repo` still blocks on it (`01`).
- The workspace is a row in its own `status` output; its uncommitted plans are
  the easiest to forget and the routine's fast-forward depends on them (`01`).
- Child task-system is **probed**, not declared in `repos.yml` — no config field
  to keep true. Under review: see Open questions (`02`).
- `.project-status-ignore` left **untracked** — a transitional artifact of a
  retiring system does not belong in the emitted allowlist (`03`, `09`).
- `dev-workspace` created **private** — it carries plans and a rollup (`03`).
- An un-automatable step is **tracked in the lockfile, not printed**, and
  **absent means outstanding** — the default has to fail loud (`10`).
- The `status` gate *is* the enforcement; the banner is a second projection, not
  a second record. No task, nothing to close by hand (`10`).
- The flag is not a git finding: `delete-repo` never refuses over it (`10`).
- Membership verbs are **re-runnable** — `add-repo` reconciles, so repairing a
  registered repo never requires deleting its checkout first (`10`).
- `05` **before** the rest of `04`: a gate with no honest exit is worse than six
  small `sources` edits, and `06` is worth proving on one repo (`05`).
- `summary.md` is a **dashboard, not a journal** — one section, rewritten. The
  journal is `git log -p summary.md`, which every run already writes (`11`).
- A quiet day **re-dates** the last real work rather than replacing it with "No
  updates"; the heading names both dates so the two never blur (`11`).
- A worktree layout is registered by pointing at a **worktree path** under the
  **repo's** name — the name, not the path, is what the remote run resolves as
  `/home/user/<name>`, and the platform pre-clones by repo (`12`).
- Partial coverage is **stated, not silent**: `create-ai-builder` is tracked on
  `main` only, and that is written into its plan slot as well as the task file —
  the §5.2 rule that a repo missing from a rollup must say so (`12`).
- A repo that exists **only as another repo's test target is a fixture, not a
  member** — tracking it reports the owner's work twice (`04`, DESIGN §8.9).
- §8.9's `second-brain` exemption is the **vault**, not the devkit. The product
  is not a repo on any floor; the generator is (`04`, DESIGN §8.9).
- A repo with **zero commits** is not a membership question — there is no
  history to roll up. Deferring to a first commit is the right answer, but it is
  a *bet* the repo happens: `create-repo-mail` never got one, because the idea
  was absorbed into the workspace as `docs/plans/mail/PLAN.md` and the empty
  remote outlived it. An empty repo is a placeholder for an idea, and ideas move
  — so the deferral needs an owner who notices, not just a trigger (`04`).
- The **second workspace happens now**: three personal repos is the trigger §10
  named, so `personal-workspace` is built rather than deferred (`15`).
- A **fixture lives beside the repo that tests it**. `git-workspace-test` moved
  onto the `dev-workspace` floor because `tests/run-tests.sh:1997` resolves it as
  `$GEN_ROOT/../git-workspace-test` — it was not there, so test 10 skipped on
  every `--remote` run. Rules out leaving fixture placement to convention.
- **Mail is addressed to repos, not agents** — an agent is a process and ends;
  a repo is a place and persists. Rules out an agent-to-agent bus, which would
  rebuild in-session coordination the harness already provides
  (`docs/plans/mail/PLAN.md`).
- **One shared `discovery.json`, one key per capability** — not a file per
  capability. Settled 08-07 when a second generator needed to declare something
  about the same repos. Rules out `inbox.json` + `context-hygiene.json`, which
  would leave a consumer probing for each in turn — the problem
  `create-project-system` `28` exists to end, one level up. Two rules follow: a
  generator **owns its keys and never rewrites another's**, and the version is
  **per key** (`mail` `001`, c-p-s `28`, c-c-h `13`).
- **CI is the hygiene gate, so it cannot be opt-in.** A pre-commit hook is
  bypassable with `--no-verify`, so it can only ever be the warning. Rules out
  the workspace owning a token counter: it runs each repo's installed checker
  and collects answers, so two counters can never disagree (c-c-h `13`).
- `create-context-hygiene` **unmuted 08-07** rather than left parked. Its
  keep-or-drop question is answered by the CI decision above — only a repo-local
  install can fail a push, so the generator is the only shape that delivers it.
- **`## Where I left off` is state, not a log.** Wrapped 08-07: three dated
  "what just happened" entries collapsed into current state. The dated history
  is `git log -p PLAN.md`, the same argument `11` made for `summary.md`.

## Done when

`dev-workspace` holds its repos, the scheduled routine has landed a rollup that
`make pull` brought down, no repo still carries `project-status` instrumentation,
and the SessionStart nag is gone.

**Amended 2026-08-04:** every repo on the floor now has an *answer*, which is
not the same as being in a workspace — a fixture, a personal repo, and a repo
with no commits are all answered without joining `dev-workspace`. `08` may only
declare `project-status` obsolete once each of its five tracked repos has one.

**MET 2026-08-06.** All four clauses: `dev-workspace` holds seven repos, the
routine has landed rollups that `make pull` brought down on three separate
days, no repo carries `project-status` instrumentation, and the nag is gone
with the hook. A second workspace exists that was never in the original scope.

**What is left is not this plan.** `16`-`22` are defects and follow-ups
dogfooding produced. They deserve their own effort rather than keeping this one
open — closing a plan whose stated goal is met is what stops it becoming a
permanent backlog. Do the graduation pass below, then start the next plan with
`16` at its head.

---

_On finishing: review every task file against `DESIGN.md`, graduate the durable
conclusions, and slim this file to pointers. It already lives in its archive
directory — parking moved it here on 2026-08-07, so finishing is a status change
in the master plan, not a second move.
**Also retire the two-repo session exception** in "Decisions already made" —
membership work returns to a `dev-workspace`-rooted session._
