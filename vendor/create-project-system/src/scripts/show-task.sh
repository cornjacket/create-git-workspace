#!/usr/bin/env bash
# Print a task's README.md to stdout.
#
# Usage:
#   show-task.sh --epic <epic> --folder <status> --name <task>
#   show-task.sh --epic <epic> --folder <status> --parent <task> --name <subtask>
#
# Examples:
#   show-task.sh --epic main --folder in-progress --name my-task
#   show-task.sh --epic main --folder in-progress --parent my-task --name my-subtask

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
    echo "Usage: show-task.sh --folder <status> --name <task> [--epic <epic>] [--parent <parent-task>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve path
# ---------------------------------------------------------------------------

STATUS_DIR="$TASKS_ROOT/$EPIC/$FOLDER"

if [[ -n "$PARENT" ]]; then
    TASK_DIR="$(resolve_subtask_dir "$STATUS_DIR/$PARENT" "$NAME")"
    if [[ -z "$TASK_DIR" ]]; then
        echo "Task not found: $STATUS_DIR/$PARENT/$NAME"
        exit 1
    fi
    README="$TASK_DIR/README.md"
else
    README="$STATUS_DIR/$NAME/README.md"
fi

if [[ ! -f "$README" ]]; then
    echo "Task not found: $README"
    exit 1
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

cat "$README"
