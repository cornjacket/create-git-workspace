# 07 — strip `project-status` instrumentation from a migrated repo

Status: in progress — procedure run twice unchanged, on `create-project-system`
(2026-08-03) and `create-ai-builder` (2026-08-04)

The **last step of migrating each repo**, not a separate cleanup pass
(`DESIGN.md` §8.9). A repo that has joined a git-workspace still carries the old
tracker's artifacts until this runs, so for a while it is instrumented twice.

## What `project-status` installed, and what replaces it

The two models instrument a repo very differently, and that asymmetry is the
whole reason this is a one-way deletion with nothing to put back:

| `project-status` installed | Replaced by |
|---|---|
| `.claude/hooks/check-daily-plan.py` — SessionStart nag when the plan went stale | nothing: staleness is **reported** in `daily-plan-summary.md` (`**STALE**`), not blocked at session start |
| `.claude/settings.json` — registers that hook | nothing |
| `project-status-guide.md` — per-repo operating reference | nothing: the workspace's `status-guide.md` lives in the **workspace**, once |
| root `daily-plan.md` — a plan in a shared repo | `.workspace/daily-plans/<repo>/daily-plan.md`, per-developer |
| `ai-project-status` block in `CLAUDE.md` | the `git-workspace-commits` block |

**Four artifacts became one.** A git-workspace injects exactly one thing into a
tracked repo — a 48-line marker block — and that block explicitly says *"Do not
create a `daily-plan.md` in this repo."*

## Procedure

Run from inside the child repo, after it is registered in the workspace.

1. **Import the plan first — never delete it blind.** The root `daily-plan.md`
   usually holds real work-in-progress (what the repo is, what last shipped, the
   ordered queue). Copy its content into the workspace's slot at
   `.workspace/daily-plans/<repo>/daily-plan.md`, **under the `## Notes`
   heading**.

   > The `## Notes` placement is load-bearing. `replan.sh` rewrites everything
   > *above* that heading as derived content on the next redraft, so an import
   > placed anywhere else is deleted silently the first time someone runs
   > `make replan`.

2. `git rm daily-plan.md project-status-guide.md`
3. `git rm .claude/hooks/check-daily-plan.py` — and `.claude/settings.json` if it
   exists **only** to register that hook (check first; a repo may keep other
   settings there). Remove `.claude/` entirely if it is then empty — on both
   repos so far it was not: `settings.local.json` and a vendored skill live
   there and are none of this task's business. Only `settings.json` was the
   hook's.
4. Strip the `ai-project-status` block from `CLAUDE.md` — it is marker-delimited
   (`<!-- ai-project-status:begin -->` … `:end`), so it comes out cleanly. Leave
   the `git-workspace-commits` block alone.
5. Commit **inside the child** (the workspace never commits into a child repo),
   then commit the workspace's plan-slot change separately.

## Which repos need it

Only repos that were `project-status` targets **and** still carry the artifacts.
Check before assuming — a repo may have been un-bootstrapped already:

```
ls daily-plan.md project-status-guide.md .claude/hooks/check-daily-plan.py
grep -c "ai-project-status:begin" CLAUDE.md
```

- `captains-log` — **already clean**; it was un-bootstrapped during its own
  migration. Nothing to do.
- `create-project-system` — **done** (`a3e02be`). `CLAUDE.md` 94 → 52 lines;
  72 lines of plan imported to the workspace slot.
- `create-ai-builder` — **done** (`cdd3104`). It carried all four artifacts;
  `CLAUDE.md` 584 → 542 lines, 36 lines of plan imported to the workspace slot.
  One thing this repo added to the procedure: it is checked out as three
  long-lived worktrees, and **the strip only applies to the branch you run it
  on**. `regression-infra` and `workspace-mgmt` still carry the old artifacts,
  hook included, until they merge `main` — so a session rooted in one of those
  worktrees still gets the nag. Not worth stripping per branch (it would
  conflict on merge); worth knowing before task `08` calls this finished.
- `customer-req-responder`, `second-brain-devkit`, `second-brain-test` —
  pending, and only if they join the workspace at all (roster is still
  undecided; `second-brain` membership is in doubt per `DESIGN.md` §8.9).
- `create-git-workspace` — **not applicable**, never a `project-status` target.

## Acceptance

- The repo carries the `git-workspace-commits` block and nothing from
  `project-status`.
- Its plan content survives in the workspace slot, under `## Notes`, and
  `make replan` preserves it across a redraft.
- No repo is left with both blocks in `CLAUDE.md`.

## Note for task 08

`08` removes the user-level SessionStart hook and archives the `project-status`
repo. It should not run until every repo that is going to migrate has been
through this — otherwise a repo keeps a nag hook pointing at a retired system.
