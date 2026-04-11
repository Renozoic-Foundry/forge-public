# Framework: FORGE
# DEPRECATED (Spec 131): /retro functionality is now inline in /close.
# Replacement: Signal capture runs automatically as part of /close chain.
# This command still executes for backward compatibility but will be removed in a future release.

Structured retrospective with three signal categories. Auto-chained by `/close`; also callable standalone.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /retro — Structured retrospective (FORGE signal capture).
  Usage: /retro [spec-number]
  Arguments: spec-number (optional) — scope the retro to a specific spec.
  Behavior:
    - Mines conversation for signals in three categories: content, process, architecture
    - Presents draft signal entries for confirmation
    - Appends confirmed entries to docs/sessions/signals.md
    - Usually auto-chained by /close; can be run standalone mid-session
  Signal types: retro-content, retro-process, retro-architecture
  See: AGENTS.md (Signal Capture)
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Scope
Identify the spec number from $ARGUMENTS (if provided) or use "session-wide" scope.

## [mechanical] Step 2 — Mine conversation
Scan the conversation for signals in three categories:

### Content signals (what worked/didn't in the deliverable)
- Did the implementation match the spec's intent?
- Were any ACs harder than expected? Easier?
- Did the deliverable quality meet expectations?
- Any gaps between spec and reality?

### Process signals (what worked/didn't in the workflow)
- Were there errors that required retries? (EA-NNN candidates)
- Did any user correction change the approach? (feedback signal)
- Was the spec well-written enough to implement without ambiguity?
- Did the change lane and ceremony level feel right?

### Architecture signals (design insights for future work)
- Did any insight emerge about the codebase design?
- Were there unexpected dependencies or coupling?
- Should future specs account for something discovered here?
- Any patterns worth reusing or anti-patterns to avoid?

## [decision] Step 3 — Present drafts
Present draft signal entries in this format:

```
SIG-NNN | <type> | <one-line summary>
Details: <2-3 sentences>
Action: <spec trigger | process update | note for future | none>
```

Types: `retro-content`, `retro-process`, `retro-architecture`

Ask: "Confirm these signals, edit, or skip any?"

## [mechanical] Step 4 — Persist
Read `docs/sessions/signals.md`. Append confirmed entries. Use the next available SIG-NNN number.

## [mechanical] Step 5 — Report
Report: "Retro complete. N signals captured (N content, N process, N architecture). Appended to signals.md."

## [mechanical] Next action
Present a context-aware next action:
- If any signal has `Action: spec trigger`: "Next: run `/spec <description>` to create a spec for the triggered item."
- If this retro was standalone (not auto-chained by `/close`): "Next: run `/close NNN` to finalize the spec, or `/implement next` to continue building."
- If auto-chained by `/close`: skip (the `/close` command handles its own next action).
