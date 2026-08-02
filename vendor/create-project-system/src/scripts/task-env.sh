#!/usr/bin/env bash
# task-env.sh — shared environment bootstrap for every task script.
#
# Gives every script two things it must never hardcode:
#   1. The subsystem's mount path — TASKS_REL, read from the generated
#      task-config.sh. Scripts build paths from TASKS_ROOT, never a literal.
#   2. The repo root — resolve_repo_root(), which is independent of how deeply
#      the subsystem is mounted and is git-worktree-aware.
#
# Usage — put these two lines at the top of every script, after `set -euo pipefail`:
#   SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPTS_DIR/task-env.sh"
#
# After sourcing you have: REPO_ROOT, TASKS_REL, DEFAULT_EPIC, TASKS_ROOT
# (= "$REPO_ROOT/$TASKS_REL"). Scripts build paths from TASKS_ROOT, never a literal.

# Directory holding this file. In a generated target this is <tasks>/scripts/,
# alongside the rendered task-config.sh and the other scripts.
_TASK_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load generated config (TASKS_REL, DEFAULT_EPIC) ------------------------
if [[ -f "$_TASK_ENV_DIR/task-config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_TASK_ENV_DIR/task-config.sh"
else
    echo "task-env.sh: task-config.sh not found beside the scripts ($_TASK_ENV_DIR)." >&2
    echo "  It is generated from task-config.sh.in — regenerate the task subsystem." >&2
    return 1 2>/dev/null || exit 1
fi

: "${TASKS_REL:?task-config.sh must define TASKS_REL}"
: "${DEFAULT_EPIC:=main}"

# --- Projects layer (optional, --with-projects) ------------------------------
# Long-running services live in a sibling of the tasks mount. If task-config.sh
# does not set PROJECTS_REL, derive it as a sibling "projects" dir, which yields
# the natural mapping:  tasks -> projects  |  pm/tasks -> pm/projects.
if [[ -z "${PROJECTS_REL:-}" ]]; then
    _tasks_parent="$(dirname "$TASKS_REL")"
    if [[ "$_tasks_parent" == "." ]]; then
        PROJECTS_REL="projects"
    else
        PROJECTS_REL="$_tasks_parent/projects"
    fi
    unset _tasks_parent
fi

# --- Resolve the repo root --------------------------------------------------
# Mount-depth-independent and robust to git worktrees. Primary: git toplevel,
# which for a LINKED WORKTREE correctly returns the worktree root (e.g.
# .../ai-builder/main), not the .bare container. Fallback (no git available):
# walk up until a repo marker or the mount dir. Note `.git` may be a FILE (linked
# worktree marker `gitdir: …`) or a DIRECTORY (normal repo) — `-e` matches both;
# a `[[ -d .git ]]` check would silently miss a worktree.
resolve_repo_root() {
    local root
    if root="$(git -C "$_TASK_ENV_DIR" rev-parse --show-toplevel 2>/dev/null)" \
       && [[ -n "$root" ]]; then
        printf '%s\n' "$root"
        return 0
    fi
    local dir="$_TASK_ENV_DIR"
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        if [[ -e "$dir/.git" ]]; then printf '%s\n' "$dir"; return 0; fi
        if [[ -n "${TASKS_REL:-}" && -d "$dir/$TASKS_REL" ]]; then
            printf '%s\n' "$dir"; return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "task-env.sh: could not resolve repo root from $_TASK_ENV_DIR" >&2
    return 1
}

if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(resolve_repo_root)" || { return 1 2>/dev/null || exit 1; }
fi
TASKS_ROOT="$REPO_ROOT/$TASKS_REL"
PROJECTS_ROOT="$REPO_ROOT/$PROJECTS_REL"
