#!/usr/bin/env python3
"""
Check whether a task and all its subtasks are complete.

Finds the task by matching the branch name as a suffix of the task directory
name (e.g. branch 'establish-regression-recordings' matches task directory
'ccf4a4-establish-regression-recordings').

Usage:
    python3 check-task-complete.py <epic-root> <branch-name>

IMPORTANT — <epic-root> is the EPIC directory, i.e. the directory that directly
contains the status folders (draft/, backlog/, in-progress/, complete/,
wont-do/). It is NOT the task subsystem mount.

    correct:  <tasks-mount>/<epic>     e.g.  tasks/main
    wrong:    <tasks-mount>            e.g.  tasks        (finds nothing, exits 2)

Exit codes:
    0  — task is complete and all subtasks are done
    1  — task is incomplete (details printed to stdout)
    2  — no task found matching the branch (removal allowed; warning printed)
"""

import os
import sys


def find_task(tasks_root: str, branch: str) -> tuple[str, str] | None:
    """
    Search all status folders for a task directory whose name ends with
    '-<branch>'. Returns (folder, task_dir_name) or None if not found.
    """
    for folder in ("complete", "in-progress", "backlog", "draft", "wont-do"):
        folder_path = os.path.join(tasks_root, folder)
        if not os.path.isdir(folder_path):
            continue
        for entry in os.listdir(folder_path):
            # Strip X- prefix (completed tasks keep their name)
            name = entry.lstrip("X-") if entry.startswith("X-") else entry
            if name == branch or name.endswith(f"-{branch}"):
                return folder, entry
    return None


def incomplete_subtasks(task_path: str) -> list[str]:
    """
    Return a list of subtask directory names that are not yet complete.
    Complete subtasks have an 'X-' prefix on their directory.
    """
    incomplete = []
    for entry in sorted(os.listdir(task_path)):
        full = os.path.join(task_path, entry)
        if not os.path.isdir(full):
            continue
        # Subtask dirs contain a subtask README (have a 4-digit sequence number)
        parts = entry.lstrip("X-").split("-")
        # Subtask names look like <hex>-NNNN-<name>; skip non-subtask dirs
        if len(parts) < 3:
            continue
        try:
            int(parts[1])  # NNNN must be numeric
        except (ValueError, IndexError):
            continue
        if not entry.startswith("X-"):
            incomplete.append(entry)
    return incomplete


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <epic-root> <branch-name>")
        return 1

    tasks_root = sys.argv[1]
    branch = sys.argv[2]

    result = find_task(tasks_root, branch)
    if result is None:
        print(f"WARNING: no task found matching branch '{branch}' in {tasks_root}")
        print("         If this worktree is not associated with a task, removal is allowed.")
        print("         If it should be, create and complete the task first.")
        # Warn but do not block — not every worktree must have a task
        # (e.g. experiments). Exit 2 to signal "no task found" distinctly.
        return 2

    folder, task_dir = result
    task_path = os.path.join(tasks_root, folder, task_dir)

    errors = []

    # Check task itself is complete
    if folder != "complete":
        errors.append(f"Task is not complete (currently in '{folder}/'): {task_dir}")

    # Check all subtasks are done
    incomplete = incomplete_subtasks(task_path)
    for sub in incomplete:
        errors.append(f"Incomplete subtask: {sub}")

    if errors:
        print(f"ERROR: task for branch '{branch}' is not fully complete.")
        for e in errors:
            print(f"  - {e}")
        print()
        print("Complete all tasks and subtasks before removing the worktree.")
        return 1

    print(f"Task '{task_dir}' is complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
