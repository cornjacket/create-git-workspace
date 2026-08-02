#!/usr/bin/env bash
# generate.sh — install the Markdown task subsystem into a target repo.
#
# Usage:
#   generate.sh --target-repo <path> [options]
#
# Options:
#   --target-repo <path>     Repo to install into (required)
#   --tasks-dir <rel-path>   Mount path inside the target (default: tasks)
#   --epic <name>            Starter epic (default: main)
#   --with-worktrees         Worktree isolation (worktrees.md + Worktree field)
#   --with-projects          Long-running projects (new-project.sh, list-projects.sh)
#   --with-status            Status-report subsystem: a status/ sibling of the
#                            tasks mount + a container README (project/ workspace)
#   --with-worktree-guard    check-task-complete.py removal guard
#   --with-skill             Emit .claude/skills/task-system/ (Claude on-demand skill)
#   --inject-claude-md       Append the kernel snippet to the target's CLAUDE.md
#                            (default: print it for manual placement)
#   --force                  Also re-seed content (worktrees.md, status task lists).
#                            NOT needed for normal regeneration — see below.
#   -h, --help               Show this help
#
# COLLISION POLICY — regeneration is safe by default:
#   * MACHINERY (scripts/, templates, docs/, task-config.sh, skill) is ALWAYS
#     overwritten. It is generated output; that is the point.
#   * CONTENT (epic + status folders, their task lists, worktrees.md) is created
#     ONLY IF MISSING and is never overwritten. Your tasks are never touched.
#   So re-running the same command upgrades the machinery and leaves task content
#   alone. --force additionally re-seeds content files (rarely wanted).
#
# UPGRADING FROM <= v0.1.0 (the Category -> Worktree rename):
#   --with-classes is now --with-worktrees, and the metadata row is `Worktree`.
#   Existing tasks and an existing classes.md need NO migration: the generated
#   scripts read both spellings permanently, because both are CONTENT that this
#   generator never rewrites. The runtime --category / --group-by-category flags
#   also still work, with a deprecation warning.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
TARGET=""
TASKS_DIR="tasks"
EPIC="main"
WITH_WORKTREES=false
WITH_PROJECTS=false
WITH_STATUS=false
WITH_GUARD=false
WITH_SKILL=false
INJECT_CLAUDE_MD=false
FORCE=false

usage() { sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-repo)        TARGET="$2"; shift 2 ;;
        --tasks-dir)          TASKS_DIR="$2"; shift 2 ;;
        --epic)               EPIC="$2"; shift 2 ;;
        --with-worktrees)     WITH_WORKTREES=true; shift ;;
        # Renamed in v0.2.0. Generate-time flags are typed once, during a
        # deliberate upgrade, so this errors rather than aliasing — pin v0.1.0
        # if you are not ready to move.
        --with-classes)
            echo "Error: --with-classes was renamed to --with-worktrees in v0.2.0." >&2
            echo "       Existing installs need no migration: the generated scripts" >&2
            echo "       read both 'Worktree' and 'Category' rows, and both" >&2
            echo "       worktrees.md and classes.md. Pin v0.1.0 to defer." >&2
            exit 1 ;;
        --with-projects)      WITH_PROJECTS=true; shift ;;
        --with-status)        WITH_STATUS=true; shift ;;
        --with-worktree-guard) WITH_GUARD=true; shift ;;
        --with-skill)         WITH_SKILL=true; shift ;;
        --inject-claude-md)   INJECT_CLAUDE_MD=true; shift ;;
        --force)              FORCE=true; shift ;;
        -h|--help)            usage; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; echo "Try --help" >&2; exit 1 ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "Error: --target-repo is required." >&2
    echo "Try --help" >&2
    exit 1
fi
if [[ ! -d "$TARGET" ]]; then
    echo "Error: target repo not found: $TARGET" >&2
    exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

# Strip any leading/trailing slashes from the mount path
TASKS_DIR="${TASKS_DIR#/}"; TASKS_DIR="${TASKS_DIR%/}"
if [[ -z "$TASKS_DIR" ]]; then
    echo "Error: --tasks-dir must not be empty." >&2
    exit 1
fi

