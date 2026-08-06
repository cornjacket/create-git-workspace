#!/usr/bin/env bash
# run-tests.sh — acceptance harness for create-git-workspace.
#
# Everything runs against throwaway targets in the gitignored sandbox/ — never a
# real repo. The headline assertion is ZERO-DIFF REGENERATION: update.sh over an
# already-current workspace must leave `git diff` empty, with no --force.
#
#   ./tests/run-tests.sh            run the local suite, wipe sandbox/ after
#   ./tests/run-tests.sh --keep     leave sandbox/ in place for inspection
#   ./tests/run-tests.sh --remote   also run the GitHub round-trip (network;
#                                   needs the ../git-workspace-test fixture)
#
# Assertions never abort the run — every test executes and the summary reports
# the total. A failing harness should tell you everything that broke at once.
set -uo pipefail

GEN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$GEN_ROOT/sandbox"
TEST_AUTHOR="test@example.invalid"

KEEP=0
RUN_REMOTE=0
for arg in "$@"; do
  case "$arg" in
    --keep)   KEEP=1 ;;
    --remote) RUN_REMOTE=1 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# The files THIS generator emits. Update deliberately when a task adds one — a
# surprise here means the generator started emitting something unplanned.
#
# Deliberately excludes the delegated task-system (.workspace/project/, .claude/) and the
# routine-owned deliverables: those sets are owned by the vendored generator and
# the daily run, so pinning their exact paths here would make an upstream
# re-vendor look like a regression in our tree. `ours()` filters them out and
# test_task_system asserts them by contract instead.
EXPECTED_TRACKED="\
.github/workflows/auto-merge-status.yml
.github/workflows/claude.yml
.gitignore
.workspace/config.yml
.workspace/daily-plans/_workspace/daily-plan.md
.workspace/prompts/per-repo.md
.workspace/prompts/polish.md
.workspace/repos.yml
.workspace/scripts/_repos_edit.py
.workspace/scripts/_status_lib.py
.workspace/scripts/add-repo.py
.workspace/scripts/aggregate-plans.py
.workspace/scripts/bootstrap.sh
.workspace/scripts/daily.sh
.workspace/scripts/delete-repo.py
.workspace/scripts/guard.sh
.workspace/scripts/inject-kernel.py
.workspace/scripts/install-hooks.sh
.workspace/scripts/lib.sh
.workspace/scripts/mute-repo.py
.workspace/scripts/new-work.py
.workspace/scripts/pull.sh
.workspace/scripts/render-readme.py
.workspace/scripts/replan.sh
.workspace/scripts/routine-registered.py
.workspace/scripts/run.py
.workspace/scripts/status.py
.workspace/scripts/sync.py
.workspace/status-guide.md
.workspace/templates/commit-kernel.md
CLAUDE.md
Makefile
README.md"

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
else G=""; R=""; Y=""; B=""; D=""; X=""; fi

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf "  ${G}✓${X} %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "  ${R}✗ %s${X}\n" "$1"; [ $# -gt 1 ] && printf "      ${D}%s${X}\n" "$2"; }
skip() { SKIP=$((SKIP+1)); printf "  ${Y}–${X} %s ${D}(skipped: %s)${X}\n" "$1" "$2"; }
section() { printf "\n${B}%s${X}\n" "$1"; }

assert_empty()   { if [ -z "$2" ]; then ok "$1"; else bad "$1" "expected empty, got: $2"; fi; }
assert_eq()      { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
assert_file()    { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing file: $2"; fi; }
assert_no_file() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "file should not exist: $2"; fi; }
assert_exec()    { if [ -x "$2" ]; then ok "$1"; else bad "$1" "not executable: $2"; fi; }
# `--` matters: a pattern starting with '-' would otherwise be read as an option.
assert_grep()    { if grep -qE -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1" "pattern not found in $3: $2"; fi; }
assert_no_grep() { if grep -qE -- "$2" "$3" 2>/dev/null; then bad "$1" "pattern SHOULD be absent from $3: $2"; else ok "$1"; fi; }
# assert_fails — the command must exit non-zero (used for the refusal paths).
assert_fails()   { local l=$1; shift; if "$@" >/dev/null 2>&1; then bad "$l" "command unexpectedly succeeded: $*"; else ok "$l"; fi; }
# assert_succeeds — the mirror. Needed because "exits 0" is itself a contract in
# places: a verb that refuses a legitimate target is as wrong as one that
# accepts a bad one.
assert_succeeds() { local l=$1; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l" "command unexpectedly failed: $*"; fi; }

ws_clean() { # a workspace with no diff AND no untracked/modified files
  [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

# The suite runs on both macOS and Linux CI, so no BSD-only idioms.
# `sed -i ''` is a syntax error under GNU sed, and `shasum` is not guaranteed.
file_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum "$1" | cut -d' ' -f1
  elif command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -d' ' -f1
  else cksum "$1" | cut -d' ' -f1
  fi
}

subst_in_file() { # subst_in_file <file> <literal-from> <literal-to>
  python3 - "$@" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace(sys.argv[2], sys.argv[3]))
PY
}

# ours <ws> — tracked files this generator owns, excluding the delegated
# task-system and the routine-owned deliverables.
ours() {
  git -C "$1" ls-files \
    | grep -v -E '^(\.workspace/project/|\.claude/|summary\.md$|daily-plan-summary\.md$)'
}

new_ws() { # new_ws <name> [extra setup.sh args...] -> path on stdout
  local name=$1; shift
  local d="$SANDBOX/$name"
  rm -rf "$d"
  "$GEN_ROOT/setup.sh" "$d" --name "$name" --author "$TEST_AUTHOR" "$@" >/dev/null 2>&1
  printf '%s\n' "$d"
}

# ---------------------------------------------------------------------------
# 1. Emitted tree + allowlist
# ---------------------------------------------------------------------------
test_emitted_tree() {
  section "1. Emitted tree and allowlist"
  local ws; ws=$(new_ws ws-tree)

  assert_eq "tracked file set is exactly the emitted tree" \
    "$EXPECTED_TRACKED" "$(ours "$ws")"
  assert_empty "nothing is left untracked by the allowlist" "$(git -C "$ws" status --porcelain)"

  assert_file "hidden control plane exists"      "$ws/.workspace"
  assert_exec "scripts are executable"           "$ws/.workspace/scripts/status.py"
  assert_grep "allowlist ignores the root"       '^/\*$' "$ws/.gitignore"
  assert_grep "allowlist un-ignores .workspace/" '^!/\.workspace/$' "$ws/.gitignore"
  assert_no_grep "no placeholders survive in CLAUDE.md" '\{\{' "$ws/CLAUDE.md"
  assert_no_grep "no placeholders survive in README"    '\{\{' "$ws/README.md"
  assert_grep "config.yml carries the author"     "$TEST_AUTHOR" "$ws/.workspace/config.yml"

  # A child checkout must be invisible to the wrapper's index.
  mkdir -p "$ws/childrepo" && git -C "$ws/childrepo" init -q
  echo hi > "$ws/childrepo/f.txt"
  git -C "$ws/childrepo" add -A
  git -C "$ws/childrepo" -c user.email=t@t -c user.name=t commit -qm init
  git -C "$ws" add -A 2>/dev/null
  assert_empty "child repo stays out of the wrapper index" "$(git -C "$ws" status --porcelain)"
}

# ---------------------------------------------------------------------------
# 2. The generated scripts work (WORKSPACE_ROOT resolves two levels up)
# ---------------------------------------------------------------------------
test_generated_scripts() {
  section "2. Generated scripts resolve their workspace root"
  local ws; ws=$(new_ws ws-scripts)
  mkdir -p "$ws/childrepo" && git -C "$ws/childrepo" init -q
  echo hi > "$ws/childrepo/f.txt"
  git -C "$ws/childrepo" add -A
  git -C "$ws/childrepo" -c user.email=t@t -c user.name=t commit -qm init
  cat > "$ws/.workspace/repos.yml" <<'YML'
repos:
  - name: childrepo
    path: childrepo
    type: standard
    branch: main
    url: https://example.invalid/childrepo.git
    routine_registered: true
YML
  # `routine_registered: true` above is load-bearing: without it the repo is in
  # the manifest but not in the routine's `sources`, which status correctly
  # reports as pending. 8p covers that gate; here it must be out of the way.
  #
  # The workspace is a row in its own report, so its edits must be committed or
  # the sweep correctly calls them pending.
  git -C "$ws" add -A; git -C "$ws" commit -qm "register childrepo"

  # Run from an unrelated cwd: the scripts must not depend on the caller's pwd.
  local out rc
  out=$(cd / && "$ws/.workspace/scripts/status.py" 2>&1); rc=$?
  assert_eq "status exits 0 when nothing is pending" "0" "$rc"
  case "$out" in
    *childrepo*clean*) ok "status reports the child clean" ;;
    *) bad "status reports the child clean" "$out" ;;
  esac
  case "$out" in
    *"(this workspace)"*) ok "the workspace itself is a row" ;;
    *) bad "the workspace itself is a row" "$out" ;;
  esac

  echo dirty > "$ws/childrepo/f.txt"
  (cd / && "$ws/.workspace/scripts/status.py" >/dev/null 2>&1)
  assert_eq "status exits non-zero when a child is dirty" "1" "$?"

  out=$(cd / && "$ws/.workspace/scripts/guard.sh" 2>&1); rc=$?
  assert_eq "guard.sh passes on a clean wrapper index" "0" "$rc"
}

# ---------------------------------------------------------------------------
# 3. ZERO-DIFF REGENERATION — the headline invariant
# ---------------------------------------------------------------------------
test_zero_diff() {
  section "3. Zero-diff regeneration (the headline test)"
  local ws; ws=$(new_ws ws-zero)

  assert_empty "setup.sh leaves a committed, clean workspace" "$(git -C "$ws" status --porcelain)"

  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "update.sh over a current workspace: git diff empty" "$(git -C "$ws" diff)"
  assert_empty "update.sh over a current workspace: nothing modified/untracked" "$(git -C "$ws" status --porcelain)"

  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "repeated updates stay at zero diff" "$(git -C "$ws" status --porcelain)"
}

# ---------------------------------------------------------------------------
# 4. Machinery is overwritten; stale machinery is pruned
# ---------------------------------------------------------------------------
test_machinery() {
  section "4. Machinery: restored and pruned"
  local ws; ws=$(new_ws ws-machinery)

  echo 'echo VANDALIZED' >> "$ws/.workspace/scripts/status.py"
  echo '#!/bin/sh' > "$ws/.workspace/scripts/retired.sh"
  echo '# vandalized' >> "$ws/Makefile"
  git -C "$ws" add -A
  git -C "$ws" commit -qm "vandalize machinery"

  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_no_grep "vandalized status.sh is restored" 'VANDALIZED' "$ws/.workspace/scripts/status.py"
  assert_no_grep "vandalized Makefile is restored"  'vandalized' "$ws/Makefile"
  assert_no_file "a script dropped from the template is pruned" "$ws/.workspace/scripts/retired.sh"

  git -C "$ws" add -A
  git -C "$ws" commit -qm restore
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "and it settles back to zero diff" "$(git -C "$ws" status --porcelain)"
}

# ---------------------------------------------------------------------------
# 5. Content and runtime are never touched
# ---------------------------------------------------------------------------
test_content_and_runtime() {
  section "5. Content is never overwritten; runtime is never touched"
  local ws; ws=$(new_ws ws-content)

  echo "# hand-written note" >> "$ws/.workspace/repos.yml"
  echo "My own house rule." >> "$ws/README.md"
  printf '\n## My directives\n\nNever push on Fridays.\n' >> "$ws/CLAUDE.md"
  printf 'name: %s\ngit_author:\n  - me@real.example\ngenerator_version: 0.1.0\n' "ws-content" \
    > "$ws/.workspace/config.yml"
  mkdir -p "$ws/.workspace/state"
  echo '{"seen":"abc123"}' > "$ws/.workspace/state/state.json"
  echo '# routine-owned summary' > "$ws/summary.md"

  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1

  assert_grep "repos.yml edit survives"          '# hand-written note'   "$ws/.workspace/repos.yml"
  assert_grep "README edit survives"             'My own house rule\.'   "$ws/README.md"
  assert_grep "user CLAUDE.md directives survive" 'Never push on Fridays' "$ws/CLAUDE.md"
  assert_grep "config.yml git_author survives"   'me@real\.example'      "$ws/.workspace/config.yml"
  assert_grep "runtime state.json untouched"     'abc123'                "$ws/.workspace/state/state.json"
  assert_grep "runtime summary.md untouched"     'routine-owned summary' "$ws/summary.md"

  # A content slot introduced by a newer generator version must reach a workspace
  # that already exists — "never overwrite" is not "never create". Only setup.sh
  # seeds, and setup.sh refuses to run on a live workspace, so without this an
  # upgraded workspace could never gain a new content file.
  rm -rf "$ws/.workspace/daily-plans"
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_file "a MISSING content slot is back-filled on update" \
    "$ws/.workspace/daily-plans/_workspace/daily-plan.md"
  assert_grep "...while existing content is still not overwritten" \
    '# hand-written note' "$ws/.workspace/repos.yml"
}

