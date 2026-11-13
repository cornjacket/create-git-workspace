# PLAN — dispatch

**Let the workspace leader start a background agent on an existing task, in a
registered worktree, and watch its status and relay its questions.**

Started 2026-10-22, from a `dev-workspace` leader proposal. Task files: drafted
inline below until they stop moving. Durable design lives in `DESIGN.md`; this
file is only this effort.

Follows [`proposals`](../proposals/PLAN.md), which turns an idea into a task in
the target repo. This effort starts work on such a task. It also replaces the
part of [`mail`](../mail/PLAN.md) that left reply paths out of scope.

Provenance for the transferable lesson: the second-brain note
`[[leader-agent-across-a-multi-repo-workspace]]`
(`vault/resources/leader-agent-across-a-multi-repo-workspace.md`).

## Overview

The leader in the workspace does two separate things: hand-over (`proposals`)
and work start (this effort).

```
                               YOU
                    ideas · answers · approvals · merges
                                │
                                ▼
 ┌──────────────────── WORKSPACE (dev-workspace) ────────────────────┐
 │  LEADER session  (rooted at workspace root, auto mode)            │
 │                                                                   │
 │  proposals/   rough ─► shaped ─► ready ─► handed-over ─► closed   │
 │  runs/<id>/   status.json · questions · replies · logs            │
 └─────────┬──────────────────────────────────────┬──────────────────┘
           │ 1. HAND-OVER   (claude -p)           │ 2. WORK START  (claude --bg)
           │ "create a task from this proposal"   │ "work on task 31"
           ▼                                      ▼
 ┌─ child repo · main checkout ─┐    ┌─ child repo · registered worktree ─┐
 │ CHILD session (repo's rules) │    │ CHILD session (repo's rules)        │
 │ creates + commits task 31    │    │ builds on a branch, commits         │
 │ replies: "31"                │    │ Stop hook ─► status.json            │
 └──────────────────────────────┘    │ questions ◄──► leader ◄──► you      │
                                     └─────────────────────────────────────┘
         task system: owns accepted work           you review + merge
```

## Where I left off

_Rewritten wholesale by `/wrap` at the end of each session — state, not a log.
Never append a new dated entry; overwrite._

- **current task** — none in flight. Effort promoted to active on 2026-11-12 and
  `dogfood` `12` and `25` pulled in; no work started yet.
- **next concrete step** — **`dogfood` `12`**, its "Full (deferred)" acceptance
  block. The design is already decided there as option (a) scoped; do not
  re-derive it. Settle open question 1 first — it is now a scope question inside
  `12`, not an ownership question. Read `25` phase 1 alongside it.
- **files mid-edit** — none.
- **uncommitted / unpushed** — none as of 2026-11-12.
- **open questions** — see **Open questions**. Question 1 no longer gates the
  effort's *start*; it gates `12`'s shape. Decision 9 records what the promotion
  settled.

## Why

Hand-over gives the target repo a task. Starting work on it still means the user
opens a terminal in that repo and drives an agent by hand. The leader should be
able to start that agent, keep it isolated in its own worktree, and tell the
user when it stops or has a question.

| | Hand-over (`proposals`) | Work start (this effort) |
|---|---|---|
| Input | A ready proposal | An existing task ID |
| Output | A task or epic ID | A branch ready for review |
| Worktree | No — the target's main checkout | Yes, registered in `repos.yml` |
| Session | Short `claude -p`, rooted in the target | `claude --bg`, rooted in the worktree |
| Back-and-forth | None | Status, questions, replies |

## Dependencies

Both are **pulled into this effort** (user, 2026-11-12). This effort drives them;
it no longer waits on `dogfood` to be un-parked. Their files stay in
`docs/plans/dogfood/` and keep their `dogfood` numbers — those paths are already
referenced from the master plan, from `dogfood`'s task table and from `26`, and
renumbering them into this effort's `001`-`008` scheme would break every link
for no gain. State is a field a plan owns, not a filesystem location.

