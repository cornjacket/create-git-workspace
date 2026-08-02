# 016 — on-demand status guide/skill

Status: todo

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
