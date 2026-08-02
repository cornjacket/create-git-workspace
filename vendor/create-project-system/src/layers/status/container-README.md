# Project

Persistent project-management workspace — the authoritative record of what is
being built, what was decided, and what happened, across both human and AI
sessions.

## Structure

```
{{CONTAINER_REL}}/
    {{TASKS_BASE}}/    # task management — what needs to be done
    status/    # periodic status reports — what shipped, where things stand
```

## {{TASKS_BASE}}/

The task management system. All work is tracked here before it begins,
organized by epic and status folder (inbox, draft, backlog, in-progress,
complete, wont-do). Managed via the scripts in `{{TASKS_REL}}/scripts/`.

Full documentation: `{{TASKS_REL}}/docs/USING.md`.

## status/

Periodic **delta** status reports — a narrative synthesis of what shipped
since the previous report, not a daily log. Read the most recent one to pick
up where the last session left off. See `{{STATUS_REL}}/README.md`.