# Sibling mounts derived from the tasks mount, mirroring task-env.sh:
#   tasks         -> projects,      status         (siblings at repo root)
#   project/tasks -> project/projects, project/status (siblings in a container)
# CONTAINER_REL is the parent dir of the tasks mount (the project/ workspace),
# or "." when the tasks mount sits at the repo root. TASKS_BASE is its leaf name.
_parent="$(dirname "$TASKS_DIR")"
TASKS_BASE="$(basename "$TASKS_DIR")"
if [[ "$_parent" == "." ]]; then
    PROJECTS_REL="projects"; STATUS_REL="status"; CONTAINER_REL="."
else
    PROJECTS_REL="$_parent/projects"; STATUS_REL="$_parent/status"; CONTAINER_REL="$_parent"
fi

if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Note: $TARGET is not a git repo. The scripts will fall back to a"
    echo "      walk-up root search, which works, but 'git init' is recommended."
fi

MOUNT="$TARGET/$TASKS_DIR"
SCRIPTS_OUT="$MOUNT/scripts"
DOCS_OUT="$MOUNT/docs"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
created=(); updated=(); skipped=()

# render <src> <dst> — copy with GENERATOR-TIME placeholders substituted.
#
# TWO PLACEHOLDER NAMESPACES — do not conflate them:
#   generator-time : {{TASKS_REL}} {{DEFAULT_EPIC}} {{PROJECTS_REL}}
#                    {{STATUS_REL}} {{CONTAINER_REL}} {{TASKS_BASE}}
#                    {{PROJECTS_REL_LINE}}   -> substituted here, must not survive.
#   runtime        : {{NAME}} {{STATUS}} {{EPIC}} {{TAGS}} {{PRIORITY}}
#                    {{PARENT}} {{CREATED}} {{WORKTREE}}
#                    -> live in the task templates and MUST survive generation;
#                       the task-creation scripts substitute them per task.
# Never add a runtime token to the substitution list below — it would bake a
# fixed value into the template and silently break task creation.
render() {
    sed -e "s|{{TASKS_REL}}|$TASKS_DIR|g" \
        -e "s|{{DEFAULT_EPIC}}|$EPIC|g" \
        -e "s|{{PROJECTS_REL}}|$PROJECTS_REL|g" \
        -e "s|{{STATUS_REL}}|$STATUS_REL|g" \
        -e "s|{{CONTAINER_REL}}|$CONTAINER_REL|g" \
        -e "s|{{TASKS_BASE}}|$TASKS_BASE|g" \
        "$1" > "$2"
}

# seed <src> <dst> [rendered] — CONTENT: write only if missing (unless --force)
seed() {
    local src="$1" dst="$2"
    if [[ -e "$dst" && "$FORCE" != true ]]; then
        skipped+=("${dst#$TARGET/}  (exists — preserved)")
        return 0
    fi
    [[ -e "$dst" ]] && updated+=("${dst#$TARGET/}  (re-seeded via --force)") || created+=("${dst#$TARGET/}")
    render "$src" "$dst"
}

echo "Generating task subsystem"
echo "  target : $TARGET"
echo "  mount  : $TASKS_DIR/"
echo "  epic   : $EPIC"
echo ""

# ---------------------------------------------------------------------------
# 1. MACHINERY — always overwritten
# ---------------------------------------------------------------------------
mkdir -p "$SCRIPTS_OUT" "$DOCS_OUT"

