#!/usr/bin/env bash
# replan.sh — redraft daily plans from task state. No model calls, ever.
#
#   replan.sh [--date YYYY-MM-DD] [--repo NAME]
#
# Targets every enabled repo that has a task-system, plus the workspace's own
# plan. `--repo NAME` does one (use `_workspace` for the workspace's own).
#
# A PLAN HERE IS A REPORT, NOT AN ACT OF PLANNING. The thinking already happened
# when you decided which task is in progress and which is next; this projects
# that state into a plan-shaped file so the aggregator can read it. Hence no
# `claude -p`: nothing here requires judgement, and a model that invents a
# plausible next step you never chose would put work in your rollup that you
# never agreed to.
#
# TWO INVARIANTS, both load-bearing:
#
#   * Draft-only. This writes plan files and stops. It never stages, commits, or
#     pushes. Git is the review surface: each redrafted plan shows up as a
#     modified file, and approving it means committing it yourself.
#   * The plan is DERIVED from task state, not invented. You encode intent by
#     curating tasks; this reads that state and never edits it.
#
# Section ownership: the derived sections (In progress / Next up / Triage) are
# rewritten every run, and everything from `## Notes` onward is yours and is
# preserved verbatim.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DATE=""
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --date) DATE=${2:-}; shift 2 ;;
    --repo) ONLY=${2:-}; shift 2 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "replan: unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$DATE" ] || DATE=$(date +%Y-%m-%d)
case "$DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "replan: --date must be YYYY-MM-DD, got '$DATE'" >&2; exit 2 ;;
esac

# find_tasks_dir <repo-root> — the task-system inside it, or nothing.
#
# Probed rather than configured: create-project-system mounts at `project/tasks`
# by default and `tasks/` when installed bare, and those two cover every repo we
# stamp. A repos.yml field would be one more thing to keep true.
find_tasks_dir() {
  local root=$1 candidate
  for candidate in "$root/project/tasks" "$root/tasks"; do
    if [ -x "$candidate/scripts/list-tasks.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# list_folder <tasks-dir> <status> — task ids in that status folder.
# Reads the task-system's own lister rather than globbing directories, so the
# folder layout stays that generator's business.
list_folder() {
  "$1/scripts/list-tasks.sh" --folder "$2" --depth 1 --all 2>/dev/null \
    | sed -n 's/^    \([^ ].*\)$/\1/p'
}

bullets() { # <empty-fallback>
  local any=0 line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    any=1
    printf -- "- [ ] %s\n" "$line"
  done
  [ "$any" -eq 1 ] || printf -- "%s\n" "$1"
}

drafted=0
skipped=0
usable=0   # rendered OR already current — i.e. a target we could read

# render <plan-path> <tasks-dir> <kind> <label>
render() {
  local plan=$1 tasks=$2 kind=$3 label=$4 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/replan.XXXXXX")
  {
    printf '# Daily plan — %s\n\n' "$DATE"
    if [ "$kind" = workspace ]; then
      printf '_Workspace-scoped work: inter-repo tasks, infrastructure, and ideas that have no\n'
      printf 'repo home yet. Forward-looking only — the workspace'"'"'s own commits are meta-noise,\n'
      printf 'so this plan has no retrospective half._\n\n'
      printf '_Derived from `.workspace/project/tasks` by `make replan`. Draft only: review the diff and\n'
      printf 'commit it yourself._\n\n'
    else
      printf '_Your plan for `%s`. Per-developer: it lives in this workspace, not in the\n' "$label"
      printf 'shared repo, so two developers never collide over one plan file._\n\n'
      printf '_Derived from `%s` by `make replan`. Draft only: review the diff and\n' "${tasks#$WORKSPACE_ROOT/}"
      printf 'commit it yourself._\n\n'
    fi

    printf '## In progress\n\n'
    list_folder "$tasks" in-progress | bullets "_Nothing in progress._"
    printf '\n## Next up\n\n'
    list_folder "$tasks" backlog | bullets "_Nothing queued._"
    printf '\n## Triage\n\n'
    { list_folder "$tasks" inbox; list_folder "$tasks" draft; } | bullets "_Nothing in triage._"
    if [ "$kind" = workspace ]; then
      printf '\n_A workspace task graduates when it earns a repo: add a subtask "create repo X",\n'
      printf 'run `add-repo`, then file a task in that child to do the work._\n'
    fi

    # Preserve the human's half verbatim, or start one.
    if [ -f "$plan" ] && grep -q '^## Notes' "$plan"; then
      printf '\n'
      sed -n '/^## Notes/,$p' "$plan"
    else
      printf '\n## Notes\n\n'
      printf '_Everything below the Notes heading is yours — `replan` never rewrites it._\n'
    fi
  } > "$tmp"

  mkdir -p "$(dirname "$plan")"
  if [ -f "$plan" ] && cmp -s "$tmp" "$plan"; then
    rm -f "$tmp"
    printf '    %-24s already current\n' "$label"
    usable=$((usable + 1))
    return 0
  fi
  mv "$tmp" "$plan"
  printf '    %-24s redrafted\n' "$label"
  drafted=$((drafted + 1))
  usable=$((usable + 1))
}

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

printf '\033[1m==>\033[0m Redrafting daily plans for %s\n' "$DATE"

# The workspace's own plan, from its own task-system.
if want "_workspace"; then
  if [ -d "$WORKSPACE_DIR/project/tasks" ]; then
    render "$WORKSPACE_DIR/daily-plans/_workspace/daily-plan.md" \
           "$WORKSPACE_DIR/project/tasks" workspace "_workspace"
  else
    printf '    %-24s no task-system at .workspace/project/tasks — skipped\n' "_workspace"
    skipped=$((skipped + 1))
  fi
fi

# One per enabled repo that is checked out AND carries a task-system. A repo
# without one is skipped rather than given an empty plan: an empty plan reads as
# "nothing to do", which is a different claim from "this repo does not track
# tasks here".
while IFS=$'\t' read -r name type path branch parent url tags; do
  want "$name" || continue
  dest="$WORKSPACE_ROOT/$path"
  if [ ! -e "$dest/.git" ]; then
    printf '    %-24s not checked out — skipped\n' "$name"
    skipped=$((skipped + 1))
    continue
  fi
  if ! tasks=$(find_tasks_dir "$dest"); then
    printf '    %-24s no task-system — skipped\n' "$name"
    skipped=$((skipped + 1))
    continue
  fi
  render "$WORKSPACE_DIR/daily-plans/$name/daily-plan.md" "$tasks" repo "$name"
done < <(parse_enabled_repos)

if [ -n "$ONLY" ] && [ "$drafted" -eq 0 ] && [ "$skipped" -eq 0 ]; then
  echo "replan: no target named '$ONLY' (use a repo name, or _workspace)." >&2
  exit 2
fi

echo
if [ "$drafted" -gt 0 ]; then
  printf '%d plan(s) redrafted. Review them (git diff) and commit yourself —\n' "$drafted"
  printf 'replan never commits.\n'
  exit 0
fi

if [ "$usable" -gt 0 ]; then
  echo "Every plan was already current — nothing changed."
  exit 0
fi

# Nothing was readable at all. A silent exit 0 here would look like success while
# producing no plan whatsoever, which is the one outcome worth failing on.
echo "replan: no task-system to derive a plan from." >&2
echo "        The workspace plan comes from .workspace/project/tasks, and a repo's" >&2
echo "        from its own task-system. Install one (setup.sh without --no-tasks)," >&2
echo "        or curate tasks in the repos you want plans for." >&2
exit 1
