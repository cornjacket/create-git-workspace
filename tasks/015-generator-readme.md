# 015 — generator README (keep in sync)

Status: in-progress

Keep `create-git-workspace/README.md` documenting the workspace steps as they are
implemented (standing request).

## Acceptance
- README covers the workspace steps: generate (`setup`) → add/mute repos →
  bootstrap → status → guard → daily loop → update, each marked built / planned.
- Updated as each task lands.

## Notes
- Initial version exists; this task tracks keeping it current through the build.
- Standing task: it closes when the build does. Stays `in-progress` so a landed
  step that skips the README is visible as a gap.

## Sync log
- **Current through `014` + `017`.** Full rewrite: every step is now ✅ (only
  `016`'s opt-in extras remain 🔧), the verbs are named as the `.py` scripts and
  `make` targets they actually are, and the emitted tree gained `project/`,
  `.claude/skills/`, `.github/workflows/`, `prompts/`, `templates/`, and
  `status-guide.md`. Added: the quick start, the machinery/content/runtime table
  (the load-bearing property a reader needs before touching `template/`), the
  generator's own layout, CI, and the vendoring/revendor step. Fixed the stale
  `.workspace/status/` → `state/`.
- Documenting `setup.sh --no-status` surfaced that it is accepted but never
  honored → filed as `018`; the README says so rather than implying it works.
- **Current through `016`/`018`.** Removed the `--no-status` mention, added
  `--create-remote` / `--public` / `--with-hook` and `make hook` to step 5, and
  refreshed the assertion count (244). Implementation-status note now says the
  build is done apart from this standing task.
