---
name: revise
description: "Revise an existing spec based on feedback or correction"
model_tier: sonnet
workflow_stage: planning
---
# Framework: FORGE
Revise an existing spec based on validation feedback or a correction.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /revise — Apply a correction or change request to an existing spec.
  Usage: /revise <spec-number> <description of change>
  Arguments:
    spec-number (required) — the spec to revise
    description (required) — what needs to change and why
  Behavior:
    - Adds a dated revision entry to the spec
    - Updates spec body and tracking files (spec docs, README, CHANGELOG, backlog)
    - Does NOT edit implementation files — run /implement after to apply changes
    - If new requirements/ACs are added to an `implemented` spec, resets status to `approved`
    - Clarification-only edits (typos, wording) do not change status
  Use when: human validation found an issue, a correction is needed, or
    requirements within the spec's existing scope need updating.
  Not for: new scope or a different problem (create a new spec instead).
  See: docs/specs/README.md (governance), CLAUDE.md (spec lifecycle)
  ```
  Stop — do not execute any further steps.

---

1. Parse $ARGUMENTS to extract the spec number and the change description.
2. Read `docs/specs/NNN-*.md` for the given spec number.
3. Confirm the change is within the spec's existing scope:
   - If yes: proceed.
   - If no: stop and recommend creating a new spec instead. "This looks like new scope — use `/spec` to create a new spec."
4. State what will change: which sections of the spec body need updating.
5. Make the changes to **spec documents and tracking files only**:
   a. Update the spec body to reflect the corrected state.
   b. Add a dated revision entry: `YYYY-MM-DD: Revised — <description of change>.`
   c. Update `docs/specs/CHANGELOG.md`: `- YYYY-MM-DD: Spec NNN revised — <description>.`
   d. Do NOT edit implementation files (code, command `.md` files in `.claude/commands/`, config). Implementation of revised scope requires `/implement`.
6. **Status reset check** — determine if this revision adds new requirements or ACs:
   - If **new requirements/ACs added** AND spec is `implemented`: reset status to `approved`.
     a. Update `Status: approved` in the spec file.
     b. Update the spec's row in `docs/specs/README.md` to `approved`.
     c. Update the spec's row in `docs/backlog.md` to `approved`.
     d. Add a CHANGELOG entry noting the reset.
     e. Add a revision entry: `YYYY-MM-DD: Status reset to approved — new scope requires /implement.`
   - If **clarification only** (typos, wording, no new ACs): do not change status.
7. Report what was changed. If status was reset, remind: "Run `/implement NNN` to deliver the new scope." Otherwise, remind to run `/handoff NNN` then `/close NNN`.
