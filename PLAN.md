# PLAN — dogfood

**Stand up the first real git-workspace (`dev-workspace`), move repos into it,
and retire `project-status`.**

Started 2026-08-02. Task files: `docs/plans/dogfood/` (drafted inline below until
they stop moving). Durable design lives in `DESIGN.md`; this file is only this
effort.

## Where I left off

- **current task** — `06`, the first genuine end-to-end run. Nothing to build
  first; it happens on its own at 12:43 UTC.
- **what just happened (2026-08-03)** — `10` landed and was **dogfooded**: the
  `routine_registered` flag (absent = outstanding), the `routine-registered`
  verb, the `make status` gate, the `daily-plan-summary.md` banner, and an
  `add-repo` that reconciles instead of refusing. 334 assertions, §8p. Then
  `update.sh` into `dev-workspace`, where the gate flagged `captains-log`
  **before any edit** — the absent-means-outstanding default paying off on a repo
  registered days earlier. The reconcile back-filled the flag in one line and a
  second run wrote nothing. Then `05`: the routine exists, so the flag is now
  honestly cleared and `status` reads clean.
- **next concrete step** — `06`: after the 12:43 UTC run, check that
  `auto/status-2026-08-04` was pushed and auto-merged, then `make pull`. Watch
  for two things the sandbox has never exercised here: whether `claude -p` is on
  `PATH` inside the CCR container (`run.py` step 3 shells out to it), and whether
  `daily.sh`'s PyYAML install works. *Then* move the rest of the repos (`04`).
- **files mid-edit** — none.
- **uncommitted / unpushed** — the hand-filed inbox task `10` superseded was
  already removed in `dev-workspace` (`9f138f2`).
- **open questions** — per-repo replan couples to child task-system internals —
  it worked against `captains-log`, so the scrape matches today;
  `.project-status-ignore` → task `09`; membership beyond `captains-log` TBD.

## Scope

**In:** the two commands that block retirement; creating `dev-workspace` inside
`cornjacket/`; moving a first few repos into it; the `/schedule` routine; winding
down `project-status`, its umbrella `CLAUDE.md`, and its SessionStart hook.

**Out:** the hygiene audit (build it after living in this — `DESIGN.md` §11); a
second workspace (personal tier) — deliberately later; anything about the
generator's own features that dogfooding does not force.

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

## Tasks

In order. Acceptance is one line each until these are extracted into files.

| # | Task | Status |
|---|---|---|
| 01 | `make status` also reports unpushed work; `--all` mode | **done** |
| 02 | per-repo replan — deterministic, no model calls | **done** |
| 03 | create `dev-workspace` locally, push it to a new remote | **done** |
| 04 | move the first repos in and register them | in progress — `captains-log` done, rest after `05`/`06` |
| 10 | track incomplete routine registration; make `add-repo` idempotent | **done**, dogfooded into `dev-workspace` |
| 05 | create the `/schedule` routine, add every repo to `sources` | **done** for the current roster |
| 06 | run a full day: routine writes, `make pull` lands it | todo |
| 07 | strip `project-status` from each migrated repo | todo |
| 08 | retire `project-status`: hook, umbrella `CLAUDE.md`, the repo | todo |
| 09 | discuss whether `.project-status-ignore` was needed at all | todo |

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

**04** — for each repo: `mv` the existing checkout into `dev-workspace/` (do not
re-clone — local branches, stashes, and worktrees must survive), then `add-repo`
registers it as-is and injects the commit kernel. Commit the kernel inside each
child. Start with one low-stakes repo and confirm the loop before moving the
rest.

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

**06** — the first genuine end-to-end: push the workspace, let the routine run,
`make pull` the aggregates down. This is the test that `git-workspace-test` could
only approximate.

**07** — per `DESIGN.md` §8.9 this is the *last* step per repo, not a separate
cleanup: remove that repo's `ai-project-status` block, root `daily-plan.md`,
`check-daily-plan.py` hook, and `project-status-guide.md`.

**08** — remove the user-level SessionStart hook from `~/.claude/settings.json`,
delete `cornjacket/CLAUDE.md` and `gen-umbrella-claude.py`, and archive the
`project-status` repo.

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

**Should `--all` honour an ignore file?** `project-status`'s sweep skips repos
carrying `.project-status-ignore`. The workspace sweep currently has no opt-out,
on the grounds that an unregistered checkout is exactly what you want flagged.
Revisit if the floor gets noisy — the hygiene audit will want the same answer.

**Membership: TBD, deliberately.** `DESIGN.md` §1 files `create-*` generators
under the personal tier, but while they are under **active development** they are
dev work, and putting them in `dev-workspace` is fine. Decide the actual roster
at task `04`; revisit the tier question once the generators stop changing daily.
`second-brain` joins no workspace either way (§8.9).

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

## Done when

`dev-workspace` holds its repos, the scheduled routine has landed a rollup that
`make pull` brought down, no repo still carries `project-status` instrumentation,
and the SessionStart nag is gone.

---

_On finishing: review every task file against `DESIGN.md`, graduate the durable
conclusions, slim this file to pointers, and move it into `docs/plans/dogfood/`._
