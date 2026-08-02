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
render() {
  local src=$1 dst=$2 name=$3 author=${4:-}
  sed -e "s|{{WORKSPACE_NAME}}|$name|g" \
      -e "s|{{GENERATOR_VERSION}}|$(generator_version)|g" \
      -e "s|{{GIT_AUTHOR}}|$author|g" \
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

  mkdir -p "$target/.workspace/scripts"
  for f in "$TEMPLATE_DIR/workspace/scripts/"*.sh; do
    base=$(basename "$f")
    cp "$f" "$target/.workspace/scripts/$base"
    chmod 755 "$target/.workspace/scripts/$base"
  done
  for f in "$target/.workspace/scripts/"*.sh; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    if [ ! -e "$TEMPLATE_DIR/workspace/scripts/$base" ]; then
      rm -f "$f"
      step "machinery: removed stale .workspace/scripts/$base"
    fi
  done
  step "machinery: .workspace/scripts/ ($(ls -1 "$TEMPLATE_DIR/workspace/scripts" | wc -l | tr -d ' ') scripts)"

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
    i = text.find(BEGIN)
    j = text.find(END, i) if i >= 0 else -1
    if i >= 0 and j < 0:
        sys.exit("%s has a begin marker but no end marker — refusing to guess" % what)
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
  ) || { rm -f "$rendered"; die "CLAUDE.md injection failed"; }
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
