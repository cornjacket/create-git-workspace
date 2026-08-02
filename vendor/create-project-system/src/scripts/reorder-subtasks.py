#!/usr/bin/env python3
"""
reorder-subtasks.py - Reorder subtasks within a task directory.

The four-digit number prefix in subtask directory names reflects ordering.
This script reassigns those numbers to match a new desired sequence while
preserving task names and all file content references.

Usage:
    # Print current order (no-op)
    python3 reorder-subtasks.py [--task-dir DIR]

    # Preview renames without applying (dry run)
    python3 reorder-subtasks.py [--task-dir DIR] name-a name-b name-c ...

    # Apply renames
    python3 reorder-subtasks.py [--task-dir DIR] --apply name-a name-b name-c ...

Names are task base-names only — strip the leading `{parent-id}-{NNNN}-`
and the `X-` completed prefix before passing them. Example:

    # Swap tasks 0001 and 0003 in 49352f:
    python3 reorder-subtasks.py \\
        oracle-goal-context-in-task-json \\
        architect-decompose-returns-components-json \\
        decompose-handler-dual-tree-and-output-dir \\
        orchestrator-job-param-replace-current-job-txt \\
        ...

Rules:
- X- (completed) tasks keep their X- prefix but are renumbered like any other.
- All current subtasks must appear in the provided list — no omissions.
- Numbers are assigned 0000, 0001, 0002... in the order given.
- File content references (README.md, task.json, etc.) are updated to match.
- Rename is done in two phases (→ tmp → final) to avoid conflicts when two
  tasks swap numbers.
"""

import argparse
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

SUBTASK_RE = re.compile(r'^(X-)?([0-9a-f]{6})-(\d{4})-(.+)$')


def parse_subtask_dirname(dirname: str):
    """
    Parse a subtask directory name into its parts.

    Returns (completed, parent_id, number_str, name) or None.
    Examples:
        49352f-0001-foo-bar   → (False, "49352f", "0001", "foo-bar")
        X-49352f-0001-foo-bar → (True,  "49352f", "0001", "foo-bar")
    """
    m = SUBTASK_RE.match(dirname)
    if not m:
        return None
    return (bool(m.group(1)), m.group(2), m.group(3), m.group(4))


def load_subtasks(task_dir: Path):
    """
    Return all subtask entries sorted by current number.
    Each entry: (completed, parent_id, number_str, name, dirpath)
    """
    entries = []
    for entry in task_dir.iterdir():
        if not entry.is_dir():
            continue
        parsed = parse_subtask_dirname(entry.name)
        if parsed is None:
            continue
        completed, parent_id, number_str, name = parsed
        entries.append((completed, parent_id, number_str, name, entry))
    entries.sort(key=lambda e: e[2])  # sort by current number
    return entries


# ---------------------------------------------------------------------------
# Rename plan
# ---------------------------------------------------------------------------

def build_rename_plan(subtasks, new_order_names, parent_id):
    """
    Given the desired name order, produce a list of (old_dirname, new_dirname)
    pairs for every subtask whose number changes.
    """
    name_to_entry = {}
    for completed, pid, number_str, name, dirpath in subtasks:
        if name in name_to_entry:
            print(f"ERROR: duplicate task name '{name}'", file=sys.stderr)
            sys.exit(1)
        name_to_entry[name] = (completed, pid, number_str, dirpath)

    known = set(name_to_entry)
    provided = set(new_order_names)

    unknown = provided - known
    if unknown:
        print(f"ERROR: unknown task name(s): {', '.join(sorted(unknown))}", file=sys.stderr)
        sys.exit(1)

    missing = known - provided
    if missing:
        print(
            f"ERROR: the following tasks are missing from the new order:\n"
            + "\n".join(f"  {n}" for n in sorted(missing)),
            file=sys.stderr,
        )
        sys.exit(1)

    plan = []
    for new_idx, name in enumerate(new_order_names):
        completed, pid, old_number_str, dirpath = name_to_entry[name]
        old_dirname = dirpath.name
        prefix = "X-" if completed else ""
        new_dirname = f"{prefix}{parent_id}-{new_idx:04d}-{name}"
        if old_dirname != new_dirname:
            plan.append((old_dirname, new_dirname))

    return plan