# ---------------------------------------------------------------------------
# 6. CLAUDE.md injection — three paths, four malformed shapes
# ---------------------------------------------------------------------------
test_claude_md() {
  section "6. CLAUDE.md marker-block injection"
  local d out

  # create
  d=$(new_ws ws-claude-create)
  assert_grep "no file -> created from template" '<!-- git-workspace:begin' "$d/CLAUDE.md"
  assert_grep "title carries the workspace name" '^# CLAUDE.md — ws-claude-create$' "$d/CLAUDE.md"
  # Inside the block too — the append path emits ONLY the block, so a name that
  # appears just in the title would vanish for a user who brought their own file.
  assert_grep "block substitutes the name"       '\(`ws-claude-create`\)'  "$d/CLAUDE.md"
  assert_grep "block carries a version echo"     'create-git-workspace v'  "$d/CLAUDE.md"

  # replace — a stale block is swapped, surrounding text preserved
  d="$SANDBOX/ws-claude-replace"; rm -rf "$d"; mkdir -p "$d"
  printf '# Mine\n\nABOVE\n\n<!-- git-workspace:begin x -->\nSTALE\n<!-- git-workspace:end -->\n\nBELOW\n' > "$d/CLAUDE.md"
  "$GEN_ROOT/setup.sh" "$d" --name wsclaude --author "$TEST_AUTHOR" --no-commit >/dev/null 2>&1
  assert_no_grep "stale block content is gone" 'STALE' "$d/CLAUDE.md"
  assert_grep "text above the block preserved" '^ABOVE$' "$d/CLAUDE.md"
  assert_grep "text below the block preserved" '^BELOW$' "$d/CLAUDE.md"

  # append — user's own file, no markers
  d="$SANDBOX/ws-claude-append"; rm -rf "$d"; mkdir -p "$d"
  printf '# Mine\nNo trailing newline.' > "$d/CLAUDE.md"   # deliberately unterminated
  "$GEN_ROOT/setup.sh" "$d" --name wsclaude --author "$TEST_AUTHOR" --no-commit >/dev/null 2>&1
  assert_eq   "user content stays first"   "# Mine" "$(head -1 "$d/CLAUDE.md")"
  assert_grep "block appended at the end"  '<!-- git-workspace:end -->' "$d/CLAUDE.md"
  local before after
  before=$(file_hash "$d/CLAUDE.md")
  "$GEN_ROOT/setup.sh" "$d" --name wsclaude --author "$TEST_AUTHOR" --no-commit --force >/dev/null 2>&1
  after=$(file_hash "$d/CLAUDE.md")
  assert_eq "re-injection is byte-identical (idempotent)" "$before" "$after"

  # malformed — must abort AND leave the file untouched
  local label body
  for case in \
    "begin marker with no end:# Mine\n<!-- git-workspace:begin x -->\nhalf\n" \
    "end marker with no begin:# Mine\n<!-- git-workspace:end -->\n" \
    "end marker before begin:# Mine\n<!-- git-workspace:end -->\nb\n<!-- git-workspace:begin x -->\n" \
    "duplicated managed block:<!-- git-workspace:begin a -->\nA\n<!-- git-workspace:end -->\n<!-- git-workspace:begin b -->\nB\n<!-- git-workspace:end -->\n"
  do
    label=${case%%:*}; body=${case#*:}
    d="$SANDBOX/ws-claude-bad"; rm -rf "$d"; mkdir -p "$d"
    printf '%b' "$body" > "$d/CLAUDE.md"
    before=$(file_hash "$d/CLAUDE.md")
    if "$GEN_ROOT/setup.sh" "$d" --name wsclaude --author "$TEST_AUTHOR" --no-commit >/dev/null 2>&1; then
      bad "$label -> aborts" "setup.sh succeeded on a malformed CLAUDE.md"
    else
      after=$(file_hash "$d/CLAUDE.md")
      assert_eq "$label -> aborts, file untouched" "$before" "$after"
    fi
  done
}

# ---------------------------------------------------------------------------
# 7. Generator version propagates, then settles
# ---------------------------------------------------------------------------
test_version_stamp() {
  section "7. Generator version stamp"
  # Work from a COPY of the generator so bumping VERSION never dirties the repo.
  local gen="$SANDBOX/gen-copy"
  rm -rf "$gen"; mkdir -p "$gen"
  cp -R "$GEN_ROOT/template" "$GEN_ROOT/lib" "$GEN_ROOT/vendor" \
        "$GEN_ROOT/setup.sh" "$GEN_ROOT/update.sh" "$GEN_ROOT/VERSION" "$gen/"

  local ws="$SANDBOX/ws-version"; rm -rf "$ws"
  "$gen/setup.sh" "$ws" --name ws-version --author "$TEST_AUTHOR" >/dev/null 2>&1
  assert_grep "config.yml stamped at setup" 'generator_version: 0\.1\.0' "$ws/.workspace/config.yml"

  echo "9.9.9" > "$gen/VERSION"
  "$gen/update.sh" "$ws" >/dev/null 2>&1
  assert_grep "config.yml key follows the bump"  'generator_version: 9\.9\.9' "$ws/.workspace/config.yml"
  assert_grep "CLAUDE.md echo follows the bump"  'create-git-workspace v9\.9\.9' "$ws/CLAUDE.md"
  assert_eq   "the bump moves exactly 2 files" "2" \
    "$(git -C "$ws" diff --name-only | wc -l | tr -d ' ')"

  git -C "$ws" add -A; git -C "$ws" commit -qm bump
  "$gen/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "and then settles to zero diff" "$(git -C "$ws" status --porcelain)"
}

# ---------------------------------------------------------------------------
# 8. Refusals and safety rails
# ---------------------------------------------------------------------------
test_refusals() {
  section "8. Refusals and safety rails"
  local ws; ws=$(new_ws ws-refuse)

  assert_fails "setup.sh refuses an existing workspace without --force" \
    "$GEN_ROOT/setup.sh" "$ws" --author "$TEST_AUTHOR"
  assert_empty "...and changes nothing when it refuses" "$(git -C "$ws" status --porcelain)"

  mkdir -p "$SANDBOX/not-a-ws"
  assert_fails "update.sh refuses a non-workspace directory" "$GEN_ROOT/update.sh" "$SANDBOX/not-a-ws"
  assert_fails "update.sh refuses a missing directory"       "$GEN_ROOT/update.sh" "$SANDBOX/nope"

  rm -rf "$SANDBOX/ws-badname"
  assert_fails "setup.sh rejects an invalid workspace name" \
    "$GEN_ROOT/setup.sh" "$SANDBOX/ws-badname" --name 'bad name/x'
  assert_no_file "...and leaves no stray directory behind" "$SANDBOX/ws-badname"

  # --no-status was removed in 018 (status IS the workspace layer, not an opt-in).
  # A flag that prints "skipped" and installs the subsystem anyway is worse than
  # no flag, so the removal is pinned: it must ERROR, not be silently ignored.
  rm -rf "$SANDBOX/ws-nostatus"
  assert_fails "setup.sh rejects the removed --no-status flag" \
    "$GEN_ROOT/setup.sh" "$SANDBOX/ws-nostatus" --name ws-nostatus --no-status
  assert_no_file "...and stamps nothing when it does" "$SANDBOX/ws-nostatus"
  local help="$SANDBOX/setup-help.txt"
  "$GEN_ROOT/setup.sh" --help > "$help" 2>&1
  assert_no_grep "--no-status is gone from the usage text" '\-\-no-status' "$help"
  assert_grep    "...while --no-tasks, which IS honored, remains" '\-\-no-tasks' "$help"

  # A rename must not rewrite the workspace name: it comes from config.yml.
  local renamed="$SANDBOX/ws-renamed"
  rm -rf "$renamed"; mv "$ws" "$renamed"
  "$GEN_ROOT/update.sh" "$renamed" >/dev/null 2>&1
  assert_grep "name survives a directory rename" '^# CLAUDE.md — ws-refuse$' "$renamed/CLAUDE.md"
  assert_empty "...and the rename produces no diff" "$(git -C "$renamed" status --porcelain)"

  # No git identity and no --author: stage, but never write a placeholder author
  # into history.
  local home; home=$(mktemp -d)
  rm -rf "$SANDBOX/ws-noident"
  env HOME="$home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    "$GEN_ROOT/setup.sh" "$SANDBOX/ws-noident" --name ws-noident >/dev/null 2>&1
  assert_fails "no git identity -> no commit is created" \
    git -C "$SANDBOX/ws-noident" rev-parse HEAD
  assert_grep "...and config.yml carries the loud placeholder" \
    'CHANGEME@example\.invalid' "$SANDBOX/ws-noident/.workspace/config.yml"
  rm -rf "$home"
}

# ---------------------------------------------------------------------------
# 8b. Delegated task-system (vendored create-project-system)
# ---------------------------------------------------------------------------
test_task_system() {
  section "8b. Task-system (delegated to the vendored generator)"
  local ws; ws=$(new_ws ws-tasks)

  # Asserted by contract, not by exact file list: the vendored generator owns
  # which files it emits, so pinning them would turn a re-vendor into a failure.
  assert_file "project/ deliverable installed under .workspace" \
    "$ws/.workspace/project/README.md"
  assert_file "task mount is .workspace/project/tasks" \
    "$ws/.workspace/project/tasks/scripts/new-user-task.sh"
  assert_file "--with-status stamped .workspace/project/status" \
    "$ws/.workspace/project/status/README.md"
  assert_no_file "nothing lands on the workspace floor" "$ws/project"
  assert_file "--with-skill stamped the skill"      "$ws/.claude/skills/task-system/SKILL.md"
  assert_empty "the allowlist tracks all of it (nothing untracked)" \
    "$(git -C "$ws" status --porcelain)"

  # The two kernels are distinct blocks and must coexist untouched.
  assert_grep "our managed block is present"        '<!-- git-workspace:begin' "$ws/CLAUDE.md"
  assert_grep "the task-system kernel is present"   '<!-- task-system:begin -->' "$ws/CLAUDE.md"
  assert_eq   "exactly one of our begin markers" "1" \
    "$(grep -c 'git-workspace:begin' "$ws/CLAUDE.md" | tr -d ' ')"
  assert_eq   "exactly one task-system begin marker" "1" \
    "$(grep -c 'task-system:begin' "$ws/CLAUDE.md" | tr -d ' ')"

  # A real task must survive regeneration — this is the delegated generator's
  # own content class, and update.sh must not disturb it.
  "$ws/.workspace/project/tasks/scripts/new-user-task.sh" --folder draft --name harness-task >/dev/null 2>&1
  local task_dir
  task_dir=$(find "$ws/.workspace/project/tasks/main/draft" -maxdepth 1 -type d -name "*harness-task*" | head -1)
  git -C "$ws" add -A; git -C "$ws" commit -qm "add a task"

  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_file  "a real task survives update.sh" "$task_dir"
  assert_empty "zero diff WITH the task-system installed" "$(git -C "$ws" status --porcelain)"
  assert_eq    "both kernels still exactly once after update" "1 1" \
    "$(grep -c 'git-workspace:begin' "$ws/CLAUDE.md" | tr -d ' ') $(grep -c 'task-system:begin' "$ws/CLAUDE.md" | tr -d ' ')"

  # --no-tasks must stay opted out: update.sh upgrades what is installed, it
  # never adds a subsystem the user declined.
  local nots; nots=$(new_ws ws-notasks --no-tasks)
  assert_no_file "--no-tasks installs no project/" "$nots/.workspace/project"
  "$GEN_ROOT/update.sh" "$nots" >/dev/null 2>&1
  assert_no_file "update.sh does not add it later" "$nots/.workspace/project"
  assert_empty   "...and stays at zero diff"       "$(git -C "$nots" status --porcelain)"

  # The mount moved from the root to .workspace/ (DESIGN §8.7). A workspace
  # stamped before that must NOT read as "opted out" — it gets the new mount and
  # is told the old one is still there. Content is never moved for it.
  local old out; old=$(new_ws ws-oldmount)
  mv "$old/.workspace/project" "$old/project"          # the pre-move layout
  out=$("$GEN_ROOT/update.sh" "$old" 2>&1 || true)
  assert_file "an old root mount is upgraded to the new one" \
    "$old/.workspace/project/tasks/scripts/new-user-task.sh"
  assert_grep "...and the stale root mount is called out" \
    'still mounted at the workspace root' <(printf '%s\n' "$out")
  assert_file "...with the old mount left untouched, never moved" \
    "$old/project/tasks/scripts/new-user-task.sh"
}

# ---------------------------------------------------------------------------
# 8c. Workspace plan — the triage area's forward-looking half
# ---------------------------------------------------------------------------
test_workspace_plan() {
  section "8c. Workspace plan (_workspace/daily-plan.md)"
  local ws; ws=$(new_ws ws-plan)
  local plan="$ws/.workspace/daily-plans/_workspace/daily-plan.md"

  assert_file "plan slot is seeded"        "$plan"
  assert_grep "seeded with a dated header" '^# Daily plan — [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$plan"

  # Derived from task state, not invented.
  local ts="$ws/.workspace/project/tasks/scripts"
  "$ts/new-user-task.sh" --folder in-progress --name doing-now  >/dev/null 2>&1
  "$ts/new-user-task.sh" --folder backlog     --name queued-up  >/dev/null 2>&1
  "$ts/new-user-task.sh" --folder draft       --name homeless   >/dev/null 2>&1
  printf '\n- my own note\n' >> "$plan"
  git -C "$ws" add -A; git -C "$ws" commit -qm "tasks + a note"

  "$ws/.workspace/scripts/replan.sh" >/dev/null 2>&1
  assert_grep "in-progress task lands under In progress" 'doing-now' "$plan"
  assert_grep "backlog task lands under Next up"         'queued-up' "$plan"
  assert_grep "draft task lands under Triage"            'homeless'  "$plan"
  assert_grep "the human's Notes are preserved"          '- my own note' "$plan"

  # Draft-only: it writes the file and stops.
  assert_eq "replan stages nothing" "" "$(git -C "$ws" diff --cached --name-only)"
  assert_eq "replan commits nothing" "2" "$(git -C "$ws" rev-list --count HEAD)"

  # Idempotent, and the date is controllable.
  local before; before=$(file_hash "$plan")
  "$ws/.workspace/scripts/replan.sh" >/dev/null 2>&1
  assert_eq "a second replan changes nothing" "$before" "$(file_hash "$plan")"
  "$ws/.workspace/scripts/replan.sh" --date 2026-12-25 >/dev/null 2>&1
  assert_eq "--date sets the header" "# Daily plan — 2026-12-25" "$(head -1 "$plan")"
  assert_fails "an unparseable --date is rejected" \
    "$ws/.workspace/scripts/replan.sh" --date "next tuesday"

  # The plan is CONTENT: regeneration must not touch it.
  git -C "$ws" add -A; git -C "$ws" commit -qm replan
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "update.sh leaves the plan alone" "$(git -C "$ws" status --porcelain)"

  # Without a task-system there is nothing to derive from — refuse, don't guess.
  local nots; nots=$(new_ws ws-plan-notasks --no-tasks)
  assert_file  "the plan is seeded even with --no-tasks" \
    "$nots/.workspace/daily-plans/_workspace/daily-plan.md"
  assert_fails "replan refuses with no task-system" "$nots/.workspace/scripts/replan.sh"
}

# ---------------------------------------------------------------------------
# 8d. Status subsystem — author-scoped telemetry, aggregation, state
# ---------------------------------------------------------------------------

# child_repo_with_commits <ws> — a child repo holding two commits by the test
# author and one by a teammate. The teammate's commit is the point: it must
# never appear in an author-scoped rollup.
child_repo_with_commits() {
  local ws=$1 d="$1/childrepo" i
  mkdir -p "$d"; git -C "$d" init -q
  for i in 1 2; do
    echo "line $i" >> "$d/f.txt"
    git -C "$d" add -A
    git -C "$d" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -q -m "feat(core): land change $i

- [Context]: exercise the telemetry parser.
- [Impact]: adds line $i to f.txt."
  done
  echo teammate >> "$d/g.txt"
  git -C "$d" add -A
  git -C "$d" -c user.email=other@example.invalid -c user.name=Other \
    commit -qm "chore(other): a teammate's commit"
  cat > "$ws/.workspace/repos.yml" <<'YML'
repos:
  - name: childrepo
    url: git@github.com:cornjacket/childrepo.git
    path: childrepo
    type: standard
    branch: main
    priority: 1
YML
}

test_status_subsystem() {
  section "8d. Status subsystem (author-scoped)"
  local ws; ws=$(new_ws ws-status)
  child_repo_with_commits "$ws"
  local S="$ws/.workspace/scripts"

  # sync is read-only and reports what it can see.
  local out
  out=$(python3 "$S/sync.py" 2>&1)
  case "$out" in *"ok       childrepo"*) ok "sync sees the local checkout" ;;
    *) bad "sync sees the local checkout" "$out" ;; esac

  out=$(python3 "$S/new-work.py" 2>&1)
  case "$out" in *"ACTIVE"*) ok "a repo with your commits is ACTIVE" ;;
    *) bad "a repo with your commits is ACTIVE" "$out" ;; esac
  case "$out" in *"land change 2"*) ok "commit telemetry is parsed" ;;
    *) bad "commit telemetry is parsed" "$out" ;; esac
  case "$out" in *"[Context]: exercise the telemetry parser."*)
      ok "the [Context]/[Impact] schema is extracted" ;;
    *) bad "the [Context]/[Impact] schema is extracted" "$out" ;; esac
  # THE author-scoping assertion: a teammate's commit and the file it touched
  # must both be absent from your rollup.
  case "$out" in *"teammate"*) bad "the teammate's commit is excluded" "leaked into the report" ;;
    *) ok "the teammate's commit is excluded" ;; esac
  case "$out" in *"g.txt"*) bad "the teammate's file is excluded from file stat" "g.txt leaked" ;;
    *) ok "the teammate's file is excluded from file stat" ;; esac

  # Full dry run: no LLM, deterministic output.
  python3 "$S/run.py" --dry-run >/dev/null 2>&1
  assert_file "run --dry-run writes summary.md"            "$ws/summary.md"
  assert_file "run --dry-run writes daily-plan-summary.md" "$ws/daily-plan-summary.md"
  assert_file "state.json is advanced"                     "$ws/.workspace/state/state.json"
  assert_grep "summary.md carries today's section"  '^## [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$ws/summary.md"
  # No dated snapshot alongside it: the history is `git log -p` on the file
  # itself, which every run commits. A second on-disk copy grew without bound.
  assert_no_file "no dated archive is written" "$ws/.workspace/state/archive"

  # The window advanced, so a re-run finds nothing of yours...
  out=$(python3 "$S/new-work.py" 2>&1)
  case "$out" in *"INACTIVE"*) ok "the window advances (re-run reports INACTIVE)" ;;
    *) bad "the window advances (re-run reports INACTIVE)" "$out" ;; esac
  # ...and a teammate moving HEAD does NOT make it active for you.
  echo more >> "$ws/childrepo/g.txt"; git -C "$ws/childrepo" add -A
  git -C "$ws/childrepo" -c user.email=other@example.invalid -c user.name=Other \
    commit -qm "chore(other): teammate again"
  out=$(python3 "$S/new-work.py" 2>&1)
  case "$out" in *"INACTIVE"*) ok "a teammate's commit does not make it ACTIVE for you" ;;
    *) bad "a teammate's commit does not make it ACTIVE for you" "$out" ;; esac

  # An unresolved author would silently produce an empty rollup — refuse instead.
  subst_in_file "$ws/.workspace/config.yml" "$TEST_AUTHOR" "CHANGEME@example.invalid"
  assert_fails "a placeholder git_author hard-fails the run" python3 "$S/run.py" --dry-run
  subst_in_file "$ws/.workspace/config.yml" "CHANGEME@example.invalid" "$TEST_AUTHOR"

  # enabled: false drops the repo entirely.
  printf '    enabled: false\n' >> "$ws/.workspace/repos.yml"
  out=$(python3 "$S/new-work.py" 2>&1)
  case "$out" in *"no enabled repos"*) ok "enabled: false removes the repo" ;;
    *) bad "enabled: false removes the repo" "$out" ;; esac

  # Re-enable it: the block below appends new entries, and `enabled: false`
  # above was appended to whatever entry happened to be last.
  grep -v '^    enabled: false$' "$ws/.workspace/repos.yml" > "$ws/.yml.tmp"
  mv "$ws/.yml.tmp" "$ws/.workspace/repos.yml"

  # -------------------------------------------------------------------------
  # dogfood 16: a repo the run could not READ must appear in the deliverable.
  #
  # It used to be skipped with a warning on stderr — which on a scheduled remote
  # run goes to a job log nobody opens, so the committed rollup showed no trace
  # and a tracked repo silently vanished. "Absent" then read as "nothing to
  # report", which is a different and false claim.
  # -------------------------------------------------------------------------
  cat >> "$ws/.workspace/repos.yml" <<'YML'
  - name: phantom
    path: phantom
    type: standard
    branch: main
    url: https://example.invalid/phantom.git
