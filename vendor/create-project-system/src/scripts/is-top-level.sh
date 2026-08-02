#!/usr/bin/env bash
# Check if a pipeline-subtask's level field is TOP.
#
# Reads level from task.json in the same directory as the argument.
#
# Usage:
#   is-top-level.sh <task-readme-path>
#
# Exit codes:
#   0 — level is TOP
#   1 — level is INTERNAL, missing, or unset
#   2 — usage error

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=task-json-helpers.sh
source "$SCRIPTS_DIR/task-json-helpers.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: is-top-level.sh <task-readme-path>" >&2
    exit 2
fi

if [[ ! -f "$1" ]]; then
    echo "File not found: $1" >&2
    exit 2
fi

TASK_DIR="$(dirname "$1")"
JSON_FILE="$TASK_DIR/task.json"

if [[ ! -f "$JSON_FILE" ]]; then
    exit 1
fi

val="$(json_get "$JSON_FILE" "level")"
[[ "$val" == "TOP" ]] && exit 0 || exit 1
