#!/usr/bin/env bash
# generator.sh — shared helpers for setup.sh and update.sh.
# Source this; do not execute it.
#
# WHY THIS FILE EXISTS: every byte of MACHINERY is written here, so setup.sh and
# update.sh emit identical output for identical inputs. That single shared path
# is what makes the zero-diff regeneration invariant hold — if the two scripts
# each rendered their own copy, they would drift and `update.sh` would produce a
# diff on an already-current workspace.
#
# Three file classes (see PLAN.md):
#   machinery — generator-owned, always overwritten     (install_machinery)
#   content   — user-owned, seeded if missing only      (seed_content_file)
#   runtime   — routine-owned, never touched here       (no function; by design)
# CLAUDE.md is the one hybrid: a machinery block inside a content file
# (inject_claude_block).

GEN_ROOT="${GEN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATE_DIR="$GEN_ROOT/template"

# The loud stand-in written into config.yml when no git author can be resolved.
# Setup tolerates it; the status run must hard-fail on it.
AUTHOR_PLACEHOLDER="CHANGEME@example.invalid"

if [ -t 2 ]; then
  _B=$'\033[1m'; _R=$'\033[31m'; _Y=$'\033[33m'; _D=$'\033[2m'; _X=$'\033[0m'
else
  _B=""; _R=""; _Y=""; _D=""; _X=""
fi

log()  { printf '%b==>%b %s\n' "$_B" "$_X" "$*"; }
step() { printf '    %s\n' "$*"; }
warn() { printf '%bwarning:%b %s\n' "$_Y" "$_X" "$*" >&2; }
die()  { printf '%berror:%b %s\n' "$_R" "$_X" "$*" >&2; exit 1; }

generator_version() {
  tr -d ' \t\n' < "$GEN_ROOT/VERSION"
}

# validate_name — the workspace name is substituted with sed, so keep it to
# characters that can never collide with a delimiter or a regex metachar.
validate_name() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*)
      die "invalid workspace name '$1' — use only letters, digits, '.', '_', '-'" ;;
  esac
}

# render <src> <dst> <name> <author> — copy a template file, substituting the
# placeholders. Uses '|' as the sed delimiter, never '/', because emitted values
# (paths, remote URLs) routinely contain slashes.
#
# {{TODAY}} is only safe in CONTENT templates (seeded once). Putting it in a
# machinery file would re-render a different value tomorrow and break zero-diff.
render() {
  local src=$1 dst=$2 name=$3 author=${4:-}
  sed -e "s|{{WORKSPACE_NAME}}|$name|g" \
      -e "s|{{GENERATOR_VERSION}}|$(generator_version)|g" \
      -e "s|{{GIT_AUTHOR}}|$author|g" \
      -e "s|{{TODAY}}|$(date +%Y-%m-%d)|g" \
      "$src" > "$dst"
}

# resolve_author [explicit] — --author -> git config user.email -> placeholder.
# Warns (to stderr) when it falls through to the placeholder; the caller decides
# what that means. Shared so setup.sh and update.sh cannot disagree.
resolve_author() {
  local a=${1:-}
  [ -n "$a" ] || a=$(git config user.email 2>/dev/null || true)
  if [ -z "$a" ]; then
    a=$AUTHOR_PLACEHOLDER
    warn "no git author found (--author / git config user.email both unset)."
    warn "using the placeholder '$AUTHOR_PLACEHOLDER' — the daily status run will"
    warn "REFUSE to run until you replace it in .workspace/config.yml."
  fi
  printf '%s\n' "$a"
}