YML

  python3 "$S/run.py" --dry-run >/dev/null 2>&1
  assert_grep "an unreadable repo is named in summary.md" 'phantom' "$ws/summary.md"
  assert_grep "...under its own heading"  'Not read this run'        "$ws/summary.md"
  assert_grep "...with an actionable cause" 'sources'                "$ws/summary.md"
  assert_grep "...and says the rollup does not cover it" \
    'does not cover them' "$ws/summary.md"

  # It must NOT be silenceable by report_inactivity — that flag is a claim about
  # the repo's activity, not about whether the run could read it.
  printf '    report_inactivity: false\n' >> "$ws/.workspace/repos.yml"
  python3 "$S/run.py" --dry-run >/dev/null 2>&1
  assert_grep "report_inactivity: false does not hide it" 'phantom' "$ws/summary.md"

  # A QUIET DAY is exactly when it would vanish: the whole body is inherited
  # from the last real section. The notice must describe THIS run, and must not
  # stack up across days.
  python3 "$S/run.py" --dry-run >/dev/null 2>&1
  assert_eq "the notice is not duplicated on a re-run" "1" \
    "$(grep -c 'Not read this run' "$ws/summary.md")"

  # And once the checkout exists, the notice goes away by itself.
  mkdir -p "$ws/phantom" && git -C "$ws/phantom" init -q
  git -C "$ws/phantom" -c user.email="$TEST_AUTHOR" -c user.name=Dev \
    commit -q --allow-empty -m "feat(phantom): now readable"
  python3 "$S/run.py" --dry-run >/dev/null 2>&1
  assert_no_grep "a readable repo drops out of the notice" \
    'Not read this run' "$ws/summary.md"

}

test_aggregation() {
  section "8e. Plan aggregation (workspace first)"
  local ws; ws=$(new_ws ws-agg)
  child_repo_with_commits "$ws"
  mkdir -p "$ws/.workspace/daily-plans/childrepo"
  printf '# Daily plan — 2026-08-01\n\n## Focus / plan\n\n- Ship the backend\n' \
    > "$ws/.workspace/daily-plans/childrepo/daily-plan.md"

  python3 "$ws/.workspace/scripts/aggregate-plans.py" >/dev/null 2>&1
  local sum="$ws/daily-plan-summary.md"

  assert_grep "an At a glance table is rendered" '^\| Repo \| Pri \| Plan \| Focus \| Idle \|' "$sum"
  # 007's ordering contract: the workspace row leads the table and the body.
  assert_eq "the workspace row is FIRST in the table" "0" \
    "$(grep -n '^| ' "$sum" | grep -n 'workspace' | cut -d: -f1 | head -1 | awk '{print $1-3}')"
  assert_eq "the workspace section is FIRST in the body" "ws-agg (workspace)" \
    "$(grep -m1 '^## [^A]' "$sum" | sed 's/^## //; s/ — .*//')"
  assert_grep "the repo's focus bullet reaches the table" 'Ship the backend' "$sum"
  assert_grep "the repo URL is linkified from repos.yml" \
    '\[childrepo\]\(https://github.com/cornjacket/childrepo\)' "$sum"
  # An embedded plan's own headings must nest UNDER its section, not beside it.
  assert_grep "embedded plan headings are demoted" '^### Focus / plan$' "$sum"

  # A plan from last month is stale; a missing one says so rather than vanishing.
  printf '# Daily plan — 2020-01-01\n\n- old\n' > "$ws/.workspace/daily-plans/childrepo/daily-plan.md"
  python3 "$ws/.workspace/scripts/aggregate-plans.py" >/dev/null 2>&1
  assert_grep "a stale plan is flagged STALE" 'STALE' "$sum"
  rm -f "$ws/.workspace/daily-plans/childrepo/daily-plan.md"
  python3 "$ws/.workspace/scripts/aggregate-plans.py" >/dev/null 2>&1
  assert_grep "a missing plan is reported, not skipped" 'no plan' "$sum"

  # Deliverables are runtime: regeneration must not touch them. Scoped to those
  # paths on purpose — this fixture hand-writes repos.yml (bypassing the verbs),
  # so README.md's roster IS legitimately stale and update.sh refreshes it. That
  # catch-up is asserted below rather than being allowed to look like a leak.
  git -C "$ws" add -A; git -C "$ws" commit -qm "status output"
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "update.sh leaves the deliverables alone" \
    "$(git -C "$ws" status --porcelain -- summary.md daily-plan-summary.md .workspace/state)"
  assert_grep "...but does refresh a roster stale from a hand-edited repos.yml" \
    '\*\*childrepo\*\*' "$ws/README.md"
}

# ---------------------------------------------------------------------------
# 8f. Repo verbs — add / delete / mute
# ---------------------------------------------------------------------------

# bare_origin <path> — a bare repo with one commit on main, usable as a remote.
bare_origin() {
  local bare=$1 seed="$1.seed"
  rm -rf "$bare" "$seed"
  git init -q --bare "$bare"
  git init -q "$seed"
  echo hello > "$seed/README.md"
  git -C "$seed" add -A
  git -C "$seed" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm init
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q origin main
  rm -rf "$seed"
}

test_repo_verbs() {
  section "8f. Repo verbs (add / delete / mute)"
  local ws; ws=$(new_ws ws-verbs)
  local S="$ws/.workspace/scripts"
  local bare="$SANDBOX/origin-verbs.git"
  bare_origin "$bare"

  local header_before; header_before=$(grep -c '^#' "$ws/.workspace/repos.yml")

  # --- add ---
  python3 "$S/add-repo.py" "$bare" --name alpha --priority 1 --tags app,demo >/dev/null 2>&1
  assert_file "add-repo clones the checkout"     "$ws/alpha/.git"
  assert_grep "add-repo registers the entry"     '^  - name: alpha$' "$ws/.workspace/repos.yml"
  assert_grep "...with the flags it was given"   '^    priority: 1$'  "$ws/.workspace/repos.yml"
  assert_file "add-repo seeds a plan slot"       "$ws/.workspace/daily-plans/alpha/daily-plan.md"
  # repos.yml is CONTENT with a long explanatory header — a YAML round-trip
  # would silently delete every comment in it.
  assert_eq "the file's comments survive the edit" \
    "$header_before" "$(grep -c '^#' "$ws/.workspace/repos.yml")"
  # Re-running is a reconcile, not a refusal — but repointing an entry is not.
  # (8p covers the reconcile in full; this pins the refusal that guards it.)
  assert_fails "re-adding under a DIFFERENT url is refused" \
    python3 "$S/add-repo.py" "$SANDBOX/other.git" --name alpha

  # add-repo injects the commit kernel and deliberately leaves it UNCOMMITTED —
  # the workspace never commits inside a child repo. Land it the way a user
  # would, or every delete below would (correctly) refuse a dirty tree.
  git -C "$ws/alpha" add -A
  git -C "$ws/alpha" -c user.email="$TEST_AUTHOR" -c user.name=Dev \
    commit -qm "docs(claude): commit-discipline kernel"
  git -C "$ws/alpha" push -q origin main

  # A failed clone must not leave a half-registered repo behind.
  python3 "$S/add-repo.py" "$SANDBOX/nonexistent.git" --name ghost >/dev/null 2>&1
  assert_no_grep "a failed clone registers nothing" 'name: ghost' "$ws/.workspace/repos.yml"

  # --- mute ---
  python3 "$S/mute-repo.py" alpha >/dev/null 2>&1
  assert_grep "mute-repo hides it on quiet days" '^    report_inactivity: false$' \
    "$ws/.workspace/repos.yml"
  python3 "$S/mute-repo.py" alpha --skip >/dev/null 2>&1
  assert_grep "--skip disables it entirely" '^    enabled: false$' "$ws/.workspace/repos.yml"
  python3 "$S/mute-repo.py" alpha --unmute >/dev/null 2>&1
  assert_grep "--unmute restores it" '^    enabled: true$' "$ws/.workspace/repos.yml"

  # --- delete: every refusal path ---
  echo scratch > "$ws/alpha/untracked.txt"
  assert_fails "delete-repo refuses a DIRTY checkout" python3 "$S/delete-repo.py" alpha
  rm -f "$ws/alpha/untracked.txt"

  echo more >> "$ws/alpha/README.md"
  git -C "$ws/alpha" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qam "local work"
  assert_fails "delete-repo refuses an UNPUSHED commit" python3 "$S/delete-repo.py" alpha
  git -C "$ws/alpha" push -q origin main

  git -C "$ws/alpha" checkout -q -b experiment
  echo x >> "$ws/alpha/README.md"
  git -C "$ws/alpha" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qam exp
  git -C "$ws/alpha" checkout -q main
  assert_fails "delete-repo refuses a branch with NO UPSTREAM" python3 "$S/delete-repo.py" alpha
  git -C "$ws/alpha" branch -q -D experiment

  echo tmp >> "$ws/alpha/README.md"
  git -C "$ws/alpha" stash -q
  assert_fails "delete-repo refuses a STASHED change" python3 "$S/delete-repo.py" alpha
  git -C "$ws/alpha" stash drop -q

  assert_file "...and the checkout survived every refusal" "$ws/alpha/.git"

  # --- delete: the clean path ---
  python3 "$S/delete-repo.py" alpha >/dev/null 2>&1
  assert_no_grep "delete-repo unregisters a clean repo" 'name: alpha' "$ws/.workspace/repos.yml"
  assert_no_file "...removes its checkout"              "$ws/alpha"
  assert_no_file "...and its plan slot"                 "$ws/.workspace/daily-plans/alpha"
  assert_grep "an emptied list is spelled 'repos: []'"  '^repos: \[\]$' "$ws/.workspace/repos.yml"

  # --keep-checkout unregisters without touching a dirty tree.
  python3 "$S/add-repo.py" "$bare" --name beta >/dev/null 2>&1
  echo scratch > "$ws/beta/untracked.txt"
  python3 "$S/delete-repo.py" beta --keep-checkout >/dev/null 2>&1
  assert_no_grep "--keep-checkout still unregisters" 'name: beta' "$ws/.workspace/repos.yml"
  assert_file "...and leaves the dirty checkout alone" "$ws/beta/untracked.txt"
}

