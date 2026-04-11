# Framework: FORGE
# DEPRECATED (Spec 131): /harvest is replaced by /note [signal].
# Replacement: Run /note [signal] <description> to capture mid-session signals.
# This command still executes for backward compatibility but will be removed in a future release.

Mid-session signal extraction. Scans conversation for uncaptured decisions, errors, insights, and corrections.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /harvest — Mid-session signal extraction (FORGE signal capture).
  Usage: /harvest
  Arguments: none
  Behavior:
    - Scans current conversation for uncaptured signals
    - Identifies decisions, errors, insights, corrections, and user feedback
    - Presents draft signal entries for confirmation
    - Appends confirmed entries to docs/sessions/signals.md
    - Complementary to /retro (which is spec-scoped); /harvest is session-scoped
  See: AGENTS.md (Signal Capture)
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Scan conversation
Mine the current conversation for uncaptured signals. Look for:

### Errors (type: `error`)
- Tool call failures, retries, workarounds
- Test failures that required debugging
- Unexpected behavior in code or process
- EA-002 pattern (Edit tool requires prior Read) recurrences

### Insights (type: `insight`)
- "Aha" moments about the codebase or architecture
- Patterns discovered that should inform future work
- User knowledge shared about the domain or project context

### Decisions (type: `decision`)
- Architecture or design choices made during conversation
- Trade-offs discussed and resolved
- Scope decisions (what was included/excluded and why)

### Corrections (type: `feedback`)
- User corrections to agent approach
- "No, instead do..." or "Don't..." guidance
- Preference changes or clarifications

## [mechanical] Step 2 — Deduplicate
Read `docs/sessions/signals.md`. Check if any draft signals duplicate existing entries. Remove duplicates.

## [decision] Step 3 — Present drafts
Present draft signal entries:

```
SIG-NNN | <type> | <one-line summary>
Details: <2-3 sentences>
Action: <spec trigger | process update | memory save | none>
```

Ask: "Confirm these signals, edit, or skip any?"

## [mechanical] Step 4 — Persist
Append confirmed entries to `docs/sessions/signals.md`.

For `feedback` type signals: also save to auto-memory (`feedback` type) so behavior persists across conversations.

For signals with `Action: spec trigger`: add to `docs/sessions/scratchpad.md` for next `/close` or `/session` review.

## [mechanical] Step 5 — Report and next action
Report: "Harvest complete. N signals captured. N added to scratchpad for spec triggers."

Present a context-aware next action:
- If spec triggers were added to scratchpad: "Next: run `/spec <description>` to create specs for triggered items, or continue current work — they'll surface at the next `/close` or `/session`."
- If feedback signals were captured: "Next: continue current work. Feedback has been saved to memory for future conversations."
- Otherwise: "Next: continue current work, or run `/now` to check project state."
