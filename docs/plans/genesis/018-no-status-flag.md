# 018 — `--no-status` is accepted but not honored

Status: done (2026-08-02) — removed the flag

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

## Outcome — removed

**The flag is gone.** The deciding argument is not implementation cost, it is
that the opt-out never had a coherent meaning: PLAN.md's own framing is that
"each workspace **intrinsically** carries what project-status did". Status is not
a layer a workspace opts into — it *is* the workspace layer. `--no-tasks` stays
precisely because the task-system is the opposite case: a separate, delegated
generator with its own machinery/content split, which a workspace can genuinely
do without.

Passing `--no-status` now fails with `unknown option`. That is deliberately
louder than ignoring it: a flag that prints "skipped" and installs the subsystem
anyway is worse than no flag at all, because it makes the user believe something
false about their workspace.

- `setup.sh` — flag removed from parsing, usage, and the dead `with_status`
  branch; a comment records why there is no such flag, so it is not "helpfully"
  re-added.
- `tests/run-tests.sh` §8 pins the removal: it must **error** (not be silently
  ignored), stamp nothing, and be absent from `--help` — while `--no-tasks`
  stays present. 223 assertions.
- `PLAN.md` §setup.sh carries the amendment, and the usage line is now real
  rather than "proposed"; `002` is annotated as superseded rather than rewritten.

### Also fixed here

`setup.sh`'s closing print still said *"Edit `.workspace/repos.yml` — add the
repos this workspace manages"* — the one thing the kernel, the guide, and the
verbs all forbid. It now points at `make add-repo`, says outright that
`repos.yml` is a lockfile, and cites `status-guide.md` §5 for the routine seams.
Same class of defect as the flag: the generator telling the user something untrue
about itself.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `018` — `setup.sh --no-status` is accepted but never honored: honor it or remove it. *(Surfaced by `015` — the flag had been inert since `002`. **Removed**: status is the workspace layer, not an opt-in to it. Also fixed setup.sh's closing print, which still told you to hand-edit `repos.yml` — the one thing the kernel forbids.)*
