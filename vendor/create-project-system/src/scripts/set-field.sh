#!/usr/bin/env bash
# Set a metadata field on an existing task or subtask README.
#
# Usage:
#   set-field.sh --folder <status> --name <task> --field <Tags|Priority> --value <value> [--epic <epic>]
#   set-field.sh --folder <status> --parent <task> --name <subtask> --field <field> --value <value>
#
# WHY THIS EXISTS: Tags and Priority were previously settable only at creation.
# Retagging meant hand-editing the metadata row (against the "scripts only"
# rule) or delete-and-recreate, which destroys the task's subtasks. That made
# the *correct* tool for topical grouping harder to reach than the wrong one —
# operators reached for --worktree instead, which is about parallel-work
# isolation, not subject matter.
#
# SCOPE — only fields that mirror nothing on the filesystem are settable here:
#   Tags       free text (comma-separated by convention); '—' clears it
#   Priority   CRITICAL | HIGH | MED | LOW; '—' clears it
# Status, Epic and the task's location are refused: they mirror the directory
# tree, so changing the row alone would desync the README from the filesystem.
# Use move-task.sh / complete-task.sh for those.
#
# Examples:
#   set-field.sh --folder backlog --name 7f21ab-add-search --field Tags --value "docs, search"
#   set-field.sh --folder in-progress --name 7f21ab-add-search --field Priority --value HIGH
#   set-field.sh --folder backlog --name 7f21ab-add-search --field Tags --value "—"
#   set-field.sh --folder in-progress --parent 7f21ab-add-search \
#       --name 7f21ab-0000-design-index --field Priority --value LOW

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
FIELD=""
VALUE=""
VALUE_SET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)   EPIC="$2";   shift 2 ;;
        --folder) FOLDER="$2"; shift 2 ;;
        --parent) PARENT="$2"; shift 2 ;;
        --name)   NAME="$2";   shift 2 ;;
        --field)  FIELD="$2";  shift 2 ;;
        --value)  VALUE="$2";  VALUE_SET=true; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$NAME" || -z "$FIELD" || "$VALUE_SET" != true ]]; then
    echo "Usage: set-field.sh --folder <status> --name <task> --field <Tags|Priority> --value <value> [--epic <epic>] [--parent <parent-task>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate the field
# ---------------------------------------------------------------------------

# Accept any capitalization; write the canonical row name.
case "$(printf '%s' "$FIELD" | tr '[:upper:]' '[:lower:]')" in
    tags)     FIELD="Tags" ;;
    priority) FIELD="Priority" ;;
    status|epic|task-type|created|completed|next-subtask-id)
        {
            echo "Error: '$FIELD' is not settable here — it mirrors the filesystem."
            echo "  Status / location : move-task.sh, complete-task.sh"
            echo "  Task-type, Created, Completed, Next-subtask-id: maintained by the scripts."
        } >&2
        exit 1 ;;
    worktree|category)
        {
            echo "Error: the Worktree field is not settable here yet."
            echo "  It validates against worktrees.md, which this script does not read."
            echo "  Set it at creation with: new-user-task.sh --worktree <name>"
        } >&2
        exit 1 ;;
    *)
        echo "Error: unknown field: '$FIELD' (settable: Tags, Priority)" >&2
        exit 1 ;;
esac

if [[ "$FIELD" == "Priority" ]]; then
    case "$VALUE" in
        CRITICAL|HIGH|MED|LOW|—) ;;
        *)
            echo "Error: invalid Priority: '$VALUE' (expected CRITICAL, HIGH, MED, LOW, or — to clear)" >&2
            exit 1 ;;
    esac
fi

# Empty value clears the field rather than writing a blank cell.
[[ -z "$VALUE" ]] && VALUE="—"

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
# Rewrite the row
#
# python3, not sed: the value is arbitrary user text that may contain the '|'
# and '/' characters a sed expression would choke on, and the replacement is
# padded to preserve the metadata table's column alignment.
# ---------------------------------------------------------------------------

python3 - "$README" "$FIELD" "$VALUE" <<'PY'
import pathlib, re, sys

path, field, value = sys.argv[1:4]
p = pathlib.Path(path)
text = p.read_text()

# `| Tags        | old value              |` -> capture both cells' widths so
# the rewritten row keeps the table aligned.
row = re.compile(
    r'^\|(?P<name>\s*' + re.escape(field) + r'\s*)\|(?P<val>[^|\n]*)\|[ \t]*$',
    re.MULTILINE,
)

match = row.search(text)
if match is None:
    sys.stderr.write(f"Error: no '{field}' row found in {path}\n")
    raise SystemExit(1)

width = len(match.group('val'))
cell = f' {value}'.ljust(width)[:max(width, len(value) + 2)]
p.write_text(text[:match.start()] + f"|{match.group('name')}|{cell}|" + text[match.end():])
PY

echo "Set $FIELD = $VALUE"
echo "Updated: ${README#$REPO_ROOT/}"
