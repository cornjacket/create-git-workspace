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
#
# A NON-ZERO EXIT HERE MEANS "no such folder", NOT "something broke". Generated
# task-systems differ by version — an older epic has no `inbox` — and treating
# that as fatal once took down the entire run: `set -e` plus `pipefail` killed
# the script mid-repo, and every repo after it silently lost its plan, unnamed.
# The interface is verified once up front (`check_lister`); past that point an
# absent folder is simply an empty one.
list_folder() {
  local out
  out=$("$1/scripts/list-tasks.sh" --folder "$2" --depth 1 --all 2>/dev/null) || return 0
  printf '%s\n' "$out" | sed -n 's/^    \([^ ].*\)$/\1/p'
}

# check_lister <tasks-dir> — does this task-system speak the interface we read?
#
# Verify before trusting, rather than discovering a mismatch through an exit
# code halfway through rendering. We scrape human output from another
# generator's script, so the coupling is real and the failure must be loud: a
# lister we cannot read produces a SKIP with a reason, never a plausible-looking
# empty plan. `in-progress` is the probe because every generated epic has it.
check_lister() {
  "$1/scripts/list-tasks.sh" --folder in-progress --depth 1 --all >/dev/null 2>&1
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
failed=0   # had a task-system we could not finish reading

# render_body <plan-path> <tasks-dir> <kind> <label> — the file, to stdout.
render_body() {
  local plan=$1 tasks=$2 kind=$3 label=$4
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
  }
}

# render <plan-path> <tasks-dir> <kind> <label>
#
# The label is already printed by the caller, so this prints only the outcome.
# That ordering is deliberate: naming the repo BEFORE working on it means a
# crash leaves its name on the line, instead of dying anonymously between two
# repos and forcing a bisect to find which one.
render() {
  local plan=$1 tasks=$2 kind=$3 label=$4 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/replan.XXXXXX")

  # Build in a subshell that keeps `set -e` on, so a partial render fails here
  # instead of being installed as a truncated plan. A half-written plan is worse
  # than none: it looks authoritative.
  if ! ( set -e; render_body "$plan" "$tasks" "$kind" "$label" ) > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    printf 'could not draft — skipped (its task-system did not read cleanly)\n'
    failed=$((failed + 1))
    return 1
  fi

  mkdir -p "$(dirname "$plan")"
  if [ -f "$plan" ] && cmp -s "$tmp" "$plan"; then
    rm -f "$tmp"
    printf 'already current\n'
    usable=$((usable + 1))
    return 0
  fi
  mv "$tmp" "$plan"
  printf 'redrafted\n'
  drafted=$((drafted + 1))
  usable=$((usable + 1))
}

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

printf '\033[1m==>\033[0m Redrafting daily plans for %s\n' "$DATE"

# The workspace's own plan, from its own task-system.
if want "_workspace"; then
  printf '    %-24s ' "_workspace"
  if [ ! -d "$WORKSPACE_DIR/project/tasks" ]; then
    printf 'no task-system at .workspace/project/tasks — skipped\n'
    skipped=$((skipped + 1))
  elif ! check_lister "$WORKSPACE_DIR/project/tasks"; then
    printf 'task-system does not answer list-tasks.sh — skipped\n'
    skipped=$((skipped + 1))
  else
    render "$WORKSPACE_DIR/daily-plans/_workspace/daily-plan.md" \
           "$WORKSPACE_DIR/project/tasks" workspace "_workspace" || true
  fi
fi

# One per enabled repo that is checked out AND carries a task-system. A repo
# without one is skipped rather than given an empty plan: an empty plan reads as
# "nothing to do", which is a different claim from "this repo does not track
# tasks here".
#
# ONE BAD REPO MUST NOT TRUNCATE THE ROSTER. Every outcome below is per-repo and
# non-fatal: the loop always reaches the last entry, and whatever went wrong is
# reported at the end with a non-zero exit. A batch verb that stops at the first
# bad row is unusable as the roster grows — and worse, it stops *silently*.
while IFS=$'\t' read -r name type path branch parent url tags; do
  want "$name" || continue
  printf '    %-24s ' "$name"
  dest="$WORKSPACE_ROOT/$path"
  if [ ! -e "$dest/.git" ]; then
    printf 'not checked out — skipped\n'
    skipped=$((skipped + 1))
    continue
  fi
  if ! tasks=$(find_tasks_dir "$dest"); then
    printf 'no task-system — skipped\n'
    skipped=$((skipped + 1))
    continue
  fi
  if ! check_lister "$tasks"; then
    printf 'task-system does not answer list-tasks.sh — skipped\n'
    skipped=$((skipped + 1))
    continue
  fi
  render "$WORKSPACE_DIR/daily-plans/$name/daily-plan.md" "$tasks" repo "$name" || true
done < <(parse_enabled_repos)

# `usable` and `failed` count too: a --repo target that was already current, or
# that failed to draft, was still FOUND. Omitting them reported a real repo as
# "no target named ..." purely because nothing about it had changed.
if [ -n "$ONLY" ] && [ "$drafted" -eq 0 ] && [ "$skipped" -eq 0 ] \
   && [ "$usable" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "replan: no target named '$ONLY' (use a repo name, or _workspace)." >&2
  exit 2
fi

echo
if [ "$drafted" -gt 0 ]; then
  printf '%d plan(s) redrafted. Review them (git diff) and commit yourself —\n' "$drafted"
  printf 'replan never commits.\n'
elif [ "$usable" -gt 0 ]; then
  echo "Every plan was already current — nothing changed."
elif [ "$failed" -eq 0 ]; then
  # Nothing was readable at all. A silent exit 0 here would look like success
  # while producing no plan whatsoever, which is the one outcome worth failing on.
  echo "replan: no task-system to derive a plan from." >&2
  echo "        The workspace plan comes from .workspace/project/tasks, and a repo's" >&2
  echo "        from its own task-system. Install one (setup.sh without --no-tasks)," >&2
  echo "        or curate tasks in the repos you want plans for." >&2
  exit 1
fi

# Reported at the END, after every other repo has been drafted. The failure is
# loud in the exit code and named in the output above, but it never costs the
# rest of the roster its plans.
if [ "$failed" -gt 0 ]; then
  echo >&2
  echo "replan: $failed plan(s) could not be drafted — named above." >&2
  echo "        Every other repo was still drafted; one unreadable task-system" >&2
  echo "        does not truncate the roster." >&2
  exit 1
fi
exit 0
