# vendor/

Third-party generator machinery copied in verbatim, so a fresh clone of
`create-git-workspace` can stamp a fully task-tracked workspace with nothing
external to fetch. Self-containment over DRY — the cookiecutter trade.

## `create-project-system/`

Installs the Markdown task-system into a target repo. `setup.sh` runs it against
every new workspace (`--tasks-dir project/tasks --with-skill --with-status`)
unless `--no-tasks`; `update.sh` re-runs it to upgrade the installed machinery.

| | |
|---|---|
| **Source** | `github.com/cornjacket/create-project-system` |
| **Vendored at** | `v0.1.0-2-gaa757cf` (`aa757cfd492f5181d0940c7a6e6bbeb38ba81549`) |
| **Vendored on** | 2026-08-01 |
| **What is copied** | `generate.sh` + `src/` — nothing else |

### Why only those two

The upstream repo is *itself* a tracked repo: it carries `daily-plan.md`,
`.claude/hooks/`, `.github/`, `tests/`, `tasks/`, and an `ai-project-status`
CLAUDE.md block. None of that is generator machinery — it is upstream's own
project-status instrumentation. The vendored copy *installs* task-systems; it is
not a tracked repo itself, so it carries no instrumentation. Copying it in would
mean a workspace's generator directory pretending to be a project.

### Boundary — what this does NOT provide

`create-project-system` injects a **task-capture** kernel (`task-system:begin`)
and installs `tasks/`. The **commit-telemetry** kernel (`ai-project-status:begin`),
daily-plan discipline, and aggregation belong to this repo's status subsystem
(project-status lineage). The two CLAUDE.md blocks are distinct and do not
overlap. Likewise `project/status/` (hand-written narrative reports for
status-review meetings) is *not* the top-level `summary.md` (the automated git
telemetry rollup).

### Re-vendoring

```bash
./tools/revendor.sh                 # from a sibling ../create-project-system
./tools/revendor.sh /path/to/repo   # or an explicit checkout
```

It refuses a dirty source checkout, replaces `generate.sh` + `src/` wholesale,
and rewrites the stamp above. Review the diff, run `./tests/run-tests.sh`, and
commit. A vendored copy can lag upstream; that is the accepted cost.