# ---------------------------------------------------------------------------
# 8g. The remote status routine (daily.sh + the side-branch dance)
# ---------------------------------------------------------------------------
test_daily_routine() {
  section "8g. Remote status routine (daily.sh)"
  local bare="$SANDBOX/origin-daily.git"
  rm -rf "$bare"; git init -q --bare "$bare"
  local ws; ws=$(new_ws ws-daily --remote "$bare")
  git -C "$ws" push -q -u origin main

  assert_file "auto-merge workflow is emitted" "$ws/.github/workflows/auto-merge-status.yml"
  assert_file "claude workflow is emitted"     "$ws/.github/workflows/claude.yml"

  # A child repo with one of the developer's commits, so the run has work to do.
  mkdir -p "$ws/child"; git -C "$ws/child" init -q
  echo x > "$ws/child/f.txt"; git -C "$ws/child" add -A
  git -C "$ws/child" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "feat(x): work

- [Context]: give the routine something to summarize.
- [Impact]: adds f.txt."
  cat > "$ws/.workspace/repos.yml" <<'YML'
repos:
  - name: child
    url: git@github.com:cornjacket/child.git
    path: child
    type: standard
    branch: main
YML
  git -C "$ws" add -A; git -C "$ws" commit -qm "register child"; git -C "$ws" push -q origin main

  # Leave uncommitted edits lying around: a routine that swept these up would
  # commit the developer's half-finished work behind their back.
  echo "# my in-progress plan edit" >> "$ws/.workspace/daily-plans/_workspace/daily-plan.md"

  ( cd "$ws" && ./.workspace/scripts/daily.sh --dry-run ) >/dev/null 2>&1
  local branch; branch="auto/status-$(date -u +%Y-%m-%d)"

  assert_eq "the run pushes a dated side branch" "$branch" \
    "$(git -C "$ws" rev-parse --abbrev-ref HEAD)"
  case "$(git -C "$bare" for-each-ref --format='%(refname:short)' refs/heads/)" in
    *"$branch"*) ok "the side branch reached origin" ;;
    *) bad "the side branch reached origin" "not found on the remote" ;;
  esac

  # Only the routine's own files, and it must be a fast-forward or the
  # auto-merge workflow (--ff-only) would fail.
  local committed; committed=$(git -C "$ws" show --pretty=format: --name-only HEAD | grep -v '^$' | sort | tr '\n' ' ')
  assert_eq "it commits exactly the routine-owned files" \
    ".workspace/state/state.json daily-plan-summary.md summary.md " \
    "$committed"
  assert_grep "the developer's plan edit is still uncommitted" \
    '# my in-progress plan edit' "$ws/.workspace/daily-plans/_workspace/daily-plan.md"
  case "$(git -C "$ws" status --porcelain)" in
    *"daily-plans/_workspace/daily-plan.md"*) ok "...and shows as a working-tree change" ;;
    *) bad "...and shows as a working-tree change" "the routine swept it up" ;;
  esac

  if git -C "$ws" merge-base --is-ancestor origin/main HEAD; then
    ok "the side branch fast-forwards onto main"
  else
    bad "the side branch fast-forwards onto main" "auto-merge --ff-only would fail"
  fi

  # A second run the same day must reuse the branch, not die on "already exists".
  echo y >> "$ws/child/f.txt"; git -C "$ws/child" add -A
  git -C "$ws/child" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "feat(x): more

- [Context]: second run.
- [Impact]: more."
  if ( cd "$ws" && ./.workspace/scripts/daily.sh --dry-run ) >/dev/null 2>&1; then
    ok "a same-day re-run reuses the branch"
  else
    bad "a same-day re-run reuses the branch" "daily.sh failed on the second run"
  fi

  # Running the Python scripts drops bytecode inside the tracked control plane.
  assert_file "running the scripts creates __pycache__" "$ws/.workspace/scripts/__pycache__"
  case "$(git -C "$ws" status --porcelain)" in
    *__pycache__*) bad "bytecode is ignored, not tracked" "__pycache__ showed up in git status" ;;
    *) ok "bytecode is ignored, not tracked" ;;
  esac
  assert_eq "no bytecode was ever committed" "0" \
    "$(git -C "$ws" ls-files | grep -c pycache)"
}

# ---------------------------------------------------------------------------
# 8h. The morning pull trigger (pull.sh)
# ---------------------------------------------------------------------------
test_pull_trigger() {
  section "8h. Morning pull trigger (pull.sh)"
  local bare="$SANDBOX/origin-pull.git"
  rm -rf "$bare"; git init -q --bare "$bare"
  local ws; ws=$(new_ws ws-pull --remote "$bare")
  git -C "$ws" push -q -u origin main
  local P="$ws/.workspace/scripts/pull.sh"

  "$P" >/dev/null 2>&1
  assert_eq "up to date exits 0" "0" "$?"

  # Stand in for the overnight routine: land aggregates on origin/main.
  local clone="$SANDBOX/ws-pull-routine"
  rm -rf "$clone"; git clone -q "$bare" "$clone"
  printf '# summary\n\nthe rollup\n' > "$clone/summary.md"
  printf '# daily-plan-summary\n' > "$clone/daily-plan-summary.md"
  git -C "$clone" add -A
  git -C "$clone" -c user.email=r@r -c user.name=Routine commit -qm "status: rollup"
  git -C "$clone" push -q origin main

  local out; out=$("$P" 2>&1); local rc=$?
  assert_eq   "a fast-forward exits 0"          "0" "$rc"
  assert_file "...and summary.md arrived"       "$ws/summary.md"
  assert_file "...and daily-plan-summary.md too" "$ws/daily-plan-summary.md"
  case "$out" in *"updated summary.md"*) ok "it names what arrived" ;;
    *) bad "it names what arrived" "$out" ;; esac

  # Purely ahead: nothing to fast-forward to. Stop and name the fix.
  echo "note" >> "$ws/.workspace/daily-plans/_workspace/daily-plan.md"
  git -C "$ws" add -A; git -C "$ws" commit -qm "local: plan edit"
  local head_before; head_before=$(git -C "$ws" rev-parse HEAD)
  out=$("$P" 2>&1); rc=$?
  assert_eq "being ahead declines with exit 1" "1" "$rc"
  case "$out" in *"git push origin main"*) ok "...and names the fix" ;;
    *) bad "...and names the fix" "$out" ;; esac

  # Diverged: the case that must never be auto-resolved.
  echo more >> "$clone/summary.md"
  git -C "$clone" -c user.email=r@r -c user.name=Routine commit -qam "status: more"
  git -C "$clone" push -q origin main
  out=$("$P" 2>&1); rc=$?
  assert_eq "a diverged history declines with exit 1" "1" "$rc"
  case "$out" in *diverged*) ok "...and says diverged" ;;
    *) bad "...and says diverged" "$out" ;; esac
  assert_eq "...leaving local HEAD untouched" "$head_before" "$(git -C "$ws" rev-parse HEAD)"
  assert_eq "...and creating no merge commit" "1" \
    "$(git -C "$ws" rev-list --count "origin/main..HEAD")"

  # Misconfiguration is exit 2, distinct from a decline.
  local nr; nr=$(new_ws ws-pull-noremote)
  assert_eq "no origin exits 2" "2" \
    "$(:; "$nr/.workspace/scripts/pull.sh" >/dev/null 2>&1; echo $?)"
}

# ---------------------------------------------------------------------------
# 8i. Child commit-kernel injection
# ---------------------------------------------------------------------------
test_commit_kernel() {
  section "8i. Child commit-kernel injection"
  local ws; ws=$(new_ws ws-kernel)
  local S="$ws/.workspace/scripts"
  local bare="$SANDBOX/origin-kernel.git" seed="$SANDBOX/kernel-seed"
  rm -rf "$bare" "$seed"; git init -q --bare "$bare"
  git init -q "$seed"
  printf '# CLAUDE.md — my repo\n\nMy own house rules.\n' > "$seed/CLAUDE.md"
  git -C "$seed" add -A
  git -C "$seed" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm init
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q origin main
  rm -rf "$seed"

  assert_file "the kernel template is emitted" "$ws/.workspace/templates/commit-kernel.md"

  python3 "$S/add-repo.py" "$bare" --name mine >/dev/null 2>&1
  local cm="$ws/mine/CLAUDE.md"
  assert_grep "add-repo injects the kernel"        'git-workspace-commits:begin' "$cm"
  assert_grep "the repo's own content is preserved" 'My own house rules\.'       "$cm"
  assert_grep "it carries the commit schema"        '\[Context\]'                "$cm"

  # It is commit-discipline ONLY: plans moved up into each developer's workspace.
  assert_no_grep "it does NOT ask for a daily-plan.md here" \
    'first line is exactly' "$cm"
  assert_grep "...and says plans live in the workspace" 'Daily plans do not live here' "$cm"

  # The block is committed to a SHARED repo, so it must name no workspace, no
  # developer, and no version — otherwise two developers tracking the same repo
  # overwrite each other's block on every injection.
  local block; block=$(sed -n '/git-workspace-commits:begin/,/git-workspace-commits:end/p' "$cm")
  case "$block" in
    *ws-kernel*) bad "the kernel names no workspace" "'ws-kernel' leaked into the block" ;;
    *) ok "the kernel names no workspace" ;;
  esac
  case "$block" in
    *"$TEST_AUTHOR"*) bad "the kernel names no developer" "the author leaked into the block" ;;
    *) ok "the kernel names no developer" ;;
  esac

  # The workspace must never commit inside a child repo.
  case "$(git -C "$ws/mine" status --porcelain)" in
    *CLAUDE.md*) ok "the change is left uncommitted in the child" ;;
    *) bad "the change is left uncommitted in the child" "it committed on your behalf" ;;
  esac
  assert_eq "...and the child has only its own commit" "1" \
    "$(git -C "$ws/mine" rev-list --count HEAD)"

  git -C "$ws/mine" add -A
  git -C "$ws/mine" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "docs: kernel"

  # Idempotent, and drift is detectable.
  local before; before=$(file_hash "$cm")
  python3 "$S/inject-kernel.py" --all >/dev/null 2>&1
  assert_eq "re-injection is byte-identical" "$before" "$(file_hash "$cm")"
  python3 "$S/inject-kernel.py" --check >/dev/null 2>&1
  assert_eq "--check passes when current" "0" "$?"

  subst_in_file "$cm" "Commit at **task granularity**" "AN OUTDATED RULE"
  assert_fails "--check catches a stale kernel" python3 "$S/inject-kernel.py" --check
  python3 "$S/inject-kernel.py" --all >/dev/null 2>&1
  assert_no_grep "...and --all refreshes it"   'AN OUTDATED RULE'          "$cm"
  assert_grep    "...restoring the real rule"  'Commit at \*\*task granularity\*\*' "$cm"
  assert_grep    "...while keeping the repo's own content" 'My own house rules\.' "$cm"
}

# ---------------------------------------------------------------------------
# 8j. The LIVE claude -p path, with `claude` stubbed
#
# --dry-run (covered in 8d) skips prompt rendering entirely, so the prompts
# themselves — the substitution, and what actually reaches the model — were
# never exercised. This puts a fake `claude` first on PATH that records each
# prompt it is handed and answers deterministically.
# ---------------------------------------------------------------------------
make_claude_stub() { # make_claude_stub <bindir>
  mkdir -p "$1"
  cat > "$1/claude" <<'STUB'
#!/usr/bin/env bash
# Stand-in for `claude -p`: records the prompt, answers deterministically.
prompt=$(cat)
if [ -n "${CLAUDE_STUB_LOG:-}" ]; then
  mkdir -p "$CLAUDE_STUB_LOG"
  n=$(find "$CLAUDE_STUB_LOG" -name 'prompt-*' | wc -l | tr -d ' ')
  printf '%s' "$prompt" > "$CLAUDE_STUB_LOG/prompt-$n.txt"
fi
[ "${CLAUDE_STUB_FAIL:-0}" = "1" ] && { echo "stub: simulated failure" >&2; exit 1; }
if printf '%s' "$prompt" | grep -q '^DRAFTS:'; then
  today=$(printf '%s' "$prompt" | sed -n 's/.*starting with `## \([0-9-]*\)`.*/\1/p' | head -1)
  printf '## %s\n\nSTUB-POLISHED\n' "${today:-unknown}"
else
  name=$(printf '%s' "$prompt" | sed -n 's/.*slice for repo `\([^`]*\)`.*/\1/p' | head -1)
  printf '### %s\n- STUB-SUMMARY for %s\n' "$name" "$name"
fi
STUB
  chmod 755 "$1/claude"
}

