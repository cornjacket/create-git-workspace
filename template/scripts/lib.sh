#!/usr/bin/env bash
# lib.sh — shared helpers for the Meta-State Workspace Wrapper scripts.
# Source this; do not execute it.

# Absolute path to the workspace root (the dir that contains this scripts/ dir).
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_YML="${REPOS_YML:-$WORKSPACE_ROOT/repos.yml}"

# parse_repos — emit one TAB-separated record per repo, in a fixed field order:
#   name  type  path  branch  parent_repo_path  url  tags(csv)
# Missing fields come back empty; `type` defaults to "standard".
# Uses python3 + PyYAML so we parse real YAML instead of guessing with awk.
parse_repos() {
  python3 - "$REPOS_YML" <<'PY'
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    sys.stderr.write("lib.sh: repos.yml not found: %s\n" % sys.argv[1]); sys.exit(2)

for r in (data.get("repos") or []):
    row = [
        r.get("name", ""),
        r.get("type", "standard"),
        r.get("path", ""),
        r.get("branch", ""),
        r.get("parent_repo_path", ""),
        r.get("url", ""),
        ",".join(r.get("tags") or []),
    ]
    print("\t".join(str(x) for x in row))
PY
}