| Task | What dispatch needs from it |
|---|---|
| [`dogfood` `12`](../dogfood/12-worktree-membership.md) | A worktree lifecycle verb. No verb registers a worktree today, and `add-repo.py` refuses them. Work start creates and later removes one |
| [`dogfood` `25`](../dogfood/25-worktree-divergence-is-invisible-debt.md), phase 1 | Divergence measurement. Every work-start worktree creates drift-from-`main` debt, and `status` cannot see it today |

Neither needs [`proposals`](../proposals/PLAN.md). That is why this effort can
hold the active slot ahead of it — see the master plan's "Order, and why".

`dogfood` `26` puts parallel work on the task record (a `Worktree` field). A
work-start worktree is that field made real.

## Scope

**In:**

- Creating a registered worktree for a task, through `12`'s verb.
- Starting `claude --bg` rooted in that worktree.
- A run directory on the workspace side for status, questions, replies, and logs.
- A `Stop` hook, injected at launch, that writes the session's status.
- Leader verbs: start work, list runs, show status, reply.
- Removing the worktree after the user merges, through `12`'s verb.
- Tests, and graduating the decisions into `DESIGN.md`.

**Out:**

- **Merging or pushing.** The user reviews and merges. The leader never commits
  or merges in a child repo.
- **Changes inside child repos.** The status channel is injected at launch; no
  child repo gains a hook or a file.
- **Rebasing a diverged worktree.** That is `25`'s `make integrate`, typed by the
  operator, never run by the leader.
- **Claude Code's built-in worktree (`-w`).** It bypasses `repos.yml`.

## Tasks

In build order.

The two pulled-in tasks come first. Their canonical status lives in their own
files, not here.

| # | Task | Status |
|---|---|---|
| `dogfood` [`12`](../dogfood/12-worktree-membership.md) | the worktree lifecycle verb — see `12`'s "Full (deferred)" block | see `12` |
| `dogfood` [`25`](../dogfood/25-worktree-divergence-is-invisible-debt.md) | divergence measurement, phase 1 only | see `25` |
| 001 | the run directory and its `status.json` schema | todo |
| 002 | the launch: worktree, `claude --bg`, run directory, session ID | todo |
| 003 | the `Stop` hook that writes `status.json` | todo |
| 004 | status, questions, and replies | todo |
| 005 | end of run: branch for review, worktree removal after merge | todo |
| 006 | the leader skill gains work start | todo |
| 007 | acceptance tests | todo |
| 008 | graduate the durable decisions into `DESIGN.md` | todo |

### 001 — the run directory

One directory per run, on the workspace side, for example
`.workspace/runs/<date>-<slug>/`. It holds `status.json`, questions, replies,
and logs. It is **runtime** in the `DESIGN.md` §7.3 split: untracked, never
committed, never overwritten by `update.sh`.

`status.json` records at least: the target repo, the task ID, the worktree path
and branch, the session ID, the state (`running`, `stopped`, `waiting`,
`finished`), and the time of the last update.

Acceptance: the wrapper's `.gitignore` keeps the run directory out of the index;
`guard.sh` still passes; the schema is written down once.

### 002 — the launch

The leader, given a target repo and a task ID:

1. Creates a worktree for a new branch through `12`'s verb, so it is registered
   in `repos.yml`.
2. Creates the run directory.
3. Starts `claude --bg` with the worktree as working directory,
   `--add-dir <run directory>`, and `--settings <file>` carrying the `Stop` hook.
4. Records the session ID that `--bg` prints. `--bg` ignores `--session-id`, so
   the leader cannot choose it.
5. Delivers the first prompt. A prompt passed as a positional argument with
   `--bg` was dropped in 2.1.308 — the session started idle. The leader
   delivered it with `SendMessage` instead. See open question 3.

The child session loads the worktree's `CLAUDE.md`, settings, hooks, and
skills, which is why work start uses a session in the target and not a leader
subagent.

Acceptance: the worktree is registered; the session is listed by
`claude agents`; `status.json` names the session ID; the child received its
prompt.

