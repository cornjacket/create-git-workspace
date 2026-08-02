# 016 — optional extras

Status: done (2026-08-02)

Nice-to-haves, built last.

## Acceptance
- `setup.sh --create-remote` → `gh repo create` (opt-in; local-only stays default).
- Install `guard.sh` as the workspace's pre-commit hook (opt-in).

## Notes
- The `Makefile` command surface is NOT here — it's a decided deliverable emitted
  by `setup.sh` (task 002).

## What landed

### `setup.sh --create-remote` (+ `--public`)

Creates the GitHub repo with `gh` and wires it as origin.

- **Private by default.** A workspace carries your plans and your rollup;
  defaulting to public would publish them on a flag whose name says nothing
  about visibility. `--public` is the explicit opt-out.
- **Mutually exclusive with `--remote`** — one creates the remote, the other
  attaches an existing one; letting both through means silently picking a winner.
- **Pre-flighted.** `gh` on PATH *and* `gh auth status` are checked before
  anything is written. Discovering a missing tool halfway through leaves a
  stamped-but-misconfigured workspace and a confusing error.
- **Creates, does not push.** Pushing is a separate outward-facing act, and
  `--no-commit` means there may be nothing to push. The closing print names the
  one command. A `gh` failure (name taken, no permission) warns rather than
  aborting — the workspace is complete and usable either way.

### The pre-commit hook

`--with-hook` at stamp time, but the installer itself is
`.workspace/scripts/install-hooks.sh` — **inside the emitted workspace**, exposed
as `make hook` / `make hook-check`.

The design point: `.git/hooks/` is not tracked by git. A workspace cloned onto a
second machine arrives with no hook, and `update.sh` cannot fix that from the
generator side. So the installer has to live where it can be re-run after any
clone. `setup.sh` only invokes it; it does not reimplement the logic.

It is idempotent (byte-compare, "already current"), supports `--check` /
`--uninstall` / `--force`, resolves the hooks directory via
`git rev-parse --git-path hooks` (so `core.hooksPath` and worktree layouts work),
and **refuses to overwrite or remove a pre-commit hook it did not write** —
deleting someone's hook is unrecoverable. It suggests chaining instead:
`.workspace/scripts/guard.sh || exit 1`.

### Tests — §8l, 244 assertions total

The hook is exercised for real rather than by inspection: install it, stage a
child repo with `git add -f`, and require the commit to **fail**. Plus the
foreign-hook refusals, `--force`, `--uninstall`, idempotency, and the
`--create-remote` contract up to (never through) the network call — including
that a missing `gh` leaves no half-stamped workspace.