# install_machinery <target> <name> — write every generator-owned file.
# Always overwrites; safe to re-run. This is the function update.sh calls.
#
# .workspace/scripts/ is MIRRORED, not merely copied over: a script dropped from
# the template is deleted from the workspace. Otherwise retired machinery lingers
# forever and every workspace slowly accretes a different set of scripts. Only
# *.sh directly in that directory is touched, and every removal is announced.
install_machinery() {
  local target=$1 name=$2 f base

  # Scripts are .sh AND .py (the status subsystem is Python — it parses YAML and
  # structured git output, which bash has no business doing). Both get the exec
  # bit; _status_lib.py is imported rather than run, but a uniform mode keeps the
  # emitted tree byte-identical run to run, which zero-diff depends on.
  mkdir -p "$target/.workspace/scripts"
  for f in "$TEMPLATE_DIR/workspace/scripts/"*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    cp "$f" "$target/.workspace/scripts/$base"
    chmod 755 "$target/.workspace/scripts/$base"
  done
  for f in "$target/.workspace/scripts/"*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ ! -e "$TEMPLATE_DIR/workspace/scripts/$base" ]; then
      rm -f "$f"
      step "machinery: removed stale .workspace/scripts/$base"
    fi
  done
  step "machinery: .workspace/scripts/ ($(ls -1 "$TEMPLATE_DIR/workspace/scripts" | wc -l | tr -d ' ') scripts)"

  # Prompts are machinery too: the wording of the summariser prompt is the
  # generator's, not the user's, and it must upgrade with the scripts that use it.
  mkdir -p "$target/.workspace/prompts"
  for f in "$TEMPLATE_DIR/workspace/prompts/"*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    cp "$f" "$target/.workspace/prompts/$base"
    chmod 644 "$target/.workspace/prompts/$base"
  done
  for f in "$target/.workspace/prompts/"*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    [ -e "$TEMPLATE_DIR/workspace/prompts/$base" ] || {
      rm -f "$f"; step "machinery: removed stale .workspace/prompts/$base"
    }
  done
  step "machinery: .workspace/prompts/"

  # Templates injected INTO other repos (the child commit kernel). Machinery:
  # the rules are the generator's, and they must upgrade with it.
  mkdir -p "$target/.workspace/templates"
  for f in "$TEMPLATE_DIR/workspace/templates/"*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    # Copied verbatim, NOT rendered: this block is committed into shared child
    # repos, so a workspace name or version stamp in it would make two
    # developers overwrite each other's block on every injection.
    cp "$f" "$target/.workspace/templates/$base"
    chmod 644 "$target/.workspace/templates/$base"
  done
  for f in "$target/.workspace/templates/"*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    [ -e "$TEMPLATE_DIR/workspace/templates/$base" ] || {
      rm -f "$f"; step "machinery: removed stale .workspace/templates/$base"
    }
  done
  step "machinery: .workspace/templates/"

  # Workflows are stored as template/github/ (no leading dot) so they stay inert
  # inside the generator repo, then land at .github/ in the workspace — the same
  # trick as template/gitignore.
  mkdir -p "$target/.github/workflows"
  for f in "$TEMPLATE_DIR/github/workflows/"*.yml; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    render "$f" "$target/.github/workflows/$base" "$name"
    chmod 644 "$target/.github/workflows/$base"
  done
  for f in "$target/.github/workflows/"*.yml; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    [ -e "$TEMPLATE_DIR/github/workflows/$base" ] || {
      rm -f "$f"; step "machinery: removed stale .github/workflows/$base"
    }
  done
  step "machinery: .github/workflows/"

  render "$TEMPLATE_DIR/gitignore" "$target/.gitignore" "$name"
  chmod 644 "$target/.gitignore"
  step "machinery: .gitignore (allowlist)"

  render "$TEMPLATE_DIR/Makefile" "$target/Makefile" "$name"
  chmod 644 "$target/Makefile"
  step "machinery: Makefile"
}

# seed_content_file <src> <dst> <name> <author> — write a CONTENT file only if it
# is missing. Never overwrites; this is the whole contract of the content class.
seed_content_file() {
  local src=$1 dst=$2 name=$3 author=${4:-}
  if [ -e "$dst" ]; then
    step "content:   ${dst##*/} — already present, left untouched"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  render "$src" "$dst" "$name" "$author"
  step "content:   ${dst##*/} — seeded"
}

