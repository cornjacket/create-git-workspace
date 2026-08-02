#!/usr/bin/env bash
# List all tasks in an epic, grouped by status.
# Reads task order and completion state from each directory's README.md.
# Optionally filter to a single status folder, set recursion depth, or
# specify a traversal root directly.
#
# By default only incomplete tasks are shown. Use --all to show everything.
# Use --tag to filter to tasks whose Tags field contains the given value — this
# is the topical filter (docs, video, education).
# Use --worktree to filter to tasks whose Worktree field equals the given value
# (use 'unclassified' to match tasks with Worktree '—' or no Worktree field).
# Use --group-by-worktree to group output by Worktree within each status folder.
# Use --sort-priority to sort tasks HIGH → MED → LOW → unset within each folder.
#
# --worktree/--group-by-worktree were called --category/--group-by-category
# before the field was named for what it selects; both remain as deprecated
# aliases that warn.
#
# Usage:
#   list-tasks.sh [--epic <epic>] [--folder <status>] [--depth <n>] [--root <path>] [--all] [--tag <tag>] [--worktree <branch>] [--group-by-worktree] [--sort-priority]
#
# Examples:
#   list-tasks.sh --epic main
#   list-tasks.sh --epic main --all
#   list-tasks.sh --epic main --folder in-progress --depth 2
#   list-tasks.sh --root main/in-progress/my-task --depth 3 --all
#   list-tasks.sh --epic main --tag tooling --depth 2
#   list-tasks.sh --epic main --folder backlog --sort-priority
#   list-tasks.sh --epic main --folder backlog --worktree task-tooling
#   list-tasks.sh --epic main --folder backlog --group-by-worktree --sort-priority

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EPIC="$DEFAULT_EPIC"
FOLDER=""
DEPTH=1
ROOT=""
SHOW_ALL=false
TAG=""
WORKTREE=""
GROUP_BY_WORKTREE=false
SORT_PRIORITY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --epic)              EPIC="$2";   shift 2 ;;
        --folder)            FOLDER="$2"; shift 2 ;;
        --depth)             DEPTH="$2";  shift 2 ;;
        --root)              ROOT="$2";   shift 2 ;;
        --all)               SHOW_ALL=true; shift ;;
        --tag)               TAG="$2";    shift 2 ;;
        --worktree)          WORKTREE="$2"; shift 2 ;;
        --group-by-worktree) GROUP_BY_WORKTREE=true; shift ;;
        # Deprecated aliases — see the header note.
        --category)
            echo "Warning: --category is deprecated; use --worktree." >&2
            WORKTREE="$2"; shift 2 ;;
        --group-by-category)
            echo "Warning: --group-by-category is deprecated; use --group-by-worktree." >&2
            GROUP_BY_WORKTREE=true; shift ;;
        --sort-priority)     SORT_PRIORITY=true; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

# Canonical worktree order, read at runtime from the worktrees layer's
# worktrees.md (the order worktrees are declared in that file). 'unclassified'
# is always appended last, for tasks whose Worktree is '—' or missing.
#
# Repos generated before the Category -> Worktree rename carry this file as
# classes.md. It is CONTENT, which the generator never rewrites, so the
# fallback below is permanent rather than transitional.
#
# When the worktrees layer is not installed at all, the order is just
# 'unclassified' — --group-by-worktree then degrades to a single group, and
# --worktree filtering still works against whatever values tasks carry.
WORKTREE_ORDER=()
_WORKTREES_FILE="$TASKS_ROOT/worktrees.md"
[[ -f "$_WORKTREES_FILE" ]] || _WORKTREES_FILE="$TASKS_ROOT/classes.md"
if [[ -f "$_WORKTREES_FILE" ]]; then
    while IFS= read -r _wt; do
        [[ -n "$_wt" ]] && WORKTREE_ORDER+=("$_wt")
    done < <(grep -oE '^\*\*Worktree branch:\*\* `[^`]+`' "$_WORKTREES_FILE" \
             | sed 's/^\*\*Worktree branch:\*\* `\([^`]*\)`/\1/')
fi
WORKTREE_ORDER+=("unclassified")

# ---------------------------------------------------------------------------
# Resolve traversal root
# ---------------------------------------------------------------------------

if [[ -n "$ROOT" ]]; then
    ROOT_DIR="$TASKS_ROOT/$ROOT"
    if [[ ! -d "$ROOT_DIR" ]]; then
        echo "Root not found: $TASKS_REL/$ROOT"
        exit 1
    fi
else
    EPIC_DIR="$TASKS_ROOT/$EPIC"
    if [[ ! -d "$EPIC_DIR" ]]; then
        echo "Epic not found: $EPIC"
        exit 1
    fi
fi

# Status display order
STATUSES=("inbox" "draft" "backlog" "in-progress" "complete" "wont-do")

# ---------------------------------------------------------------------------
# Helper: read Priority field from a task README
# ---------------------------------------------------------------------------

get_priority() {
    local readme="$1"
    local priority
    priority=$(grep -m1 "^| Priority" "$readme" 2>/dev/null | sed 's/| Priority *| *\(.*\) *|/\1/' | tr -d ' ')
    echo "${priority:-—}"
}

