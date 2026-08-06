# 16 — an UNAVAILABLE repo vanishes from the rollup

Status: **FIXED 2026-08-06.** 369 assertions; dogfooded into both workspaces.
See "What shipped" at the bottom.

A repo whose checkout cannot be read in the sandbox is dropped from `summary.md`
with **no trace in the deliverable** — only a `stderr` warning, which on a
scheduled remote run goes to a log nobody opens.

## The defect

`.workspace/scripts/run.py`:

```python
if e["status"] == "UNAVAILABLE":
    print(f"[run] WARNING: {e['name']} has no readable checkout; skipping",
          file=sys.stderr)
    continue
```

`continue` skips it into neither `drafts` nor `inactive_entries`. So the repo is
in `repos.yml`, is enabled, is registered in the routine — and appears nowhere
in the file the run commits. The workspace looks like it covered everything.

This is the **§5.2 silent-omission failure** the design names and forbids. §12
predicted it, but scoped the prediction to *worktree* entries ("the
silent-omission failure of §5.2, permanently, by construction"). The prediction
was right and the scope was too narrow: it is general to any entry whose
checkout does not resolve remotely.

## How it showed up

`create-ai-builder` was registered at 07:36 UTC and its `routine_registered`
flag cleared at 07:43. The routine ran at **12:44 UTC**, five hours later, and
its rollup (`699236a`) contains:

- `create-project-system` — a section
- `create-git-workspace` — a section
- `captains-log` — a "No updates" line
- `create-ai-builder` — **nothing at all**

`state.json` gained no key for it either. The tell that this is the
UNAVAILABLE path and not an empty commit window: an empty window produces a
"No updates" line, which is a *statement*; this produced silence.

The giveaway that the two halves disagree: `daily-plan-summary.md` **does**
list `create-ai-builder` (its P2 row and its whole imported plan). That
aggregator reads the workspace's own `daily-plans/` directory locally, while
the rollup reads git history from the platform's pre-clone. One saw the repo
and the other did not, and only the one that did not is silent about it.

## Why the checkout was unreadable — CONFIRMED

Read the live routine config (`RemoteTrigger get trig_01TA28JDCMTd8Em8sceLpxEC`).
**`sources` holds exactly four repos**: `dev-workspace`, `captains-log`,
`create-project-system`, `create-git-workspace`. Neither `create-ai-builder` nor
`second-brain-devkit` is there, and `updated_at` (07:10:35Z) **predates both
registrations**. No propagation lag, no platform behaviour to explain: the two
`sources` edits never saved.

So `/home/user/create-ai-builder` was never created, `prebuilt_source_path`
returned `None`, and the fallback could not save it (below). The manual seam
§8.5 tracks is real, and this is the first time it has silently failed *open*.

**The local fallback is dead code on the remote run.** `repo_dir()` falls back to
`WORKSPACE_ROOT / repo["path"]`, but the workspace's allowlist `.gitignore`
excludes every child, so a sandbox checkout of the workspace contains no children
at all. The pre-clone is a single point of failure with no backup, by
construction. Worth stating in the fix.

**There was a report — it just landed where nobody looks.** The routine's prompt
already ends with: *"Also report any repo the run named as UNAVAILABLE or
unreadable: that means it is registered in `.workspace/repos.yml` but missing
from this routine's `sources`."* That report goes into the routine's session
transcript in the app. The deliverable the run commits — the only artifact anyone
reads — stayed silent. Two channels, and the instrumented one is the one nobody
opens. That is the whole bug in one sentence, and it is why the fix has to put
the fact in `summary.md` rather than anywhere else.

**Correction to a claim made earlier in this effort:** the routine config *is*
readable from a session, via the `RemoteTrigger` tool (`CronList` only sees
session-created crons, which is what led to the wrong conclusion). `05` and `14`
both describe editing `sources` as a hand-only step in the Claude app — it is
not, and a verb that reconciles `sources` against `repos.yml` is now clearly
buildable. That would remove the manual seam entirely rather than tracking it.

## The fix

An UNAVAILABLE repo is **reported, not skipped**. It has its own line in
`summary.md`, in the same class as "No updates" — a repo that is tracked and
was not read is a fact the reader needs, and it is a different fact from "this
repo did nothing".

Sketch: give `render_inactives_block` a sibling, or extend it, so the run emits

```
### Not read this run
- create-ai-builder — no readable checkout (registered in `sources`?)
```

Two things to get right:

- **It must be actionable.** "No readable checkout" without the likely cause
  sends the reader to the wrong place. The overwhelmingly likely cause is the
  `sources` pre-clone, which is the manual seam §8.5 already tracks.
- **It must not be suppressible by `report_inactivity: false`.** That flag opts
  a repo out of the *quiet-day* list, which is a statement about the repo's
  activity. Being unreadable is a statement about the *run*, and silencing it
  would rebuild this bug behind a config field.

## Wider question this raises

`status --all` and the rollup now disagree about what is on the floor, and
neither is wrong on its own terms. Worth checking during the fix whether any
other `continue` in the run drops an entry without a deliverable-visible trace —
this one was found by accident, on the one day someone happened to read the
rollup closely.

## Acceptance

- ✅ A repo that is registered but unreadable appears in `summary.md` by name,
  with a cause, on every run where that is true.
- ✅ The line is not suppressible by `report_inactivity: false`.
- ✅ A test asserts it — seven of them.

## What shipped

`### Not read this run`, a block alongside `### No updates`, naming each repo
and pointing at the likely cause (the routine's `sources` pre-clone list), and
closing with "these repos are tracked but were not summarized, so this rollup
does not cover them."

Three things the implementation forced that the filing had not anticipated:

1. **The quiet-day path would have swallowed it anyway.** A day with no new
   commits re-uses the previous section's whole body (task `11`), so a freshly
   unreadable repo would have vanished exactly on the days it was most likely
   to go unnoticed. The carried body is now stripped of any stale notice and
   the current one appended — so it always describes *this* run, and re-running
   never stacks duplicates. There is a test for each half.
2. **Order in the dispatch loop is load-bearing.** `UNAVAILABLE` is now checked
   *above* `INACTIVE_SUPPRESSED`. The two statuses happen to be mutually
   exclusive today, but relying on that would have left the "not suppressible"
   guarantee resting on an accident.
3. **The notice has to clear itself.** A repo that becomes readable drops out
   with no further action — asserted, because a warning that outlives its cause
   is how people learn to ignore warnings.

## Still open

`DESIGN.md` §5.2 does not yet carry this as a worked example. The principle was
already written there and the code violated it for weeks, which is the strongest
possible argument for the example — deferred to the graduation pass.
