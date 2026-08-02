#!/usr/bin/env bash
# Print the absolute path of the next incomplete subtask README under a
# given parent task, or exit 1 if all subtasks are complete.
#
# Reads the subtask list from the parent's task.json.
#
# Usage:
#   next-subtask.sh --epic <epic> --folder <status> --parent <parent-id-name>
#
# Exit codes:
#   0 — next incomplete subtask found; path printed to stdout
#   1 — all subtasks complete (or no subtasks)

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
# shellcheck source=task-json-helpers.sh
source "$SCRIPTS_DIR/task-json-helpers.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
FOLDER=""
PARENT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)   EPIC="$2";   shift 2 ;;
        --folder) FOLDER="$2"; shift 2 ;;
        --parent) PARENT="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$PARENT" ]]; then
    echo "Usage: next-subtask.sh --folder <status> --parent <parent-id-name> [--epic <epic>]" >&2
    exit 1
fi

PARENT_DIR="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT"
PARENT_JSON="$PARENT_DIR/task.json"

if [[ ! -f "$PARENT_JSON" ]]; then
    echo "Parent task.json not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Find first incomplete subtask
# ---------------------------------------------------------------------------

NEXT_NAME="$(json_next_subtask "$PARENT_JSON")" || exit 1

if [[ -z "$NEXT_NAME" ]]; then
    exit 1
fi

SUBTASK_README="$PARENT_DIR/$NEXT_NAME/README.md"

if [[ ! -f "$SUBTASK_README" ]]; then
    echo "Subtask directory not found: $NEXT_NAME" >&2
    exit 1
fi

echo "$SUBTASK_README"
