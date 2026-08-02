#!/usr/bin/env bash
# update.sh — re-apply this generator's MACHINERY to an existing git-workspace.
#
# The contract, in one line: running this over an already-current workspace must
# leave `git diff` empty. No --force, ever. If a normal upgrade needs one, the
# machinery/content split is wrong — fix the split, not the flag.
#
# What it writes:  .workspace/scripts/*, .gitignore, Makefile, the CLAUDE.md
#                  managed block, and the generator_version key in config.yml.
# What it does NOT touch:
#   content — .workspace/repos.yml, the rest of config.yml, README.md, and
#             everything outside the CLAUDE.md markers.
#   runtime — .workspace/state/**, summary.md, daily-plan-summary.md. The daily
#             status routine owns those; update must never race it.
#
# It also never commits. The whole point is to leave a reviewable diff.
set -euo pipefail

GEN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$GEN_ROOT/lib/generator.sh"

usage() {
  cat <<EOF
usage: update.sh <target-dir>

Re-applies the generator's machinery to an existing git-workspace and leaves the
changes uncommitted for review. Content and routine-owned files are untouched.

  -h, --help   show this
EOF
}

target=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*)        die "unknown option: $1" ;;
    *)         [ -z "$target" ] || die "unexpected argument: $1"; target=$1; shift ;;
  esac
done

[ -n "$target" ] || { usage >&2; exit 2; }
[ -d "$target" ] || die "no such directory: $target"
target=$(cd "$target" && pwd)

[ -d "$target/.workspace" ] || die "$target is not a git-workspace (no .workspace/ directory).
       Use './setup.sh $target' to create one."

# Recover the name from config.yml, not from the directory name — so renaming the
# workspace directory never rewrites CLAUDE.md behind your back (PLAN Q7).
if name=$(workspace_name "$target" 2>/dev/null); then
  :
else
  name=$(basename "$target")
  warn ".workspace/config.yml is missing or has no 'name' — falling back to '$name'."
  warn "seeding config.yml now; check its git_author before the next status run."
  seed_content_file "$TEMPLATE_DIR/workspace/config.yml" \
    "$target/.workspace/config.yml" "$name" "$(resolve_author "")"
fi
validate_name "$name"

log "Updating git-workspace '$name' at $target"

if [ -e "$target/.git" ] && [ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]; then
  warn "the workspace has uncommitted changes — this update's diff will mix in with them."
fi

install_machinery "$target" "$name"
inject_claude_block "$target" "$name"

# Seed content slots that are MISSING — never overwrite one that exists.
#
# The content rule is "never overwrite", not "never create". Without this, a
# content slot introduced by a newer generator version could never reach a
# workspace that already exists: only setup.sh seeds, and setup.sh refuses to run
# on a live workspace. Creating an absent file destroys nothing, and zero-diff is
# unaffected — on a current workspace every slot is already present, so nothing
# is written.
seed_content_file "$TEMPLATE_DIR/workspace/repos.yml" "$target/.workspace/repos.yml" "$name"
seed_content_file "$TEMPLATE_DIR/README.md"           "$target/README.md"            "$name"
seed_content_file "$TEMPLATE_DIR/workspace/daily-plans/_workspace/daily-plan.md" \
                  "$target/.workspace/daily-plans/_workspace/daily-plan.md"                 "$name"

stamp_generator_version "$target"

# The README roster block. This is how a workspace stamped by an older generator
# GAINS the block — the renderer is machinery that was just (re)installed above,
# and it only rewrites between its own markers, so the user's README survives.
render_readme_block "$target"

# The vendored create-project-system owns the installed task-system's own
# machinery/content split; delegate its upgrade to it rather than reimplementing.
# Only upgrade what is already installed — update.sh must never ADD a subsystem
# the user opted out of with --no-tasks.
if [ -d "$target/project/tasks" ]; then
  install_task_system "$target"
fi

echo
if [ -e "$target/.git" ] && git -C "$target" diff --quiet 2>/dev/null && \
   [ -z "$(git -C "$target" status --porcelain 2>/dev/null)" ]; then
  log "Already current — nothing changed (zero diff)."
else
  log "Machinery re-applied. Review and commit:"
  step "cd $target && git diff"
fi