# ---------------------------------------------------------------------------
# Helper: map a priority value to a sort key (lower = higher priority)
# ---------------------------------------------------------------------------

priority_sort_key() {
    case "$1" in
        HIGH) echo "1" ;;
        MED)  echo "2" ;;
        LOW)  echo "3" ;;
        *)    echo "4" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: check if a task README's Tags field contains the given tag (case-insensitive)
# Returns 0 (true) if tag matches or no TAG filter is set.
# ---------------------------------------------------------------------------

has_tag() {
    local readme="$1"
    [[ -z "$TAG" ]] && return 0
    local tags
    tags=$(grep -m1 "^| Tags" "$readme" 2>/dev/null | sed 's/| Tags *| *\(.*\) *|/\1/' | tr '[:upper:]' '[:lower:]')
    echo "$tags" | grep -qiw "$(echo "$TAG" | tr '[:upper:]' '[:lower:]')"
}

# ---------------------------------------------------------------------------
# Helper: read the Worktree field from a task README.
# Returns the raw value, or "unclassified" if the field is missing/blank/'—'.
#
# Tasks created before the Category -> Worktree rename carry a `| Category |`
# row. Task READMEs are CONTENT — the generator never rewrites them — so this
# reader accepts both spellings permanently, and no migration of existing tasks
# is required. A repo may hold a mix of both rows indefinitely.
# ---------------------------------------------------------------------------

get_worktree() {
    local readme="$1"
    local worktree
    worktree=$(grep -m1 "^| Worktree" "$readme" 2>/dev/null | sed 's/| Worktree *| *\(.*\) *|/\1/' | tr -d ' ')
    if [[ -z "$worktree" ]]; then
        worktree=$(grep -m1 "^| Category" "$readme" 2>/dev/null | sed 's/| Category *| *\(.*\) *|/\1/' | tr -d ' ')
    fi
    if [[ -z "$worktree" || "$worktree" == "—" ]]; then
        echo "unclassified"
    else
        echo "$worktree"
    fi
}

# ---------------------------------------------------------------------------
# Helper: check if a task README's Worktree matches the --worktree filter.
# Returns 0 (true) if no WORKTREE filter is set or the field matches.
# ---------------------------------------------------------------------------

matches_worktree() {
    local readme="$1"
    [[ -z "$WORKTREE" ]] && return 0
    local actual
    actual="$(get_worktree "$readme")"
    [[ "$actual" == "$WORKTREE" ]]
}

# ---------------------------------------------------------------------------
# Helper: parse task dirnames from a README in listed order.
#
# For task-list entries (no checkbox):   always included.
# For subtask-list entries with [ ]:     always included.
# For subtask-list entries with [x]:     included only when SHOW_ALL=true.
# Falls back to sorted find if no markers are present.
# ---------------------------------------------------------------------------

parse_readme_order() {
    local readme="$1"
    local dir="$2"

    if ! grep -q "<!-- task-list-start -->\|<!-- subtask-list-start -->" "$readme" 2>/dev/null; then
        # No markers — fall back to alphabetical find
        find "$dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort
        return
    fi

    local in_block=0
    while IFS= read -r line; do
        if [[ "$line" == *"<!-- task-list-start -->"* || "$line" == *"<!-- subtask-list-start -->"* ]]; then
            in_block=1; continue
        fi
        if [[ "$line" == *"<!-- task-list-end -->"* || "$line" == *"<!-- subtask-list-end -->"* ]]; then
            in_block=0; continue
        fi
        [[ $in_block -eq 0 ]] && continue

        # Skip completed subtask entries unless --all
        if [[ "$SHOW_ALL" == false ]] && [[ "$line" == *"- [x]"* ]]; then
            continue
        fi

        # Extract directory name from (dirname/)
        local dirname
        dirname=$(echo "$line" | sed 's/.*(\(.*\)\/)/\1/')
        [[ -z "$dirname" ]] && continue

        local task_dir="$dir/$dirname"
        [[ -d "$task_dir" ]] && echo "$task_dir"
    done < "$readme"
}

# ---------------------------------------------------------------------------
# Recursive print function
# ---------------------------------------------------------------------------

print_dir_tasks() {
    local dir="$1"
    local current_depth="$2"
    local max_depth="$3"
    local indent="$4"
    local readme="$dir/README.md"

    [[ -f "$readme" ]] || return

    while IFS= read -r task_dir; do
        [[ -f "$task_dir/README.md" ]] || continue
        has_tag "$task_dir/README.md" || continue
        # Worktree filter only applies at depth 1 (top-level tasks own the field).
        if [[ "$current_depth" -eq 1 ]]; then
            matches_worktree "$task_dir/README.md" || continue
        fi
        local task_name priority
        task_name="$(basename "$task_dir")"
        priority="$(get_priority "$task_dir/README.md")"

        if [[ "$priority" != "—" ]]; then
            echo "${indent}${task_name} [${priority}]"
        else
            echo "${indent}${task_name}"
        fi

        if [[ "$current_depth" -lt "$max_depth" ]]; then
            print_dir_tasks "$task_dir" $(( current_depth + 1 )) "$max_depth" "${indent}  └── "
        fi
    done < <(parse_readme_order "$readme" "$dir")
}

