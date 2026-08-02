#!/usr/bin/env bash
# insert-subtask.sh — insert a new subtask at a given position, shifting later ones up.
#
# All subtasks at position >= --at are renamed up by one (NNNN → NNNN+1).
# A new subtask is then created at the vacated position.
# The parent README's subtask list is updated and re-sorted.
# Next-subtask-id is bumped if necessary.
#
# Usage:
#   insert-subtask.sh --epic <epic> --folder <status> --parent <task> \
#       --at NNNN --name <name> [--type user|pipeline] [--tags <tags>] [--priority <p>]
#
# Arguments:
#   --at        4-digit position for the new subtask (e.g. 0003)
#   --name      Base name for the new subtask (e.g. my-new-step)
#   --type      Subtask type: user (default) or pipeline
#
# Example:
#   insert-subtask.sh --epic main --folder in-progress --parent my-task \
#       --at 0003 --name design-review

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
AT=""
NAME=""
TYPE="user"
TAGS="—"
PRIORITY="—"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)     EPIC="$2";     shift 2 ;;
        --folder)   FOLDER="$2";   shift 2 ;;
        --parent)   PARENT="$2";   shift 2 ;;
        --at)       AT="$2";       shift 2 ;;
        --name)     NAME="$2";     shift 2 ;;
        --type)     TYPE="$2";     shift 2 ;;
        --tags)     TAGS="$2";     shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$FOLDER" || -z "$PARENT" || -z "$AT" || -z "$NAME" ]]; then
    echo "Usage: insert-subtask.sh --folder <status> --parent <task> --at NNNN --name <name> [--epic <epic>] [--type user|pipeline] [--tags <t>] [--priority <p>]"
    exit 1
fi

if [[ "$TYPE" != "user" && "$TYPE" != "pipeline" ]]; then
    echo "ERROR: --type must be 'user' or 'pipeline'"
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

