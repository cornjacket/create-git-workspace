#!/usr/bin/env bash
# rename-subtask.sh — rename a subtask's NNNN position ID.
#
# Renames the subtask directory and updates the parent README's subtask list.
# Also bumps Next-subtask-id in the parent if the new ID equals or exceeds
# the current value.
#
# Usage:
#   rename-subtask.sh --epic <epic> --folder <status> --parent <task> --name <subtask> --new-id NNNN
#
# Arguments:
#   --name      Full subtask directory name, e.g. a3f2c1-0003-my-sub
#               (without the X- prefix; script resolves completed tasks too)
#   --new-id    Target 4-digit position, e.g. 0005
#
# Example:
#   rename-subtask.sh --epic main --folder in-progress --parent my-task \
#       --name a3f2c1-0003-my-sub --new-id 0005

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
NEW_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)    EPIC="$2";   shift 2 ;;
        --folder)  FOLDER="$2"; shift 2 ;;
        --parent)  PARENT="$2"; shift 2 ;;
        --name)    NAME="$2";   shift 2 ;;
        --new-id)  NEW_ID="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$PARENT" || -z "$NAME" || -z "$NEW_ID" ]]; then
    echo "Usage: rename-subtask.sh --folder <status> --parent <task> --name <subtask> --new-id NNNN [--epic <epic>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

PARENT_DIR="$TASKS_ROOT/$EPIC/$FOLDER/$PARENT"
PARENT_README="$PARENT_DIR/README.md"

if [[ ! -d "$PARENT_DIR" ]]; then
    echo "Parent directory not found: $PARENT_DIR"
    exit 1
fi

# Resolve subtask directory (handles X- completion prefix)
OLD_DIR=$(resolve_subtask_dir "$PARENT_DIR" "$NAME")
if [[ -z "$OLD_DIR" ]]; then
    echo "ERROR: Subtask not found: $NAME (nor X-$NAME) under $PARENT_DIR"
    exit 1
fi
OLD_DIRNAME="$(basename "$OLD_DIR")"

# ---------------------------------------------------------------------------
# Parse old dirname: (X-)?HHHHHH-NNNN-name
# ---------------------------------------------------------------------------

if [[ "$OLD_DIRNAME" =~ ^(X-)?([0-9a-f]{6})-([0-9]{4})-(.+)$ ]]; then
    X_PREFIX="${BASH_REMATCH[1]}"
    PARENT_SHORT_ID="${BASH_REMATCH[2]}"
    OLD_ID="${BASH_REMATCH[3]}"
    SUBTASK_NAME="${BASH_REMATCH[4]}"
else
    echo "ERROR: Cannot parse subtask directory name: $OLD_DIRNAME"
    exit 1
fi

# Zero-pad new ID to 4 digits
NEW_ID_PADDED="$(printf '%04d' "$(( 10#$NEW_ID ))")"
NEW_DIRNAME="${X_PREFIX}${PARENT_SHORT_ID}-${NEW_ID_PADDED}-${SUBTASK_NAME}"

if [[ "$OLD_DIRNAME" == "$NEW_DIRNAME" ]]; then
    echo "No change needed — subtask is already named $OLD_DIRNAME"
    exit 0
fi

NEW_DIR="$PARENT_DIR/$NEW_DIRNAME"
if [[ -d "$NEW_DIR" ]]; then
    echo "ERROR: Target directory already exists: $NEW_DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Rename directory and update references
# ---------------------------------------------------------------------------

mv "$OLD_DIR" "$NEW_DIR"
echo "Renamed: $OLD_DIRNAME"
echo "     to: $NEW_DIRNAME"

# Update parent README subtask list
_sed_i "s|$OLD_DIRNAME|$NEW_DIRNAME|g" "$PARENT_README"
echo "Updated: $(basename "$PARENT_README") (subtask list)"

# ---------------------------------------------------------------------------
# Bump Next-subtask-id if new position equals or exceeds current value
# ---------------------------------------------------------------------------

CURRENT_NEXT="$(get_next_subtask_id "$PARENT_README")"
if [[ -n "$CURRENT_NEXT" ]] && (( 10#$NEW_ID_PADDED >= 10#$CURRENT_NEXT )); then
    NEW_NEXT="$(printf '%04d' $(( 10#$NEW_ID_PADDED + 1 )))"
    _sed_i "s/| Next-subtask-id *|[^|]*|/| Next-subtask-id | $NEW_NEXT |/" "$PARENT_README"
    echo "Bumped Next-subtask-id: $CURRENT_NEXT → $NEW_NEXT"
fi

echo ""
echo "Done."
