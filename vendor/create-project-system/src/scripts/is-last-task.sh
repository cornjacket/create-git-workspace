#!/usr/bin/env bash
# Check whether a task is marked as the last (integration) task.
#
# Reads last-task from task.json in the same directory as the README argument.
#
# Usage:
#   is-last-task.sh <task-readme-path>
#
# Exit codes:
#   0 — last-task: true
#   1 — last-task: false, field absent, or file not found
#
# Example:
#   if is-last-task.sh <tasks>/main/in-progress/abc123-my-task/xyz-integrate/README.md
#   then echo "integration step"
#   fi

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=task-json-helpers.sh
source "$SCRIPTS_DIR/task-json-helpers.sh"

README="${1:-}"

if [[ -z "$README" ]]; then
    echo "Usage: is-last-task.sh <task-readme-path>"
    exit 1
fi

if [[ ! -f "$README" ]]; then
    exit 1
fi

TASK_DIR="$(dirname "$README")"
JSON_FILE="$TASK_DIR/task.json"

if [[ ! -f "$JSON_FILE" ]]; then
    exit 1
fi

val="$(json_get "$JSON_FILE" "last-task")"
[[ "$val" == "true" ]] && exit 0 || exit 1