AT_PADDED="$(printf '%04d' "$(( 10#$AT ))")"

# Select template based on type
if [[ "$TYPE" == "user" ]]; then
    TEMPLATE="$SCRIPTS_DIR/user-subtask-template.md"
else
    TEMPLATE="$SCRIPTS_DIR/pipeline-build-template.md"
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "ERROR: Template not found: $TEMPLATE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Find subtasks at position >= AT (to shift up)
# ---------------------------------------------------------------------------

SUBTASK_PATTERN='^(X-)?([0-9a-f]{6})-([0-9]{4})-(.+)$'

# Collect subtasks to shift (position >= AT), sorted descending by number
# so we rename highest first and avoid directory name conflicts.
declare -a TO_SHIFT=()
while IFS= read -r entry; do
    dirname="$(basename "$entry")"
    if [[ "$dirname" =~ $SUBTASK_PATTERN ]]; then
        num="${BASH_REMATCH[3]}"
        if (( 10#$num >= 10#$AT_PADDED )); then
            TO_SHIFT+=("$dirname")
        fi
    fi
done < <(find "$PARENT_DIR" -maxdepth 1 -mindepth 1 -type d | sort -r)

# Check that position AT is not already occupied by an exact match
# (after the shift it will be free, but we need to warn if no shift targets exist
# and AT is already taken)
for entry in "${TO_SHIFT[@]}"; do
    if [[ "$entry" =~ $SUBTASK_PATTERN ]]; then
        num="${BASH_REMATCH[3]}"
        # If exactly AT is occupied by a non-shifted entry, that's fine — it will be shifted.
        break
    fi
done

# New entry target dirname
PARENT_SHORT_ID="$(get_parent_short_id "$PARENT_DIR")"
NEW_DIRNAME="${PARENT_SHORT_ID}-${AT_PADDED}-${NAME}"
NEW_DIR="$PARENT_DIR/$NEW_DIRNAME"

if [[ -d "$NEW_DIR" || -d "$PARENT_DIR/X-$NEW_DIRNAME" ]]; then
    # Only a conflict if no shift would move it out of the way
    # Check if the conflicting dir is in TO_SHIFT (it will be moved)
    conflict_found=false
    for entry in "${TO_SHIFT[@]}"; do
        if [[ "$entry" == "$NEW_DIRNAME" || "$entry" == "X-$NEW_DIRNAME" ]]; then
            conflict_found=true
            break
        fi
    done
    if [[ "$conflict_found" == false ]]; then
        echo "ERROR: Target directory already exists and will not be shifted: $NEW_DIR"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Shift subtasks up (rename highest-numbered first to avoid conflicts)
# ---------------------------------------------------------------------------

if [[ ${#TO_SHIFT[@]} -gt 0 ]]; then
    echo "Shifting ${#TO_SHIFT[@]} subtask(s) up by one position..."
    for old_dirname in "${TO_SHIFT[@]}"; do
        if [[ "$old_dirname" =~ $SUBTASK_PATTERN ]]; then
            x_prefix="${BASH_REMATCH[1]}"
            pid="${BASH_REMATCH[2]}"
            num="${BASH_REMATCH[3]}"
            sname="${BASH_REMATCH[4]}"
            new_num="$(printf '%04d' $(( 10#$num + 1 )))"
            new_dirname="${x_prefix}${pid}-${new_num}-${sname}"
            mv "$PARENT_DIR/$old_dirname" "$PARENT_DIR/$new_dirname"
            # Update parent README
            _sed_i "s|$old_dirname|$new_dirname|g" "$PARENT_README"
            echo "  $old_dirname → $new_dirname"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Create the new subtask at position AT
# ---------------------------------------------------------------------------

echo ""
echo "Creating new subtask at position $AT_PADDED: $NEW_DIRNAME"
mkdir -p "$NEW_DIR"

sed \
    -e "s/{{NAME}}/$NAME/g" \
    -e "s/{{EPIC}}/$EPIC/g" \
    -e "s/{{TAGS}}/$TAGS/g" \
    -e "s|{{PARENT}}|$PARENT|g" \
    -e "s/{{PRIORITY}}/$PRIORITY/g" \
    "$TEMPLATE" > "$NEW_DIR/README.md"

# ---------------------------------------------------------------------------
# Insert new entry into parent README subtask list
# ---------------------------------------------------------------------------

if grep -q "<!-- subtask-list-end -->" "$PARENT_README"; then
    _sed_i "s|<!-- subtask-list-end -->|- [ ] [$NEW_DIRNAME]($NEW_DIRNAME/)\n<!-- subtask-list-end -->|" "$PARENT_README"
else
    echo "Warning: no subtask list markers found in $PARENT_README — add the entry manually."
fi

# ---------------------------------------------------------------------------
# Re-sort the subtask list block in numeric order
# ---------------------------------------------------------------------------

python3 - "$PARENT_README" <<'PYEOF'
import re, sys

readme_path = sys.argv[1]
content = open(readme_path).read()

start_marker = "<!-- subtask-list-start -->"
end_marker   = "<!-- subtask-list-end -->"

start_idx = content.find(start_marker)
end_idx   = content.find(end_marker)
if start_idx == -1 or end_idx == -1:
    sys.exit(0)  # no markers, nothing to sort

block_start = start_idx + len(start_marker)
block = content[block_start:end_idx]

num_re = re.compile(r'\[(?:X-)?[0-9a-f]{6}-(\d{4})-')

lines = block.splitlines(keepends=True)
list_lines  = [l for l in lines if l.strip().startswith("- ")]
other_lines = [l for l in lines if not l.strip().startswith("- ")]

def sort_key(line):
    m = num_re.search(line)
    return int(m.group(1)) if m else 9999

sorted_lines = sorted(list_lines, key=sort_key)
new_block = "".join(other_lines[:1]) + "".join(sorted_lines) + "".join(other_lines[1:])
new_content = content[:block_start] + new_block + content[end_idx:]

if new_content != content:
    open(readme_path, "w").write(new_content)
PYEOF

# ---------------------------------------------------------------------------
# Bump Next-subtask-id if necessary
# ---------------------------------------------------------------------------

CURRENT_NEXT="$(get_next_subtask_id "$PARENT_README")"

# After shifting, the highest occupied position is CURRENT_NEXT-1 shifted to CURRENT_NEXT
# (or just CURRENT_NEXT-1 if nothing was shifted). Either way, bump if needed.
if [[ -n "$CURRENT_NEXT" ]]; then
    NEW_NEXT="$(printf '%04d' $(( 10#$CURRENT_NEXT + ${#TO_SHIFT[@]} )))"
    if [[ "$NEW_NEXT" != "$CURRENT_NEXT" ]]; then
        _sed_i "s/| Next-subtask-id *|[^|]*|/| Next-subtask-id | $NEW_NEXT |/" "$PARENT_README"
        echo "Bumped Next-subtask-id: $CURRENT_NEXT → $NEW_NEXT"
    fi
fi

echo ""
echo "Created: $TASKS_REL/$EPIC/$FOLDER/$PARENT/$NEW_DIRNAME/"
echo "Updated: $PARENT_README"
echo ""
echo "Done."
