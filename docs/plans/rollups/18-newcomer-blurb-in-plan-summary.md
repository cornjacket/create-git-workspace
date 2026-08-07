# 18 — `daily-plan-summary.md` never says what a repo *is*

Status: **filed 2026-08-04**. Not started.

The rollup a newcomer reads every morning names five repos and describes none of
them. `create-ai-builder`, `captains-log`, `create-git-workspace` — the reader
gets a link, a priority band, and a wall of plan detail written by someone who
already knows what the repo does.

## The gap

`.workspace/scripts/aggregate-plans.py` renders each repo section as:

```
## [create-ai-builder](https://github.com/cornjacket/create-ai-builder) — plan for 2026-08-04
```

…and then the plan body. Nothing between the two answers "what is this repo".

`project-status`'s version of the same file does answer it, in every section:

```
**What this repo is (for a newcomer):** A Cookiecutter-style *generator* that
installs a Markdown-based project-management workspace — a task tracker
(`tasks/`) plus periodic status reports (`status/`) — into any target repo at a
caller-chosen mount, non-destructively and re-runnably.
```

That line is the thing to reproduce. **Its mechanism is not.**

## Do not copy `project-status`'s mechanism

In `project-status` the blurb is *authored into each repo's `daily-plan.md`* —
`prompts/replan.md` field 1 mandates it, the aggregator embeds the plan verbatim,
and `tools/gen-umbrella-claude.py` then regex-scrapes it back out
(`^\*\*What this repo is \(for a newcomer\):\*\*`) to build the umbrella
`CLAUDE.md` roster. A durable fact round-trips through a file that is rewritten
daily.

That was reasonable there because there was nowhere else to keep it. **Here there
is.** `.workspace/repos.yml` already carries `description` — one line of "what is
this repo", seeded by `add-repo.py` from the GitHub description, falling back to
a README/`CLAUDE.md` prose scrape (`_status_lib.describe_remote` /
`describe_checkout`), normalized by `load_repos()`, and already rendered into
`README.md`'s roster by `render-readme.py`. §10 decision **14** locked that
field's semantics: stored, not re-derived.

So this task is a **second projection of an existing field**, exactly like the
`routine_registered` banner in §10 decision 15 — the same fact, rendered again in
the file people actually read each morning. It is the same argument
`remote_to_url()` already makes in its own docstring: derived from `repos.yml`
(single source of truth) rather than self-reported by each repo, so it cannot
drift. Putting the description in the plan instead would create one stale copy
per repo per day, and `replan.py` overwrites plans, so those copies would have to
be re-authored or lost.

## The change

`aggregate-plans.py`, three small edits:

1. `repo_row()` carries `"description": repo["description"]` (already normalized
   and stripped by `load_repos()` — no new parsing).
2. `workspace_row()` carries `"description": None`. The workspace is not a repo,
   has no `repos.yml` entry, and its plan body already opens with its own
   preamble (`_Workspace-scoped work: inter-repo tasks…_`) written by
   `replan.py`. Nothing to add; do **not** invent a `description` key in
   `config.yml` for this.
3. `render_section()` emits the line between the header and the body, in **every**
   state — `fresh`, `stale`, `missing`, `unparseable`. A repo with no plan is
   precisely where a newcomer most needs to know what it is, and that is the
   branch that returns early today.

No pipe-escaping needed (`render-readme.py`'s `_cell` exists because the roster
is a table; this is a paragraph). No new dependency between the two renderers —
one shared field, two independent projections.

## Open question — the missing-description fallback

`render-readme.py` prints `_no description — add one in `repos.yml`_` when the
field is empty, and `add-repo.py` warns at registration when it cannot find one.
Reproduce that nudge here, or omit the line silently?

**Leaning: reproduce it.** A silently absent line makes a repo with no
description indistinguishable from one with a good one — the §5.2 silent-omission
shape that [`16`](16-unavailable-is-a-silent-omission.md) just caught in the
rollup. The rollup is also the place a human is most likely to notice and fix it.

## Open question — the "At a glance" table

Leave it alone. The table already has a `Focus` column, and `MAX_FOCUS_CHARS =
64` exists specifically to stop rows from wrapping; a description column would
roughly double the width and defeat what the table is for. The sections are where
prose belongs. Revisit only if the sections turn out not to be read.

## Wording

Keep `**What this repo is (for a newcomer):**` verbatim. Not for compatibility —
[`07`](07-strip-project-status.md) and `08` are retiring `project-status`, and any
future umbrella roster here reads `repos.yml` directly rather than regexing the
rollup, which is the whole point of sourcing from the registry. Keep it because
the label is what tells a newcomer the line is addressed to *them*, and because
it survives `demote_headings()` and section embedding intact (it is not a
heading).

## Acceptance

- Every repo section in `daily-plan-summary.md` carries its `repos.yml`
  description, in all four plan states.
- The workspace section carries none, and gains no new config field.
- Editing a description in `repos.yml` changes both `README.md` (via `make
  readme`) and the next `daily-plan-summary.md`, with the value stored in exactly
  one place.
- A repo with an empty description renders the same "add one in `repos.yml`"
  nudge the README roster uses.
- `tests/run-tests.sh` asserts it alongside the existing `aggregate-plans.py`
  cases (~L1553–1572): a registered repo with a description has it in the
  rollup; one without gets the nudge; the workspace section has neither.
- Dogfood into `dev-workspace` via `update.sh` and read the resulting file as a
  newcomer would — this task is only done if the rollup now explains itself.
