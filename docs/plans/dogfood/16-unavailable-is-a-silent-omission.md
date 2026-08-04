# 16 — an UNAVAILABLE repo vanishes from the rollup

Status: **filed 2026-08-04**, confirmed in production on the first run after
`create-ai-builder` was registered. Not yet fixed.

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

## Why the checkout was unreadable

Not yet confirmed, and worth separating from the defect above — the omission is
a bug **whatever** the cause. The likely cause is that
`/home/user/create-ai-builder` did not exist on that run: the `sources` edit was
made by hand shortly before, and the platform pre-clone list may be snapshotted
per run rather than read live. If so, a newly registered repo is expected to
miss exactly one run — which is fine, and is precisely the kind of thing the
rollup must *say* rather than swallow.

Check on the next run before doing anything else: if the repo appears, the cause
was propagation and only the reporting needs fixing.

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

- A repo that is registered but unreadable appears in `summary.md` by name,
  with a cause, on every run where that is true.
- The line is not suppressible by `report_inactivity: false`.
- A test asserts it: a registered repo with no resolvable checkout produces a
  rollup containing its name. That test is the actual deliverable — the current
  code passes every existing test while losing a repo.
- `DESIGN.md` §5.2 gains this as a worked example, since the principle was
  already written down and the code still violated it.