# ---------------------------------------------------------------------------
# Print tasks for a single status folder
# ---------------------------------------------------------------------------

print_status_tasks() {
    local status_dir="$1"
    local status="$2"
    local readme="$status_dir/README.md"

    # At the status level there are no checkboxes, so we always show all
    # top-level tasks regardless of --all (status folder = completion state).

    # Build the list of task dirs, optionally sorted by priority.
    local task_dirs=()
    while IFS= read -r task_dir; do
        [[ -f "$task_dir/README.md" ]] || continue
        has_tag "$task_dir/README.md" || continue
        matches_worktree "$task_dir/README.md" || continue
        task_dirs+=("$task_dir")
    done < <(
        if [[ -f "$readme" ]]; then
            parse_readme_order "$readme" "$status_dir"
        else
            find "$status_dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort
        fi
    )

    if [[ "$SORT_PRIORITY" == true && ${#task_dirs[@]} -gt 0 ]]; then
        # Decorate with sort key, stable-sort, then undecorate.
        local decorated=()
        for task_dir in "${task_dirs[@]}"; do
            local p key
            p="$(get_priority "$task_dir/README.md")"
            key="$(priority_sort_key "$p")"
            decorated+=("${key}|${task_dir}")
        done
        # Sort by key (first field), preserving original order within same priority.
        local sorted_dirs=()
        while IFS= read -r entry; do
            sorted_dirs+=("${entry#*|}")
        done < <(printf '%s\n' "${decorated[@]}" | sort -t'|' -k1,1 -s)
        task_dirs=("${sorted_dirs[@]}")
    fi

    [[ ${#task_dirs[@]} -eq 0 ]] && return

    echo ""
    echo "  [$status]"

    if [[ "$GROUP_BY_WORKTREE" == true ]]; then
        # Walk WORKTREE_ORDER and print each non-empty group in canonical order.
        for worktree in "${WORKTREE_ORDER[@]}"; do
            local group_first=1
            for task_dir in "${task_dirs[@]}"; do
                local task_wt
                task_wt="$(get_worktree "$task_dir/README.md")"
                [[ "$task_wt" == "$worktree" ]] || continue
                if [[ $group_first -eq 1 ]]; then
                    echo "    [$worktree]"
                    group_first=0
                fi
                local task_name priority
                task_name="$(basename "$task_dir")"
                priority="$(get_priority "$task_dir/README.md")"
                if [[ "$priority" != "—" ]]; then
                    echo "      $task_name [$priority]"
                else
                    echo "      $task_name"
                fi
                if [[ "$DEPTH" -gt 1 ]]; then
                    print_dir_tasks "$task_dir" 2 "$DEPTH" "        └── "
                fi
            done
        done
    else
        for task_dir in "${task_dirs[@]}"; do
            local task_name priority
            task_name="$(basename "$task_dir")"
            priority="$(get_priority "$task_dir/README.md")"
            if [[ "$priority" != "—" ]]; then
                echo "    $task_name [$priority]"
            else
                echo "    $task_name"
            fi
            if [[ "$DEPTH" -gt 1 ]]; then
                print_dir_tasks "$task_dir" 2 "$DEPTH" "      └── "
            fi
        done
    fi
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

FILTER_LABEL="incomplete only"
[[ "$SHOW_ALL" == true ]] && FILTER_LABEL="all"
[[ -n "$TAG" ]] && FILTER_LABEL="$FILTER_LABEL, tag: $TAG"
[[ -n "$WORKTREE" ]] && FILTER_LABEL="$FILTER_LABEL, worktree: $WORKTREE"
[[ "$GROUP_BY_WORKTREE" == true ]] && FILTER_LABEL="$FILTER_LABEL, grouped by worktree"
[[ "$SORT_PRIORITY" == true ]] && FILTER_LABEL="$FILTER_LABEL, sorted by priority"

if [[ -n "$ROOT" ]]; then
    echo "Tasks — root: $ROOT  (depth: $DEPTH, $FILTER_LABEL)"
    echo "========================================"
    echo ""
    print_dir_tasks "$ROOT_DIR" 1 "$DEPTH" "  "
    echo ""
else
    echo "Tasks — epic: $EPIC  (depth: $DEPTH, $FILTER_LABEL)"
    echo "========================================"

    if [[ -n "$FOLDER" ]]; then
        status_dir="$EPIC_DIR/$FOLDER"
        if [[ ! -d "$status_dir" ]]; then
            echo "Status folder not found: $FOLDER"
            exit 1
        fi
        print_status_tasks "$status_dir" "$FOLDER"
    else
        for status in "${STATUSES[@]}"; do
            status_dir="$EPIC_DIR/$status"
            if [[ -d "$status_dir" ]]; then
                print_status_tasks "$status_dir" "$status"
            fi
        done
    fi

    echo ""
fi
