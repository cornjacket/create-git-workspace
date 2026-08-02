# Oracle Operator Guide — Task Management

This guide covers the judgment rules for driving the pipeline: how to size
tasks, how to respond to TESTER failures, and when to decompose further.
The mechanical workflow (scripts, folder conventions, status transitions) is
in `CLAUDE.md`.

---

## Task granularity rules

A top-level task should be completable in a single
ARCHITECT → IMPLEMENTOR → TESTER pipeline run (roughly one focused session).

**Split a task when IMPLEMENTOR would:**
- Touch more than ~5 unrelated files, or
- Implement more than ~3 independent concerns

**A subtask should be a single, verifiable action** — e.g. "write function X",
"add migration Y", "update config Z". Not a phase or theme.

When in doubt, smaller is better. Tasks can always be consolidated; unclear
scope causes pipeline failures.

---

## When to break a task down further

Break a task into subtasks (or split into multiple tasks) when:
- The ARCHITECT cannot produce a coherent design without first resolving an
  unknown (e.g. "what format does the API return?")
- The IMPLEMENTOR would need to make a structural decision that should be
  reviewed before proceeding
- Two parts of the task are independently testable and have no shared state

Proceed as a single task when:
- All inputs and outputs are known
- The IMPLEMENTOR can work linearly through the subtasks without branching
- The TESTER can verify the whole task in one pass

---

## TESTER failure decision rules

| Failure type | Action |
|---|---|
| Bug in code just written | Create a new subtask in the current task for the fix; do not widen scope |
| Requirement misunderstood | Update the task description; restart the ARCHITECT for this task |
| Systemic issue (missing dependency, wrong environment) | Create a new blocking task; pause current task until resolved |
| Flaky test or environment noise | Retry the TESTER once; if it fails again, treat as a real failure |