test_claude_pipeline() {
  section "8j. Live claude -p path (stubbed)"
  local bin="$SANDBOX/stub-bin"; rm -rf "$bin"; make_claude_stub "$bin"
  local log="$SANDBOX/stub-prompts"; rm -rf "$log"

  local ws; ws=$(new_ws ws-claude)
  local S="$ws/.workspace/scripts"

  # Two repos with the developer's commits (so the polish step triggers) and one
  # teammate commit that must never reach a prompt.
  local r
  for r in alpha beta; do
    mkdir -p "$ws/$r"; git -C "$ws/$r" init -q
    echo one > "$ws/$r/f.txt"; git -C "$ws/$r" add -A
    git -C "$ws/$r" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "feat($r): build the thing

- [Context]: exercise prompt rendering.
- [Impact]: adds f.txt to $r."
  done
  echo secret > "$ws/alpha/teammate.txt"; git -C "$ws/alpha" add -A
  git -C "$ws/alpha" -c user.email=other@example.invalid -c user.name=Other \
    commit -qm "chore(other): TEAMMATE-ONLY change"
  cat > "$ws/.workspace/repos.yml" <<'YML'
repos:
  - name: alpha
    url: git@github.com:cornjacket/alpha.git
    path: alpha
    type: standard
    branch: main
  - name: beta
    url: git@github.com:cornjacket/beta.git
    path: beta
    type: standard
    branch: main
YML

  ( cd "$ws" && PATH="$bin:$PATH" CLAUDE_STUB_LOG="$log" python3 "$S/run.py" ) >/dev/null 2>&1

  # Two ACTIVE repos -> two per-repo calls plus one polish call.
  assert_eq "claude is called once per repo, plus polish" "3" \
    "$(find "$log" -name 'prompt-*' 2>/dev/null | wc -l | tr -d ' ')"

  local prompts; prompts=$(cat "$log"/prompt-*.txt 2>/dev/null)
  case "$prompts" in
    *'{{'*) bad "every placeholder is substituted" "a {{...}} reached the model" ;;
    *) ok "every placeholder is substituted" ;;
  esac
  case "$prompts" in
    *"build the thing"*) ok "the prompt carries real commit telemetry" ;;
    *) bad "the prompt carries real commit telemetry" "telemetry missing" ;;
  esac
  case "$prompts" in
    *"exercise prompt rendering"*) ok "...including [Context]/[Impact]" ;;
    *) bad "...including [Context]/[Impact]" "schema lines missing" ;;
  esac
  # The author-scoping guarantee has to hold at the PROMPT boundary too: a
  # teammate's work must never be handed to the model as this developer's.
  case "$prompts" in
    *TEAMMATE-ONLY*) bad "no teammate work reaches the model" "it leaked into a prompt" ;;
    *) ok "no teammate work reaches the model" ;;
  esac
  case "$prompts" in
    *"ws-claude"*) ok "the polish prompt names the workspace" ;;
    *) bad "the polish prompt names the workspace" "{{WORKSPACE_NAME}} not filled" ;;
  esac

  assert_grep "the model's output lands in summary.md" 'STUB-POLISHED' "$ws/summary.md"

  # One ACTIVE repo must NOT trigger polish — there is nothing cross-repo to
  # merge, and paying for a second call would be waste.
  rm -rf "$log"
  local ws1; ws1=$(new_ws ws-claude-single)
  mkdir -p "$ws1/solo"; git -C "$ws1/solo" init -q
  echo one > "$ws1/solo/f.txt"; git -C "$ws1/solo" add -A
  git -C "$ws1/solo" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "feat(solo): work

- [Context]: single-repo day.
- [Impact]: adds f.txt."
  cat > "$ws1/.workspace/repos.yml" <<'YML'
repos:
  - name: solo
    url: git@github.com:cornjacket/solo.git
    path: solo
    type: standard
    branch: main
YML
  ( cd "$ws1" && PATH="$bin:$PATH" CLAUDE_STUB_LOG="$log" \
      python3 "$ws1/.workspace/scripts/run.py" ) >/dev/null 2>&1
  assert_eq "a single active repo skips the polish call" "1" \
    "$(find "$log" -name 'prompt-*' 2>/dev/null | wc -l | tr -d ' ')"
  assert_grep "...and its section still lands" 'STUB-SUMMARY for solo' "$ws1/summary.md"

  # --dry-run must not shell out at all.
  rm -rf "$log"
  echo two > "$ws1/solo/f.txt"; git -C "$ws1/solo" add -A
  git -C "$ws1/solo" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "feat(solo): more

- [Context]: second day.
- [Impact]: changes f.txt."
  ( cd "$ws1" && PATH="$bin:$PATH" CLAUDE_STUB_LOG="$log" \
      python3 "$ws1/.workspace/scripts/run.py" --dry-run ) >/dev/null 2>&1
  assert_eq "--dry-run calls claude zero times" "0" \
    "$(find "$log" 2>/dev/null -name 'prompt-*' | wc -l | tr -d ' ')"

  # WINDOWED, NOT A JOURNAL: the newer run REPLACES the older section rather
  # than stacking on top of it, so the file's size is bounded. The previous
  # run's model output must be gone, and exactly one section may remain.
  assert_eq "summary.md holds exactly one section" "1" \
    "$(grep -c '^## [0-9]' "$ws1/summary.md" | tr -d ' ')"
  assert_grep "...and it is the newest run"   'dry-run'      "$ws1/summary.md"
  assert_no_grep "...the older section is gone" 'STUB-SUMMARY' "$ws1/summary.md"

  # A failing model call must abort loudly, not write a half-built summary.
  # Needs fresh work, or the repo is INACTIVE and claude is never called at all.
  echo three > "$ws1/solo/f.txt"; git -C "$ws1/solo" add -A
  git -C "$ws1/solo" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "feat(solo): third

- [Context]: give the failing run something to summarize.
- [Impact]: changes f.txt."
  local before state_before
  before=$(file_hash "$ws1/summary.md")
  state_before=$(file_hash "$ws1/.workspace/state/state.json")
  ( cd "$ws1" && PATH="$bin:$PATH" CLAUDE_STUB_FAIL=1 \
      python3 "$ws1/.workspace/scripts/run.py" ) >/dev/null 2>&1
  assert_eq "a failing claude call aborts the run" "1" "$?"
  assert_eq "...leaving summary.md untouched" "$before" "$(file_hash "$ws1/summary.md")"
  # State must not advance past work that was never summarized, or the next run
  # would skip it and the day would silently vanish from the record.
  assert_eq "...and NOT advancing the commit window" \
    "$state_before" "$(file_hash "$ws1/.workspace/state/state.json")"

  # The same work is still pending, so a good run picks it up.
  rm -rf "$log"
  ( cd "$ws1" && PATH="$bin:$PATH" CLAUDE_STUB_LOG="$log" \
      python3 "$ws1/.workspace/scripts/run.py" ) >/dev/null 2>&1
  assert_eq "a retry after the failure summarizes the same work" "1" \
    "$(find "$log" -name 'prompt-*' 2>/dev/null | wc -l | tr -d ' ')"

  # A QUIET DAY CARRIES THE LAST REAL WORK FORWARD. Overwriting it with an
  # empty "No updates" list would read as "nothing has happened", when what is
  # true is "nothing has happened *since*". Back-date the section by hand so the
  # re-dating is visible (both runs here land on the same calendar day).
  rm -rf "$log"
  local dtoday; dtoday=$(date +%Y-%m-%d)
  subst_in_file "$ws1/summary.md" "## $dtoday" "## 2026-01-05"
  ( cd "$ws1" && PATH="$bin:$PATH" CLAUDE_STUB_LOG="$log" \
      python3 "$ws1/.workspace/scripts/run.py" ) >/dev/null 2>&1
  assert_grep "a quiet day re-dates the section, naming both dates" \
    "^## $dtoday — no new work since 2026-01-05$" "$ws1/summary.md"
  assert_grep "...keeping the last real activity verbatim" 'STUB-SUMMARY' "$ws1/summary.md"
  assert_eq "...with no model call" "0" \
    "$(find "$log" -name 'prompt-*' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "...and still exactly one section" "1" \
    "$(grep -c '^## [0-9]' "$ws1/summary.md" | tr -d ' ')"

  # The activity date must not creep forward one quiet day at a time — it is
  # parsed back out of the heading, not re-derived from it.
  ( cd "$ws1" && PATH="$bin:$PATH" python3 "$ws1/.workspace/scripts/run.py" ) >/dev/null 2>&1
  assert_grep "a second quiet day keeps the ORIGINAL activity date" \
    "no new work since 2026-01-05" "$ws1/summary.md"

  # With NO prior section there is nothing to carry, so the inactivity report
  # is the whole story and must still be written.
  rm -f "$ws1/summary.md"
  ( cd "$ws1" && PATH="$bin:$PATH" python3 "$ws1/.workspace/scripts/run.py" ) >/dev/null 2>&1
  assert_grep "a first run with no activity still reports 'No updates'" \
    'No updates' "$ws1/summary.md"
}

# ---------------------------------------------------------------------------
# 8k. The kernel / guide / skill split
#
# The CLAUDE.md block is always-on context, so it must stay a small kernel: the
# rules that would be too late if they loaded on demand, plus a pointer. The
# procedure lives in .workspace/status-guide.md (agent-agnostic) and is surfaced
# on demand by the workspace-status skill. This test pins that split — a kernel
# that quietly re-absorbs the procedure is the failure mode.
# ---------------------------------------------------------------------------
test_guide_and_skill() {
  section "8k. On-demand guide and skill (kernel split)"
  local ws; ws=$(new_ws ws-guide)
  local guide="$ws/.workspace/status-guide.md"
  local skill="$ws/.claude/skills/workspace-status/SKILL.md"

  assert_file "the guide is emitted"            "$guide"
  assert_file "the skill is emitted"            "$skill"
  assert_no_grep "no placeholders survive in the guide" '\{\{' "$guide"
  assert_no_grep "no placeholders survive in the skill" '\{\{' "$skill"
  assert_grep "the guide is named for the workspace" '^# Workspace guide — ws-guide$' "$guide"
  assert_grep "the skill declares its name"     '^name: workspace-status$' "$skill"
  assert_grep "the skill points at the guide"   '\.workspace/status-guide\.md' "$skill"
  assert_empty "both are tracked by the allowlist" "$(git -C "$ws" status --porcelain)"

  # The guide is the canonical home for the routine seams (task 014's whole point).
  assert_grep "guide documents creating the /schedule routine" '/schedule' "$guide"
  assert_grep "guide documents the sources pre-clone list"     'sources'   "$guide"
  assert_grep "guide documents the ff-only pull"               'ff-only'   "$guide"
  assert_grep "guide documents the repo verbs"                 'delete-repo\.py' "$guide"
  assert_grep "guide separates project/status from summary.md" \
    'summary\.md.* is not .*\.workspace/project/status/' "$guide"

  # The kernel: small, and a pointer rather than a restatement.
  local block
  block=$(sed -n '/git-workspace:begin/,/git-workspace:end/p' "$ws/CLAUDE.md")
  local lines; lines=$(printf '%s\n' "$block" | wc -l | tr -d ' ')
  if [ "$lines" -le 60 ]; then ok "the managed block stays a kernel ($lines lines)"
  else bad "the managed block stays a kernel" "grew to $lines lines (limit 60)"; fi
  case "$block" in
    *".workspace/status-guide.md"*) ok "the kernel points at the guide" ;;
    *) bad "the kernel points at the guide" "no pointer in the managed block" ;;
  esac
  case "$block" in
    *"auto/status-"*|*launchd*|*StartCalendarInterval*)
      bad "the kernel does not restate routine mechanics" "found push/pull detail inline" ;;
    *) ok "the kernel does not restate routine mechanics" ;;
  esac

  # Machinery: overwritten, and OUR skill dir is mirrored — but the vendored
  # generator's sibling skill must survive, since we do not own it.
  echo 'VANDALIZED' >> "$guide"
  echo 'VANDALIZED' >> "$skill"
  echo 'stale' > "$ws/.claude/skills/workspace-status/RETIRED.md"
  git -C "$ws" add -A; git -C "$ws" commit -qm "vandalize the guide"
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_no_grep "a vandalized guide is restored" 'VANDALIZED' "$guide"
  assert_no_grep "a vandalized skill is restored" 'VANDALIZED' "$skill"
  assert_no_file "a stale file in our skill dir is pruned" \
    "$ws/.claude/skills/workspace-status/RETIRED.md"
  assert_file "the vendored task-system skill is NOT pruned" \
    "$ws/.claude/skills/task-system/SKILL.md"

  git -C "$ws" add -A; git -C "$ws" commit -qm restore
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "and it settles back to zero diff" "$(git -C "$ws" status --porcelain)"

  # The skill is ours, not the vendored generator's, so --no-tasks keeps it.
  local nots; nots=$(new_ws ws-guide-notasks --no-tasks)
  assert_file "--no-tasks still emits our skill" \
    "$nots/.claude/skills/workspace-status/SKILL.md"
  assert_no_file "...and still no task-system skill" \
    "$nots/.claude/skills/task-system"
}

