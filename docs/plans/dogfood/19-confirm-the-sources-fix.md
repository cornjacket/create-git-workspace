# 19 — confirm the `sources` fix on the 2026-08-05 run

Status: **prediction recorded 2026-08-04, awaiting the 12:43 UTC run.**

A one-shot verification with the expected outcome **written down before the
run**, so tomorrow is a test rather than a look. Two repos were missing from the
routine's pre-clone list; that is now fixed, and the run is the only thing that
can prove it.

## What was wrong, and what changed

- `create-ai-builder` and `second-brain-devkit` were registered in `repos.yml`
  and had `routine_registered: true`, but neither was in the routine's `sources`.
  Both by-hand edits had silently failed to save — confirmed by reading the live
  config, whose `updated_at` predated both registrations.
- `sources` went 4 → 6 on 2026-08-04 at 19:38 UTC, via `RemoteTrigger update`
  with the **entire** job config resent. Prompt, cron, model, allowed tools and
  MCP connections are byte-identical; only `sources` changed.
- Nothing about task `16`'s reporting bug was touched. That is deliberate — the
  two questions are separable and this run separates them.

## Prediction

Written in advance. If the run disagrees with this, the disagreement is the
finding.

1. **`summary.md` names all five member repos.** `create-ai-builder` and
   `second-brain-devkit` each get either a section or a "No updates" line. Both
   have real commits from 08-04, so sections are the more likely shape.
2. **Their first window is `EMPTY_TREE..HEAD`**, so each section covers the
   repo's entire history rather than one day. Expected, not a bug — `06` saw the
   same thing on `captains-log` and it is what motivated `11`. Do not "fix" it.
3. **`state.json` gains a key for each**, which is the durable proof the run
   actually read them; the rollup text alone could in principle come from
   anywhere.
4. **No repo is UNAVAILABLE**, so task `16`'s bug does not fire this run and
   stays unproven-but-known. It is still real; this run simply cannot exercise
   it.

## How to check

```
cd <workspace> && make pull
python3 -c "import json;print(sorted(json.load(open('.workspace/state/state.json'))))"
grep -n '^### ' summary.md
```

Expect five keys and every member named in `summary.md`.

## Reading the result

| outcome | means |
|---|---|
| both appear | the `sources` fix worked; the seam was the only cause |
| both still missing | the update did not take either — escalate to the platform, not the code |
| exactly one appears | something repo-specific; `create-ai-builder` is the suspect, since its entry name and its checkout path differ (`create-ai-builder` vs `create-ai-builder/main`) and only the **name** is used remotely |

That third row is the one worth watching. It is the only outstanding doubt about
`12`'s decision to name the entry after the repo, and this run tests it for free.

## Then what

- **On success:** close this, and let it be the evidence that `16`'s fix should
  be built — a bug that only shows when someone forgets a manual step is exactly
  the bug that will recur, since the manual step has now failed twice.
- **The deeper fix is `20`:** `sources` should not be hand-edited at all.
  `RemoteTrigger` makes it writable from a session, so a verb can reconcile the
  routine's `sources` against `repos.yml` — which deletes the seam rather than
  tracking it, and would have made this whole failure impossible.
