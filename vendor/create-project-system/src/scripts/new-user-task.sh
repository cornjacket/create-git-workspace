#!/usr/bin/env bash
# Create a new top-level user-task directory with a user-task-template README.md.
# Updates the status folder's README.md task list.
#
# Usage:
#   new-user-task.sh --epic <epic> --folder <status> --name <task-name> [--worktree <name>] [--id HEX] [--tags <tags>] [--priority <p>]
#
# --worktree NAME  Optional. The worktree this task belongs to — which files it
#                  touches, so unrelated work can run in parallel branches. This
#                  is about isolation, NOT topic: to group tasks by subject
#                  matter, use --tags. When a worktrees.md exists at the root of
#                  the task subsystem, the value must be a branch name listed in
#                  it, or the literal `unclassified` if none fits; run with an
#                  unknown value to see the list of valid options. When
#                  worktrees.md is absent, the value is accepted as-is. Omitted
#                  entirely, the Worktree field is left as `—`.
#
#                  `--category` is a deprecated alias, kept so existing callers
#                  keep working; it warns and behaves identically.
#
# --id HEX  Use the given 6-char hex string as the task ID instead of generating
#           a random one. Intended for replay regression tests that need to
#           reproduce the exact task directory names from a prior recording.
#
# Priority values: CRITICAL, HIGH, MED, LOW (default: —)
#
# Examples:
#   new-user-task.sh --epic main --folder draft --name my-feature --worktree task-tooling
#   new-user-task.sh --epic main --folder in-progress --name my-feature --worktree docs --priority HIGH
#   new-user-task.sh --epic main --folder in-progress --name my-feature --worktree unclassified --id 61857e

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
# shellcheck source=task-id-helpers.sh
source "$SCRIPTS_DIR/task-id-helpers.sh"
TASK_TEMPLATE="$SCRIPTS_DIR/user-task-template.md"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
FOLDER=""
NAME=""
TAGS="—"
PRIORITY="—"
WORKTREE=""
FIXED_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)     EPIC="$2";     shift 2 ;;
        --folder)   FOLDER="$2";   shift 2 ;;
        --name)     NAME="$2";     shift 2 ;;
        --id)       FIXED_ID="$2"; shift 2 ;;
        --tags)     TAGS="$2";     shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --worktree) WORKTREE="$2"; shift 2 ;;
        # Deprecated alias — the field was called Category before it was named
        # for what it actually selects. Warns, then behaves identically.
        --category)
            echo "Warning: --category is deprecated; use --worktree." >&2
            WORKTREE="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$NAME" ]]; then
    echo "Usage: new-user-task.sh --folder <status> --name <task-name> [--worktree <name>] [--epic <epic>] [--id HEX] [--tags <tags>] [--priority <CRITICAL|HIGH|MED|LOW>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate --worktree against the worktree branches declared in worktrees.md.
#
# The worktrees layer is optional: with no worktrees.md the value is accepted
# as-is. Repos generated before the Category -> Worktree rename still carry the
# file under its old name, so fall back to classes.md — that file is CONTENT,
# which the generator never rewrites, so the fallback is permanent.
# ---------------------------------------------------------------------------

WORKTREES_FILE="$TASKS_ROOT/worktrees.md"
[[ -f "$WORKTREES_FILE" ]] || WORKTREES_FILE="$TASKS_ROOT/classes.md"

if [[ -n "$WORKTREE" && -f "$WORKTREES_FILE" ]]; then
    # Extract branch names from `**Worktree branch:** \`name\`` lines.
    VALID_WORKTREES="$(grep -oE '^\*\*Worktree branch:\*\* `[^`]+`' "$WORKTREES_FILE" \
        | sed 's/^\*\*Worktree branch:\*\* `\([^`]*\)`/\1/')"

    if [[ -z "$VALID_WORKTREES" ]]; then
        echo "Error: no worktree branches found in $WORKTREES_FILE." >&2
        exit 1
    fi

    # `unclassified` is always permitted (for tasks that fit no worktree).
    if [[ "$WORKTREE" != "unclassified" ]] \
       && ! grep -qxF "$WORKTREE" <<< "$VALID_WORKTREES"; then
        {
            echo "Error: unknown --worktree value: '$WORKTREE'"
            echo "Valid values (from $WORKTREES_FILE):"
            sed 's/^/  /' <<< "$VALID_WORKTREES"
            echo "  unclassified"
            echo ""
            echo "Note: --worktree selects which files a task touches, so unrelated"
            echo "      work can run in parallel branches. To group tasks by subject"
            echo "      matter instead, use --tags."
        } >&2
        exit 1
    fi
fi

# No --worktree supplied: leave the Worktree field unset.
if [[ -z "$WORKTREE" ]]; then
    WORKTREE="—"
fi

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

STATUS_DIR="$TASKS_ROOT/$EPIC/$FOLDER"

if [[ ! -d "$STATUS_DIR" ]]; then
    echo "Status directory not found: $STATUS_DIR"
    exit 1
fi

STATUS="$FOLDER"
CREATED="$(date +%Y-%m-%d)"

# Generate a short unique ID and build the directory name
if [[ -n "$FIXED_ID" ]]; then
    ID="$FIXED_ID"
else
    ID="$(openssl rand -hex 3)"
fi
DIRNAME="$ID-$NAME"

TASK_DIR="$STATUS_DIR/$DIRNAME"
PARENT_README="$STATUS_DIR/README.md"

# ---------------------------------------------------------------------------
# Create task directory and README
# ---------------------------------------------------------------------------

mkdir -p "$TASK_DIR"

sed \
    -e "s/{{NAME}}/$NAME/g" \
    -e "s/{{STATUS}}/$STATUS/g" \
    -e "s/{{EPIC}}/$EPIC/g" \
    -e "s/{{TAGS}}/$TAGS/g" \
    -e "s/{{PRIORITY}}/$PRIORITY/g" \
    -e "s/{{WORKTREE}}/$WORKTREE/g" \
    -e "s/{{CREATED}}/$CREATED/g" \
    "$TASK_TEMPLATE" > "$TASK_DIR/README.md"

# ---------------------------------------------------------------------------
# Create parent README if it doesn't exist (status directory case)
# ---------------------------------------------------------------------------

if [[ ! -f "$PARENT_README" ]]; then
    cat > "$PARENT_README" << EOF
# $EPIC / $FOLDER

## Tasks

<!-- When a task is finished, run move-task.sh --to complete before moving on. -->
<!-- task-list-start -->
<!-- task-list-end -->
EOF
fi

# ---------------------------------------------------------------------------
# Append to parent README
# ---------------------------------------------------------------------------

if grep -q "<!-- task-list-end -->" "$PARENT_README"; then
    _sed_i "s|<!-- task-list-end -->|- [$DIRNAME]($DIRNAME/)\n<!-- task-list-end -->|" "$PARENT_README"
else
    echo "Warning: no task list markers found in $PARENT_README — add the entry manually."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo "Created user-task: $TASKS_REL/$EPIC/$FOLDER/$DIRNAME/"
echo "Updated:           $PARENT_README"
