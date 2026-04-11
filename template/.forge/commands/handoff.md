---
name: handoff
description: "DEPRECATED — Display human validation steps for completed work"
model_tier: sonnet
workflow_stage: review
deprecated: true
---

# Framework: FORGE
# DEPRECATED (Spec 131): /handoff is absorbed by /now "review" option.
# Replacement: Run /now — select "review NNN" from the validation queue.
# This command still executes for backward compatibility but will be removed in a future release.

Display the human validation steps for the work just completed.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /handoff — Display full validation steps for context switch or session end.
  Usage: /handoff [spec-number]
  Arguments: spec-number (optional) — inferred from session context if omitted.
  Behavior: Like /close but prints FULL Quick Check lists (not abbreviated),
    reviews scratchpad, and prints a Handoff Summary block.
  See: docs/process-kit/human-validation-runbook.md, docs/process-kit/context-anchoring-guide.md
  ```
  Stop — do not execute any further steps.

---

This is the handoff variant of `/close` — use this when switching context, ending a session, or handing off to another person or agent.

1. Infer the most recently implemented spec from the session log or ask if ambiguous.
2. Read the spec's Test Plan and Acceptance Criteria sections.
3. Read docs/process-kit/human-validation-runbook.md.
4. Identify which sections apply (same trigger logic as `/close`):
   <!-- customize: add project-specific section triggers below -->
   - Code was changed → section A
   - Primary output changed → section B
   - Harness was run → section C
   - Spec was created/updated → section D
   - Spec just moved to `implemented` → section F (evolve loop trigger)
   - Always → section G
5. Print the **full** Quick Check list for each applicable section (not abbreviated).
6. For each item, state exactly which file to open and what to look for in VS Code UI terms.
6b. **Review Brief output (Spec 160)**: After the Quick Check list, generate a Review Brief using the format from `docs/process-kit/gate-categories.md`:
   - Categorize each validation item as machine-verifiable, human-judgment-required, or confidence-gated.
   - Present in the three-section Review Brief format: Machine-Verified, Needs Your Review, Machine-Handled.
   - If the spec scope involves physical-world recommendations, include a Physical Logic Check in "Needs Your Review".
   - Prioritize "Needs Your Review" items: irreversible actions first, LOW confidence second, physical logic third, UX fourth, rest fifth.
   - This Review Brief is informational for handoff context — no enforcement mode applies (handoff is not a gate transition).
7. Check `docs/sessions/context-snapshot.md` for open scratchpad note count; if snapshot is missing or stale, read `docs/sessions/scratchpad.md` directly. List all unresolved items.
8. **Visual Evidence Package (Spec 093)**: Check for browser test evidence at `tmp/evidence/SPEC-NNN-browser-*/manifest.json`. If found:
   a. Read the most recent manifest.
   b. Present the visual evidence package:
      ```
      ## Visual Evidence Package — Spec NNN
      Evidence dir: <path>
      Results: <passed>/<total> UI checks passed

      ### Screenshot Review
      For each step in the manifest, present:
      | Step | Action | Expected | Actual | Status | Screenshot |
      |------|--------|----------|--------|--------|------------|
      | 1    | <desc> | <expected> | <actual> | PASS/FAIL | <path> |
      ...

      ### Video Recording
      <path to video if captured, or "No video recorded">

      ### Human Observation Checklist
      For each step, present a confirmation checkbox:
      - [ ] Step 1: Confirm <expected outcome> is visible in screenshot
      - [ ] Step 2: Confirm <expected outcome> is visible in screenshot
      ...
      ```
   c. If no evidence found, skip this section silently (spec has no UI components).

9. Print a "Handoff Summary" block (use snapshot for "Next recommended spec" if available; otherwise read `docs/backlog.md`):
   ```
   ## Handoff Summary
   Spec: NNN — <title>
   Status: <implemented / in-progress>
   Validation required: <sections A/B/C/D/F/G that apply>
   Open scratchpad notes: <count>
   Next recommended spec: <top-ranked approved or draft spec from backlog>
   ```
10. Remind me to update the `Last evolve loop review:` field in today's session log if this spec is now `implemented`.
11. Remind: run `/close NNN` to confirm and transition to `closed`, or `/revise NNN` if changes are needed.
