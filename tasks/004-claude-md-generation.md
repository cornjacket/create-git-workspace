# 004 — CLAUDE.md marker-block injection

Status: todo

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
- Open: append vs prepend when no markers exist; name source on update (PLAN Qs 6–7).
