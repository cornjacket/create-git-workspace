# 017 — CI: run the acceptance suite on push

Status: done (2026-08-01)

Not in the original 001–016 breakdown. Added after noticing that eleven commits
had reached `main` with **no automated verification at all** — the 117-assertion
suite only ran when someone ran it by hand, so the zero-diff invariant was
protected by discipline rather than by the repo.

## Acceptance
- `.github/workflows/tests.yml` runs `./tests/run-tests.sh` on push to `main`,
  on pull requests, and on demand (`workflow_dispatch`).
- Installs PyYAML — the only third-party dependency of the emitted workspace
  (both the `repos.yml` parser and the status subsystem import it).
- Configures a git identity, or `setup.sh` takes its "no git identity → stage but
  do not commit" path and every assertion that reads git history fails.
- Runs **without** `--remote`: the GitHub round-trip needs the
  `../git-workspace-test` sibling checkout, which does not exist on a runner.
  That section skips itself with a reason rather than failing.
- Uploads `sandbox/` as an artifact when the run fails.

## Two portability bugs this surfaced
The suite was macOS-only and would have gone red on its first Linux run:
- **`sed -i ''`** is a syntax error under GNU sed (it reads `''` as the script).
  Replaced with `subst_in_file`, a literal python3 replacement.
- **`shasum`** is not guaranteed outside macOS. Replaced with `file_hash`, which
  falls back `shasum` → `sha1sum` → `cksum`.

While replacing them, the regex for the second edit rewrote `file_hash`'s own
body into a call to itself. The suite still reported **117 passed** — the
recursion returned empty for both sides of every hash comparison, so
`assert_eq "" ""` passed. A green suite proved nothing there; the fix was
verified by mutation (make `replan` non-idempotent → the assertion fails with
two real, different hashes).

## Also changed
`run-tests.sh` now **keeps `sandbox/` when any assertion failed** (previously
only with `--keep`). The generated workspaces are the evidence; wiping them
forces a local reproduction to see what broke. This is what makes the CI
artifact upload useful.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `017` — **CI**: run the acceptance suite on push/PR (`tests.yml`). *(Not in the original breakdown — added once it was clear commits were landing on `main` with no automated verification.)*
