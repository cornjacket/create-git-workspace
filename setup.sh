#!/usr/bin/env bash
# setup.sh — stamp out a new git-workspace: a wrapper repo that manages the set
# of repos and worktrees checked out beside it.
#
# Creates the WRAPPER only. It never clones, inits, or creates the managed child
# repos — that is `.workspace/scripts/bootstrap.sh`'s job, driven by repos.yml.
#
# To re-apply the generator's machinery to a workspace that already exists, use
# update.sh instead; this script refuses to run over one.
set -euo pipefail

GEN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$GEN_ROOT/lib/generator.sh"

usage() {
  cat <<EOF
usage: setup.sh <target-dir> [options]

  --name NAME     workspace name (default: basename of <target-dir>)
  --author EMAIL  git author to scope the status summary to
                  (default: git config user.email)
  --remote URL    git remote add origin URL
  --no-tasks      skip installing the task-system (project/tasks)
  --no-status     skip the status subsystem
  --no-commit     leave the generated files uncommitted
  --force         proceed even if <target-dir> already looks like a workspace
  -h, --help      show this
EOF
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
target=""; name=""; author=""; remote=""
with_tasks=1; with_status=1; do_commit=1; force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name)     name=${2:-}; shift 2 || die "--name needs a value" ;;
    --author)   author=${2:-}; shift 2 || die "--author needs a value" ;;
    --remote)   remote=${2:-}; shift 2 || die "--remote needs a value" ;;
    --no-tasks)  with_tasks=0; shift ;;
    --no-status) with_status=0; shift ;;
    --no-commit) do_commit=0; shift ;;
    --force)     force=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          [ -z "$target" ] || die "unexpected argument: $1"; target=$1; shift ;;
  esac
done

[ -n "$target" ] || { usage >&2; exit 2; }

# Validate before creating anything, so a bad name leaves no stray directory.
[ -n "$name" ] || name=$(basename "${target%/}")
validate_name "$name"

mkdir -p "$target"
target=$(cd "$target" && pwd)

if [ -d "$target/.workspace" ] && [ "$force" -eq 0 ]; then
  die "$target already looks like a git-workspace (.workspace/ exists).
       Use './update.sh $target' to re-apply the machinery, or --force to overwrite."
fi

# Setup still succeeds on a placeholder author; the STATUS RUN is what hard-fails
# on it, because an empty/wrong author silently corrupts the author-scoped summary.
author=$(resolve_author "$author")

log "Creating git-workspace '$name' at $target"

# ---------------------------------------------------------------------------
# 1. git init the wrapper
# ---------------------------------------------------------------------------
if [ -e "$target/.git" ]; then
  step "git:       already a git repo — left as is"
else
  git init -q "$target"
  # Normalize the initial branch to main without depending on `git init -b`
  # (git >= 2.28) or on the user's init.defaultBranch. Safe only pre-first-commit.
  git -C "$target" symbolic-ref HEAD refs/heads/main
  step "git:       initialized (branch main)"
fi

# ---------------------------------------------------------------------------
# 2. Machinery — always overwritten, shared with update.sh
# ---------------------------------------------------------------------------
install_machinery "$target" "$name"

# ---------------------------------------------------------------------------
# 3. CLAUDE.md — the hybrid: managed block inside a content file
# ---------------------------------------------------------------------------
inject_claude_block "$target" "$name"

# ---------------------------------------------------------------------------
# 4. Content — seeded if missing, never overwritten (here or by update.sh)
# ---------------------------------------------------------------------------
seed_content_file "$TEMPLATE_DIR/workspace/config.yml" "$target/.workspace/config.yml" "$name" "$author"
seed_content_file "$TEMPLATE_DIR/workspace/repos.yml"  "$target/.workspace/repos.yml"  "$name" "$author"
seed_content_file "$TEMPLATE_DIR/README.md"            "$target/README.md"             "$name" "$author"

# generator_version is the one generator-owned key inside that content file.
stamp_generator_version "$target"

# ---------------------------------------------------------------------------
# 5. Remote
# ---------------------------------------------------------------------------
if [ -n "$remote" ]; then
  if git -C "$target" remote get-url origin >/dev/null 2>&1; then
    step "git:       remote 'origin' already set — left as is"
  else
    git -C "$target" remote add origin "$remote"
    step "git:       remote origin -> $remote"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Task-system (vendored create-project-system) — default on
# ---------------------------------------------------------------------------
vendor_gen="$GEN_ROOT/vendor/create-project-system/generate.sh"
if [ "$with_tasks" -eq 1 ]; then
  if [ -x "$vendor_gen" ]; then
    log "Installing the task-system (vendored create-project-system)"
    "$vendor_gen" "$target" --tasks-dir project/tasks --with-skill --with-status
  else
    warn "task-system skipped: vendor/create-project-system is not vendored yet (task 006)."
  fi
else
  step "tasks:     skipped (--no-tasks)"
fi

if [ "$with_status" -eq 0 ]; then
  step "status:    skipped (--no-status)"
fi
# NOTE: the status subsystem (scripts, prompts, workflows) lands in tasks 008-010;
# until then --no-status only records the intent.

# ---------------------------------------------------------------------------
# 7. Initial commit — makes the zero-diff regeneration test meaningful
# ---------------------------------------------------------------------------
if [ "$do_commit" -eq 1 ]; then
  git -C "$target" add -A
  if git -C "$target" diff --cached --quiet; then
    step "git:       nothing to commit"
  else
    ident=()
    git -C "$target" config user.email >/dev/null 2>&1 || ident+=(-c "user.email=$author")
    git -C "$target" config user.name  >/dev/null 2>&1 || ident+=(-c "user.name=${author%%@*}")
    if [ "${#ident[@]}" -gt 0 ] && [ "$author" = "$AUTHOR_PLACEHOLDER" ]; then
      # No git identity anywhere and no --author: committing here would write the
      # placeholder into history permanently. Leave it staged instead.
      warn "no git identity available — the files are staged but NOT committed."
      warn "set user.email/user.name (or pass --author) and commit by hand."
    elif git -C "$target" ${ident[@]+"${ident[@]}"} commit -q -F - <<EOF
workspace(init): create git-workspace $name

- [Context]: stamped by create-git-workspace v$(generator_version).
- [Impact]: adds the hidden .workspace/ control plane (scripts, repos.yml,
  config.yml), the allowlist .gitignore, the Makefile command surface, the
  CLAUDE.md managed block, and a starter README.
EOF
    then
      step "git:       initial commit"
    else
      warn "could not create the initial commit — the files are staged, commit by hand."
    fi
  fi
else
  step "git:       left uncommitted (--no-commit)"
fi

# ---------------------------------------------------------------------------
# Next steps
# ---------------------------------------------------------------------------
cat <<EOF

$(printf '%b' "$_B")Workspace '$name' is ready.$(printf '%b' "$_X")

Next:
  1. cd $target
  2. Edit .workspace/repos.yml — add the repos/worktrees this workspace manages.
  3. make bootstrap    # clone/attach them
     make status       # verify

Two steps the generator cannot do for you (the routine seams):
  * Create the Claude /schedule routine and point it at the daily status script.
  * Add every tracked repo to that routine's 'sources' pre-clone list, or the
    remote run cannot read its git log.
EOF

if [ "$author" = "$AUTHOR_PLACEHOLDER" ]; then
  echo
  warn "set a real git_author in .workspace/config.yml before the first status run."
fi
