# PLAN — dogfood

**Stand up the first real git-workspace (`dev-workspace`), move repos into it,
and retire `project-status`.**

Started 2026-08-02. Task files: `docs/plans/dogfood/` (drafted inline below until
they stop moving). Durable design lives in `DESIGN.md`; this file is only this
effort.

## Where I left off

- **current task** — `01`–`03` done; `04` (move repos in) is next
- **next concrete step** — push `dev-workspace` (`git push -u origin main`), then
  pick the first repo to move and confirm the loop before moving the rest
- **files mid-edit** — none
- **uncommitted / unpushed** — `create-git-workspace`: 2 commits unpushed (`a4b3cc0`, `29dd07d`) plus this file. `dev-workspace`: initial commit unpushed.
- **open questions** — see the section at the bottom; per-repo replan is the big one

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
| 03 | create `dev-workspace` locally, push it to a new remote | **done (unpushed)** |
| 04 | move the first repos in and register them | todo |
| 05 | create the `/schedule` routine, add every repo to `sources` | todo |
| 06 | run a full day: routine writes, `make pull` lands it | todo |
| 07 | strip `project-status` from each migrated repo | todo |
| 08 | retire `project-status`: hook, umbrella `CLAUDE.md`, the repo | todo |

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

**05** — the two manual seams (`DESIGN.md` §8.5). Record the routine URL in
`config.yml` as `routine_url` so the README roster links it.

**06** — the first genuine end-to-end: push the workspace, let the routine run,
`make pull` the aggregates down. This is the test that `git-workspace-test` could
only approximate.

**07** — per `DESIGN.md` §8.9 this is the *last* step per repo, not a separate
cleanup: remove that repo's `ai-project-status` block, root `daily-plan.md`,
`check-daily-plan.py` hook, and `project-status-guide.md`.

**08** — remove the user-level SessionStart hook from `~/.claude/settings.json`,
delete `cornjacket/CLAUDE.md` and `gen-umbrella-claude.py`, and archive the
`project-status` repo.

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

## Done when

`dev-workspace` holds its repos, the scheduled routine has landed a rollup that
`make pull` brought down, no repo still carries `project-status` instrumentation,
and the SessionStart nag is gone.

---

_On finishing: review every task file against `DESIGN.md`, graduate the durable
conclusions, slim this file to pointers, and move it into `docs/plans/dogfood/`._
