#!/usr/bin/env bash
# Mark a subtask as wont-do.
#
# Sets Status to 'wont-do' in the subtask's README and removes its entry
# from the parent README's subtask list. The subtask directory is kept in
# place for reference.
#
# Usage:
#   wont-do-subtask.sh --epic <epic> --folder <status> --parent <task> --name <subtask>
#
# Examples:
#   wont-do-subtask.sh --epic main --folder in-progress --parent my-task --name my-subtask

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

if [[ -z "$FOLDER" || -z "$PARENT" || -z "$NAME" ]]; then
    echo "Usage: wont-do-subtask.sh --folder <status> --parent <task> --name <subtask> [--epic <epic>]"
    exit 1
fi

PARENT_DIR="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT"
PARENT_README="$PARENT_DIR/README.md"

if [[ ! -f "$PARENT_README" ]]; then
    echo "Parent task not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT"
    exit 1
fi

SUBTASK_DIR="$(resolve_subtask_dir "$PARENT_DIR" "$NAME")"
if [[ -z "$SUBTASK_DIR" ]]; then
    echo "Subtask not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$NAME"
    exit 1
fi
SUBTASK_README="$SUBTASK_DIR/README.md"

# ---------------------------------------------------------------------------
# Set Status to wont-do in subtask README
# ---------------------------------------------------------------------------

_sed_i "s/| Status *|[^|]*|/| Status | wont-do |/" "$SUBTASK_README"

# ---------------------------------------------------------------------------
# Remove entry from parent README subtask list (any format, any check state)
# ---------------------------------------------------------------------------

# Linked format: - [ ] [NAME](NAME/)  or  - [x] [X-NAME](X-NAME/)
_sed_i "/- \[.\] \[$NAME\]($NAME\/)/d" "$PARENT_README"
_sed_i "/- \[.\] \[X-$NAME\](X-$NAME\/)/d" "$PARENT_README"
# Plain format:   - [ ] NAME  or  - [x] X-NAME
_sed_i "/- \[.\] $NAME$/d" "$PARENT_README"
_sed_i "/- \[.\] X-$NAME$/d" "$PARENT_README"

echo "Marked wont-do: $NAME"
echo "Updated:        $PARENT_README"