# ---------------------------------------------------------------------------
# File content update
# ---------------------------------------------------------------------------

CONTENT_EXTENSIONS = {".md", ".json", ".txt", ".sh", ".py"}


def find_files_with_references(task_dir: Path, old_names: list[str]) -> list[Path]:
    """Return all files under task_dir that contain any of the old names."""
    hits = []
    for filepath in sorted(task_dir.rglob("*")):
        if not filepath.is_file():
            continue
        if filepath.suffix not in CONTENT_EXTENSIONS:
            continue
        try:
            content = filepath.read_text(encoding="utf-8")
        except Exception:
            continue
        if any(name in content for name in old_names):
            hits.append(filepath)
    return hits


def sort_subtask_list(content: str) -> str:
    """
    Re-sort the lines inside the <!-- subtask-list-start/end --> block
    of a task README.md in ascending numeric order.

    Lines look like:
        - [ ] [49352f-0003-foo](49352f-0003-foo/)
        - [x] [X-49352f-0001-bar](X-49352f-0001-bar/)
    """
    start_marker = "<!-- subtask-list-start -->"
    end_marker = "<!-- subtask-list-end -->"

    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker)
    if start_idx == -1 or end_idx == -1:
        return content

    block_start = start_idx + len(start_marker)
    block = content[block_start:end_idx]

    # Extract the number from a subtask list line for sorting.
    # Handles both normal and X- (completed) entries.
    num_re = re.compile(r'\[(?:X-)?[0-9a-f]{6}-(\d{4})-')

    lines = block.splitlines(keepends=True)
    list_lines = [l for l in lines if l.strip().startswith("- ")]
    other_lines = [l for l in lines if not l.strip().startswith("- ")]

    def sort_key(line):
        m = num_re.search(line)
        return int(m.group(1)) if m else 9999

    sorted_list = sorted(list_lines, key=sort_key)
    new_block = "".join(other_lines[:1]) + "".join(sorted_list) + "".join(other_lines[1:])

    return content[:block_start] + new_block + content[end_idx:]


def apply_content_replacements(files: list[Path], plan: list[tuple[str, str]], task_dir: Path):
    """
    Replace all occurrences of old dirnames with new dirnames in file content.
    For the parent task README.md, also re-sorts the subtask list by number.
    """
    parent_readme = task_dir / "README.md"
    for filepath in files:
        try:
            content = filepath.read_text(encoding="utf-8")
        except Exception as e:
            print(f"  WARNING: could not read {filepath}: {e}")
            continue
        new_content = content
        for old_dirname, new_dirname in plan:
            new_content = new_content.replace(old_dirname, new_dirname)
        # Re-sort the subtask list in the parent README after replacements.
        if filepath.resolve() == parent_readme.resolve():
            new_content = sort_subtask_list(new_content)
        if new_content != content:
            filepath.write_text(new_content, encoding="utf-8")
            print(f"  updated: {filepath.relative_to(task_dir)}")


# ---------------------------------------------------------------------------
# Rename directories (two-phase to avoid conflicts on number swaps)
# ---------------------------------------------------------------------------

