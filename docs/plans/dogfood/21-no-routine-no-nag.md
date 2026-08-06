# 21 — a workspace with no routine should not nag about routine registration

Status: **filed 2026-08-04**, hit immediately on `personal-workspace`.

`make status` reports `routine not registered` and exits non-zero for every repo
in a workspace that **has no scheduled routine at all**. There is no second
phase to complete, so the debt it reports does not exist.

## The concrete case

`personal-workspace` was created without a routine — deliberately: its repos are
personal content and are not wanted in a remote run. `config.yml` therefore has
`routine_url` commented out. Yet:

```
foa              standard  main  routine not registered
ymca-basketball  standard  main  routine not registered
make: *** [status] Error 1
```

Permanently red, for a step the owner has decided not to take. That is the
"gate with no honest exit" problem `05` already identified once — and `05`'s
answer was to create the routine. Here creating one is the wrong answer.

## Why this is workspace-level, not per-repo

The obvious patch is a per-repo opt-out field in `repos.yml`. **That is the
right idea for the wrong case.**

- The gate's question is *"did you finish the two-phase registration?"* Phase two
  is "add it to the routine's `sources`". **If there is no routine, there is no
  phase two** — for any repo, not for some. The fact is a property of the
  workspace, and it is already recorded: `config.yml: routine_url`.
- A per-repo field would put the same answer on every row, which is the tell
  that it belongs one level up.
- It would also store a **claim** in the lockfile. Task `20` documents exactly
  what that costs: `routine_registered: true` sat next to a `sources` list that
  did not contain the repo, and nothing noticed. Adding a second hand-set
  field with no way to verify it repeats the mistake.

## The fix

One function. `_status_lib.routine_pending()` is the single chokepoint every
projection reads — the `status` gate and the `daily-plan-summary.md` banner both
go through it, which is `10`'s "two projections, one field, recomputed every
run" paying off:

```python
def routine_pending(repos=None):
    # No routine means no phase two, so nothing can be outstanding. The gate
    # exists to catch a forgotten step, not to demand a routine exist.
    if not load_config().get("routine_url"):
        return []
    ...
```

Also needed:

- **`add-repo`'s printed nudge** must not tell you to add a repo to a routine
  that does not exist. Same condition.
- **`routine-registered` should refuse** (or warn loudly) when there is no
  `routine_url`, rather than writing `true` — a `true` with no routine is a lie
  in the lockfile, and the only currently available way to silence the gate.
- **`setup.sh` should say so**: a workspace generated without a routine is a
  supported state, not an unfinished one.

## What this does NOT cover, deliberately

A workspace that **does** have a routine, where **one** repo is deliberately
excluded from the remote run. That genuinely is per-repo, and it is what a
`repos.yml` field would be for. Not built, because:

- it has no user yet — `dev-workspace` wants every repo in its routine;
- and after task `20` it becomes checkable rather than declarable: `status`
  reads the real `sources`, so "absent, and that is declared fine" is a
  verified statement rather than a stored one.

File it when a real case appears. Guessing at the shape now would bake in the
declare-don't-verify pattern `20` is trying to remove.

## Acceptance

- ✅ A workspace with no `routine_url` reports no routine findings and `make
  status` exits zero on an otherwise clean floor.
- ✅ Adding a `routine_url` brings every outstanding repo straight back into
  view, because nothing is stored — same recompute property as `10`.
- ✅ `routine-registered` will not write `true` in a workspace with no routine.
- ✅ `personal-workspace` goes green without faking a flag.
- ✅ A test covers the no-routine workspace.

## What shipped — and the correction that changed the fix

**The estimate above said "one function". It was wrong, and the reason is the
interesting part.**

`10` describes the gate and the banner as "two projections of one field". In
code they were **two independent reads**: `aggregate-plans.py` asked
`routine_pending()`, while `status.py` re-derived the condition inline
(`repo["enabled"] and not repo["routine_registered"]`). Gating only
`routine_pending()` would have silenced the banner and left `make status` red —
the exact symptom being fixed. Two readers of one fact is how they drift, and
they had already drifted without anyone noticing, because until now the two
always agreed.

So the fix makes the chokepoint real before using it:

1. **`routine_configured()`** in `_status_lib` — reads `routine_url` from
   `config.yml`.
2. **`routine_pending()` returns `[]` when unconfigured.** No routine, no phase
   two, nothing outstanding — for every repo, which is what makes this
   workspace-level rather than a per-repo opt-out.
3. **`status.py` now routes through `routine_pending()`** instead of its own
   inline condition. One answer, asked once.
4. **`routine-registered` refuses** to write `true` with no routine, since that
   asserts membership of a `sources` list that does not exist. `--unset` is
   still allowed: clearing a flag claims nothing. This closes the only route to
   a green gate by falsehood.
5. **`add-repo` stops nudging** toward a routine that is not there.

**Deliberately not cached.** Restoring `routine_url` brings every outstanding
registration straight back, and there is a test for exactly that — the same
recompute property `10` chose, now load-bearing in a second place.

## Still open, deliberately

The **per-repo** exclusion — a routine exists, but one repo should stay out of
the remote run — is untouched. It is still waiting on `20`, after which the
question becomes checkable against live `sources` rather than declared in a
lockfile. Nothing in this change makes that harder.
