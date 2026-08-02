#!/usr/bin/env bash
# Shared helper functions for incremental subtask ID management.
# Source this file in scripts that create or complete subtasks.
#
# Functions:
#   get_parent_short_id <parent-dir>        — extracts the 6-char hex prefix
#   get_next_subtask_id <parent-readme>     — reads Next-subtask-id field value
#   increment_subtask_id <parent-readme>    — increments Next-subtask-id in place

# Cross-platform in-place sed. BSD sed (macOS) requires an empty-string argument
# after -i; GNU sed (Linux) does not. Use this wrapper instead of `sed -i ''`.
_sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Extract the short ID (first dash-delimited segment) from a directory basename.
# Works for both top-level tasks (6abc12-name) and subtasks (6abc12-0001-name).
get_parent_short_id() {
    local parent_dir="$1"
    basename "$parent_dir" | cut -d'-' -f1
}

# Read the current Next-subtask-id value from a README.
# Returns the raw 4-digit string, e.g. "0003".
get_next_subtask_id() {
    local readme="$1"
    grep -m1 "^| Next-subtask-id" "$readme" \
        | sed 's/| Next-subtask-id *| *\([0-9]*\) *|/\1/' \
        | tr -d ' '
}

# Increment the Next-subtask-id field in a README by one.
# Zero-pads to 4 digits.
increment_subtask_id() {
    local readme="$1"
    local current next
    current="$(get_next_subtask_id "$readme")"
    next="$(printf '%04d' $(( 10#$current + 1 )))"
    _sed_i "s/| Next-subtask-id *|[^|]*|/| Next-subtask-id | $next |/" "$readme"
}

# Resolve a subtask directory, accounting for the X- completion prefix.
# Tries <parent-dir>/<name> first, then <parent-dir>/X-<name>.
# Prints the resolved path; exits non-zero if neither exists.
resolve_subtask_dir() {
    local parent_dir="$1"
    local name="$2"
    if [[ -d "$parent_dir/$name" ]]; then
        echo "$parent_dir/$name"
    elif [[ -d "$parent_dir/X-$name" ]]; then
        echo "$parent_dir/X-$name"
    else
        echo ""
    fi
}