# core scripts
for f in "$SRC_DIR"/scripts/*; do
    base="$(basename "$f")"
    case "$base" in
        *.md) render "$f" "$SCRIPTS_OUT/$base" ;;   # e.g. list-tasks.md
        *)    cp "$f" "$SCRIPTS_OUT/$base" ;;
    esac
done

# templates live BESIDE the scripts (scripts reference "$SCRIPTS_DIR/*-template.md")
for f in "$SRC_DIR"/templates/*.md; do
    render "$f" "$SCRIPTS_OUT/$(basename "$f")"
done

# EMIT RULE: without the worktrees layer, strip the Worktree row from the
# user-task template so repos without it don't carry a dead field.
if [[ "$WITH_WORKTREES" != true ]]; then
    perl -0pi -e 's{^\| Worktree[^\n]*\n}{}m' "$SCRIPTS_OUT/user-task-template.md"
fi

# generated config
PROJECTS_REL_LINE="# (projects layer not installed)"
if [[ "$WITH_PROJECTS" == true ]]; then
    PROJECTS_REL_LINE="PROJECTS_REL=\"$PROJECTS_REL\""
fi
sed -e "s|{{TASKS_REL}}|$TASKS_DIR|g" \
    -e "s|{{DEFAULT_EPIC}}|$EPIC|g" \
    -e "s|{{PROJECTS_REL_LINE}}|$PROJECTS_REL_LINE|g" \
    "$SRC_DIR/config/task-config.sh.in" > "$SCRIPTS_OUT/task-config.sh"

chmod +x "$SCRIPTS_OUT"/*.sh "$SCRIPTS_OUT"/*.py 2>/dev/null || true

# docs — USING.md is ALWAYS emitted (the skill is an accelerator, not the only copy)
render "$SRC_DIR/docs/USING.md"        "$DOCS_OUT/USING.md"
render "$SRC_DIR/docs/README.md"       "$DOCS_OUT/README.md"
render "$SRC_DIR/docs/task-manager.md" "$DOCS_OUT/task-manager.md"
updated+=("$TASKS_DIR/scripts/  (machinery: $(ls "$SCRIPTS_OUT" | wc -l | tr -d ' ') files)")
updated+=("$TASKS_DIR/docs/     (USING.md, README.md, task-manager.md)")

# ---------------------------------------------------------------------------
# 2. LAYERS
# ---------------------------------------------------------------------------
if [[ "$WITH_PROJECTS" == true ]]; then
    for f in "$SRC_DIR"/layers/projects/scripts/*.sh; do
        cp "$f" "$SCRIPTS_OUT/$(basename "$f")"; chmod +x "$SCRIPTS_OUT/$(basename "$f")"
    done
    updated+=("$TASKS_DIR/scripts/{new,list}-project*.sh  (projects layer)")
fi

if [[ "$WITH_GUARD" == true ]]; then
    cp "$SRC_DIR/layers/worktree-guard/check-task-complete.py" "$SCRIPTS_OUT/"
    chmod +x "$SCRIPTS_OUT/check-task-complete.py"
    updated+=("$TASKS_DIR/scripts/check-task-complete.py  (worktree guard)")
fi

# worktrees.md is CONTENT — the user edits it; never clobber their definitions.
#
# Pre-rename installs hold this file as classes.md, which the generated scripts
# still read. Seeding worktrees.md beside it would leave two files where the
# reader silently prefers the fresh, empty one over the operator's real
# definitions — so seed only when NEITHER name is present. This holds even
# under --force, for the same reason: the failure is silent and the recovery
# (noticing your worktrees vanished) is not.
if [[ "$WITH_WORKTREES" == true ]]; then
    if [[ -e "$MOUNT/classes.md" && ! -e "$MOUNT/worktrees.md" ]]; then
        skipped+=("$TASKS_DIR/classes.md  (pre-rename name — still read; rename it by hand to finish the move)")
    else
        seed "$SRC_DIR/layers/worktrees/worktrees.md" "$MOUNT/worktrees.md"
    fi
fi

# Status subsystem. Both the log README and the container README are CONTENT
# (the user grows the log table and may customize the workspace overview), so
# they are seeded, never clobbered. The full workflow lives in docs/USING.md
# (machinery), so these stubs stay thin and the convention stays single-source.
if [[ "$WITH_STATUS" == true ]]; then
    STATUS_OUT="$TARGET/$STATUS_REL"
    mkdir -p "$STATUS_OUT"
    seed "$SRC_DIR/layers/status/README.md" "$STATUS_OUT/README.md"
    # The container README describes the project/ workspace (tasks + status).
    # Only emit it when the tasks mount actually sits inside a container dir;
    # at the repo root there is no container to document (and writing the repo's
    # own README.md would clobber it).
    if [[ "$CONTAINER_REL" != "." ]]; then
        seed "$SRC_DIR/layers/status/container-README.md" "$TARGET/$CONTAINER_REL/README.md"
    else
        echo "Note: --with-status at the repo root emits '$STATUS_REL/' but no"
        echo "      container README (there is no project/ dir to document)."
    fi
fi

if [[ "$WITH_SKILL" == true ]]; then
    SKILL_OUT="$TARGET/.claude/skills/task-system"
    mkdir -p "$SKILL_OUT"
    render "$SRC_DIR/skill/task-system/SKILL.md" "$SKILL_OUT/SKILL.md"
    updated+=(".claude/skills/task-system/SKILL.md  (on-demand skill)")
fi

# ---------------------------------------------------------------------------
# 3. CONTENT — starter epic (created only if missing)
# ---------------------------------------------------------------------------
if [[ -d "$MOUNT/$EPIC" ]]; then
    skipped+=("$TASKS_DIR/$EPIC/  (epic exists — task content preserved)")
else
    ( cd "$TARGET" && "$SCRIPTS_OUT/new-epic.sh" --name "$EPIC" >/dev/null )
    created+=("$TASKS_DIR/$EPIC/{inbox,draft,backlog,in-progress,complete,wont-do}/")
fi

# ---------------------------------------------------------------------------
# 4. CLAUDE.md kernel snippet
# ---------------------------------------------------------------------------
# The snippet carries its own <!-- task-system:begin/end --> markers, so the
# injected block is locatable and refreshable. On --inject-claude-md we REPLACE
# in place when the begin marker is already present (updatable, never duplicated),
# and APPEND otherwise. Same begin/end-marker convention as
# project-status/setup-new-repo.sh.
CM_BEGIN="<!-- task-system:begin -->"
CM_END="<!-- task-system:end -->"
SNIPPET="$(render "$SRC_DIR/snippets/claude-md.snippet.md" /dev/stdout)"
if [[ "$INJECT_CLAUDE_MD" == true ]]; then
    CMD_FILE="$TARGET/CLAUDE.md"
    if [[ -f "$CMD_FILE" ]] && grep -qF "$CM_BEGIN" "$CMD_FILE"; then
        # Replace everything between begin/end (inclusive) with the current snippet.
        # Python, not sed/awk: the multi-line replacement is passed safely via a
        # file, and BSD awk chokes on newlines in -v (see setup-new-repo.sh).
        printf '%s\n' "$SNIPPET" > "$MOUNT/.claude-md-snippet.tmp"
        python3 - "$CMD_FILE" "$MOUNT/.claude-md-snippet.tmp" "$CM_BEGIN" "$CM_END" <<'PY'
import sys, pathlib
claude_path, repl_path, begin, end = sys.argv[1:5]
repl = pathlib.Path(repl_path).read_text().rstrip("\n")
out, in_block, printed = [], False, False
for line in pathlib.Path(claude_path).read_text().splitlines():
    if line == begin:
        in_block = True
        if not printed:
            out.append(repl)   # the snippet already includes begin+end markers
            printed = True
        continue
    if line == end:
        in_block = False
        continue
    if not in_block:
        out.append(line)
pathlib.Path(claude_path).write_text("\n".join(out) + "\n")
PY
        rm -f "$MOUNT/.claude-md-snippet.tmp"
        updated+=("CLAUDE.md  (task-tracking block refreshed in place)")
    else
        printf '\n%s\n' "$SNIPPET" >> "$CMD_FILE"
        updated+=("CLAUDE.md  (task-tracking block appended)")
    fi
fi

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
echo "Created:"; for i in "${created[@]:-}";  do [[ -n "$i" ]] && echo "  + $i"; done
echo "Written:"; for i in "${updated[@]:-}";  do [[ -n "$i" ]] && echo "  ~ $i"; done
if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "Preserved:"; for i in "${skipped[@]:-}"; do [[ -n "$i" ]] && echo "  = $i"; done
fi

echo ""
echo "Layers: worktrees=$WITH_WORKTREES projects=$WITH_PROJECTS status=$WITH_STATUS guard=$WITH_GUARD skill=$WITH_SKILL"
echo ""
echo "Next:"
echo "  $TASKS_DIR/scripts/new-user-task.sh --folder draft --name my-first-task"
echo "  $TASKS_DIR/scripts/list-tasks.sh --folder draft --depth 2"
echo "  Docs: $TASKS_DIR/docs/USING.md"
if [[ "$WITH_STATUS" == true ]]; then
    echo "  Status reports: $STATUS_REL/  (workflow in $TASKS_DIR/docs/USING.md)"
fi
if [[ "$WITH_GUARD" == true ]]; then
    echo ""
    echo "  Worktree guard — note the first argument is the EPIC dir, not the mount:"
    echo "    python3 $TASKS_DIR/scripts/check-task-complete.py $TASKS_DIR/$EPIC <branch>"
fi
if [[ "$INJECT_CLAUDE_MD" != true ]]; then
    echo ""
    echo "--- add this to the target's CLAUDE.md (or GEMINI.md — it is agent-neutral) ---"
    echo "$SNIPPET"
    echo "--- end snippet ---"
fi
