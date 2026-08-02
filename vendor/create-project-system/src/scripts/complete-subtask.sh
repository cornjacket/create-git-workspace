#!/usr/bin/env bash
# Mark a subtask as complete or incomplete.
#
# Complete: updates [ ] → [x] in parent README, sets Status to 'complete'
#           in the subtask's own README.
# Undo:     updates [x] → [ ] in parent README, restores Status to the
#           folder name in the subtask's own README.
#
# Usage:
#   complete-subtask.sh --epic <epic> --folder <status> --parent <task> --name <subtask>
#   complete-subtask.sh --epic <epic> --folder <status> --parent <task> --name <subtask> --undo
#
# Examples:
#   complete-subtask.sh --epic main --folder in-progress --parent my-task --name my-subtask
#   complete-subtask.sh --epic main --folder in-progress --parent my-task --name my-subtask --undo

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
UNDO=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)   EPIC="$2";   shift 2 ;;
        --folder) FOLDER="$2"; shift 2 ;;
        --parent) PARENT="$2"; shift 2 ;;
        --name)   NAME="$2";   shift 2 ;;
        --undo)   UNDO=true;   shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$PARENT" || -z "$NAME" ]]; then
    echo "Usage: complete-subtask.sh --folder <status> --parent <task> --name <subtask> [--epic <epic>] [--undo]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

PARENT_README="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT/README.md"
SUBTASK_README="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT/$NAME/README.md"

if [[ ! -f "$PARENT_README" ]]; then
    echo "Parent task not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT"
    exit 1
fi

if [[ ! -f "$SUBTASK_README" ]]; then
    echo "Subtask not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$NAME"
    exit 1
fi

# ---------------------------------------------------------------------------
# Update parent README checkbox and subtask README status
# ---------------------------------------------------------------------------

if [[ "$UNDO" == true ]]; then
    # [x] → [ ]
    if ! grep -q "\- \[x\] \[$NAME\]" "$PARENT_README"; then
        echo "Subtask '$NAME' is not marked complete in $PARENT_README"
        exit 1
    fi
    _sed_i "s|- \[x\] \[$NAME\](\(.*\))|- [ ] [$NAME](\1)|" "$PARENT_README"
    # Restore status to folder name
    _sed_i "s/| Status *|[^|]*|/| Status | $FOLDER |/" "$SUBTASK_README"
    echo "Marked incomplete: $NAME"
else
    # [ ] → [x]
    if ! grep -q "\- \[ \] \[$NAME\]" "$PARENT_README"; then
        echo "Subtask '$NAME' not found or already complete in $PARENT_README"
        exit 1
    fi
    _sed_i "s|- \[ \] \[$NAME\](\(.*\))|- [x] [$NAME](\1)|" "$PARENT_README"
    # Update status to complete
    _sed_i "s/| Status *|[^|]*|/| Status | complete |/" "$SUBTASK_README"
    echo "Marked complete: $NAME"
fi