# inject_claude_block <target> <name> — the hybrid file (PLAN §CLAUDE.md).
#   no CLAUDE.md          -> write the whole rendered template
#   markers present       -> replace ONLY the text between them
#   no markers (user's)   -> append the block, preserving every existing byte
# Idempotent: re-injecting a current block rewrites nothing at all.
inject_claude_block() {
  local target=$1 name=$2 rendered action
  rendered=$(mktemp "${TMPDIR:-/tmp}/cgw-claude.XXXXXX")
  render "$TEMPLATE_DIR/CLAUDE.md" "$rendered" "$name"

  action=$(python3 - "$target/CLAUDE.md" "$rendered" <<'PY'
import pathlib, sys

dst = pathlib.Path(sys.argv[1])
rendered = pathlib.Path(sys.argv[2]).read_text()

BEGIN = "<!-- git-workspace:begin"
END = "<!-- git-workspace:end -->"

def region(text, what):
    """Locate the managed block, or None. Refuses to guess at anything malformed:
    a half-open block or a duplicated one means a human (or an older buggy run)
    left the file in a state where any edit we make could silently destroy
    content. Better to stop and say so than to mangle a CLAUDE.md."""
    nbegin, nend = text.count(BEGIN), text.count(END)
    if nbegin > 1 or nend > 1:
        sys.exit("%s contains %d begin / %d end markers — expected at most one "
                 "managed block. Delete the extras, then re-run." % (what, nbegin, nend))
    i = text.find(BEGIN)
    j = text.find(END)
    if i >= 0 and j < 0:
        sys.exit("%s has a begin marker but no end marker — refusing to guess "
                 "where the managed block ends." % what)
    if j >= 0 and i < 0:
        sys.exit("%s has an end marker but no begin marker — refusing to guess "
                 "where the managed block starts." % what)
    if i >= 0 and j < i:
        sys.exit("%s has its end marker before its begin marker — refusing to "
                 "guess." % what)
    return (i, j + len(END)) if i >= 0 else None

span = region(rendered, "template CLAUDE.md")
if span is None:
    sys.exit("template CLAUDE.md has no managed block")
block = rendered[span[0]:span[1]]

if not dst.exists():
    dst.write_text(rendered)
    print("create")
    raise SystemExit

cur = dst.read_text()
span = region(cur, str(dst))
if span:
    new = cur[:span[0]] + block + cur[span[1]:]
    action = "replace"
else:
    # No markers: the user brought their own CLAUDE.md. Append at the end —
    # least disruptive to their framing. The next run finds markers and takes
    # the replace path, so this stays idempotent.
    sep = "" if cur.endswith("\n\n") else ("\n" if cur.endswith("\n") else "\n\n")
    new = cur + sep + block + "\n"
    action = "append"

if new == cur:
    print("unchanged")
else:
    dst.write_text(new)
    print(action)
PY
  ) || { rm -f "$rendered"; die "CLAUDE.md injection aborted (see above) — the file was left untouched"; }
  rm -f "$rendered"

  case "$action" in
    create)    step "hybrid:    CLAUDE.md — created from template" ;;
    replace)   step "hybrid:    CLAUDE.md — managed block refreshed" ;;
    append)    step "hybrid:    CLAUDE.md — no markers found, block appended" ;;
    unchanged) step "hybrid:    CLAUDE.md — managed block already current" ;;
  esac
}

# stamp_generator_version <target> — rewrite the ONE generator-owned key in the
# otherwise user-owned config.yml.
#
# config.yml is content ("never overwritten"), but `generator_version` is
# canonical version telemetry — leaving it frozen at the setup-time value makes
# it lie after every upgrade. So this applies the CLAUDE.md hybrid rule at
# single-line granularity: the generator owns exactly this key, the user owns
# every other byte. Idempotent, so the zero-diff invariant survives.
stamp_generator_version() {
  local target=$1 result
  result=$(python3 - "$target/.workspace/config.yml" "$(generator_version)" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
if not path.exists():
    print("missing")
    raise SystemExit

cur = path.read_text()
line = "generator_version: %s" % version
new, n = re.subn(r"(?m)^generator_version:.*$", line.replace("\\", "\\\\"), cur)
if n == 0:
    sep = "" if cur.endswith("\n") else "\n"
    new = cur + sep + line + "\n"

if new == cur:
    print("unchanged")
else:
    path.write_text(new)
    print("stamped")
PY
  ) || die "could not stamp generator_version into .workspace/config.yml"

  case "$result" in
    stamped)   step "stamp:     .workspace/config.yml generator_version -> $(generator_version)" ;;
    unchanged) step "stamp:     .workspace/config.yml generator_version already $(generator_version)" ;;
    missing)   warn ".workspace/config.yml not found — version stamp skipped" ;;
  esac
}

# install_task_system <target> — delegate to the vendored create-project-system.
#
# DELEGATED class: that generator owns its own machinery/content split (it
# overwrites its scripts and never touches your tasks), so both setup and update
# call it with the identical command and let it decide what to rewrite. Its
# CLAUDE.md kernel is a SEPARATE marker block (task-system:begin) from ours
# (git-workspace:begin) — task capture vs workspace machinery, no overlap.
install_task_system() {
  local target=$1
  local gen="$GEN_ROOT/vendor/create-project-system/generate.sh"
  if [ ! -x "$gen" ]; then
    # Return 0, not 1: callers run under `set -e`, so a non-zero return here
    # would abort setup.sh mid-stamp and leave a half-built workspace with no
    # initial commit. A missing vendor means "no task-system", which is a
    # legitimate state (--no-tasks produces it) — warn and carry on.
    warn "task-system skipped: vendor/create-project-system/generate.sh is missing."
    warn "run ./tools/revendor.sh to restore it."
    return 0
  fi
  log "Task-system (vendored create-project-system)"
  "$gen" --target-repo "$target" \
         --tasks-dir project/tasks \
         --with-skill --with-status --inject-claude-md \
    | sed 's/^/    /'
}

# workspace_name <target> — recover the name from .workspace/config.yml, so a
# directory rename never breaks regeneration (PLAN Q7).
workspace_name() {
  local target=$1
  python3 - "$target/.workspace/config.yml" <<'PY'
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        cfg = yaml.safe_load(f) or {}
except FileNotFoundError:
    sys.exit(2)
name = cfg.get("name") or ""
if not name:
    sys.exit(3)
print(name)
PY
}
