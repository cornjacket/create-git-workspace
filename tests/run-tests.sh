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

# The emitted tree. Update this list deliberately when a task adds a file —
# a surprise here means the generator started emitting something unplanned.
EXPECTED_TRACKED="\
.gitignore
.workspace/config.yml
.workspace/repos.yml
.workspace/scripts/bootstrap.sh
.workspace/scripts/guard.sh
.workspace/scripts/lib.sh
.workspace/scripts/status.sh
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
assert_grep()    { if grep -qE "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1" "pattern not found in $3: $2"; fi; }
assert_no_grep() { if grep -qE "$2" "$3" 2>/dev/null; then bad "$1" "pattern SHOULD be absent from $3: $2"; else ok "$1"; fi; }
# assert_fails — the command must exit non-zero (used for the refusal paths).
assert_fails()   { local l=$1; shift; if "$@" >/dev/null 2>&1; then bad "$l" "command unexpectedly succeeded: $*"; else ok "$l"; fi; }

ws_clean() { # a workspace with no diff AND no untracked/modified files
  [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]
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
    "$EXPECTED_TRACKED" "$(git -C "$ws" ls-files)"

  assert_file "hidden control plane exists"      "$ws/.workspace"
  assert_exec "scripts are executable"           "$ws/.workspace/scripts/status.sh"
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
YML

  # Run from an unrelated cwd: the scripts must not depend on the caller's pwd.
  local out rc
  out=$(cd / && "$ws/.workspace/scripts/status.sh" 2>&1); rc=$?
  assert_eq "status.sh exits 0 with a clean child" "0" "$rc"
  case "$out" in
    *childrepo*clean*) ok "status.sh reports the child clean" ;;
    *) bad "status.sh reports the child clean" "$out" ;;
  esac

  echo dirty > "$ws/childrepo/f.txt"
  (cd / && "$ws/.workspace/scripts/status.sh" >/dev/null 2>&1)
  assert_eq "status.sh exits non-zero when a child is dirty" "1" "$?"

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

  echo 'echo VANDALIZED' >> "$ws/.workspace/scripts/status.sh"
  echo '#!/bin/sh' > "$ws/.workspace/scripts/retired.sh"
  echo '# vandalized' >> "$ws/Makefile"
  git -C "$ws" add -A
  git -C "$ws" commit -qm "vandalize machinery"

  "$GEN_ROOT/update.sh" "$ws" >/dev/null 2>&1
  assert_no_grep "vandalized status.sh is restored" 'VANDALIZED' "$ws/.workspace/scripts/status.sh"
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
  assert_grep "workspace name substituted"       '^ws-claude-create/'      "$d/CLAUDE.md"
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
  before=$(shasum "$d/CLAUDE.md" | cut -d' ' -f1)
  "$GEN_ROOT/setup.sh" "$d" --name wsclaude --author "$TEST_AUTHOR" --no-commit --force >/dev/null 2>&1
  after=$(shasum "$d/CLAUDE.md" | cut -d' ' -f1)
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
    before=$(shasum "$d/CLAUDE.md" | cut -d' ' -f1)
    if "$GEN_ROOT/setup.sh" "$d" --name wsclaude --author "$TEST_AUTHOR" --no-commit >/dev/null 2>&1; then
      bad "$label -> aborts" "setup.sh succeeded on a malformed CLAUDE.md"
    else
      after=$(shasum "$d/CLAUDE.md" | cut -d' ' -f1)
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
  cp -R "$GEN_ROOT/template" "$GEN_ROOT/lib" "$GEN_ROOT/setup.sh" "$GEN_ROOT/update.sh" "$GEN_ROOT/VERSION" "$gen/"

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
      "$EXPECTED_TRACKED" "$(git -C "$clone" ls-files)"
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
  section "10. GitHub round-trip (opt-in)"
  local fixture="$GEN_ROOT/../git-workspace-test"
  if [ "$RUN_REMOTE" -eq 0 ]; then
    skip "GitHub round-trip" "pass --remote to run"
    return
  fi
  if [ ! -d "$fixture" ]; then
    skip "GitHub round-trip" "fixture $fixture does not exist yet"
    return
  fi
  skip "GitHub round-trip" "routine scripts (daily.sh/pull.sh) land in tasks 010-011"
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
  test_local_remote
  test_github_remote

  if [ "$KEEP" -eq 1 ]; then
    printf "\n${D}sandbox kept at %s${X}\n" "$SANDBOX"
  else
    rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
  fi

  printf "\n${B}%d passed, %d failed, %d skipped${X}\n" "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]
}

main