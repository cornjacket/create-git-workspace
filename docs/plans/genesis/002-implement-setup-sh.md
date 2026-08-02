# 002 — implement setup.sh

Status: done (2026-08-01) — task-system install deferred to 006 (warns + skips)

Create `setup.sh <target-dir> [--name NAME] [--author EMAIL] [--remote URL] [--no-tasks] [--no-status]`
that stamps out a new git-workspace from `template/`. Full-featured by default.

> **Superseded in `018`:** `--no-status` was never honored and has been removed.
> The status subsystem is the workspace layer, not something a workspace opts
> into. This line is left as written for the record.

## Acceptance
- Refuses to run over an existing workspace (has `.workspace/`) unless `--force`
  (points to `update.sh`).
- `git init`s `<target-dir>`.
- **Machinery:** `template/workspace/scripts/` → `.workspace/scripts/` (chmod +x);
  `template/gitignore` → `.gitignore`; emit the `Makefile` command surface.
- **CLAUDE.md:** create-or-inject the managed block (`{{WORKSPACE_NAME}}` substituted);
  never overwrite a user's file (append if no markers).
- **Content (seed if missing):** `.workspace/repos.yml`; `.workspace/config.yml`
  (name + `git_author`, resolved `--author` → `git config user.email` →
  placeholder + warn); a starter `README.md` linking `summary.md` /
  `daily-plan-summary.md`.
- **Tasks (default):** run the vendored `create-project-system`
  (`--tasks-dir project/tasks --with-skill --with-status`) unless `--no-tasks`.
- `--remote` → `git remote add origin`. Does NOT init/create child repos
  (that's `bootstrap.sh`).
- Prints next steps + the two manual routine-setup reminders.

## Notes
- Plain copy + `sed`; use a **non-`/` delimiter** for values that contain `/`
  (e.g. a remote URL).

## What landed
- `lib/generator.sh` — **all machinery is written here**, not in `setup.sh`, so
  `update.sh` can reuse the identical code path. That single shared writer is
  what makes zero-diff hold; two independent renderers would drift.
  - `install_machinery` (overwrite) · `seed_content_file` (never overwrite) ·
    `inject_claude_block` (hybrid) · `workspace_name` (recover from config.yml).
- New template files: `template/Makefile` (machinery), `template/README.md`
  (content seed), `template/workspace/config.yml` (content seed). `repos.yml` now
  seeds `repos: []` with the schema commented out — a starter list of real repos
  would make `bootstrap.sh` clone someone else's work.
- `VERSION` (0.1.0) is the generator stamp: canonical into `config.yml`, echoed
  into the CLAUDE.md block.
- Allowlist gained `!/Makefile` (caught by the emitted-tree assertion — the
  Makefile was generated but untracked).
- Workspace names are validated to `[A-Za-z0-9._-]`, which also removes any
  chance of a `sed` delimiter collision.
- `setup.sh` makes the **initial commit** by default (`--no-commit` opts out).
  Without a commit, `git diff` is trivially empty and the zero-diff test proves
  nothing. If no git identity exists *and* no `--author` was given, it stages but
  refuses to commit rather than writing the placeholder author into history.

## Verified (sandbox, then wiped)
- Emitted tree tracked by the allowlist: `.gitignore`, `Makefile`, `CLAUDE.md`,
  `README.md`, `.workspace/{config.yml,repos.yml,scripts/*}` — child checkouts
  ignored; `make help|status|guard` all work.
- **Zero-diff probe:** re-running `setup.sh --force` over a committed workspace
  leaves `git status --porcelain` empty.
- All three CLAUDE.md paths: create · append-when-no-markers (user content
  preserved byte-for-byte) · replace-block, and a second run is byte-identical.
- Content is never overwritten: a hand-edited `repos.yml` survives a re-run.
- `--author` / `--remote` / default-name-from-basename / refusal without
  `--force` / invalid name rejected before any directory is created.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `002` — implement `setup.sh` (create wrapper: machinery, CLAUDE.md block, `config.yml`, `Makefile`; seed content; run tasks by default). *(task-system install deferred to `006`; setup warns and skips.)*