def rename_directories(task_dir: Path, plan: list[tuple[str, str]], dry_run: bool):
    """
    Rename directories according to plan.
    Phase 1: rename each old → _tmp_{old}
    Phase 2: rename each _tmp_{old} → new
    This avoids conflicts when two tasks swap numbers.
    """
    # Phase 1: old → tmp
    tmp_map = {}  # old_dirname → tmp_dirname
    for old_dirname, new_dirname in plan:
        tmp_dirname = f"_tmp_{old_dirname}"
        if not dry_run:
            (task_dir / old_dirname).rename(task_dir / tmp_dirname)
        tmp_map[old_dirname] = tmp_dirname
        print(f"  {old_dirname}")
        print(f"    → {new_dirname}")

    # Phase 2: tmp → new
    if not dry_run:
        for old_dirname, new_dirname in plan:
            tmp_dirname = tmp_map[old_dirname]
            (task_dir / tmp_dirname).rename(task_dir / new_dirname)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def find_task_dir(start: Path) -> Path | None:
    """
    Find a task directory by looking for subtask entries in start or its parents.
    Returns the first directory that contains at least one subtask-pattern entry.
    """
    candidate = start.resolve()
    for _ in range(6):
        entries = list(candidate.iterdir()) if candidate.is_dir() else []
        if any(SUBTASK_RE.match(e.name) for e in entries if e.is_dir()):
            return candidate
        if candidate.parent == candidate:
            break
        candidate = candidate.parent
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Reorder subtasks within a task directory.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--task-dir", type=Path,
        help="Task directory (default: auto-detect from cwd)",
    )
    parser.add_argument(
        "--apply", action="store_true",
        help="Apply renames and content updates (default: dry run)",
    )
    parser.add_argument(
        "names", nargs="*",
        help="Task base-names in the desired new order",
    )
    args = parser.parse_args()

    # Resolve task directory
    task_dir = args.task_dir or find_task_dir(Path.cwd())
    if task_dir is None:
        print(
            "ERROR: could not find a task directory containing subtasks.\n"
            "Run from inside a task directory or pass --task-dir.",
            file=sys.stderr,
        )
        sys.exit(1)
    task_dir = task_dir.resolve()

    # Load current subtasks
    subtasks = load_subtasks(task_dir)
    if not subtasks:
        print(f"No subtasks found in {task_dir}", file=sys.stderr)
        sys.exit(1)

    parent_id = subtasks[0][1]  # hex ID shared by all siblings

    # No names provided → print current order and exit
    if not args.names:
        print(f"Task directory: {task_dir}")
        print(f"\nCurrent order ({len(subtasks)} subtasks):")
        for completed, pid, number_str, name, dirpath in subtasks:
            prefix = "X-" if completed else "  "
            print(f"  {prefix}{pid}-{number_str}-{name}")
        print("\nPass task base-names in the new desired order to reorder.")
        print("Use --apply to write changes.")
        sys.exit(0)

    # Build rename plan
    plan = build_rename_plan(subtasks, args.names, parent_id)

    mode = "DRY RUN" if not args.apply else "APPLYING"
    print(f"Task directory: {task_dir}")

    if plan:
        print(f"\n[{mode}] {len(plan)} director{'y' if len(plan) == 1 else 'ies'} to rename:\n")

        # Find files with references before renaming
        old_names = [old for old, new in plan]
        files = find_files_with_references(task_dir, old_names)

        # Rename directories
        rename_directories(task_dir, plan, dry_run=not args.apply)

        # Update file content (includes subtask list sort for parent README)
        if files:
            print(f"\n{'Updating' if args.apply else 'Would update'} {len(files)} file(s):")
            if args.apply:
                apply_content_replacements(files, plan, task_dir)
            else:
                for f in files:
                    print(f"  {f.relative_to(task_dir)}")
    else:
        print("\nNo directory renames needed.")

    # Always sort the parent README subtask list when applying, even if no
    # renames were needed (e.g. the list got out of order some other way).
    if args.apply:
        parent_readme = task_dir / "README.md"
        if parent_readme.exists():
            original = parent_readme.read_text(encoding="utf-8")
            sorted_content = sort_subtask_list(original)
            if sorted_content != original:
                parent_readme.write_text(sorted_content, encoding="utf-8")
                print(f"\nRe-sorted subtask list in README.md")

    if not args.apply:
        print("\nDry run complete. Pass --apply to make changes.")
    else:
        print("\nDone.")


if __name__ == "__main__":
    main()
