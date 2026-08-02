#!/usr/bin/env bash
# Move a task (and all its subtasks) to a different status directory.
# Updates the source and destination status READMEs and the task's own README.
#
# Usage:
#   move-task.sh --epic <epic> --name <task> --from <status> --to <status>
#
# Example:
#   move-task.sh --epic main --name create-project-management-system \
#       --from draft --to backlog

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
# shellcheck source=task-json-helpers.sh
source "$SCRIPTS_DIR/task-json-helpers.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
NAME=""
FROM=""
TO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic) EPIC="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --from) FROM="$2"; shift 2 ;;
        --to)   TO="$2";   shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$NAME" || -z "$FROM" || -z "$TO" ]]; then
    echo "Usage: move-task.sh --name <task> --from <status> --to <status> [--epic <epic>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SRC_DIR="$TASKS_ROOT/$EPIC/$FROM/$NAME"
DST_DIR="$TASKS_ROOT/$EPIC/$TO/$NAME"
SRC_README="$TASKS_ROOT/$EPIC/$FROM/README.md"
DST_STATUS_DIR="$TASKS_ROOT/$EPIC/$TO"
DST_README="$DST_STATUS_DIR/README.md"
TASK_README="$DST_DIR/README.md"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Task not found: $TASKS_REL/$EPIC/$FROM/$NAME"
    exit 1
fi

if [[ -d "$DST_DIR" ]]; then
    echo "Task already exists at destination: $TASKS_REL/$EPIC/$TO/$NAME"
    exit 1
fi

# ---------------------------------------------------------------------------
# Move the task directory
# ---------------------------------------------------------------------------

mkdir -p "$DST_STATUS_DIR"
mv "$SRC_DIR" "$DST_DIR"

# ---------------------------------------------------------------------------
# Update task README: change Status field (user tasks only — prose-only
# pipeline task READMEs have no metadata table so the sed is a no-op)
# ---------------------------------------------------------------------------

_sed_i "s/| Status *|[^|]*|/| Status | $TO |/" "$TASK_README"

# For pipeline tasks, status lives in task.json
if is_pipeline_task "$DST_DIR"; then
    json_set_str "$DST_DIR/task.json" "status" "$TO"
fi

# ---------------------------------------------------------------------------
# Remove task from source status README
# ---------------------------------------------------------------------------

if [[ -f "$SRC_README" ]]; then
    _sed_i "/^\- \[$NAME\]/d" "$SRC_README"
fi

# ---------------------------------------------------------------------------
# Add task to destination status README (create if needed)
# ---------------------------------------------------------------------------

if [[ ! -f "$DST_README" ]]; then
    cat > "$DST_README" << EOF
# $EPIC / $TO

## Tasks

<!-- task-list-start -->
<!-- task-list-end -->
EOF
fi

_sed_i "s|<!-- task-list-end -->|- [$NAME]($NAME/)\n<!-- task-list-end -->|" "$DST_README"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo "Moved: $TASKS_REL/$EPIC/$FROM/$NAME"
echo "   ->  $TASKS_REL/$EPIC/$TO/$NAME"
