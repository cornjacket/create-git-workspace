# Skill layer — `--with-skill`

Emits an on-demand **skill** so the task-system procedure isn't carried in the
target's always-on context.

## Why

`CLAUDE.md` is loaded every session, every turn. Putting the full task procedure
there taxes every conversation, including the ones that never touch a task. A
skill uses progressive disclosure: only its one-line `description` sits in
context until the model actually invokes it.

For scale: ai-builder's `CLAUDE.md` ran 550 lines, ~300 of which were
task-system + worktree procedure — always loaded. The layered split below
reduces the always-on cost to ~12 lines.

## The three layers, and what belongs in each

| Artifact | Loaded | Contains |
|---|---|---|
| `snippets/claude-md.snippet.md` | **always** | Only rules that would be *too late* if loaded on demand: "work needs a task", "only scripts mutate task state", "never close without confirmation" + a pointer. ~12 lines. |
| `skill/task-system/SKILL.md` | **on demand** | Orientation + the one critical rule + a pointer to `USING.md`. Deliberately thin. |
| `docs/USING.md` | **on demand / by reference** | The substance: task types, `NNNN` ordering contract, status model, full command reference, lifecycle walkthrough, optional-layer commands. |

**Single source of truth:** `USING.md` holds the procedure. The skill and the
kernel *point at it* rather than restating it, so there is exactly one copy to
keep correct. Resist the urge to inline command examples into the skill — that
duplication is precisely what rots.

## Emit rules for `generate.sh`

1. **Always** emit `docs/USING.md` — it is agent-agnostic and is the reference
   the other two point to. The skill is an accelerator, never the only copy.
2. **Always** emit/print the kernel snippet (append with `--inject-claude-md`).
3. **With `--with-skill`**: emit `skill/task-system/SKILL.md` →
   `<target>/.claude/skills/task-system/SKILL.md`.
4. Render `{{TASKS_REL}}` in all three.

## Multi-agent parity

Skills are Claude-specific. Other agents (e.g. Gemini CLI reading `GEMINI.md`)
will not load `SKILL.md` — but they don't need to, because the substance lives in
`USING.md`, which is plain Markdown.

The kernel snippet is deliberately **agent-neutral**: it names both the skill
*and* `USING.md`. So the same snippet works verbatim in `GEMINI.md` (or any other
agent instruction file) — no separate variant to maintain and keep in sync. Where
a repo symlinks `GEMINI.md → CLAUDE.md`, parity is automatic.

Targets not driven by Claude simply skip `--with-skill` and use `USING.md`
directly.
