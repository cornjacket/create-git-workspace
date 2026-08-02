#!/usr/bin/env bash
# revendor.sh — refresh vendor/create-project-system/ from an upstream checkout.
#
#   ./tools/revendor.sh [path-to-create-project-system]
#
# Copies ONLY generate.sh + src/ (see vendor/README.md for why), rewrites the
# version stamp, and leaves everything uncommitted for review. It never touches
# the source checkout.
set -euo pipefail

GEN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC=${1:-$GEN_ROOT/../create-project-system}
DEST="$GEN_ROOT/vendor/create-project-system"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$SRC" ] || die "no such directory: $SRC"
SRC=$(cd "$SRC" && pwd)
[ -f "$SRC/generate.sh" ] || die "$SRC does not look like create-project-system (no generate.sh)"

# A dirty source means the stamp would name a commit that does not describe what
# was actually copied — the one thing the stamp exists to prevent.
if [ -n "$(git -C "$SRC" status --porcelain 2>/dev/null)" ]; then
  git -C "$SRC" status --short >&2
  die "source checkout has uncommitted changes — commit or stash them first"
fi

version=$(git -C "$SRC" describe --tags --always 2>/dev/null || echo "unknown")
sha=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo "unknown")
today=$(date +%Y-%m-%d)

rm -rf "$DEST"
mkdir -p "$DEST"
cp "$SRC/generate.sh" "$DEST/generate.sh"
cp -R "$SRC/src" "$DEST/src"
chmod +x "$DEST/generate.sh"

python3 - "$GEN_ROOT/vendor/README.md" "$version" "$sha" "$today" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); version, sha, today = sys.argv[2:5]
t = p.read_text()
t = re.sub(r"(?m)^\| \*\*Vendored at\*\* \|.*$",
           "| **Vendored at** | `%s` (`%s`) |" % (version, sha), t)
t = re.sub(r"(?m)^\| \*\*Vendored on\*\* \|.*$",
           "| **Vendored on** | %s |" % today, t)
p.write_text(t)
PY

printf '\033[1m==>\033[0m re-vendored create-project-system %s (%s)\n' "$version" "${sha:0:12}"
printf '    %s files under vendor/create-project-system/\n' "$(find "$DEST" -type f | wc -l | tr -d ' ')"
printf '    next: git diff · ./tests/run-tests.sh · commit\n'