# ---------------------------------------------------------------------------
# 8l. Optional extras (task 016): the pre-commit hook and --create-remote
#
# Both are opt-in. The hook is exercised for real — install it, then try to
# commit a child repo and require the commit to FAIL. --create-remote is checked
# up to the point of the network call: the flag contract, the refusals, and the
# fact that a workspace is never stamped when the preconditions fail.
# ---------------------------------------------------------------------------
test_optional_extras() {
  section "8l. Optional extras (hook, --create-remote)"
  local ws; ws=$(new_ws ws-extras)
  local hook; hook="$(git -C "$ws" rev-parse --absolute-git-dir)/hooks/pre-commit"

  # Not installed unless asked for.
  assert_no_file "no hook without --with-hook" "$hook"
  assert_fails   "hook-check reports it missing" "$ws/.workspace/scripts/install-hooks.sh" --check

  "$ws/.workspace/scripts/install-hooks.sh" >/dev/null 2>&1
  assert_exec "install-hooks.sh installs an executable hook" "$hook"
  assert_grep "the hook execs guard.sh" 'guard\.sh' "$hook"
  local out
  out=$("$ws/.workspace/scripts/install-hooks.sh" 2>&1)
  case "$out" in *"already current"*) ok "re-running is idempotent" ;;
                 *) bad "re-running is idempotent" "$out" ;; esac
  "$ws/.workspace/scripts/install-hooks.sh" --check >/dev/null 2>&1
  assert_eq "--check passes once installed" "0" "$?"

  # The real thing: a staged child repo must abort the commit.
  mkdir -p "$ws/kid" && git -C "$ws/kid" init -q
  echo hi > "$ws/kid/f.txt"
  git -C "$ws/kid" add -A
  git -C "$ws/kid" -c user.email=t@t -c user.name=t commit -qm init
  git -C "$ws" add -f kid >/dev/null 2>&1
  assert_fails "the hook blocks a commit that swallows a child repo" \
    git -C "$ws" -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -m "oops"
  git -C "$ws" reset -q; rm -rf "$ws/kid"

  # A foreign hook is never clobbered — that is unrecoverable work.
  printf '#!/bin/sh\necho mine\n' > "$hook"; chmod 755 "$hook"
  assert_fails "refuses to overwrite a hook it did not write" \
    "$ws/.workspace/scripts/install-hooks.sh"
  assert_grep "...leaving the foreign hook intact" 'echo mine' "$hook"
  assert_fails "refuses to remove a hook it did not write" \
    "$ws/.workspace/scripts/install-hooks.sh" --uninstall
  "$ws/.workspace/scripts/install-hooks.sh" --force >/dev/null 2>&1
  assert_grep "--force replaces it" 'guard\.sh' "$hook"
  "$ws/.workspace/scripts/install-hooks.sh" --uninstall >/dev/null 2>&1
  assert_no_file "--uninstall removes our own hook" "$hook"

  # setup.sh --with-hook wires it at stamp time.
  local wh; wh=$(new_ws ws-hooked --with-hook)
  assert_file "setup.sh --with-hook installs it" \
    "$(git -C "$wh" rev-parse --absolute-git-dir)/hooks/pre-commit"

  # --create-remote: contract and refusals. No network, no gh call.
  rm -rf "$SANDBOX/ws-cr"
  assert_fails "--create-remote conflicts with --remote" \
    "$GEN_ROOT/setup.sh" "$SANDBOX/ws-cr" --name ws-cr --author "$TEST_AUTHOR" \
      --create-remote --remote git@example.invalid:x/y.git
  assert_no_file "...and stamps nothing when it refuses" "$SANDBOX/ws-cr"
  assert_fails "--public without --create-remote is rejected" \
    "$GEN_ROOT/setup.sh" "$SANDBOX/ws-cr" --name ws-cr --author "$TEST_AUTHOR" --public
  assert_no_file "...and stamps nothing either" "$SANDBOX/ws-cr"

  # gh missing must fail BEFORE anything is written, not halfway through.
  local bin="$SANDBOX/nogh-bin"; rm -rf "$bin"; mkdir -p "$bin"
  assert_fails "no gh on PATH -> refuses up front" \
    env PATH="$bin:/usr/bin:/bin" "$GEN_ROOT/setup.sh" "$SANDBOX/ws-cr" \
      --name ws-cr --author "$TEST_AUTHOR" --create-remote
  assert_no_file "...leaving no half-stamped workspace" "$SANDBOX/ws-cr"

  local help="$SANDBOX/extras-help.txt"
  "$GEN_ROOT/setup.sh" --help > "$help" 2>&1
  assert_grep "--create-remote is documented in --help" '\-\-create-remote' "$help"
  assert_grep "--with-hook is documented in --help"     '\-\-with-hook'     "$help"
}

