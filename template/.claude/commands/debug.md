---
name: debug
description: "Structured debugging session — hypothesis-first, verify before fixing"
workflow_stage: implementation
---
# Framework: FORGE
Structured debugging session — hypothesis-first, verify before fixing. Usage: /debug [defect description]

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /debug — Systematic debugging session (Spec 525; pattern ported FORGE-native).
  Usage: /debug [defect description]
  Flow: reproduce → hypothesize → instrument → verify root cause → fix → capture.
  Hard rule: NO fix is proposed or applied before the root cause is VERIFIED by
  direct observation. Closes by offering a pre-filled /note [bug] so the insight
  lands in FORGE's signal pipeline instead of vanishing into chat.
  Invocation-only: /debug adds no hooks and no always-on surface.
  ```
  Stop — do not execute any further steps.

---

## Goal

Find the **verified** root cause of the defect described in $ARGUMENTS (or elicited
from the operator if absent), then fix it. The failure mode this skill exists to
prevent: pattern-matching a symptom to a familiar cause and "fixing" the wrong thing —
a signal that resembles a known failure may have a different cause.

**The one hard rule: no fix before a verified root cause.** Instrumentation and
observation come first; the fix is the LAST edit of the session, never the first.

## Flow

1. **Reproduce** — establish the failing behavior with a concrete command or input
   the operator can re-run. If it cannot be reproduced, say so and stop — do not fix
   what cannot be observed. A disposable reproduction fixture belongs in the session
   scratch/temp directory, never in tracked FORGE process files.
2. **Hypothesize** — list the candidate causes (ranked, most likely first), each with
   the observation that would confirm or kill it. State what evidence each hypothesis
   predicts.
3. **Instrument** — add observation only (logging, a probe, a minimal test, a
   bisect), never behavior changes. Run the reproduction against the instrumentation.
4. **Verify** — the root cause is verified only when the observed evidence matches
   one hypothesis's prediction AND contradicts the alternatives. Say explicitly:
   "Root cause verified: <cause> — evidence: <observation>." If evidence kills every
   hypothesis, return to step 2 with what was learned; do not guess-fix.
5. **Fix** — the minimal change that removes the verified cause. Remove the
   instrumentation. Re-run the reproduction to show the defect is gone and the
   fix's blast radius is clean (nearby tests still pass).
6. **Capture** — offer the operator a pre-filled signal, matching /note's real
   `[bug]` contract (a description string + severity prompt — Step 3b of note.md):
   ```
   /note [bug] <symptom> — root cause: <verified cause>; evidence: <observation>; fix: <one-line summary>
   ```
   If the debugging session happened inside an active /implement, remind that the
   defect and its root cause belong in the spec's Evidence section too.

## Constraints

- The fix edit is gated by FORGE's normal rules: inside an active `/implement`, the
  fix must be within the active spec's scope; outside one, the edit-gate applies and
  the answer may be "this needs a spec first" — say so rather than editing.
- Instrumentation added in step 3 MUST be removed (or explicitly promoted with the
  operator's agreement) before the session ends.
- This skill is advisory workflow structure, not a gate — it never blocks other
  commands, and it activates only when invoked.
