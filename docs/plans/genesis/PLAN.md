# PLAN — genesis (COMPLETE)

**Build `create-git-workspace`: a generator that stamps out a git-workspace — a
wrapper repo that manages other repos and worktrees, with an intrinsic
per-developer status subsystem.**

Started 2026-07-31 from the architecture in `DESIGN.md` §1–6, which existed first
as a hand-built wrapper. Finished 2026-08-02. Every design decision this effort
produced has graduated into [`DESIGN.md`](../../../DESIGN.md); what remains here
is the sequence and the task files.

## Status

Complete. 19 tasks, all closed except `015`, which was a *standing* task — keep
the generator README current as steps land — and closes with the effort itself.

Delivered: `setup.sh` / `update.sh` with the zero-diff invariant, the
machinery/content/runtime split, the two marker-block hybrids, the full status
subsystem (verbs, pipeline, remote routine, morning pull), the child commit
kernel, the kernel/skill/guide instruction split, a 279-assertion acceptance
suite, and CI.

## Task files

Numbered in **build order**. `001`–`005` are the generator skeleton; `006`–`016`
the status subsystem on top of that proven base; `017`+ were discovered during
the build rather than planned up front.

| # | Task | Outcome |
|---|---|---|
| [001](001-restructure-template-hidden-dir.md) | restructure `template/` into the hidden `.workspace/` layout | done |
| [002](002-implement-setup-sh.md) | implement `setup.sh` | done |
| [003](003-implement-update-sh.md) | implement `update.sh` (zero-diff) | done |
| [004](004-claude-md-generation.md) | `CLAUDE.md` marker-block injection | done |
| [005](005-test-harness.md) | the acceptance harness | done |
| [006](006-vendor-create-project-system.md) | vendor `create-project-system` | done |
| [007](007-workspace-level-plan.md) | workspace task-system + `_workspace` plan | done |
| [008](008-status-subsystem-core.md) | status core: sync / new-work / aggregate / run | done |
| [009](009-repo-verbs.md) | `add-repo` / `delete-repo` / `mute-repo` | done |
| [010](010-remote-status-routine.md) | the remote routine (`daily.sh` + workflows) | done |
| [011](011-morning-pull-trigger.md) | the morning pull trigger (`pull.sh`) | done |
| [012](012-child-commit-kernel-injection.md) | child commit-kernel injection | done |
| [013](013-status-pipeline-tests.md) | status-pipeline tests (stubbed `claude`) | done |
| [014](014-status-guide-skill.md) | the on-demand status guide + skill | done |
| [015](015-generator-readme.md) | generator `README.md` — **standing** | closed with the effort |
| [016](016-optional-extras.md) | `--create-remote`, the pre-commit hook installer | done |
| [017](017-ci-workflow.md) | CI: run the suite on push/PR | done |
| [018](018-no-status-flag.md) | remove the inert `--no-status` flag | done |
| [019](019-living-readme.md) | the living README roster block | done |

Each file carries its own acceptance criteria, what actually landed, and — under
`## Plan note` — the summary line this plan used to hold before it was slimmed to
pointers.

## What this effort taught the design

Recorded in full in `DESIGN.md`; the short list of things that were *not* obvious
at the start:

- **Zero-diff is the acceptance test, not a nice-to-have.** It is what forces
  every emitted file to be classified exactly once, and every ambiguity in the
  split shows up as a diff.
- **"Never overwrite" is not "never create."** Found the moment a new content
  slot could not reach an existing workspace (`007`).
- **A flag that lies is worse than a missing flag.** `--no-status` printed
  "skipped" and installed the subsystem anyway for sixteen tasks (`018`).
- **Instructions are a token tax.** The `CLAUDE.md` block reached ~150 lines
  before it was cut to a 47-line kernel plus pointers (`014`).
- **A seeded-once file goes stale.** `README.md` described the workspace on the
  day it was stamped and never again, until it gained a generated block (`019`).
- **Machinery the user must re-run belongs *in* the artifact.** The hook
  installer and the README renderer live in the workspace, not the generator,
  because a second clone needs them and `update.sh` cannot reach that far
  (`016`, `019`).

## Follow-on work

Not part of this effort; see `DESIGN.md` §11 for the design-level gaps. The
obvious next effort is **dogfooding** — stamp a real workspace, migrate the
`cornjacket` repos into it, and retire `project-status`.
