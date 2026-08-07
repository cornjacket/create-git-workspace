# 20 — `sources` should be a verb, not a manual seam

Status: **reader half DONE 2026-08-07**; writer half still open. Filed
2026-08-04. Supersedes half of `10`.

## What landed (2026-08-07)

`.workspace/scripts/routine-sync.py --check` — the gate now asks the routine
instead of believing a flag. 394 assertions green; dogfooded into
`dev-workspace` via `update.sh` and run against the live routine.

- **Transport is `claude -p`,** which reaches `RemoteTrigger` exactly as `run.py`
  already shells out for summaries. Two alternatives were rejected: `curl` with a
  token scraped from the macOS keychain (macOS-only, while the sandbox is Linux,
  and it breaks on rotation — the tool's contract says use it *instead of* curl),
  and letting the model perform the diff (a reconcile a model does is a reconcile
  nobody can test). The model is a dumb pipe; every comparison is Python.
- **Three exit codes, and the third is the point.** `0` verified-clean, `1`
  verified-drifted, `2` could-not-verify. A missing `sources` key raises rather
  than reading as an empty list, and an unrecognized payload refuses rather than
  reporting all repos drifted.
- **The verdict outranks the flag in both directions,** via `routine_pending()`
  so the gate and the banner cannot disagree. Proven in production the same day:
  `create-context-hygiene` had been reading `routine not registered` from a stale
  flag, and the verified check cleared it.
- **Cached with a 12h TTL** in `.workspace/state/routine-check.json`, always
  re-taken on `--all`. Gitignored — writing it into the tracked tree made `make
  status` report the workspace dirty for having been run, found by the suite.
- **`make routine-check` now verifies**; the old flag reporter moved to `make
  routine-flags`.
- **`normalize_remote` moved into `_status_lib`.** `repos.yml` mixes `git@…` with
  `https://….git` while the routine stores bare https, so an un-normalized
  comparison reports every repo as drifted. Two copies of "are these the same
  repo?" is the drift this check exists to catch.
- **`DESIGN.md` §8.5 carries the correction** — the `CronList`-vs-`RemoteTrigger`
  false premise, and the flag's demotion to offline fallback.

Two things the suite caught that review would not have:

- Three assertions passed against a fixture whose repos had **no checkouts**, so
  the routine column could not render at all and the phrase they searched for
  could never appear —
  [[tests-that-cannot-fail]]'s "observer goes blind", written first-hand.
- A fixture repo named `off` parsed as boolean `False` in YAML.

## Still open — the writer

Resending a reconciled config. This is the dangerous half and is deliberately
not built: `RemoteTrigger update` is a **partial** update, so every field left
out is dropped, and the job config carries the run prompt, the model, and the
allowed-tools list. Land it behind a **round-trip verification** — send, re-`get`,
assert the returned config matches what was intended, fail loudly otherwise —
which converts a silent field-drop into an error. Until then `sources` is still
edited by hand; the difference is that drifting from `repos.yml` is now caught
within 12 hours instead of never.

---


**The four steps below were run by hand on 2026-08-07** to register
`create-context-hygiene`, against the live routine
(`trig_01TA28JDCMTd8Em8sceLpxEC`): read `routine_url` from `config.yml`,
`RemoteTrigger get`, diff the returned `sources` against `repos.yml`, resend the
**entire** `job_config` with the eighth repo appended. It worked, and the
response confirmed the prompt, model and `allowed_tools` all survived the write.

So the design below is no longer a proposal — it is a transcript. Two things
that only became clear by doing it:

- **The API takes a partial update and the guide forbids using it.**
  `RemoteTrigger update` is documented as a partial update, which is exactly the
  trap §5.2 warns about. Whatever is built must send the whole config
  unconditionally; the safe path is not the default path.
- **This was the third hand-edit of this seam.** Each one has been correct and
  each has cost a full read-modify-write of a config carrying the run prompt.
  The risk is not effort, it is that one of these eventually drops a field and
  the failure is silent until a run behaves oddly.

The routine's `sources` pre-clone list must mirror `repos.yml`. Today that
mirroring is done by hand, tracked by a flag, and enforced by a gate. It can
just be *done*.

## Why this is now buildable, when it was not before

`DESIGN.md` §8.5 files this as one of the "two manual seams", on the stated
grounds that editing the routine is a step only a human can take in the Claude
app. **That premise is false**, and this effort believed it for two weeks:

- The `RemoteTrigger` tool reads and writes the routine config from a session
  (`list` / `get` / `update` / `run`).
- The wrong conclusion came from checking `CronList`, which only lists crons
  created *in the current session* and therefore cannot see a cloud routine.
  One tool answered "no" for a different question and the answer was
  generalized.

Both `05` and `14` document the hand-edit as the only path. Both are wrong and
should be corrected when this lands.

## What it should do

A verb — `make routine-sync`, or folded into `add-repo` — that:

1. reads the routine id from `config.yml` (`routine_url` is already there),
2. `RemoteTrigger get`s the current job config,
3. computes the set difference against enabled `repos.yml` entries,
4. resends the **entire** config with `sources` reconciled.

Constraints that fall straight out of what went wrong:

- **Whole config, never a partial merge.** The failure mode is dropping the
  fields you omit — the prompt, the model, the allowed-tools list. `05` and
  `14` both already say this; now something enforces it.
- **Re-runnable, like every other membership verb** (§10 #16). Reconcile,
  report a zero-diff run honestly, never refuse.
- **Read-only mode.** `--check` for `make status` to call, so the gate verifies
  the *actual* remote state instead of a flag asserting it.

## What it does to task 10

`10`'s `routine_registered` flag exists because the step was un-automatable, and
its whole design — absent-means-outstanding, a `status` gate, a
`daily-plan-summary.md` banner, a dedicated writer verb — is scaffolding around
a fact that could not be checked. **If the fact becomes checkable, the flag
becomes a cache of it, and a cache that can go stale is worse than no cache.**

The evidence is this effort's own failure: the flag said `true` for
`create-ai-builder` while `sources` did not contain it. It was not lying — it
faithfully recorded that a human said they had done it. That is exactly the
weakness of storing a claim instead of verifying a state.

So the honest end state is probably: **delete the flag, keep the gate**, and
have `status` ask the routine. Worth deciding deliberately rather than
accreting — `10` was good work against the constraint it was given, and the
constraint moved.

## Open questions

- **Does `status` want a network call?** It is currently local and fast, and
  `--check` on every invocation would change that. Perhaps the gate calls it
  only in `--all`, or caches with an explicit staleness window.
- **Where does the routine id live for a fresh clone?** `config.yml` has
  `routine_url`; a bootstrap on a new machine needs the id parsed from it, or
  stored properly.
- **What about a workspace with no routine yet?** The verb must no-op cleanly
  rather than fail, or `setup.sh --with-hook` gets a hard dependency on a
  routine existing first.

## Acceptance

- A verb reconciles the routine's `sources` against `repos.yml` and is
  re-runnable with a zero-diff no-op.
- Resending drops no field of the job config; a test proves the prompt and
  allowed-tools survive a reconcile.
- `make status` verifies the real `sources`, not a stored claim.
- `DESIGN.md` §8.5 loses this seam, and the `CronList`-vs-`RemoteTrigger`
  correction is recorded so the false premise cannot return.
