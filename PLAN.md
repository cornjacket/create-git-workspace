# PLAN — dogfood

**Stand up the first real git-workspace (`dev-workspace`), move repos into it,
and retire `project-status`.**

Started 2026-08-02. Task files: `docs/plans/dogfood/` (drafted inline below until
they stop moving). Durable design lives in `DESIGN.md`; this file is only this
effort.

## Where I left off

- **current task** — `01` done; `02` (per-repo replan) is next but needs a design decision
- **next concrete step** — pick a replan shape (A–D below), or skip to `03` and
  create `dev-workspace`, which is unblocked
- **files mid-edit** — none
- **uncommitted / unpushed** — task `01`'s changes are uncommitted
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
| 02 | per-repo replan — **design undecided**, see open questions | todo |
| 03 | create `dev-workspace` locally, push it to a new remote | todo |
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

**02** — blocked on the design question below.

**03** — `./setup.sh ~/src/github.com/cornjacket/dev-workspace --name dev-workspace
--with-hook`, then `--create-remote` or an existing remote, push, and confirm the
emitted tree is what the suite says it should be. Add `.project-status-ignore`.

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

**Per-repo replan (blocks `02`).** Four candidate shapes, discussed:

- **A — deterministic**, mirroring today's `replan.sh`: read each child's task
  system, render bullets. Free, offline, exactly testable. *Current lean.*
- **B — one `claude -p` per repo**, porting `replan.py`: richer, costs N calls,
  needs the read-only/draft-only/skip-if-dated guardrails.
- **C — A by default, `--ai` to enrich.**
- **D — one call for all repos.** Cheapest LLM option, most fragile.

**Should `--all` honour an ignore file?** `project-status`'s sweep skips repos
carrying `.project-status-ignore`. The workspace sweep currently has no opt-out,
on the grounds that an unregistered checkout is exactly what you want flagged.
Revisit if the floor gets noisy — the hygiene audit will want the same answer.

Either way: **where does a child's task system live?** `<repo>/project/tasks` or
`<repo>/tasks` depending on how it was stamped — needs a convention or a
`repos.yml` field.

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
