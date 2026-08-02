#!/usr/bin/env bash
# install-hooks.sh — install guard.sh as this workspace's pre-commit hook.
#
#   install-hooks.sh              install (or refresh) the hook
#   install-hooks.sh --check      report status; exit 1 if missing or stale
#   install-hooks.sh --uninstall  remove it (only if we own it)
#   install-hooks.sh --force      overwrite a pre-commit hook we did not write
#
# WHY THIS IS A SCRIPT AND NOT SOMETHING setup.sh JUST DOES: hooks live in
# `.git/hooks/`, which git does not track. A workspace cloned onto a second
# machine arrives with no hook at all, and `update.sh` cannot fix that from the
# generator side. So the installer ships *inside* the workspace, where it can be
# re-run after any clone — `make hook`.
#
# The hook itself is one line: exec guard.sh, which fails the commit if a child
# repo, a `.git` dir, or a worktree pointer was staged into the wrapper index.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MARKER="# managed by create-git-workspace (install-hooks.sh)"

mode=install
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     mode=check; shift ;;
    --uninstall) mode=uninstall; shift ;;
    --force)     force=1; shift ;;
    -h|--help)   sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)           echo "install-hooks: unknown option: $1" >&2; exit 2 ;;
  esac
done

cd "$WORKSPACE_ROOT"
git rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "install-hooks: not a git repo — run 'git init' first." >&2; exit 2; }

# --git-path honours core.hooksPath and worktree layouts; do not hardcode .git/hooks.
hooks_dir=$(git rev-parse --git-path hooks)
hook="$hooks_dir/pre-commit"

read -r -d '' body <<EOF || true
#!/bin/sh
$MARKER
# Do not edit — re-run '.workspace/scripts/install-hooks.sh' to refresh.
#
# Refuses a commit that would swallow a managed child repo, a .git directory, or
# a worktree pointer into the wrapper's index.
exec "\$(git rev-parse --show-toplevel)/.workspace/scripts/guard.sh"
EOF

ours() { [ -f "$hook" ] && grep -qF "$MARKER" "$hook"; }

case "$mode" in
  check)
    if [ ! -e "$hook" ]; then
      echo "hook: NOT installed — run 'make hook'"; exit 1
    elif ! ours; then
      echo "hook: a pre-commit hook exists but is NOT ours ($hook)"; exit 1
    elif [ "$(cat "$hook")" != "$body" ]; then
      echo "hook: installed but STALE — run 'make hook' to refresh"; exit 1
    fi
    echo "hook: installed and current ($hook)"
    ;;

  uninstall)
    if [ ! -e "$hook" ]; then
      echo "hook: nothing to remove."
    elif ours || [ "$force" -eq 1 ]; then
      rm -f "$hook"; echo "hook: removed $hook"
    else
      # Never delete a hook someone else wrote — that is unrecoverable work.
      echo "install-hooks: $hook is not ours; refusing to remove it (--force overrides)." >&2
      exit 1
    fi
    ;;

  install)
    if [ -e "$hook" ] && ! ours && [ "$force" -eq 0 ]; then
      echo "install-hooks: $hook already exists and was not written by us." >&2
      echo "               Inspect it, then re-run with --force to replace it," >&2
      echo "               or chain guard.sh from your own hook:" >&2
      echo "                 .workspace/scripts/guard.sh || exit 1" >&2
      exit 1
    fi
    if [ -f "$hook" ] && [ "$(cat "$hook")" = "$body" ]; then
      echo "hook: already current ($hook)"
      exit 0
    fi
    mkdir -p "$hooks_dir"
    printf '%s\n' "$body" > "$hook"
    chmod 755 "$hook"
    echo "hook: installed guard.sh as pre-commit ($hook)"
    ;;
esac
