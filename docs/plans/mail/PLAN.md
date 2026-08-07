# PLAN — mail

**Give a workspace a standard way for one repo to file a task into another
repo's inbox, addressed by location and declared by the receiver.**

Started 2026-08-06. Task files: drafted inline below until they stop moving.
Durable design lives in `DESIGN.md`; this file is only this effort.

<!-- PARKED: this effort is queued, not active. The root PLAN.md slot is held by
     `dogfood` (tasks 16-22 open). Per docs/plans/README.md there is one active
     plan at a time — promote this file to the repo root when dogfood archives.
     Nothing here is blocked by that; it is a sequencing rule, not a dependency. -->

## Where I left off

_Rewritten wholesale by `/wrap` at the end of each session — state, not a log.
Never append a new dated entry; overwrite._

- **current task** — none; effort not started. `001` is the entry point.
- **next concrete step** — read `create-project-system` task `27`
  (`tasks/27-list-tasks-json-output.md`) **before** writing the `001` contract.
  It states the same missing-declaration problem from the consumer side and
  decides the payload shape this effort has to interoperate with; designing the
  two independently is how they end up disagreeing. Then write `001` — everything
  else reads or writes that file, so it is the only thing that cannot be
  parallelised.
- **files mid-edit** — none.
- **uncommitted / unpushed** — none as of 2026-08-07.
- **open questions** — see **Open questions** below; none block `001`. The one
  that did — single-purpose file versus shared manifest — was **settled on
  2026-08-07** in favour of a shared `discovery.json`, recorded under
  **Decisions**.

## Why

Cross-repo findings die at the session boundary. Working in repo A you notice
something repo B must change; the context is fresh now and gone in an hour, and
the only durable channel today is remembering to go open B.

`DESIGN.md` §8.7 makes this a *documented* gap rather than an oversight: the
workspace task-system takes work belonging to **no** child repo, and explicitly
sends anything that belongs to an existing child *to that child* — while
providing no mechanism to send it. This effort is that mechanism.

The receiving surface already exists. `create-project-system` installs
`<tasks>/<epic>/{inbox,draft,backlog,...}/` in every repo it touches, and
`USING.md` defines `inbox/` as *"raw ideas, not yet evaluated"* — which is
exactly what foreign mail is. Nothing new is needed to *hold* a message; what is
missing is addressing, delivery, and notification.

## Scope

**In:**

- The `inbox` key in a per-repo `discovery.json` — the receiver **declares** its
  intake. Read live, never cached by the workspace. One shared manifest, one key
  per capability; this effort owns `inbox` and leaves other keys alone.
- Workspace-side send: resolve address from `repos.yml`, read the target's
  declaration, write the message.
- Workspace-side sweep: what mail is outstanding across the whole roster.
- Notification: pending mail must surface in the existing daily status read
  without being asked for.
- A `send-mail` skill so the procedure lives in **one** place, on demand.

**Out:**

- **Reply paths.** Solo workflow; you walk over. Leave room in the frontmatter,
  build nothing.
- **A `to:` field.** Delivery is positional — the address *is* the path. A `to:`
  makes the workspace a router and assumes every repo is in exactly one
  workspace forever, which breaks when membership changes.
- **`INBOX.md` in every repo.** Superseded by `discovery.json` + the skill: receiving
  is per-repo, sending is uniform, and uniform things get one copy.
- **`create-mail.sh` / `list-new-mail.sh` inside receiving repos.** Both are
  sender-side tools; installing them in the receiver puts them on the wrong side
  of the wire. `list-tasks.sh --epic main --folder inbox` already exists locally.
- **The workspace installing task-systems into children.** `add-repo.py` touches
  nothing inside a child repo today and should keep that property. A repo with no
  inbox declares none and is told so.
- **Sending from a repo that is in no workspace.** The address book is
  `repos.yml`; with no workspace there are no addresses. The repo is the
  endpoint, the workspace is the address resolver.

## Tasks

In build order. Inline detail below; extract to `NNN-slug.md` once a task stops
moving.

