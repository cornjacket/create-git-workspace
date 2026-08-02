# 018 — `--no-status` is accepted but not honored

Status: todo

`setup.sh --no-status` parses, prints `status: skipped (--no-status)`, and then
installs the status subsystem anyway. The flag was added in `002` with a note
that the subsystem lands in `008`–`010`; those landed, and nobody came back to
wire it. Found while bringing the generator README current (`015`) — documenting
a flag that does nothing was the tell.

## Acceptance
- Either **honor it** — skip the status scripts, prompts, workflows, the status
  half of the `Makefile`, and the status sections of the emitted `CLAUDE.md`
  kernel + `status-guide.md` — or **remove it** and say the subsystem is
  intrinsic.
- Whichever way: `update.sh` must not add the subsystem later to a workspace that
  opted out (the `--no-tasks` precedent, tested in §8b).
- `tests/run-tests.sh` covers the chosen behaviour, and zero-diff still holds.

## Notes
- Honoring it is a real slice of work: the emitted tree, the allowlist, the
  `Makefile`, `EXPECTED_TRACKED`, and the kernel all currently assume the status
  subsystem exists. Removing the flag is the cheaper honest answer if a
  status-free workspace is not actually a use case — a wrapper with no rollup is
  just `bootstrap.sh` + `guard.sh`, which may still be worth supporting.
- Compare `--no-tasks`, which *is* honored end to end, including the "update
  never adds a declined subsystem" rule.
