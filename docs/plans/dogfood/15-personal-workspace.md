# 15 — stand up `personal-workspace`

Status: **built 2026-08-04** — workspace created, `foa` and `ymca-basketball`
registered. **Outstanding: the routine.** `dotfiles` was removed from scope; see
"The `dotfiles` hazard" below for what that investigation actually found.

The second workspace. It was explicitly **out of scope** for this effort until
the roster decision made it necessary: `foa`, `ymca-basketball`, and `dotfiles`
are not dev work, so they have no home in `dev-workspace` — and `DESIGN.md` §10
says to build the second workspace when one *actually happens* rather than
speculatively. It has now happened.

## Why this is not just "run the generator again"

Everything proven so far was proven on a workspace with **one** of everything.
A second workspace is the first real test of three claims this design has been
making on credit:

1. **"Identical machinery; only `config.yml` differs"** (§8.9). Untested. If
   anything in the generated output is implicitly single-workspace — a hardcoded
   name, a path assumption, a routine that collides — this is where it shows.
2. **Two routines, two schedules.** `dev-workspace` runs at 12:43 UTC, chosen to
   sit 30 minutes behind `project-status`'s 12:13 while both existed. `08`
   retires that one and frees 12:13; a second workspace needs its own slot and
   its own `trig_` id, and the two runs must not overlap.
3. **The `04` migration recipe on repos nobody is developing.** `dotfiles` is
   symlinked into live locations on this machine — the one repo so far where
   moving the checkout could break something outside git.

## The `dotfiles` hazard — investigated, and it changed the answer

**Outcome: `dotfiles` joins no workspace at all.** Not this one, not
`dev-workspace`. Graduated to `DESIGN.md` §8.9.

The hazard as filed: the live config is a symlink into the repo, so moving the
checkout breaks it — the same class of failure as `14`'s "deleting the ground
the session stands on" and `12`'s worktree pointers, and the third time this
effort hit it. What the investigation added:

- **Exactly one link exists**, and it is
  `~/.claude/CLAUDE.md → <repo>/claude/CLAUDE.md` — the *global* Claude
  instructions loaded into every session on the machine.
- **It fails silently.** A dangling symlink reads as a missing file, and a
  missing global `CLAUDE.md` is not an error. Every session would run without
  those standing preferences and nothing would report it. Same shape as `16`:
  the thing that breaks does not announce itself.
- **`readlink` is not a sufficient check** — it prints a path whether or not
  anything is there. `test -e` follows the link and is what actually proves the
  target exists.

So the repair is one command and the risk is small — but the *reason to migrate
it at all* turned out to be absent, which is the real finding. `dotfiles` is
**config, not a project**: consumed by every session in every repo, a member of
none. §8.9's `second-brain` argument, applied to config instead of content.

The hazard and the exclusion are now recorded **in `dotfiles`' own README**, so
the next person to consider migrating it is warned by the repo rather than by
someone happening to check. The stated cost of staying out: nothing watches it
— no status sweep, no rollup — so `git status` in that directory is the only
check there is.

## Open questions

- **Does `captains-log` move here?** §8.9's end state says `personal-workspace`
  tracks it; §2's footnote says it stays in `dev-workspace` only while its
  content is judged workspace-specific. Both cannot be true once this workspace
  exists, and the tiebreaker is a judgement about the log's *content*, which is
  the owner's to make. **Assumed for now: it stays put** — it is registered,
  green, and moving it is reversible. Confirm before `08` calls the end state
  reached.
- **Where does it live on disk?** `dev-workspace` sits at
  `cornjacket/dev-workspace/`. A sibling `cornjacket/personal-workspace/` is the
  obvious answer, but `dotfiles` and `foa` are not `cornjacket`-scoped work in
  the way the dev repos are.
- **Private or public?** `dev-workspace` is private because it carries plans and
  a rollup (`03`). Same argument applies here, more strongly.
- **Does it need a task-system?** `dev-workspace` mounts one at
  `.workspace/project/` and has zero tasks in it. Personal repos may not need
  the triage area at all; `--no-tasks` exists.

## Acceptance

- ✅ `personal-workspace` exists, private, pushed, guard installed, task-system
  included (deliberately the same shape as `dev-workspace`, so the "identical
  machinery" claim is actually exercised rather than dodged).
- ✅ `foa` (`4f79c15`) and `ymca-basketball` (`af535d6`) registered by clone at
  the HEADs their old checkouts had, kernels committed inside each, old
  checkouts removed.
- ✅ `dotfiles` resolved — **excluded**, and its symlink verified intact
  (`test -e` passes, still pointing at the untouched checkout).
- ⏳ `make status` green — red on `routine not registered` for both repos, which
  is correct: there is no routine yet.
- ⏳ Its own routine on a slot that does not overlap `dev-workspace`'s 12:43 UTC.
  `08` frees 12:13 when `project-status` retires. Note `20`: `RemoteTrigger` can
  create it from a session, so this is no longer a hand-only step.
- ⏳ A run has landed a rollup that `make pull` brought down.
- **Setup itself reported nothing anomalous** — `setup.sh --create-remote
  --with-hook` produced a second workspace with no generator change required,
  which is the first evidence for §8.9's "identical machinery; only
  `config.yml` differs". Not yet proof: the claim is really about the *running*
  system, and no run has happened here.
