# 27 — ship the step-map convention into every tracked child repo

Status: **filed 2026-08-13**, from `second-brain-devkit`, where the pattern was
built and used across three design docs.

A **step map** is the 100-ft view of a multi-step task: one row per step, with a
status marker, a short title, and a single sentence of what that step entails.
High enough to read a whole effort in one screen, low enough to say what each
step actually does.

| | Step | What it entails |
| --- | --- | --- |
| ✅ | 1. The mechanism | Keys, names and the envelope, as byte operations that know nothing about git. |
| ☐ | 2. Ship it | Final vendor → template → CI pass proving the off path is bit-identical. |

`second-brain-devkit` now carries it as a local `CLAUDE.md` convention, applied to
`docs/encrypted-notes.md`, `docs/pdf-ingestion.md` and `docs/tag-hygiene.md`. It
should be a property of **every** repo this workspace tracks, not one repo's habit.

## The load-bearing half is the reporting rule, not the table

The table is the visible part; it is not what makes this worth injecting.

- **Authoring** — a design doc with a staged plan opens that plan with a step map,
  detail underneath. A doc with no stages gets none; a map over a doc with no steps
  is noise.
- **Reporting — show it, never offer it.** When a step lands, print the current step
  map as part of reporting the work. Do **not** ask whether to show it, and do not
  substitute prose about progress. The point is that the reader never has to ask
  "so where are we?" — and asking *is* the failure, because it hands the burden of
  remembering the convention back to the person the convention exists to serve.

That second rule only fires if it is **always loaded**, which is exactly what the
injected `CLAUDE.md` block is for. A rule you must remember to go and fetch gets
forgotten silently — the note still gets written, just without the map.

## Shape: a peer block, not more paragraphs in the commit kernel

`inject-kernel.py` already does all the work — marker-delimited splice, everything
outside preserved, never commits into the child, nothing workspace-specific in the
text. Reuse that **mechanism**. Do not reuse its **concern**:

- the commit kernel is *telemetry* — the schema the status run parses;
- the step map is *task-doc authoring and reporting*.

Two unrelated concerns sharing one marker pair would mean a repo cannot take one
without the other, and the block's name would stop describing its contents. Give it
its own template and its own marker pair — `git-workspace-stepmap:begin/end` — spliced
by the same injector, which should grow to handle **a list of kernels** rather than
one hard-coded `KERNEL` path.

**One source, not four.** Task `17` exists because the commit schema was copied into
four places and now needs four edits to fix one blank line. A second kernel must not
repeat that: one template file, every consumer reading it.

## Deliberately NOT gated on a third adopter

The default for extracting a shared convention is rule-of-three — copy it by hand
until a third consumer proves the pattern, since a convention generalised from one
instance usually encodes that instance. **Overridden here, by the owner, on purpose:**
this is wanted in the child repos now.

The risk that buys is worth naming so it can be designed around rather than
discovered: the prototype assumes `docs/`-shaped design docs and an eight-step build
order. **The injected text must describe the shape of the map and when to show it —
never where the doc lives or how many steps it has.** A repo with plans in
`docs/plans/`, in `PLAN.md`, or in a task-system should be able to obey it unchanged.

## Acceptance

- A new template beside `commit-kernel.md`, with its own marker pair, spliced by
  `inject-kernel.py` — `--all` and `--check` covering it like the commit kernel.
- The text names no directory, no file layout, and no step count.
- `--check` reports drift on a repo whose block is stale, and exits non-zero.
- Injected into one real child repo and confirmed: block spliced, everything outside
  the markers byte-identical, nothing committed by the workspace.
- `second-brain-devkit`'s hand-written version is replaced by the injected block, so
  there is one source rather than two that can disagree.
