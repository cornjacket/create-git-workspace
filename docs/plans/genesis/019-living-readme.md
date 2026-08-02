# 019 — the generated workspace README reflects its current state

Status: done (2026-08-02)

The emitted `README.md` is seeded once and then frozen, so it describes the
workspace on the day it was stamped and never again. It should show what this
workspace *currently* contains: the tracked repos with a one-line description of
each, the deliverable links, and whether the scheduled routine exists.

## Decisions

- **`README.md` becomes a hybrid**, like `CLAUDE.md`: a generator-managed block
  (`git-workspace-roster`) inside a file the user still owns. Content outside the
  markers is preserved verbatim. This is the only way "reflects current state"
  and "your file" can both hold.
- **Descriptions live in `repos.yml`** as a `description:` field, seeded at
  registration from the best available source and overridable with
  `add-repo --description`: the repo's own **GitHub description** (`gh repo
  view --json description`) first, since that is the one field a human already
  wrote *as* a one-liner, then a capped, sentence-aware scrape of its
  `README.md`/`CLAUDE.md`. Missing `gh`, a non-GitHub remote, or an unset
  description all fall through silently. The
  registry is the right home: a repo's purpose is a property of the repo, not of
  one developer's plan. Storing rather than re-scraping keeps renders stable and
  lets a bad guess be fixed by hand.
- **No `branch` column.** A branch is mutable and, for worktrees, per-checkout —
  a registry value rendered as fact would drift into a lie. Path and mute state
  only.
- **The renderer ships inside the workspace** (`render-readme.py`, `make readme`)
  and the generator calls it — same reasoning as `install-hooks.sh`. One
  implementation, and `update.sh` can back-fill the block into workspaces that
  already exist.
- **Re-rendered by the membership verbs and by `update.sh`, never by the daily
  run.** Membership only changes locally, so the routine has no reason to touch
  `README.md` — and keeping it out of `daily.sh`'s commit set preserves the rule
  that setup/update never race the routine.
- **No last-run date in the block.** It would make a verb-triggered block depend
  on runtime state and go quietly stale between renders.

## Acceptance
- The block lists every tracked repo: name, one-line description, path, plus
  markers for muted (`report_inactivity: false`), skipped (`enabled: false`), and
  not-checked-out-on-this-machine.
- It links `summary.md`, `daily-plan-summary.md`, and `.workspace/state/archive/`.
- It reports the scheduled routine: a link when `routine_url` is set in
  `config.yml`, a pointer to `status-guide.md` §5.1 when it is not.
- `add-repo` / `delete-repo` / `mute-repo` refresh it; `make readme` refreshes it
  by hand; `make readme-check` reports staleness without writing.
- Idempotent — re-rendering an unchanged workspace is byte-identical, so
  `update.sh` still holds zero-diff.
- Text outside the markers survives; malformed markers are refused, not guessed.

## What landed

`render-readme.py` (machinery, in the workspace) + `description` in `repos.yml` +
optional `routine_url` in `config.yml` + `make readme` / `readme-check`. Called
by `setup.sh`, `update.sh`, and all three membership verbs. Tests: §8m, 276
assertions total.

### Two bugs the tests caught, both worth remembering

1. **Badge lines scraped as descriptions.** The first prose-paragraph filter
   skipped lines starting with `#`, `>`, `-`, `*`, `|`, `!`, `=` — but a linked
   badge is `[![build](img)](ci)`, which starts with `[`. The first repo added
   got `description: "[![badge](x)](y)"`. Fixed by stripping image/link syntax
   and asking whether any word characters survive, rather than pattern-matching
   prefixes.
2. **`set -e` ate the graceful degradation.** `out=$(python3 render-readme.py)`
   takes the substitution's exit status, so a malformed-marker exit 3 killed
   `update.sh` *before* the `case` that was written to downgrade it to a warning
   — the precise opposite of the intent, and invisible until a test asserted
   that `update.sh` still exits 0. Capture with `if out=$(...); then` instead.

### A judgement call worth recording

`render-readme.py` exits **3** on malformed markers and the generator downgrades
that to a warning, whereas malformed `CLAUDE.md` markers **abort** the run. The
asymmetry is deliberate: the kernel carries rules an agent must obey, so a
mangled one is a correctness problem; the roster is a dashboard, and a stale
dashboard must never take down a machinery upgrade.

Also: the aggregation test's "update.sh leaves the deliverables alone" assertion
was checking `git status` wholesale. That fixture hand-writes `repos.yml`, so the
roster is legitimately stale and `update.sh` legitimately refreshes it. Narrowed
the assertion to the runtime paths it was actually about, and added one asserting
the catch-up happens — the behaviour is now pinned instead of looking like a leak.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `019` — the generated `README.md` reflects current state: a managed roster block (tracked repos + one-line descriptions from `repos.yml`, deliverable links, routine status). *(Makes `README.md` the second hybrid; `add-repo` seeds each description by scraping the child's own README. No branch column — mutable, and per-checkout for worktrees.)*
