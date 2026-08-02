#!/usr/bin/env bash
# Mark a task or subtask as complete (or undo a completion).
#
# Top-level task (no --parent):
#   Moves the task directory from <folder> to complete/, updates the source
#   status README and the task's own Status field.
#   --undo moves it back from complete/ to <folder>.
#
# Subtask (with --parent):
#   Pipeline subtask (parent has task.json):
#     Renames dir to X-<name>, updates parent task.json subtask entry,
#     updates child task.json status. Does NOT modify any README.
#   User subtask (parent has no task.json):
#     Updates [ ] → [x] in the parent README and sets Status to 'complete'
#     in the subtask's own README.
#   --undo reverses the respective changes.
#
# Usage:
#   complete-task.sh --epic <epic> --folder <status> --name <task>
#   complete-task.sh --epic <epic> --folder <status> --name <task> --undo
#   complete-task.sh --epic <epic> --folder <status> --parent <task> --name <subtask>
#   complete-task.sh --epic <epic> --folder <status> --parent <task> --name <subtask> --undo
#
# Examples:
#   complete-task.sh --epic main --folder in-progress --name my-task
#   complete-task.sh --epic main --folder in-progress --name my-task --undo
#   complete-task.sh --epic main --folder in-progress --parent my-task --name my-subtask
#   complete-task.sh --epic main --folder in-progress --parent my-task --name my-subtask --undo

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"
# shellcheck source=task-id-helpers.sh
source "$SCRIPTS_DIR/task-id-helpers.sh"
# shellcheck source=task-json-helpers.sh
source "$SCRIPTS_DIR/task-json-helpers.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
FOLDER=""
PARENT=""
NAME=""
UNDO=false
SKIP_RENAME=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)        EPIC="$2";   shift 2 ;;
        --folder)      FOLDER="$2"; shift 2 ;;
        --parent)      PARENT="$2"; shift 2 ;;
        --name)        NAME="$2";   shift 2 ;;
        --undo)        UNDO=true;   shift ;;
        --skip-rename) SKIP_RENAME=true; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$NAME" ]]; then
    echo "Usage: complete-task.sh --folder <status> --name <task> [--epic <epic>] [--parent <parent-task>] [--undo]"
    exit 1
fi

TASKS_DIR="$TASKS_ROOT/$EPIC"

# ---------------------------------------------------------------------------
# Subtask path: update in place
# ---------------------------------------------------------------------------

if [[ -n "$PARENT" ]]; then
    PARENT_DIR="$TASKS_DIR/$FOLDER/$PARENT"
    PARENT_JSON="$PARENT_DIR/task.json"
    PARENT_README="$PARENT_DIR/README.md"

    if [[ ! -d "$PARENT_DIR" ]]; then
        echo "Parent task not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT"
        exit 1
    fi

    SUBTASK_DIR="$TASKS_DIR/$FOLDER/$PARENT/$NAME"
    XNAME="X-$NAME"
    XSUBTASK_DIR="$TASKS_DIR/$FOLDER/$PARENT/$XNAME"

    # ------------------------------------------------------------------
    # Pipeline subtask path (parent has task.json)
    # ------------------------------------------------------------------
    if is_pipeline_task "$PARENT_DIR"; then
        if [[ "$UNDO" == true ]]; then
            # Rename X-NAME back to NAME on disk if needed
            if [[ -d "$XSUBTASK_DIR" ]]; then
                mv "$XSUBTASK_DIR" "$SUBTASK_DIR"
            fi
            # Restore subtask entry in parent task.json
            python3 - "$PARENT_JSON" "$NAME" <<'EOF'
import sys, json
path, name = sys.argv[1], sys.argv[2]
data = json.load(open(path))
for entry in data.get("subtasks", []):
    if entry.get("name") == name:
        entry["complete"] = False
        break
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF
            # Restore status and clear completed_at in child task.json if present
            if [[ -f "$SUBTASK_DIR/task.json" ]]; then
                json_set_str "$SUBTASK_DIR/task.json" "status" "—"
                python3 - "$SUBTASK_DIR/task.json" <<'PYEOF'