### 003 — the `Stop` hook

Injected with `--settings` at launch. Each time the child session stops, the
hook writes `status.json` in the run directory. No child repo changes.

Depends on an unchecked fact: whether hooks from `--settings` merge with the
child's own hooks or replace them. If they replace them, injecting this hook
disables the child's hooks, which is not acceptable — find another channel.

Acceptance: a child session that stops updates `status.json`; the child's own
hooks still run.

### 004 — status, questions, and replies

Leader verbs, for example `make runs` and `make run-status RUN=<slug>`. A run
whose child is waiting on a question surfaces the question; the leader relays it
to the user and delivers the reply.

The reply channel is open (question 4): a file in the run directory, or
`SendMessage` to the child session.

Acceptance: the leader lists every run with its state; a waiting run shows its
question; a reply reaches the child.

### 005 — end of run

The child commits on its branch. The run is done when the branch is ready for
review. The user reviews and merges. After the merge, the leader removes the
worktree and its `repos.yml` entry through `12`'s verb.

`25`'s divergence measurement reports a work-start worktree that drifts too far
from `main` while the run is open.

Acceptance: the leader never merges or pushes; removal refuses an unmerged
branch; a removed run leaves no `repos.yml` entry behind.

### 006 — the leader skill gains work start

The `proposals` effort ships the leader skill. Work start either joins it or
becomes a sibling skill. Decide when this effort opens, by trigger: if "start
work on task X" and "hand over proposal Y" load in the same moments, one skill.

### 007 — acceptance tests

Extend `tests/run-tests.sh` against the `git-workspace-test` fixture. Replace the
`claude --bg` call with a stub. Assert on the command line the leader builds, the
registered worktree, the run directory, and a `status.json` written by the hook
script when run directly.

### 008 — graduate to `DESIGN.md`

Per `docs/plans/README.md`. §8.6 owns membership verbs, so the worktree
lifecycle lands there with `12`.

## Decisions

Settled by the user on 2026-10-22 unless marked. One line each.

1. **Work start is separate from hand-over.** It takes an existing task ID, not a
   proposal, and often never happens.
2. **The worktree is registered in `repos.yml`.** Rules out `claude -w`, which
   creates a worktree the workspace cannot see.
3. **The leader never commits or merges in a child repo.** The child commits on
   its branch; the user merges.
4. **The status channel is injected at launch, not installed in the child.** A
   `Stop` hook through `--settings` and a run directory through `--add-dir`.
   Rules out a hook file in every child repo. (Proposal mechanics, adopted with
   the effort; `003` must confirm it is possible.)
5. **Child sessions do not run with bypass permissions.** The profile they do
   get is open question 2.
