# Framework: FORGE
# DEPRECATED (Spec 131): /bug is replaced by /note [bug].
# Replacement: Run /note [bug] <description> — prompts for severity and routes automatically.
# This command still executes for backward compatibility but will be removed in a future release.

Structured bug report with severity and routing.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /bug — Structured bug report (FORGE signal capture).
  Usage: /bug <description>
  Arguments: description (required) — short summary of the bug.
  Behavior:
    - Creates a structured bug report with severity, observed/expected, repro steps
    - Routes to existing spec or flags "new spec needed"
    - Appends to docs/sessions/signals.md
    - Adds to scratchpad if spec trigger needed
  See: AGENTS.md (Signal Capture)
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Capture
Get the bug description from $ARGUMENTS or ask if not provided.

## [decision] Step 2 — Classify and detail
Build the bug report interactively:

```
### BUG-NNN: <summary>

- **Severity**: critical | high | medium | low
  - critical: data loss, crash, security vulnerability
  - high: feature broken, incorrect output, blocks workflow
  - medium: degraded behavior, workaround exists
  - low: cosmetic, minor inconvenience
- **Observed**: <what actually happens>
- **Expected**: <what should happen>
- **Repro steps**:
  1. <step>
- **Routing**: Spec NNN (if existing spec covers this) | "new spec needed"
- **Related files**: <file paths if known>
```

Present the draft and ask: "Confirm this bug report, or edit?"

## [mechanical] Step 3 — Persist
Read `docs/sessions/signals.md`. Append the confirmed bug entry as type `bug`.

## [mechanical] Step 4 — Route
- If routing = existing spec: add a `/note` to scratchpad tagged `[validate]` referencing the spec.
- If routing = "new spec needed": add a `/note` to scratchpad tagged `[session]` with the bug summary and "needs spec".

## [mechanical] Step 5 — Report and next action
Report: "Bug BUG-NNN filed. Severity: <level>. Routed to: <spec NNN | scratchpad for new spec>."

Present a context-aware next action:
- If severity is `critical` or `high`: "Next: run `/spec <bug summary>` to create a hotfix spec immediately."
- If routed to an existing spec: "Next: run `/revise NNN` to add the bug to the spec's scope, or continue current work."
- If routed to scratchpad: "Next: continue current work. The bug will surface at the next `/close` or `/session`."
