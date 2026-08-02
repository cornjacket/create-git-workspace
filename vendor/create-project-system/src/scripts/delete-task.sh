#!/usr/bin/env bash
# Soft-delete a task or subtask.
#
# - Removes the entry from the parent directory's README.md.
# - Renames the task directory to .<name> (hidden, but not destroyed).
#
# Works for both top-level tasks and subtasks — the parent is always the
# containing directory, the same convention used by new-task.sh.
#
# Usage:
#   delete-task.sh --epic <epic> --folder <status> --name <task>
#   delete-task.sh --epic <epic> --folder <status> --parent <task> --name <subtask>
#
# Examples:
#   delete-task.sh --epic main --folder draft --name my-task
#   delete-task.sh --epic main --folder in-progress --parent my-task --name my-subtask

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
    echo "Usage: delete-task.sh --folder <status> --name <task> [--epic <epic>] [--parent <parent-task>]"
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

PARENT_README="$PARENT_DIR/README.md"

# Resolve actual directory name (may have X- prefix if already completed)
if [[ -n "$PARENT" ]]; then
    RESOLVED_DIR="$(resolve_subtask_dir "$PARENT_DIR" "$NAME")"
    if [[ -z "$RESOLVED_DIR" ]]; then
        echo "Task not found: $PARENT_DIR/$NAME"
        exit 1
    fi
else
    RESOLVED_DIR="$PARENT_DIR/$NAME"
    if [[ ! -d "$RESOLVED_DIR" ]]; then
        echo "Task not found: $RESOLVED_DIR"
        exit 1
    fi
fi

TASK_DIR="$RESOLVED_DIR"
ACTUAL_NAME="$(basename "$TASK_DIR")"
HIDDEN_DIR="$PARENT_DIR/.$ACTUAL_NAME"

if [[ ! -f "$PARENT_README" ]]; then
    echo "Parent README not found: $PARENT_README"
    exit 1
fi

if [[ -d "$HIDDEN_DIR" ]]; then
    echo "Hidden directory already exists: $HIDDEN_DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Remove entry from parent README
# ---------------------------------------------------------------------------

# Remove entry from parent README — match by original name or X-prefixed name
if grep -q "\[$NAME\]" "$PARENT_README"; then
    _sed_i "/\[$NAME\]/d" "$PARENT_README"
elif grep -q "\[X-$NAME\]" "$PARENT_README"; then
    _sed_i "/\[X-$NAME\]/d" "$PARENT_README"
else
    echo "Warning: no entry for '$NAME' found in $PARENT_README — skipping README update."
fi

# ---------------------------------------------------------------------------
# Rename directory to hidden
# ---------------------------------------------------------------------------

mv "$TASK_DIR" "$HIDDEN_DIR"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

if [[ -n "$PARENT" ]]; then
    echo "Deleted subtask: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$ACTUAL_NAME/ → .$ACTUAL_NAME/"
else
    echo "Deleted task:    $TASKS_REL/$EPIC/$FOLDER/$ACTUAL_NAME/ → .$ACTUAL_NAME/"
fi
echo "Updated:         $PARENT_README"
