#!/usr/bin/env bash
# Create a new epic directory with all status subdirectories.
#
# Without --project: creates <tasks-root>/<epic-name>/
# With --project:    creates <projects-root>/<project-name>/<epic-name>/
#
# Usage:
#   new-epic.sh --name <epic-name>
#   new-epic.sh --name <epic-name> --project <project-name>
#
# Examples:
#   new-epic.sh --name main
#   new-epic.sh --name main --project my-project

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/task-env.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

NAME=""
PROJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)    NAME="$2";    shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$NAME" ]]; then
    echo "Usage: new-epic.sh --name <epic-name> [--project <project-name>]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve base path
# ---------------------------------------------------------------------------

if [[ -n "$PROJECT" ]]; then
    BASE_DIR="$PROJECTS_ROOT/$PROJECT"
    if [[ ! -d "$BASE_DIR" ]]; then
        echo "Project directory not found: $BASE_DIR"
        echo "Run new-project.sh --name $PROJECT first."
        exit 1
    fi
    EPIC_DIR="$BASE_DIR/$NAME"
    DISPLAY_PATH="$PROJECTS_REL/$PROJECT/$NAME"
else
    BASE_DIR="$TASKS_ROOT"
    EPIC_DIR="$BASE_DIR/$NAME"
    DISPLAY_PATH="$TASKS_REL/$NAME"
fi

if [[ -d "$EPIC_DIR" ]]; then
    echo "Epic already exists: $DISPLAY_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Create epic directory and status subdirectories
# ---------------------------------------------------------------------------

STATUS_DIRS=(inbox draft backlog in-progress complete wont-do)

mkdir -p "$EPIC_DIR"

for STATUS in "${STATUS_DIRS[@]}"; do
    mkdir -p "$EPIC_DIR/$STATUS"
    cat > "$EPIC_DIR/$STATUS/README.md" << EOF
# $NAME / $STATUS

## Tasks

<!-- When a task is finished, run move-task.sh --to complete before moving on. -->
<!-- task-list-start -->
<!-- task-list-end -->
EOF
done

# Epic-level README
cat > "$EPIC_DIR/README.md" << EOF
# Epic: $NAME

## Status

| Status      | Tasks |
|-------------|-------|
| inbox       |       |
| draft       |       |
| backlog     |       |
| in-progress |       |
| complete    |       |
| wont-do     |       |
EOF

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo "Created epic: $DISPLAY_PATH"
echo "  Subdirectories: ${STATUS_DIRS[*]}"
