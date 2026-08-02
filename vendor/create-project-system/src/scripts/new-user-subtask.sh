#!/usr/bin/env bash
# Create a new user-subtask directory with a user-subtask-template README.md.
# Updates the parent task's README.md subtask list.
#
# Usage:
#   new-user-subtask.sh --epic <epic> --folder <status> --parent <task> --name <name> [--tags <tags>] [--priority <p>]
#
# Priority values: CRITICAL, HIGH, MED, LOW (default: —)
#
# Examples:
#   new-user-subtask.sh --epic main --folder in-progress --parent my-task --name my-review
#   new-user-subtask.sh --epic main --folder draft --parent my-task --name planning-step --priority HIGH

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
TASK_TEMPLATE="$SCRIPTS_DIR/user-subtask-template.md"
# shellcheck source=task-id-helpers.sh
source "$SCRIPTS_DIR/task-id-helpers.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
FOLDER=""
PARENT=""
NAME=""
TAGS="—"
PRIORITY="—"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)     EPIC="$2";     shift 2 ;;
        --folder)   FOLDER="$2";   shift 2 ;;
        --parent)   PARENT="$2";   shift 2 ;;
        --name)     NAME="$2";     shift 2 ;;
        --tags)     TAGS="$2";     shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$PARENT" || -z "$NAME" ]]; then
    echo "Usage: new-user-subtask.sh --folder <status> --parent <task> --name <name> [--epic <epic>] [--tags <tags>] [--priority <CRITICAL|HIGH|MED|LOW>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

PARENT_DIR="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT"

if [[ ! -d "$PARENT_DIR" ]]; then
    echo "Parent directory not found: $PARENT_DIR"
    exit 1
fi

# Derive incremental ID from parent
PARENT_README="$PARENT_DIR/README.md"
PARENT_SHORT_ID="$(get_parent_short_id "$PARENT_DIR")"
NEXT_ID="$(get_next_subtask_id "$PARENT_README")"
# Default to 0000 and add the field if the parent predates the Next-subtask-id convention
if [[ -z "$NEXT_ID" ]]; then
    NEXT_ID="0000"
    _sed_i "s/| Priority *|[^|]*|/&\n| Next-subtask-id | 0000               |/" "$PARENT_README"
fi
DIRNAME="$PARENT_SHORT_ID-$NEXT_ID-$NAME"
CREATED="$(date +%Y-%m-%d)"

TASK_DIR="$PARENT_DIR/$DIRNAME"

# ---------------------------------------------------------------------------
# Create subtask directory and README
# ---------------------------------------------------------------------------

mkdir -p "$TASK_DIR"

sed \
    -e "s/{{NAME}}/$NAME/g" \
    -e "s/{{EPIC}}/$EPIC/g" \
    -e "s/{{TAGS}}/$TAGS/g" \
    -e "s|{{PARENT}}|$PARENT|g" \
    -e "s/{{PRIORITY}}/$PRIORITY/g" \
    -e "s/{{CREATED}}/$CREATED/g" \
    "$TASK_TEMPLATE" > "$TASK_DIR/README.md"

# ---------------------------------------------------------------------------
# Append to parent README subtask list
# ---------------------------------------------------------------------------

if grep -q "<!-- subtask-list-end -->" "$PARENT_README"; then
    _sed_i "s|<!-- subtask-list-end -->|- [ ] [$DIRNAME]($DIRNAME/)\n<!-- subtask-list-end -->|" "$PARENT_README"
else
    echo "Warning: no subtask list markers found in $PARENT_README — add the entry manually."
fi

# Increment Next-subtask-id in parent
increment_subtask_id "$PARENT_README"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo "Created user-subtask: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$DIRNAME/"
echo "Updated:              $PARENT_README"
