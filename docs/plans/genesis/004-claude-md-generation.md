# 004 — CLAUDE.md marker-block injection

Status: done (2026-08-01)

Inject/refresh the workspace directives in `CLAUDE.md` **without overwriting user
directives**, on both `setup.sh` and `update.sh`. CLAUDE.md is hybrid, not
machinery — see PLAN.md "CLAUDE.md: marker-block injection".

## Acceptance
- Managed block delimited by `<!-- git-workspace:begin -->` / `<!-- git-workspace:end -->`.
- No file → create `# CLAUDE.md — <name>` + block.
- File with markers → replace only between markers.
- File without markers (user's own) → inject block, preserve all user content.
- `{{WORKSPACE_NAME}}` substituted; block carries a generator-version stamp.
- Idempotent: re-injecting a current block yields no diff (supports 002's zero-diff).
- Block content covers: wrapper role, hidden `.workspace/` layout, the four
  scripts, and the worktree rules (`cd` into target; `[ -e .git ]` not `[ -d .git ]`).

## Notes
- Same convention as the cornjacket umbrella CLAUDE.md's `project-status:begin/end`.
- RESOLVED (PLAN Qs 6–7): append at the end when no markers exist; the name comes
  from `.workspace/config.yml` on update, so a directory rename is safe.

## What landed
- `inject_claude_block` in `lib/generator.sh` — one implementation, called by both
  `setup.sh` and `update.sh`.
- **Malformed markers abort instead of guessing.** A half-open block (begin with
  no end, or the reverse), a reversed pair, or a duplicated block all stop the run
  with a specific message and leave `CLAUDE.md` byte-for-byte untouched. Any of
  those states means an edit could silently destroy user content, and a mangled
  CLAUDE.md is worse than a failed update.
- The block ends with a human-visible version echo; `.workspace/config.yml` stays
  canonical.

## Verified (sandbox, then wiped)
- Three paths: **create** (no file) · **replace** (stale block swapped, user text
  above and below preserved) · **append** (user's own file, their content stays
  first). Each is byte-identical on a second run.
- Append handles a file with no trailing newline and is idempotent afterwards —
  the next run finds markers and takes the replace path.
- All four malformed shapes abort with the file unmodified.
- No `{{PLACEHOLDER}}` survives; `{{WORKSPACE_NAME}}` lands in the layout tree.
- Block content covers wrapper role, hidden `.workspace/` layout, all four
  scripts, and both worktree rules (`cd` into the target; `[ -e .git ]`).

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `004` — `CLAUDE.md` marker-block injection (append when no markers; version echo).