# ---------------------------------------------------------------------------
# 8o. Per-repo replan (dogfood 02)
#
# A plan is a REPORT of decisions already made, so this is deterministic: task
# state in, plan out, no model call. Which means the suite can assert the exact
# output — the whole argument for choosing this shape.
# ---------------------------------------------------------------------------
test_per_repo_replan() {
  section "8o. Per-repo replan (deterministic)"
  local ws; ws=$(new_ws ws-replan)
  local rp="$ws/.workspace/scripts/replan.sh"

  # A child repo carrying its own task-system, installed the same way a real one
  # would be: by the vendored generator.
  mkdir -p "$ws/kid" && git -C "$ws/kid" init -q
  "$GEN_ROOT/vendor/create-project-system/generate.sh" --target-repo "$ws/kid" \
      --tasks-dir project/tasks >/dev/null 2>&1
  git -C "$ws/kid" add -A
  git -C "$ws/kid" -c user.email=t@t -c user.name=t commit -qm init
  cat > "$ws/.workspace/repos.yml" <<'YML'
repos:
  - name: kid
    path: kid
    type: standard
    branch: main
    url: https://example.invalid/kid.git
  - name: ghost
    path: ghost
    type: standard
    branch: main
    url: https://example.invalid/ghost.git
  - name: off
    path: off
    type: standard
    branch: main
    url: https://example.invalid/off.git
    enabled: false
YML

  "$ws/kid/project/tasks/scripts/new-user-task.sh" --folder in-progress --name ship-the-thing \
    >/dev/null 2>&1
  "$ws/kid/project/tasks/scripts/new-user-task.sh" --folder backlog --name later-thing \
    >/dev/null 2>&1

  local out; out=$("$rp" 2>&1)
  local plan="$ws/.workspace/daily-plans/kid/daily-plan.md"
  assert_file "a repo with a task-system gets a plan" "$plan"
  assert_grep "its in-progress task lands under In progress" 'ship-the-thing' "$plan"
  assert_grep "its backlog task lands under Next up"         'later-thing'    "$plan"
  assert_grep "the plan says where it came from"  'Derived from `kid/project/tasks`' "$plan"
  assert_grep "the workspace's own plan is still drafted" 'Daily plan' \
    "$ws/.workspace/daily-plans/_workspace/daily-plan.md"

  # A registered repo with no checkout, and one switched off, are both skipped —
  # and skipped LOUDLY, so a missing plan is never a silent absence.
  case "$out" in *ghost*"not checked out"*) ok "a missing checkout is skipped, and says so" ;;
                 *) bad "a missing checkout is skipped, and says so" "$out" ;; esac
  assert_no_file "a repo with enabled:false gets no plan" \
    "$ws/.workspace/daily-plans/off/daily-plan.md"

  # Deterministic: the same task state renders byte-identically.
  local before; before=$(file_hash "$plan")
  out=$("$rp" 2>&1)
  assert_eq "re-running is byte-identical" "$before" "$(file_hash "$plan")"
  case "$out" in *"already current"*) ok "...and it says so rather than rewriting" ;;
                 *) bad "...and it says so rather than rewriting" "$out" ;; esac

  # The human's half survives a redraft, exactly like the workspace plan.
  printf '\n- a note I typed\n' >> "$plan"
  "$ws/kid/project/tasks/scripts/new-user-task.sh" --folder backlog --name third-thing >/dev/null 2>&1
  "$rp" >/dev/null 2>&1
  assert_grep "text under ## Notes survives"   'a note I typed' "$plan"
  assert_grep "...and the new task appeared"   'third-thing'    "$plan"

  # --repo targets one; --date sets the header; neither commits anything.
  "$rp" --repo kid --date 2026-12-25 >/dev/null 2>&1
  assert_eq "--repo + --date redraft just that plan" "# Daily plan — 2026-12-25" \
    "$(head -1 "$plan")"
  assert_no_grep "...leaving the workspace plan alone" '2026-12-25' \
    "$ws/.workspace/daily-plans/_workspace/daily-plan.md"
  assert_fails "an unknown --repo is rejected" "$rp" --repo nope
  case "$(git -C "$ws" diff --cached --name-only)" in
    "") ok "replan stages nothing" ;;
    *)  bad "replan stages nothing" "$(git -C "$ws" diff --cached --name-only)" ;;
  esac

  # No model call, ever: a stub `claude` that fails loudly must never be reached.
  local bin="$SANDBOX/replan-nocall"; rm -rf "$bin"; mkdir -p "$bin"
  printf '#!/bin/sh\necho "MODEL CALLED" >&2\nexit 9\n' > "$bin/claude"
  chmod 755 "$bin/claude"
  out=$( PATH="$bin:$PATH" "$rp" --date 2026-12-26 2>&1 )
  case "$out" in *"MODEL CALLED"*) bad "replan makes no model call" "$out" ;;
                 *) ok "replan makes no model call" ;; esac

  # A --repo target that is already current is still a target. This once
  # reported "no target named" for a real repo purely because nothing changed.
  "$rp" --repo kid --date 2026-12-26 >/dev/null 2>&1
  assert_succeeds "--repo on an already-current plan is not 'no such target'" \
    "$rp" --repo kid --date 2026-12-26

  # -------------------------------------------------------------------------
  # dogfood 22: an older generated task-system has no `inbox` folder. That is a
  # VERSION DIFFERENCE, not a failure — and it must not cost any repo its plan.
  #
  # The regression this pins is not "one plan was wrong": it is that a non-zero
  # exit from one folder listing killed the whole run, so every repo AFTER the
  # offending one was never drafted and never even named. Ordering matters here,
  # so `oldkid` is registered BEFORE `latekid`.
  # -------------------------------------------------------------------------
  mkdir -p "$ws/oldkid" && git -C "$ws/oldkid" init -q
  "$GEN_ROOT/vendor/create-project-system/generate.sh" --target-repo "$ws/oldkid" \
      --tasks-dir project/tasks >/dev/null 2>&1
  "$ws/oldkid/project/tasks/scripts/new-user-task.sh" --folder in-progress \
      --name legacy-layout-task >/dev/null 2>&1
  # Downgrade it to the older vocabulary.
  rm -rf "$ws"/oldkid/project/tasks/*/inbox
  git -C "$ws/oldkid" add -A
  git -C "$ws/oldkid" -c user.email=t@t -c user.name=t commit -qm init

  mkdir -p "$ws/latekid" && git -C "$ws/latekid" init -q
  "$GEN_ROOT/vendor/create-project-system/generate.sh" --target-repo "$ws/latekid" \
      --tasks-dir project/tasks >/dev/null 2>&1
  "$ws/latekid/project/tasks/scripts/new-user-task.sh" --folder in-progress \
      --name drafted-after-the-old-one >/dev/null 2>&1
  git -C "$ws/latekid" add -A
  git -C "$ws/latekid" -c user.email=t@t -c user.name=t commit -qm init

  cat >> "$ws/.workspace/repos.yml" <<'YML'
  - name: oldkid
    path: oldkid
    type: standard
    branch: main
    url: https://example.invalid/oldkid.git
  - name: latekid
    path: latekid
    type: standard
    branch: main
    url: https://example.invalid/latekid.git
YML

  out=$("$rp" --date 2026-12-27 2>&1) || true
  assert_grep "a task-system with no inbox still gets a plan" 'legacy-layout-task' \
    "$ws/.workspace/daily-plans/oldkid/daily-plan.md"
  assert_grep "...and its Triage section renders as empty, not broken" \
    '_Nothing in triage._' "$ws/.workspace/daily-plans/oldkid/daily-plan.md"

  # THE regression: the repo listed after it is still drafted.
  assert_file "a repo after it is still drafted" \
    "$ws/.workspace/daily-plans/latekid/daily-plan.md"
  assert_grep "...with its real task state" 'drafted-after-the-old-one' \
    "$ws/.workspace/daily-plans/latekid/daily-plan.md"
  case "$out" in *latekid*) ok "every repo is named in the output" ;;
                 *) bad "every repo is named in the output" "$out" ;; esac

  # A task-system whose lister does not answer at all is skipped LOUDLY —
  # never given a plausible-looking empty plan.
  mkdir -p "$ws/brokekid" && git -C "$ws/brokekid" init -q
  "$GEN_ROOT/vendor/create-project-system/generate.sh" --target-repo "$ws/brokekid" \
      --tasks-dir project/tasks >/dev/null 2>&1
  printf '#!/bin/sh\nexit 3\n' > "$ws/brokekid/project/tasks/scripts/list-tasks.sh"
  chmod 755 "$ws/brokekid/project/tasks/scripts/list-tasks.sh"
  git -C "$ws/brokekid" add -A
  git -C "$ws/brokekid" -c user.email=t@t -c user.name=t commit -qm init
  cat >> "$ws/.workspace/repos.yml" <<'YML'
  - name: brokekid
    path: brokekid
    type: standard
    branch: main
    url: https://example.invalid/brokekid.git
YML

  out=$("$rp" --date 2026-12-28 2>&1) || true
  case "$out" in *brokekid*"does not answer"*) ok "an unreadable lister is skipped, and says why" ;;
                 *) bad "an unreadable lister is skipped, and says why" "$out" ;; esac
  assert_no_file "...and gets no plausible-looking empty plan" \
    "$ws/.workspace/daily-plans/brokekid/daily-plan.md"
  assert_grep "...while the rest of the roster is still drafted" '2026-12-28' \
    "$ws/.workspace/daily-plans/latekid/daily-plan.md"
}

# ---------------------------------------------------------------------------
# 8n. The pending sweep (dogfood 01)
#
# The dangerous case: a repo you COMMITTED but never PUSHED looks perfectly
# clean to `git status`. Only a sweep at this level can see it. The detector is
# shared with delete-repo, so this also pins that the two never disagree.
# ---------------------------------------------------------------------------
test_pending_sweep() {
  section "8n. Pending work sweep (uncommitted + unpushed)"
  local ws; ws=$(new_ws ws-pending)
  local st="$ws/.workspace/scripts/status.py"

  # A child with a real upstream, so "ahead" is meaningful.
  local bare="$SANDBOX/pending-remote.git"; rm -rf "$bare"; git init -q --bare "$bare"
  git -C "$ws" -c init.defaultBranch=main clone -q "$bare" "$ws/kid" 2>/dev/null
  git -C "$ws/kid" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
  git -C "$ws/kid" push -q -u origin HEAD:main 2>/dev/null
  cat > "$ws/.workspace/repos.yml" <<'YML'
repos:
  - name: kid
    path: kid
    type: standard
    branch: main
    url: https://example.invalid/kid.git
    routine_registered: true
YML
  git -C "$ws" add -A; git -C "$ws" commit -qm "register kid"

  local out
  out=$("$st" 2>&1)
  case "$out" in *kid*clean*) ok "a pushed child reads clean" ;;
                 *) bad "a pushed child reads clean" "$out" ;; esac
  assert_eq "...and the sweep exits 0" "0" "$("$st" >/dev/null 2>&1; echo $?)"

  # THE case: committed, not pushed. `git status` in that repo says nothing.
  git -C "$ws/kid" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local work"
  assert_empty "git status in the child still reports nothing" \
    "$(git -C "$ws/kid" status --porcelain)"
  out=$("$st" 2>&1)
  case "$out" in *kid*unpushed*) ok "the sweep catches the unpushed commit" ;;
                 *) bad "the sweep catches the unpushed commit" "$out" ;; esac
  assert_eq "...and exits non-zero" "1" "$("$st" >/dev/null 2>&1; echo $?)"
  out=$("$st" -v 2>&1)
  case "$out" in *"1 commit(s) ahead"*) ok "-v names the finding" ;;
                 *) bad "-v names the finding" "$out" ;; esac

  # A repo with NO remote is local by design, not forgotten work.
  mkdir -p "$ws/solo" && git -C "$ws/solo" init -q
  git -C "$ws/solo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m only
  out=$("$st" --all 2>&1)
  case "$out" in *solo*"local-only"*) ok "a remoteless repo reads clean (local-only)" ;;
                 *) bad "a remoteless repo reads clean (local-only)" "$out" ;; esac

  # --all surfaces a checkout nobody registered; the default view does not.
  case "$out" in *solo*unregistered*) ok "--all flags an unregistered checkout" ;;
                 *) bad "--all flags an unregistered checkout" "$out" ;; esac
  out=$("$st" 2>&1)
  case "$out" in *solo*) bad "the default view omits unregistered repos" "$out" ;;
                 *) ok "the default view omits unregistered repos" ;; esac

  # The workspace's own uncommitted work is the easiest to forget.
  echo "scratch" >> "$ws/README.md"
  out=$("$st" 2>&1)
  case "$out" in *"(this workspace)"*dirty*) ok "the workspace's own dirt is reported" ;;
                 *) bad "the workspace's own dirt is reported" "$out" ;; esac
  git -C "$ws" checkout -q -- README.md

  # Shared detector: delete-repo must agree with what status just reported.
  local del
  del=$( (cd "$ws" && python3 .workspace/scripts/delete-repo.py kid) 2>&1 )
  case "$del" in *unpushed*) ok "delete-repo refuses on the same finding" ;;
                 *) bad "delete-repo refuses on the same finding" "$del" ;; esac
}

# ---------------------------------------------------------------------------
# 8p. Routine registration — the second, un-automatable phase (dogfood 10)
#
# `add-repo` can do everything except the one step that makes a repo readable to
# the remote run: adding it to the routine's `sources`, which lives in the Claude
# app. Skipping it fails SILENTLY — the run reports the repo as unreadable and
# omits it. So the outstanding state is a field in repos.yml, and the whole point
# of these assertions is that the two things that render it (the status gate and
# the summary banner) are projections which cannot disagree with that field.
# ---------------------------------------------------------------------------
test_routine_registration() {
  section "8p. Routine registration (phase two)"
  local ws; ws=$(new_ws ws-routine)
  local S="$ws/.workspace/scripts"
  local yml="$ws/.workspace/repos.yml"
  local sum="$ws/daily-plan-summary.md"
  local bare="$SANDBOX/origin-routine.git"
  bare_origin "$bare"

  # The workspace is a row in its own status output, so every membership edit
  # must be committed or `dirty` masks the exit code these assertions read.
  wcommit() { git -C "$ws" add -A; git -C "$ws" \
    -c user.email="$TEST_AUTHOR" -c user.name=Dev commit -qm "${1:-wip}" >/dev/null 2>&1; }
  rc_of() { "$S/status.py" >/dev/null 2>&1; echo $?; }

  # dogfood 21: the gate reports an outstanding registration only where a
  # routine EXISTS to be registered in. Everything below this line therefore
  # needs a routine_url; the no-routine half is asserted at the end.
  printf 'routine_url: https://claude.ai/code/routines/trig_TEST\n' >> "$ws/.workspace/config.yml"

  python3 "$S/add-repo.py" "$bare" --name gamma >/dev/null 2>&1
  assert_grep "a new entry is born OUTSTANDING" '^    routine_registered: false$' "$yml"
  # Land the kernel add-repo deliberately left uncommitted, so registration is
  # the only thing status can still be complaining about.
  git -C "$ws/gamma" add -A
  git -C "$ws/gamma" -c user.email="$TEST_AUTHOR" -c user.name=Dev \
    commit -qm "docs(claude): commit-discipline kernel"
  git -C "$ws/gamma" push -q origin main
  wcommit "register gamma"

  local out
  out=$("$S/status.py" 2>&1)
  case "$out" in *gamma*"routine not registered"*) ok "status names the outstanding repo" ;;
                 *) bad "status names the outstanding repo" "$out" ;; esac
  assert_eq "...and the gate exits non-zero" "1" "$(rc_of)"
  out=$("$S/status.py" -v 2>&1)
  case "$out" in *"make routine-registered"*) ok "-v says how to clear it" ;;
                 *) bad "-v says how to clear it" "$out" ;; esac

  python3 "$S/aggregate-plans.py" >/dev/null 2>&1
  assert_grep "the summary opens with a banner"  'Routine registration incomplete' "$sum"
  assert_grep "...naming the repo"               '`gamma`' "$sum"
  # Above the table: the banner invalidates everything below it.
  assert_eq "...before the At a glance table" "before" \
    "$(awk '/Routine registration incomplete/{print "before"; exit} /At a glance/{print "after"; exit}' "$sum")"

  # A repo switched off is out of the run entirely, so it has no debt to report.
  python3 "$S/mute-repo.py" gamma --skip >/dev/null 2>&1; wcommit "mute gamma"
  assert_eq "a disabled repo is exempt from the gate" "0" "$(rc_of)"
  python3 "$S/aggregate-plans.py" >/dev/null 2>&1
  assert_no_grep "...and out of the banner"     'Routine registration incomplete' "$sum"
  python3 "$S/mute-repo.py" gamma --unmute >/dev/null 2>&1; wcommit "unmute gamma"
  assert_eq "...and re-enabling brings it back" "1" "$(rc_of)"

  # --- the clearing verb: the only writer of a true ---
  python3 "$S/routine-registered.py" gamma >/dev/null 2>&1; wcommit "gamma in sources"
  assert_grep "the verb clears the flag"        '^    routine_registered: true$' "$yml"
  assert_eq "...and the gate goes green"        "0" "$(rc_of)"
  python3 "$S/aggregate-plans.py" >/dev/null 2>&1
  assert_no_grep "...and the banner disappears" 'Routine registration incomplete' "$sum"
  assert_eq "--check agrees nothing is outstanding" "0" \
    "$(python3 "$S/routine-registered.py" --check >/dev/null 2>&1; echo $?)"

  python3 "$S/routine-registered.py" gamma --unset >/dev/null 2>&1; wcommit "unset"
  assert_grep "--unset puts it back to outstanding" '^    routine_registered: false$' "$yml"
  assert_fails "--check reports it" python3 "$S/routine-registered.py" --check

  # ABSENT MEANS OUTSTANDING — the case every repo registered before this field
  # existed is in. Failing open here would silently claim they were all done.
  grep -v 'routine_registered' "$yml" > "$yml.tmp" && mv "$yml.tmp" "$yml"
  wcommit "strip the flag"
  out=$("$S/status.py" 2>&1)
  case "$out" in *gamma*"routine not registered"*) ok "an ABSENT flag reads as outstanding" ;;
                 *) bad "an ABSENT flag reads as outstanding" "$out" ;; esac

  # --- add-repo reconciles instead of refusing ---
  out=$(python3 "$S/add-repo.py" "$bare" --name gamma 2>&1)
  assert_grep "re-running add-repo back-fills the missing flag" \
    '^    routine_registered: false$' "$yml"
  case "$out" in *reconciling*) ok "...and says it is reconciling" ;;
                 *) bad "...and says it is reconciling" "$out" ;; esac
  case "$out" in *"already current"*) ok "...leaving an up-to-date kernel alone" ;;
                 *) bad "...leaving an up-to-date kernel alone" "$out" ;; esac

  # A reconcile of a complete entry is a zero-line diff. This is what makes the
  # verb safe to re-run over a registered repo instead of unregistering first.
  local before; before=$(file_hash "$yml")
  out=$(python3 "$S/add-repo.py" "$bare" --name gamma 2>&1)
  assert_eq "a second reconcile changes nothing" "$before" "$(file_hash "$yml")"
  case "$out" in *"already complete"*) ok "...and says so" ;;
                 *) bad "...and says so" "$out" ;; esac

  # It repairs what IS missing: a deleted plan slot comes back.
  rm -rf "$ws/.workspace/daily-plans/gamma"
  python3 "$S/add-repo.py" "$bare" --name gamma >/dev/null 2>&1
  assert_file "a reconcile re-seeds a deleted plan slot" \
    "$ws/.workspace/daily-plans/gamma/daily-plan.md"

  # And it never overwrites a cleared flag with false — the one way a reconcile
  # could quietly undo work you actually did.
  python3 "$S/routine-registered.py" gamma >/dev/null 2>&1
  python3 "$S/add-repo.py" "$bare" --name gamma >/dev/null 2>&1
  assert_grep "a reconcile preserves a cleared flag" '^    routine_registered: true$' "$yml"

  # --all is the one-shot after populating `sources` in a single edit.
  python3 "$S/routine-registered.py" gamma --unset >/dev/null 2>&1
  python3 "$S/routine-registered.py" --all >/dev/null 2>&1
  assert_grep "--all clears every registered repo" '^    routine_registered: true$' "$yml"
  assert_fails "an unknown name is refused" python3 "$S/routine-registered.py" nosuchrepo

  # repos.yml is CONTENT: the header comments must survive every write above.
  assert_grep "the file's header survives the flag edits" '^# repos.yml' "$yml"

  # -------------------------------------------------------------------------
  # dogfood 21: a workspace with NO routine has no phase two, so nothing can be
  # outstanding. Before this, such a workspace was permanently red for a step
  # its owner had deliberately decided not to take — and the only way to green
  # it was to record a `true` that was not true.
  # -------------------------------------------------------------------------
  python3 "$S/routine-registered.py" --all --unset >/dev/null 2>&1
  grep -v '^routine_url:' "$ws/.workspace/config.yml" > "$ws/.cfg.tmp"
  mv "$ws/.cfg.tmp" "$ws/.workspace/config.yml"
  wcommit "drop the routine"

  out=$("$S/status.py" 2>&1)
  case "$out" in *"routine not registered"*) bad "no routine means no finding" "$out" ;;
                 *) ok "no routine means no finding" ;; esac
  assert_eq "...and the gate exits ZERO on a clean floor" "0" "$(rc_of)"

  # The banner is the other projection of the same fact — it must agree.
  python3 "$S/aggregate-plans.py" >/dev/null 2>&1
  assert_no_grep "...and the summary banner is silent too" \
    'Routine registration incomplete' "$sum"

  # Recording a registration that cannot be true is refused outright.
  assert_fails "routine-registered refuses with no routine" \
    python3 "$S/routine-registered.py" gamma
  assert_grep "...leaving the flag untouched" '^    routine_registered: false$' "$yml"
  assert_succeeds "--check says there is nothing to register" \
    python3 "$S/routine-registered.py" --check

  # Nothing is cached: restoring the routine brings the debt straight back.
  printf 'routine_url: https://claude.ai/code/routines/trig_TEST\n' >> "$ws/.workspace/config.yml"
  wcommit "restore the routine"
  out=$("$S/status.py" 2>&1)
  case "$out" in *gamma*"routine not registered"*) ok "restoring a routine restores the finding" ;;
                 *) bad "restoring a routine restores the finding" "$out" ;; esac
  assert_eq "...and the gate is red again" "1" "$(rc_of)"
}

# ---------------------------------------------------------------------------
# 8m. The living README (task 019)
#
# README.md is the second hybrid: the generator owns the git-workspace-roster
# block, the user owns every other byte. The block must track membership without
# being remembered — so the verbs refresh it — and must stay byte-stable, or
# zero-diff dies.
# ---------------------------------------------------------------------------
test_living_readme() {
  section "8m. Living README (roster block)"
  local ws; ws=$(new_ws ws-readme)
  local rm="$ws/README.md"

  assert_grep "the roster block is emitted"    'git-workspace-roster:begin' "$rm"
  assert_grep "an empty workspace says so"     'No repos tracked yet'       "$rm"
  assert_grep "the deliverables are linked"    '\(daily-plan-summary\.md\)' "$rm"
  assert_no_grep "no archive is linked"        'state/archive/'             "$rm"
  assert_grep "...and git log is named as the history" 'git log -p'            "$rm"
  assert_grep "an unset routine is called out" 'Not set up yet'             "$rm"
  assert_no_grep "the seed placeholder is replaced" 'renders here on the first' "$rm"

  # A child repo whose README opens with a badge — the classic false positive.
  local seed="$SANDBOX/readme-seed"; rm -rf "$seed"; mkdir -p "$seed"
  git -C "$seed" init -q
  printf '# alpha\n\n[![build](img.svg)](ci)\n\nAlpha turns webhooks into pizza orders for a demo. Second sentence.\n' \
    > "$seed/README.md"
  git -C "$seed" add -A
  git -C "$seed" -c user.email=t@t -c user.name=t commit -qm init

  ( cd "$ws" && python3 .workspace/scripts/add-repo.py "$seed" --name alpha ) >/dev/null 2>&1
  assert_grep "add-repo scrapes a description into repos.yml" \
    'description: "Alpha turns webhooks' "$ws/.workspace/repos.yml"
  assert_no_grep "...and skips the badge line" 'description: "\[!\[' "$ws/.workspace/repos.yml"

  # GitHub's own description outranks the scrape — a human wrote it *as* a
  # one-liner. Stubbed on PATH so the suite never touches the network.
  local ghbin="$SANDBOX/gh-stub"; rm -rf "$ghbin"; mkdir -p "$ghbin"
  cat > "$ghbin/gh" <<'STUB'
#!/bin/sh
[ "$1" = "repo" ] && [ "$2" = "view" ] && { echo "The canonical GitHub blurb."; exit 0; }
exit 1
STUB
  chmod 755 "$ghbin/gh"
  ( cd "$ws" && PATH="$ghbin:$PATH" python3 .workspace/scripts/add-repo.py "$seed" --name ghrepo ) >/dev/null 2>&1
  assert_grep "the GitHub description wins over the README scrape" \
    'description: "The canonical GitHub blurb\."' "$ws/.workspace/repos.yml"

  # gh present but failing (not GitHub, not authed, no description) must fall
  # through to the scrape rather than leaving the repo undescribed.
  cat > "$ghbin/gh" <<'STUB'
#!/bin/sh
exit 1
STUB
  chmod 755 "$ghbin/gh"
  ( cd "$ws" && PATH="$ghbin:$PATH" python3 .workspace/scripts/add-repo.py "$seed" --name ghfail ) >/dev/null 2>&1
  assert_grep "a failing gh falls back to the README scrape" \
    'name: ghfail' "$ws/.workspace/repos.yml"
  assert_eq "...with the scraped text, not an empty description" "2" \
    "$(grep -c 'description: "Alpha turns webhooks' "$ws/.workspace/repos.yml" | tr -d ' ')"
  ( cd "$ws" && python3 .workspace/scripts/delete-repo.py ghrepo ) >/dev/null 2>&1
  ( cd "$ws" && python3 .workspace/scripts/delete-repo.py ghfail ) >/dev/null 2>&1
  assert_grep "the roster lists the repo"      '\*\*alpha\*\*'        "$rm"
  assert_grep "...with its description"        'Alpha turns webhooks' "$rm"
  assert_no_grep "...and no longer says empty" 'No repos tracked yet' "$rm"

  # An explicit description must survive YAML round-tripping unmangled.
  ( cd "$ws" && python3 .workspace/scripts/add-repo.py "$seed" --name beta \
      --description 'Beta: has a colon, a "quote", a #hash and a | pipe.' ) >/dev/null 2>&1
  assert_grep "--description round-trips through repos.yml" \
    'a #hash and a' "$ws/.workspace/repos.yml"
  assert_grep "...and a pipe is escaped so the table survives" \
    'a \\\| pipe' "$rm"

  # Registered but not checked out: the roster must say so, not omit it.
  ( cd "$ws" && python3 .workspace/scripts/add-repo.py "$seed" --name gamma --no-clone ) >/dev/null 2>&1
  assert_grep "an unmaterialized repo is flagged" 'not checked out' "$rm"
  assert_grep "...with the bootstrap nudge"       'make bootstrap'  "$rm"

  # The verbs keep it in sync without being asked.
  ( cd "$ws" && python3 .workspace/scripts/mute-repo.py beta ) >/dev/null 2>&1
  assert_grep "mute-repo refreshes the roster" 'muted' "$rm"
  ( cd "$ws" && python3 .workspace/scripts/mute-repo.py gamma --skip ) >/dev/null 2>&1
  assert_grep "--skip shows as skipped" 'skipped' "$rm"
  ( cd "$ws" && python3 .workspace/scripts/delete-repo.py gamma ) >/dev/null 2>&1
  assert_no_grep "delete-repo drops the row" 'gamma' "$rm"

  # routine_url turns the nudge into a link.
  printf 'routine_url: https://claude.ai/code/routines/trig_TEST\n' >> "$ws/.workspace/config.yml"
  ( cd "$ws" && python3 .workspace/scripts/render-readme.py ) >/dev/null 2>&1
  assert_grep "a configured routine is linked" 'trig_TEST' "$rm"
  assert_no_grep "...and the nudge is gone"    'Not set up yet' "$rm"

  # Byte-stability: the whole zero-diff invariant rides on this.
  local before after
  before=$(file_hash "$rm")
  ( cd "$ws" && python3 .workspace/scripts/render-readme.py ) >/dev/null 2>&1
  after=$(file_hash "$rm")
  assert_eq "re-rendering is byte-identical" "$before" "$after"
  ( cd "$ws" && python3 .workspace/scripts/render-readme.py --check ) >/dev/null 2>&1
  assert_eq "--check passes when current" "0" "$?"

  # The user's own text is content and must survive every render.
  printf '\n## My notes\n\nDo not lose this.\n' >> "$rm"
  ( cd "$ws" && python3 .workspace/scripts/add-repo.py "$seed" --name delta ) >/dev/null 2>&1
  assert_grep "text outside the markers survives a refresh" 'Do not lose this\.' "$rm"
  assert_grep "...and the new repo still landed"            '\*\*delta\*\*'      "$rm"

  git -C "$ws" add -A; git -C "$ws" commit -qm "roster"
  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_empty "update.sh over a rendered workspace: still zero diff" \
    "$(git -C "$ws" status --porcelain)"

  # A README with no markers (an older workspace, or the user's own) gains the
  # block by APPEND — update.sh is how an existing workspace catches up.
  local old; old=$(new_ws ws-readme-old)
  python3 - "$old/README.md" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text()
i, j = t.find("<!-- git-workspace-roster:begin"), t.find("<!-- git-workspace-roster:end -->")
p.write_text(t[:i] + t[j + len("<!-- git-workspace-roster:end -->"):])
PY
  git -C "$old" add -A; git -C "$old" commit -qm "strip the block"
  "$GEN_ROOT/update.sh" "$old" >/dev/null 2>&1
  assert_grep "update.sh back-fills a missing block" 'git-workspace-roster:begin' "$old/README.md"
  git -C "$old" add -A; git -C "$old" commit -qm "back-filled"
  "$GEN_ROOT/update.sh" "$old" >/dev/null 2>&1
  assert_empty "...and settles at zero diff" "$(git -C "$old" status --porcelain)"

  # Malformed markers: refuse to guess, leave the file alone — but do NOT take
  # the machinery upgrade down with it. A dashboard is not a kernel.
  local bad; bad=$(new_ws ws-readme-bad)
  printf '# Mine\n\n<!-- git-workspace-roster:begin -->\nhalf open\n' > "$bad/README.md"
  before=$(file_hash "$bad/README.md")
  # No cd needed: the renderer resolves the workspace from its own location, not
  # from cwd — and `env -C` is not portable to the BSD env on macOS.
  assert_fails "a half-open block is refused" \
    python3 "$bad/.workspace/scripts/render-readme.py"
  assert_eq "...leaving the README untouched" "$before" "$(file_hash "$bad/README.md")"
  "$GEN_ROOT/update.sh" "$bad" >/dev/null 2>&1
  assert_eq "...and update.sh still succeeds (warns, does not abort)" "0" "$?"
  assert_eq "...still untouched afterwards" "$before" "$(file_hash "$bad/README.md")"
}

# ---------------------------------------------------------------------------
# 9. Push round-trip against a LOCAL bare remote (no network)
# ---------------------------------------------------------------------------
test_local_remote() {
  section "9. Push round-trip (local bare remote, no network)"
  local bare="$SANDBOX/remote.git"
  rm -rf "$bare"; git init -q --bare "$bare"

  local ws; ws=$(new_ws ws-remote --remote "$bare")
  assert_eq "origin is wired by --remote" "$bare" "$(git -C "$ws" remote get-url origin)"

  # A child checkout must not ride along in the push.
  mkdir -p "$ws/childrepo" && git -C "$ws/childrepo" init -q
  echo hi > "$ws/childrepo/f.txt"

  if git -C "$ws" push -q -u origin main 2>/dev/null; then
    ok "workspace pushes to origin/main"
    local clone="$SANDBOX/ws-remote-clone"
    rm -rf "$clone"; git clone -q "$bare" "$clone"
    assert_eq "the clone carries exactly the emitted tree" \
      "$EXPECTED_TRACKED" "$(ours "$clone")"
    assert_no_file "the child repo did NOT ride along" "$clone/childrepo"

    # Simulate the routine landing an aggregate remotely, then pull it down.
    echo '# summary from the routine' > "$clone/summary.md"
    git -C "$clone" add -f summary.md
    git -C "$clone" -c user.email=t@t -c user.name=t commit -qm "status: aggregates"
    git -C "$clone" push -q origin main
    if git -C "$ws" pull -q --ff-only origin main 2>/dev/null; then
      ok "ff-only pull brings the aggregate down"
      assert_file "summary.md landed locally" "$ws/summary.md"
    else
      bad "ff-only pull brings the aggregate down" "pull --ff-only failed"
    fi
  else
    bad "workspace pushes to origin/main" "push failed"
  fi
}

# ---------------------------------------------------------------------------
# 10. GitHub round-trip — opt-in, needs the persistent fixture
# ---------------------------------------------------------------------------
test_github_remote() {
  section "10. GitHub round-trip (opt-in, needs network)"
  local fixture="$GEN_ROOT/../git-workspace-test"

  if [ "$RUN_REMOTE" -eq 0 ]; then
    skip "GitHub round-trip" "pass --remote to run"
    return
  fi
  if [ ! -d "$fixture/.git" ]; then
    skip "GitHub round-trip" "fixture $fixture is not a checkout"
    return
  fi
  # Never run against a fixture with work in it — this test pulls into it.
  if [ -n "$(git -C "$fixture" status --porcelain)" ]; then
    skip "GitHub round-trip" "fixture has uncommitted changes; refusing to touch it"
    return
  fi
  if ! git -C "$fixture" fetch -q origin 2>/dev/null; then
    skip "GitHub round-trip" "cannot reach origin (offline?)"
    return
  fi

  # (a) Bring the fixture up to the current machinery, then assert that a SECOND
  # update is a no-op. The invariant is idempotence, not "the fixture happens to
  # be current" — a genuine machinery upgrade landing here is expected and gets
  # committed, exactly as a maintainer would.
  "$GEN_ROOT/update.sh" "$fixture" >/dev/null 2>&1
  if [ -n "$(git -C "$fixture" status --porcelain)" ]; then
    git -C "$fixture" add -A
    git -C "$fixture" commit -qm "workspace(machinery): re-apply generator machinery

- [Context]: acceptance run against the current create-git-workspace.
- [Impact]: brings the fixture's machinery up to date."
  fi
  "$GEN_ROOT/update.sh" "$fixture" >/dev/null 2>&1
  assert_empty "fixture: a second update.sh leaves zero diff" "$(git -C "$fixture" status --porcelain)"

  git -C "$fixture" push -q origin main 2>/dev/null

  # (b) a fresh clone — this is what the remote routine's sandbox actually sees
  local clone="$SANDBOX/gh-routine"
  rm -rf "$clone"
  if ! git clone -q "$(git -C "$fixture" remote get-url origin)" "$clone" 2>/dev/null; then
    bad "fixture: clone from origin" "clone failed"
    return
  fi
  assert_eq "clone: emitted tree arrived over the wire" \
    "$EXPECTED_TRACKED" "$(ours "$clone")"

  # (c) the routine writes both deliverables and lands them on main.
  # No `git add -f`: if the allowlist ignores them, this test fails — which is
  # exactly how the missing !/summary.md line was found.
  printf '# summary — round-trip %s\n' "$$" > "$clone/summary.md"
  printf '# daily-plan-summary — round-trip %s\n' "$$" > "$clone/daily-plan-summary.md"
  git -C "$clone" add -A
  local staged; staged=$(git -C "$clone" diff --cached --name-only | sort | tr '\n' ' ')
  assert_eq "routine: allowlist lets both deliverables be staged" \
    "daily-plan-summary.md summary.md " "$staged"
  git -C "$clone" -c user.email="$TEST_AUTHOR" -c user.name=routine commit -qm "status(aggregate): round-trip"
  if git -C "$clone" push -q origin main 2>/dev/null; then
    ok "routine: aggregates pushed to main"
  else
    bad "routine: aggregates pushed to main" "push failed"
    return
  fi

  # (d) the morning pull brings them down
  local rc
  git -C "$fixture" pull --ff-only -q origin main >/dev/null 2>&1; rc=$?
  assert_eq   "morning: pull --ff-only succeeds" "0" "$rc"
  assert_grep "morning: summary.md landed"            "round-trip $$" "$fixture/summary.md"
  assert_grep "morning: daily-plan-summary.md landed" "round-trip $$" "$fixture/daily-plan-summary.md"

  # (e) the decline path. Run it in a THROWAWAY clone, never the user's fixture:
  # --ff-only must refuse a diverged history rather than merge or clobber.
  local diverged="$SANDBOX/gh-diverged"
  rm -rf "$diverged"
  git clone -q "$(git -C "$fixture" remote get-url origin)" "$diverged" 2>/dev/null
  echo "local-only work" >> "$diverged/README.md"
  git -C "$diverged" -c user.email="$TEST_AUTHOR" -c user.name=dev commit -qam "local: diverging commit"
  local local_head; local_head=$(git -C "$diverged" rev-parse HEAD)
  printf '# summary — moved on %s\n' "$$" > "$clone/summary.md"
  git -C "$clone" -c user.email="$TEST_AUTHOR" -c user.name=routine commit -qam "status: remote moves on"
  git -C "$clone" push -q origin main 2>/dev/null

  git -C "$diverged" pull --ff-only -q origin main >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then ok "diverged: pull --ff-only safely declines"
  else bad "diverged: pull --ff-only safely declines" "it fast-forwarded over a diverged history"; fi
  assert_eq "diverged: the local commit is untouched" "$local_head" "$(git -C "$diverged" rev-parse HEAD)"

  # Leave the fixture current so the next run starts from a clean slate.
  git -C "$fixture" pull --ff-only -q origin main >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
main() {
  printf "${B}create-git-workspace acceptance suite${X}\n"
  printf "${D}sandbox: %s${X}\n" "$SANDBOX"
  rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"

  test_emitted_tree
  test_generated_scripts
  test_zero_diff
  test_machinery
  test_content_and_runtime
  test_claude_md
  test_version_stamp
  test_refusals
  test_task_system
  test_workspace_plan
  test_status_subsystem
  test_aggregation
  test_repo_verbs
  test_daily_routine
  test_pull_trigger
  test_commit_kernel
  test_claude_pipeline
  test_guide_and_skill
  test_optional_extras
  test_living_readme
  test_pending_sweep
  test_routine_registration
  test_per_repo_replan
  test_local_remote
  test_github_remote

  # Keep the generated workspaces when anything failed: they ARE the evidence,
  # and wiping them forces a local reproduction to see what went wrong (in CI,
  # where reproducing is expensive, they get uploaded as an artifact).
  if [ "$KEEP" -eq 1 ] || [ "$FAIL" -gt 0 ]; then
    printf "\n${D}sandbox kept at %s${X}\n" "$SANDBOX"
  else
    rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
  fi

  printf "\n${B}%d passed, %d failed, %d skipped${X}\n" "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]
}

main