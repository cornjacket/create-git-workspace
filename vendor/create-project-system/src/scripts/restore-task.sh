#!/usr/bin/env bash
# Restore a soft-deleted task or subtask.
#
# Reverses delete-task.sh:
# - Renames .<name> back to <name>.
# - Re-inserts the entry into the parent directory's README.md.
#
# Usage:
#   restore-task.sh --epic <epic> --folder <status> --name <task>
#   restore-task.sh --epic <epic> --folder <status> --parent <task> --name <subtask>
#
# Examples:
#   restore-task.sh --epic main --folder draft --name my-task
#   restore-task.sh --epic main --folder in-progress --parent my-task --name my-subtask

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
# shellcheck source=task-id-helpers.sh
source "$SCRIPTS_DIR/task-id-helpers.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
FOLDER=""
PARENT=""
NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)   EPIC="$2";   shift 2 ;;
        --folder) FOLDER="$2"; shift 2 ;;
        --parent) PARENT="$2"; shift 2 ;;
        --name)   NAME="$2";   shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$NAME" ]]; then
    echo "Usage: restore-task.sh --folder <status> --name <task> [--epic <epic>] [--parent <parent-task>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

STATUS_DIR="$TASKS_ROOT/$EPIC/$FOLDER"

if [[ -n "$PARENT" ]]; then
    PARENT_DIR="$STATUS_DIR/$PARENT"
else
    PARENT_DIR="$STATUS_DIR"
fi

TASK_DIR="$PARENT_DIR/$NAME"
HIDDEN_DIR="$PARENT_DIR/.$NAME"
PARENT_README="$PARENT_DIR/README.md"

if [[ ! -d "$HIDDEN_DIR" ]]; then
    echo "Hidden task not found: $HIDDEN_DIR"
    exit 1
fi

if [[ -d "$TASK_DIR" ]]; then
    echo "Task directory already exists (not hidden): $TASK_DIR"
    exit 1
fi

if [[ ! -f "$PARENT_README" ]]; then
    echo "Parent README not found: $PARENT_README"
    exit 1
fi

# ---------------------------------------------------------------------------
# Rename directory back to visible
# ---------------------------------------------------------------------------

mv "$HIDDEN_DIR" "$TASK_DIR"

# ---------------------------------------------------------------------------
# Re-insert entry into parent README
# ---------------------------------------------------------------------------

# Use whichever marker is present. Subtask lists get a checkbox entry;
# task lists get a plain link entry.
if grep -q "<!-- subtask-list-end -->" "$PARENT_README"; then
    _sed_i "s|<!-- subtask-list-end -->|- [ ] [$NAME]($NAME/)\n<!-- subtask-list-end -->|" "$PARENT_README"
elif grep -q "<!-- task-list-end -->" "$PARENT_README"; then
    _sed_i "s|<!-- task-list-end -->|- [$NAME]($NAME/)\n<!-- task-list-end -->|" "$PARENT_README"
else
    echo "Warning: no task list markers found in $PARENT_README — add the entry manually."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

if [[ -n "$PARENT" ]]; then
    echo "Restored subtask: $TASKS_REL/$EPIC/$FOLDER/$PARENT/.$NAME/ → $NAME/"
else
    echo "Restored task:    $TASKS_REL/$EPIC/$FOLDER/.$NAME/ → $NAME/"
fi
echo "Updated:         $PARENT_README"
