# 15 — stand up `personal-workspace`

Status: **todo** — filed 2026-08-04 out of the `04` roster decision.

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

## The `dotfiles` hazard

**The live config is a symlink into the repo.** Moving the checkout breaks every
symlink pointing at the old path — the same class of failure as `14`'s
"deleting the ground the session stands on" and `12`'s worktree pointers, and
the third time this effort has hit it. Either re-point the symlinks after the
move, or register it in place with `add-repo --no-clone --path` and leave the
checkout where it is.

Decide which **before** moving anything. This is the first repo whose migration
can break something that is not a git operation.

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

- `personal-workspace` exists, private, pushed, with `foa`, `ymca-basketball`,
  and `dotfiles` registered and `make status` green.
- `dotfiles` still works — whatever depends on its symlinks resolves after the
  migration, and how that was achieved is written down.
- It has its own routine on a slot that does not overlap `dev-workspace`'s, and
  a run has landed a rollup that `make pull` brought down.
- Anything that turned out **not** to be "only `config.yml` differs" is filed
  against the generator, not patched in the generated workspace.
