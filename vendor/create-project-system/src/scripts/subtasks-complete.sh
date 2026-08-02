#!/usr/bin/env bash
# Check whether all subtasks of a parent task are marked complete.
#
# Reads the subtask list from the parent's task.json.
#
# Usage:
#   subtasks-complete.sh --epic <epic> --folder <status> --parent <parent-task>
#
# Exit codes:
#   0 — all subtasks complete (or no subtasks exist)
#   1 — one or more subtasks remain incomplete
#
# Example:
#   subtasks-complete.sh --epic main --folder in-progress --parent abc123-my-task
#   if subtasks-complete.sh ...; then echo "all done"; fi

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
# shellcheck source=task-json-helpers.sh
source "$SCRIPTS_DIR/task-json-helpers.sh"

EPIC="$DEFAULT_EPIC"
FOLDER=""
PARENT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)   EPIC="$2";   shift 2 ;;
        --folder) FOLDER="$2"; shift 2 ;;
        --parent) PARENT="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$PARENT" ]]; then
    echo "Usage: subtasks-complete.sh --epic <epic> --folder <status> --parent <parent-task>"
    exit 1
fi

PARENT_DIR="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT"
PARENT_JSON="$PARENT_DIR/task.json"

if [[ ! -f "$PARENT_JSON" ]]; then
    echo "Parent task.json not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT"
    exit 1
fi

json_subtasks_complete "$PARENT_JSON"