| # | Task | Status |
|---|---|---|
| 001 | the `inbox` key in `discovery.json` + required message fields | todo |
| 002 | `send-mail.sh` — resolve, read declaration, write the message | todo |
| 003 | `make mail` — sweep every repo's inbox, list what is outstanding | todo |
| 004 | `status.py`: inbox-only dirt reads as `mail pending`, not `uncommitted` | todo |
| 005 | generalize the skill install loop to own more than one skill dir | todo |
| 006 | the `send-mail` skill | todo |
| 007 | acceptance tests | todo |
| 008 | upstream: `create-project-system` writes its `discovery.json` keys (non-blocking) | todo |
| 009 | graduate the durable decisions into `DESIGN.md` | todo |

### 001 — the `inbox` key in `discovery.json`

The receiver declares its intake at its repo root. Everything else in this effort
reads or writes this file, so it is settled first and changed reluctantly.

**This is not a mail-only file.** `discovery.json` is one shared manifest listing
everything a repo offers the outside, with **one key per capability**:

```json
{
  "inbox":           { "version": 1, "kind": "create-project-system",
                       "path": "project/tasks/main/inbox",
                       "format": "user-task",
                       "create": "project/tasks/scripts/new-user-task.sh --epic main --folder inbox" },
  "tasks":           { "version": 1, "mount": "project/tasks", "epic": "main" },
  "context-hygiene": { "version": 1, "ci": true }
}
```

This effort owns **`inbox`** and reads the rest. `create-project-system` task
`28` writes `inbox` and `tasks`; `create-context-hygiene` task `13` writes
`context-hygiene`. A file per capability would have a consumer probing for
`inbox.json`, then `context-hygiene.json`, then the next — the same probing
task `28` exists to end, one level up.

- `path` is **required** and is what makes `003` possible — a command string
  alone cannot be listed.
- `create` is an escape hatch for repos whose intake is not a directory. See
  **Open questions** on executing it.
- `format` implies the required message fields. Mandate them here: `from`
  (originating repo), the evidence (`file:line` and what was observed), and what
  the sender already ruled out. Without this you get one-line drive-bys and the
  reader in March has the instruction but not the reasoning — which is the loss
  the whole effort exists to prevent.
- **Version per key, not per file.** Different generators write their keys at
  different times on different release schedules, so one file-level version
  cannot stay true.

Acceptance: the schema is written down, `version` is present on the `inbox` key
from day one, a repo with no `discovery.json` **or** no `inbox` key is a defined
state ("declares no inbox") rather than an error, and reading is tolerant of keys
this effort does not own.

### 002 — `send-mail.sh`

`.workspace/scripts/send-mail.sh --to <repo> --name <slug>`

Resolves `<repo>` through `repos.yml` (which already carries the path, and for
worktree members resolves to the registered checkout — `create-ai-builder`
addresses to `create-ai-builder/main`, not the bare container). Reads
`<path>/discovery.json` **live** and takes its `inbox` key. Writes the message.
Stamps `from:`.

Does **not** commit. See `004` for why that is the right call and how it is made
visible instead.

Acceptance: a message lands in the target's inbox directory; a target with no
declaration fails with a message that says what to do about it; nothing is
written into `repos.yml`.

### 003 — `make mail`

Sweep every repo in `repos.yml`, read each declaration, list outstanding inbox
items with their `from:`. This is the verb that cannot exist anywhere but the
workspace, because only the workspace knows the roster.

