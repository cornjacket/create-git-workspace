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
  --create-remote create a PRIVATE GitHub repo with 'gh' and wire it as origin
                  (--public to create it public; conflicts with --remote)
  --public        with --create-remote, create a public repo instead
  --with-hook     install guard.sh as the pre-commit hook
  --no-tasks      skip installing the task-system (project/tasks)
  --no-commit     leave the generated files uncommitted
  --force         proceed even if <target-dir> already looks like a workspace
  -h, --help      show this
EOF
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
target=""; name=""; author=""; remote=""
with_tasks=1; do_commit=1; force=0; create_remote=0; public=0; with_hook=0
created_remote=0

# There is deliberately no --no-status. The status subsystem is not a layer a
# workspace opts into — it IS the workspace layer (PLAN: "each workspace
# intrinsically carries what project-status did"). The flag existed from 002 to
# 018 and was never honored; an unknown-option error is more honest than a
# switch that prints "skipped" and installs the subsystem anyway. If a
# status-free wrapper ever becomes a real use case, add it back deliberately,
# with the emitted tree, allowlist, Makefile, kernel, and tests all threaded.
while [ $# -gt 0 ]; do
  case "$1" in
    --name)     name=${2:-}; shift 2 || die "--name needs a value" ;;
    --author)   author=${2:-}; shift 2 || die "--author needs a value" ;;
    --remote)   remote=${2:-}; shift 2 || die "--remote needs a value" ;;
    --create-remote) create_remote=1; shift ;;
    --public)        public=1; shift ;;
    --with-hook)     with_hook=1; shift ;;
    --no-tasks)  with_tasks=0; shift ;;
    --no-commit) do_commit=0; shift ;;
    --force)     force=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          [ -z "$target" ] || die "unexpected argument: $1"; target=$1; shift ;;
  esac
done

[ -n "$target" ] || { usage >&2; exit 2; }

# Two ways to get an origin, and they would fight over it. Fail before creating
# anything rather than silently letting one win.
if [ "$create_remote" -eq 1 ] && [ -n "$remote" ]; then
  die "--create-remote and --remote are mutually exclusive: one creates the
       remote repo, the other attaches an existing one. Pick one."
fi
if [ "$public" -eq 1 ] && [ "$create_remote" -eq 0 ]; then
  die "--public only means something with --create-remote."
fi
# Check for gh up front: discovering it is missing AFTER stamping a workspace
# leaves a half-configured repo and a confusing error.
if [ "$create_remote" -eq 1 ]; then
  command -v gh >/dev/null 2>&1 \
    || die "--create-remote needs the GitHub CLI ('gh') on PATH. Install it, or
       create the repo yourself and pass --remote <url>."
  gh auth status >/dev/null 2>&1 \
    || die "'gh' is installed but not authenticated. Run 'gh auth login' first."
fi

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
seed_content_file "$TEMPLATE_DIR/workspace/plans/_workspace/daily-plan.md" \
                  "$target/.workspace/plans/_workspace/daily-plan.md"      "$name" "$author"

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

# --create-remote: opt-in, and PRIVATE unless you say otherwise. A workspace
# carries your plans and your rollup; defaulting to public would publish them on
# a flag whose name says nothing about visibility.
#
# It creates the repo and wires origin, but does NOT push: pushing is a separate,
# outward-facing act, and --no-commit means there may be nothing to push. The
# closing print names the one command.
if [ "$create_remote" -eq 1 ]; then
  if git -C "$target" remote get-url origin >/dev/null 2>&1; then
    step "git:       remote 'origin' already set — skipping --create-remote"
  else
    vis="--private"; [ "$public" -eq 1 ] && vis="--public"
    if gh repo create "$name" $vis --source "$target" --remote origin >/dev/null 2>&1; then
      step "gh:        created ${vis#--} repo -> $(git -C "$target" remote get-url origin)"
      created_remote=1
    else
      # Not fatal: the workspace is fully stamped and usable. Losing the whole
      # run because a repo name is taken would be a poor trade.
      warn "gh repo create failed (name taken, or no permission?)."
      warn "the workspace is fine — attach a remote by hand:"
      warn "  git -C $target remote add origin <url>"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 6. Task-system (vendored create-project-system) — default on
# ---------------------------------------------------------------------------
if [ "$with_tasks" -eq 1 ]; then
  install_task_system "$target"
else
  step "tasks:     skipped (--no-tasks)"
fi

# ---------------------------------------------------------------------------
# 6b. Pre-commit hook (opt-in)
#
# Hooks live in .git/hooks/, which git does not track — so this is per-clone, and
# the installer ships inside the workspace (`make hook`) to be re-run after any
# clone. setup.sh only invokes it; it does not reimplement it.
# ---------------------------------------------------------------------------
if [ "$with_hook" -eq 1 ]; then
  if "$target/.workspace/scripts/install-hooks.sh" >/dev/null 2>&1; then
    step "hook:      guard.sh installed as pre-commit"
  else
    warn "could not install the pre-commit hook — run 'make hook' in the"
    warn "workspace to see why (an existing hook is never overwritten)."
  fi
fi

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
  2. make add-repo ARGS="<url>"   # register + clone each repo this manages
     (repos.yml is a lockfile the verbs write — do not hand-edit it)
  3. make status                  # verify
     make                         # list every command

Two steps the generator cannot do for you (the routine seams):
  * Create the Claude /schedule routine and point it at .workspace/scripts/daily.sh.
  * Add every tracked repo to that routine's 'sources' pre-clone list, or the
    remote run cannot read its git log.
  Both are written up in .workspace/status-guide.md (section 5).
EOF

if [ "$created_remote" -eq 1 ]; then
  cat <<EOF

The remote exists but is empty — nothing was pushed for you:
  git -C $target push -u origin main
EOF
fi

if [ "$with_hook" -eq 0 ]; then
  cat <<EOF

Optional: 'make hook' installs guard.sh as the pre-commit hook, so a child repo
can never be committed into the wrapper. Per-clone (hooks are not tracked).
EOF
fi

if [ "$author" = "$AUTHOR_PLACEHOLDER" ]; then
  echo
  warn "set a real git_author in .workspace/config.yml before the first status run."
fi