import sys, json
path = sys.argv[1]
data = json.load(open(path))
data["completed_at"] = None
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
            fi
            echo "Marked incomplete: $NAME"
        else
            if [[ ! -d "$SUBTASK_DIR" ]]; then
                echo "Subtask not found or already renamed: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$NAME"
                exit 1
            fi
            if [[ "$SKIP_RENAME" == true ]]; then
                # JSON updates only — caller will rename the directory after flushing
                # in-memory state (e.g. orchestrator metrics). The rename must be
                # the last step so that in-memory paths remain valid for writes.
                json_complete_subtask "$PARENT_JSON" "$NAME"
                if [[ -f "$SUBTASK_DIR/task.json" ]]; then
                    json_set_str "$SUBTASK_DIR/task.json" "status" "complete"
                    json_set_str "$SUBTASK_DIR/task.json" "completed_at" "$(date +%Y-%m-%d)"
                fi
                echo "Marked complete (rename deferred): $NAME"
            else
                # Rename directory: NAME → X-NAME
                mv "$SUBTASK_DIR" "$XSUBTASK_DIR"
                # Update subtask entry in parent task.json
                json_complete_subtask "$PARENT_JSON" "$NAME"
                # Update status and completed_at in child task.json
                if [[ -f "$XSUBTASK_DIR/task.json" ]]; then
                    json_set_str "$XSUBTASK_DIR/task.json" "status" "complete"
                    json_set_str "$XSUBTASK_DIR/task.json" "completed_at" "$(date +%Y-%m-%d)"
                fi
                echo "Marked complete: $NAME"
            fi
        fi
        exit 0
    fi

    # ------------------------------------------------------------------
    # User subtask path (parent has no task.json — README-based)
    # ------------------------------------------------------------------
    SUBTASK_README="$SUBTASK_DIR/README.md"

    if [[ ! -f "$PARENT_README" ]]; then
        echo "Parent task not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT"
        exit 1
    fi
    if [[ ! -f "$SUBTASK_README" ]]; then
        echo "Subtask not found: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$NAME"
        exit 1
    fi

    if [[ "$UNDO" == true ]]; then
        # Accept either X-NAME (already renamed) or NAME (not yet renamed)
        if grep -q "\- \[x\].*$XNAME" "$PARENT_README"; then
            CURRENT_SUBTASK_DIR="$XSUBTASK_DIR"
        elif grep -q "\- \[x\].*$NAME" "$PARENT_README"; then
            CURRENT_SUBTASK_DIR="$SUBTASK_DIR"
        else
            echo "Subtask '$NAME' is not marked complete in $PARENT_README"
            exit 1
        fi
        # Rename X-NAME back to NAME on disk if needed
        if [[ -d "$XSUBTASK_DIR" ]]; then
            mv "$XSUBTASK_DIR" "$SUBTASK_DIR"
        fi
        # Restore checkbox and link in parent README
        _sed_i "s|- \[x\] \[$XNAME\](X-$NAME/)|- [ ] [$NAME]($NAME/)|" "$PARENT_README"
        _sed_i "s|- \[x\] \[$NAME\](\(.*\))|- [ ] [$NAME](\1)|" "$PARENT_README"
        _sed_i "s|- \[x\] $NAME$|- [ ] $NAME|" "$PARENT_README"
        _sed_i "s/| Status *|[^|]*|/| Status | — |/" "$SUBTASK_README"
        _sed_i "s/| Completed *|[^|]*|/| Completed | — |/" "$SUBTASK_README"
        echo "Marked incomplete: $NAME"
    else
        if ! grep -q "\- \[ \].*$NAME" "$PARENT_README"; then
            echo "Subtask '$NAME' not found or already complete in $PARENT_README"
            exit 1
        fi
        if [[ "$SKIP_RENAME" == false ]]; then
            # Rename directory: NAME → X-NAME
            mv "$SUBTASK_DIR" "$XSUBTASK_DIR"
        fi
        # Update checkbox and link in parent README
        _sed_i "s|- \[ \] \[$NAME\]($NAME/)|- [x] [$XNAME](X-$NAME/)|" "$PARENT_README"
        # Handle plain format: - [ ] NAME (no link)
        _sed_i "s|- \[ \] $NAME$|- [x] $XNAME|" "$PARENT_README"
        COMPLETED_DATE="$(date +%Y-%m-%d)"
        if [[ "$SKIP_RENAME" == true ]]; then
            _sed_i "s/| Status *|[^|]*|/| Status | complete |/" "$SUBTASK_DIR/README.md"
            _sed_i "s/| Completed *|[^|]*|/| Completed | $COMPLETED_DATE |/" "$SUBTASK_DIR/README.md"
        else
            _sed_i "s/| Status *|[^|]*|/| Status | complete |/" "$XSUBTASK_DIR/README.md"
            _sed_i "s/| Completed *|[^|]*|/| Completed | $COMPLETED_DATE |/" "$XSUBTASK_DIR/README.md"
        fi
        echo "Marked complete: $NAME"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Top-level task path: move between status folders