**Read the inbox through `list-tasks.sh --json`, not by scraping.** That flag is
`create-project-system` task `27`, already filed and unbuilt. Until it lands, the
only machine interface to a task-system is the human output — and `replan.sh` is
the cautionary tale: it scrapes a four-space indent (`replan.sh:74-78`), which
has made that indent load-bearing public contract. Do not add a second consumer
to that contract. If `27` has not landed when this task is reached, read the
inbox *directory* (which `001`'s `path` gives us) rather than the lister, and
switch to `--json` when it exists.

Acceptance: one row per repo with pending mail; silent when the floor is clean;
no scrape of human-formatted output anywhere in the implementation.

### 004 — `status.py`: pending mail is not uncommitted work

Delivery leaves the target repo dirty, and the existing sweep reports that as
uncommitted work — indistinguishable from you having left something half-done.
Committing instead is worse: it means a session rooted in A committing into B
under B's hooks and commit schema, which is the actual violation of the
work-inside-the-owning-repo rule. The file write is not.

So: write without committing, and teach `status.py` that dirt confined to a
declared inbox path is `mail pending`, not `uncommitted`.

This is the task that decides whether the design works. `make status` already
sweeps every repo daily, so notification costs a display rule instead of a new
mechanism. `DESIGN.md:682` records that inter-repo tasks piled up in
`captains-log` *because* nothing surfaced them — an inbox nobody drains rebuilds
that pile under a new name.

Acceptance: a repo with only inbox additions reports `mail pending`, not
`uncommitted`; a repo with both reports both.

### 005 — generalize the skill install loop

`lib/generator.sh:160-178` is hardcoded to `workspace-status`, and its comment
explains why it is not a blind glob: `.claude/skills/` also holds `task-system/`,
owned by the vendored `create-project-system`, which this generator must not
prune.

So this is **not** "loop over `template/claude/skills/*`". It needs an explicit
list of skill directories this generator owns, iterated for both the render pass
and the stale-file prune, leaving unlisted directories untouched.

Acceptance: two skills install and re-install zero-diff; `task-system/` survives
an `update.sh`; a file deleted from a template skill is pruned from the install.

### 006 — the `send-mail` skill

Source: `template/claude/skills/send-mail/SKILL.md` (tracked here).
Installed: `<workspace>/.claude/skills/send-mail/SKILL.md` (tracked there,
machinery — regenerated, never hand-edited).

A separate skill rather than a section of `workspace-status`: different trigger,
different task, and it should load only when someone is actually sending.

Follow the `workspace-status` precedent exactly — a trigger-shaped `description`,
and a body that **points at the contract rather than restating it**, so there is
one copy to keep correct.

Acceptance: the skill fires on "send a message to repo X"; it restates neither
`001`'s schema nor `002`'s usage.

### 007 — acceptance tests

Extend `tests/run-tests.sh`: a generated workspace with two child repos, one
declaring an inbox and one not; send; assert the message landed with `from:` and
the required fields; assert `make mail` lists it; assert `status.py` calls it
`mail pending`; assert the undeclared repo fails informatively.

### 008 — upstream: `create-project-system` writes its `discovery.json` keys

The generator just installed an inbox at a path it chose, so it can declare it in
the same breath. This is the **only** change outside this repo, and it is one
file of output — not the two scripts originally sketched, which were sender-side
tools sitting on the receiver.

**Deliberately non-blocking.** `discovery.json` can be hand-written for the handful
of repos that matter now, so this effort does not wait on
`create-project-system`'s active generator-extraction plan. Do it when that
effort next opens, then re-vendor.

Note `tools/revendor.sh` does `rm -rf "$DEST"` — anything added to
`vendor/create-project-system/` directly is destroyed on the next re-vendor.
Upstream or not at all.

**File it beside task `27`, and read `27` first.** That task already states this
problem from the other side — its first listed coupling is *"probe for the mount
— `find_tasks_dir()` tries `project/tasks` then `tasks`, because nothing in an
install declares where it is."* The `tasks` key is the declaration that removes that
probe. The two want to be designed together: `27` makes a task-system's
*contents* machine-readable, this makes its *location* machine-readable, and
neither alone is enough for `003`.

Note also **how task `27` was filed** — "Requested by `dev-workspace` on
2026-08-04 … Filed here because the workspace states the problem and this repo
owns the interface." That is this effort's own workflow, executed by hand,
before it existed. Same *demonstrated, not speculative* evidence `DESIGN.md` §8.7
used to justify the triage area, and worth citing in `009`.

### 009 — graduate to `DESIGN.md`

Per `docs/plans/README.md`, a decision left only in a plan is one the next effort
re-litigates. Candidates are in **Decisions** below; the transferable ones go to
the second-brain instead, as lessons, linking here as evidence rather than
copying.

## Decisions

Made while designing this effort, newest last. One line each: what was chosen,
what it rules out, why.

- **Mail is addressed to repos, not agents.** An agent is a process and ends;
  anything addressed to it dies with it. A repo is a place and persists. Agents
  are the couriers, not the correspondents. Rules out an agent-to-agent message
  bus, which would rebuild coordination the harness already provides in-session.
- **Delivery is positional; `to:` is not needed, `from:` is.** Location is the
  address, so a routing field is redundant — but provenance cannot be derived
  from location, so it must be carried.
- **The receiver declares; the workspace does not detect.** Rules out scanning
  for known layouts, which would encode `create-project-system` internals in a
  repo that `vendor/README.md` deliberately walls off from them — and which would
  need a re-scan on `update.sh` to avoid going stale. A declaration cannot go
  stale; it *is* the truth.
- **One shared `discovery.json`, one key per capability — not a file per
  capability.** Settled 2026-08-07, when `create-context-hygiene` task `13` needed
  to declare something about the same repos before mail was built. `inbox.json` +
  `context-hygiene.json` would leave a consumer probing for one file, then the
  next — exactly the probing `28` exists to end, one level up. Two rules follow:
  a generator **owns its keys and never rewrites another's**, and the version is
  **per key**, since generators write at different times on different schedules.
- **The declaration is read live, never cached into `repos.yml`.** A cache is a
  second copy that goes stale the moment the repo edits its own file, and it buys
  nothing: you can only send to a checked-out repo, and then the file is one read
  away. `repos.yml` owns the address; the repo owns the capability.
- **Sending instructions live once, in a workspace skill.** The procedure is
  identical for every repo, so N copies is N things to keep correct. Rules out
  `INBOX.md` per repo. Not `CLAUDE.md` either — always-on tax for something used
  only when sending, which is the on-demand bucket in
  `[[agent-instruction-placement]]`.
- **Deliver by writing, not committing.** Committing into a repo from a session
  rooted elsewhere is the real boundary violation; a file write is not. The cost
  is a dirty tree, paid for by `004`.
- **The mail mechanism belongs to `create-git-workspace`, not
  `create-project-system`.** Only the workspace has the address book. The
  receiving surface (`inbox/`) already exists upstream and needs no new scripts.

## Open questions

Move each to **Decisions** once resolved, with the reasoning, rather than
deleting it.

- **Does the workspace ever execute `create`?** If it shells out to a string from
  a checked-in file, adding a repo means running its code. For repos you own this
  is nothing; it matters the day you add one you do not. Options: never execute
  (workspace always writes the file itself, `create` is documentation for a human
  or agent), execute only for `kind` values on an allowlist, or execute freely
  and accept it. Not needed for `001`-`004`, all of which use `path`.
- **Which key does a repo with no task-system use?** `inbox` is deliberately
  separate from `tasks` so a repo without a generated task-system can hand-write
  the one key and still receive mail. Confirm `002` treats a hand-written `inbox`
  identically to a generated one — no `kind` allowlist that quietly excludes it.
- **Which epic receives, when a repo has several?** `main` is the catch-all and
  the obvious default, but the epic is a variable in the generator
  (`generate.sh:278` creates the status folders per epic), so the declaration
  should name it rather than the workspace assuming.

## Done when

From a session rooted in one repo, `send-mail.sh --to <other>` files a task with
`from:` and evidence into that repo's declared inbox; `make mail` lists it from
anywhere in the workspace; `make status` reports it as `mail pending` rather than
uncommitted work; a repo declaring no inbox fails with an actionable message; and
the suite covers all four.

---

_On finishing: review every task file against `DESIGN.md`, graduate the durable
conclusions, slim this file to pointers, and leave it in `docs/plans/mail/`._