6. **The session ID is recorded from `--bg`'s output, not chosen.** Found at
   launch on 2.1.308: `--bg` ignores `--session-id` ("--bg manages the session
   id"). Replaces the proposal's plan to start each session with
   `--session-id <uuid>`.
7. **Matching permission modes** (user, 2026-10-23). The leader and every child
   run in the same mode (auto). Messages between sessions in different modes are
   held for human approval. See the first-dispatch findings below.
8. **The leader creates and registers every worktree** (user, 2026-10-23). The
   child never picks one. Rules out a child making its own worktree that
   `repos.yml` cannot see, which the first dispatch did.
9. **This effort owns `dogfood` `12` and `25`** (user, 2026-11-12). Promoting
   `dispatch` ahead of `proposals` and pulling both tasks in replaces the earlier
   plan of waiting for `dogfood` to be un-parked. This settles the *ownership*
   half of open question 1: the worktree-registration verb is part of `12`, built
   here. It does not settle the *scope* half — see question 1 as narrowed.

## Open questions

Move each to **Decisions** once resolved, with the reasoning, rather than
deleting it. Numbers in brackets are the leader proposal's original numbers.

1. **[4] Does `12`'s verb cover a short-lived worktree on a normal clone?**
   Narrowed by decision 9, which settled that the verb is part of `12` and is
   built here. What remains is scope, not ownership: `12` designs long-lived
   workstreams on a **bare** clone with one worktree per branch, while a
   work-start worktree is **short-lived on a normal clone**. Either `12`'s verb
   takes both layouts, or it takes the bare-container case and work start gets a
   second, simpler verb. Gates `12`'s shape, and therefore `002` and `005`.
   Settle it before writing code.
2. **[5] What is the default permission profile for a child session?** Not
   bypass. It has to edit, run tests, and commit with no one at the prompt.
   Shared with `proposals`. **Partly settled by decision 7:** the mode is auto,
   the same as the leader. Still open: whether auto alone is enough, or the
   launch also scopes `--allowedTools`.
3. **How does the leader deliver the first prompt?** The positional prompt was
   dropped with `--bg`, and `SendMessage` worked. `SendMessage` is a tool of a
   Claude session, so a `make` verb alone cannot start work. Either work start is
   leader-only (skill, not verb), or another CLI path exists.
4. **Which channel carries replies?** A file in the run directory, or
   `SendMessage` to the child. `SendMessage` reached this effort's own planning
   session, so it works between local sessions.
5. **When is a run finished?** The `Stop` hook fires every time the child stops,
   including when it stops to ask. `status.json` needs a way to tell "waiting"
   from "done".
6. **How long does the run directory live?** Delete it with the worktree, or
   keep logs for debugging until the user clears them.

### CLI facts

Read from `claude --help` on 2026-10-22 (installed version 2.1.309 on
2026-10-23). Check each one against the installed version before a task
depends on it.

| Flag / command | Use |
|---|---|
| `--bg` | Detached interactive session; prints its id. Fits work start |
| `claude agents`, `attach`, `logs`, `stop` | List, join, read, and stop background sessions |
| `--resume <id>` | Re-enter a session |
| `--settings <file-or-json>` | Inject the `Stop` hook |
| `--add-dir <dir>` | Give the child access to the run directory |
| `--debug-file <path>` | Debug hook and MCP failures |
| `-w` | Built-in worktree. Do not use: it bypasses `repos.yml` |

Transcripts are written to
`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, so the recorded session ID
names the transcript.

**Found at launch** (2.1.308, when the leader started this effort's planning
session):

- `--bg` ignores `--session-id` and says "--bg manages the session id".
- A prompt passed as a positional argument with `--bg` was dropped. The session
  started idle and needed the prompt delivered by `SendMessage`.

**Found in the first real dispatch** (2.1.308, this effort's own planning
session):

- A cross-session message from a bypass-mode leader to an acceptEdits child was
  held until the user approved it in the child's view. Idle notices from that
  child also did not reach the leader within 12 hours. Decision 7 follows.
- acceptEdits prompted for every shell command, including read-only `ls` and
  `cat`. The child sat at its first prompt for about 12 hours. It ran only after
  the user picked "Yes, and switch to auto mode".
- The child created its own worktree at `.claude/worktrees/proposals-and-dispatch`
  (branch `plan/proposals-and-dispatch`). That worktree is not in `repos.yml`,
  and it shows as untracked `.claude/worktrees/` in the main checkout.
  Decision 8 follows.

**Not yet checked:**

- What a `--bg` session does after it finishes: idle, or exit.
- Whether hooks from `--settings` merge with the child's own hooks or replace
  them. Decides `003`.
- Whether the positional-prompt drop is a defect fixed in a later version, or
  intended. Decides open question 3.

## Done when

From the workspace root, the leader starts work on a task in a child repo. A
registered worktree exists, a background session runs in it, and `status.json`
tracks it. The leader shows the user the session's state and questions and
delivers replies. The branch reaches review without the leader committing,
merging, or pushing, and after the user merges, the worktree and its
`repos.yml` entry go together. The suite covers launch, status, and removal.

---

_On finishing: review every task file against `DESIGN.md`, graduate the durable
conclusions, slim this file to pointers, and leave it in `docs/plans/dispatch/`._
