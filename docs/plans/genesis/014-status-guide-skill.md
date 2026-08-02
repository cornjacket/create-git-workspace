# 014 — on-demand status guide/skill

Status: done

Give the workspace a durable, on-demand home for the status subsystem's
operational directions — so they survive beyond a scrolled-past `add-repo` print.
Mirrors project-status's kernel-+-guide split and create-project-system's
on-demand skill pattern.

## Acceptance
- An on-demand guide/skill in the workspace (e.g. `.workspace/status-guide.md` or a
  `.claude/skills/workspace-status/` skill) documenting:
  - creating the Claude `/schedule` routine and pointing it at `daily.sh`;
  - adding each tracked repo to the routine's `sources` (sandbox pre-clone list);
  - the daily loop (push up / ff-only pull down) and the verbs (add/delete/mute).
- The always-on `CLAUDE.md` managed block carries only a **one-line pointer** to it
  (keep the kernel small).
- The generated `README.md` names the two manual routine-setup steps for humans.

## Notes
- Canonical home for the "seams" in PLAN.md; `add-repo`'s print + README are the
  just-in-time nudges.

## Outcome

Both artifacts, not either/or — the same three-layer split create-project-system
uses:

- `.workspace/status-guide.md` (machinery) — the procedure, once. Layout, command
  surface, repo verbs, the push/pull daily loop, the two routine seams (§5.1
  `/schedule`, §5.2 `sources`), who writes what, the child commit kernel, the
  triage area, and the `summary.md` vs `project/status/` distinction PLAN.md
  asked for.
- `.claude/skills/workspace-status/SKILL.md` (machinery) — thin: frontmatter
  description, four rules, a pointer at the guide. It does not restate the guide,
  so there is one copy to keep correct. Emitted even under `--no-tasks`; it is
  ours, not the vendored generator's.
- `CLAUDE.md` managed block — cut from ~150 lines to 47: only the too-late rules
  plus the pointer. `tests/run-tests.sh` §8k caps it at 60 lines and fails if the
  routine mechanics creep back in.

Also: `README.md` (content, seeded once) shed the mechanics that would drift and
now points at the guide; `add-repo.py`'s reminder cites §5.2; `make guide` prints
it; `make help` names it.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `014` — on-demand status guide/skill (durable home for routine-setup directions). *(three layers: `.workspace/status-guide.md` holds the procedure, `.claude/skills/workspace-status/` surfaces it on demand, and the `CLAUDE.md` block shrank from ~150 lines to a 47-line kernel — a test now caps it at 60 and fails if it re-absorbs the mechanics.)*
