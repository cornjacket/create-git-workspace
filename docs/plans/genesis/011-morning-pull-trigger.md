# 011 — local morning pull trigger

Status: done (2026-08-02)

Bring the remote-generated aggregates down to the local workspace each morning.
The mirror of the remote push routine — closes the push-up / pull-down loop.

## Acceptance
- `.workspace/scripts/pull.sh` — `git pull --ff-only` on the workspace repo.
  - Fast-forward → advance silently.
  - Diverged → **notify and stop** (never force, never auto-merge/rebase).
  - Optional: chain `bootstrap.sh` to materialize any repo added remotely.
- Trigger wiring documented for cron / macOS launchd / Claude Code SessionStart
  hook (ship the script; let the user pick the trigger — PLAN Q9).

## Notes
- `--ff-only` is deliberate: safe for unattended runs. The dev keeps ff clean by
  pushing workspace edits (plans, repos.yml) before the remote routine runs.

## What landed
- `.workspace/scripts/pull.sh` + `make pull`. Fetches, then decides *before*
  touching anything: equal → say so; behind only → `merge --ff-only` and name
  which deliverables arrived; ahead or diverged → **notify and stop**.
- `--bootstrap` chains `bootstrap.sh`, materializing a repo you registered from
  another machine (it arrives as a registry entry with no checkout). Opt-in,
  because it clones.
- `--quiet` for unattended triggers; notifications go through `osascript` on
  macOS, `notify-send` on Linux, and **always** stderr so a cron log still has it.

### Three exit codes, because "declined" is not "broken"
| 0 | up to date or fast-forwarded |
| 1 | declined — ahead or diverged; the message names the fix |
| 2 | misconfigured — no origin, detached HEAD, unreachable remote |

A trigger that treats every non-zero as failure would nag daily about the
perfectly normal "you have unpushed work" state. Separating them lets the wiring
alert only on 2.

### Why it never resolves history
`--ff-only` is the whole design. This runs unattended, so it has exactly two
outcomes: advance cleanly, or stop and tell you. An unattended job that merges or
rebases is one that eventually destroys something at 6am while you are asleep.
The "ahead" case is called out separately from "diverged" because the fix
differs: push, versus reconcile by hand.

## Trigger wiring — documented, not chosen (PLAN Q9)
The emitted README carries all three with the trade-off named: **cron** (skips
the run entirely if the laptop was asleep at 08:00), **launchd** (runs it on
wake — the right default on a laptop), and a **Claude Code SessionStart hook**
(fires when you actually sit down, which matches the real trigger better than a
clock does).

## Verified — §8h (162 local / 171 with `--remote`)
Up-to-date exits 0; a routine-landed rollup fast-forwards and the script names
`summary.md` as arriving; being purely ahead exits 1 and prints the exact
`git push` to run; a diverged history exits 1, leaves local HEAD untouched, and
creates **no merge commit**; a workspace with no origin exits 2.

## Plan note

_Verbatim from the genesis `PLAN.md` task breakdown, kept here so the plan could be slimmed to pointers without losing it._

- [x] `011` — local morning trigger: `pull.sh` (ff-only, notify-on-decline) + wiring. *(three exit codes — 0 advanced, 1 declined, 2 misconfigured — so a trigger can alert on breakage without nagging about unpushed work.)*