# ---------------------------------------------------------------------------

if [[ "$UNDO" == true ]]; then
    # complete/ → original folder
    SRC_DIR="$TASKS_DIR/complete/$NAME"
    DST_DIR="$TASKS_DIR/$FOLDER/$NAME"
    SRC_STATUS_README="$TASKS_DIR/complete/README.md"
    DST_STATUS_README="$TASKS_DIR/$FOLDER/README.md"
    FROM="complete"
    TO="$FOLDER"
else
    # folder → complete/
    SRC_DIR="$TASKS_DIR/$FOLDER/$NAME"
    DST_DIR="$TASKS_DIR/complete/$NAME"
    SRC_STATUS_README="$TASKS_DIR/$FOLDER/README.md"
    DST_STATUS_README="$TASKS_DIR/complete/README.md"
    FROM="$FOLDER"
    TO="complete"
fi

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Task not found: $TASKS_REL/$EPIC/$FROM/$NAME"
    exit 1
fi

if [[ -d "$DST_DIR" ]]; then
    echo "Task already exists at destination: $TASKS_REL/$EPIC/$TO/$NAME"
    exit 1
fi

# Move directory
mkdir -p "$(dirname "$DST_DIR")"
mv "$SRC_DIR" "$DST_DIR"

# Update task README Status field (for user tasks that have a metadata table)
if [[ -f "$DST_DIR/README.md" ]]; then
    _sed_i "s/| Status *|[^|]*|/| Status | $TO |/" "$DST_DIR/README.md"
    if [[ "$UNDO" == true ]]; then
        _sed_i "s/| Completed *|[^|]*|/| Completed | — |/" "$DST_DIR/README.md"
    else
        _sed_i "s/| Completed *|[^|]*|/| Completed | $(date +%Y-%m-%d) |/" "$DST_DIR/README.md"
    fi
fi

# Also update task.json status if this is a pipeline task
if [[ -f "$DST_DIR/task.json" ]]; then
    json_set_str "$DST_DIR/task.json" "status" "$TO"
fi

# Remove from source status README
if [[ -f "$SRC_STATUS_README" ]]; then
    _sed_i "/\[$NAME\]($NAME\/)/d" "$SRC_STATUS_README"
fi

# Add to destination status README (create if needed)
if [[ ! -f "$DST_STATUS_README" ]]; then
    cat > "$DST_STATUS_README" << EOF
# $EPIC / $TO

## Tasks

<!-- When a task is finished, run move-task.sh --to complete before moving on. -->
<!-- task-list-start -->
<!-- task-list-end -->
EOF
fi
_sed_i "s|<!-- task-list-end -->|- [$NAME]($NAME/)\n<!-- task-list-end -->|" "$DST_STATUS_README"

echo "Moved: $TASKS_REL/$EPIC/$FROM/$NAME"
echo "   ->  $TASKS_REL/$EPIC/$TO/$NAME"
