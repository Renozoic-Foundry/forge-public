---
name: revise
description: "Revise an existing spec based on feedback or correction"
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
  Note: when revising a draft spec, /revise refreshes `valid-until:` to today
        + forge.spec.draft_validity_days (default 90) — explicit operator
        engagement is the renewal signal (Spec 363).
  See: docs/specs/README.md (governance), CLAUDE.md (spec lifecycle)
  ```
  Stop — do not execute any further steps.

---

1. Parse $ARGUMENTS to extract the spec number and the change description.
2. Read `docs/specs/NNN-*.md` for the given spec number.
2b. **Lane B sealed check (Spec 052)**: If the spec has `Lane-B-Sealed:` in its frontmatter:
   - Stop and report: "Spec NNN is sealed (Lane B). Sealed specs cannot be revised — they are frozen audit records. To change this spec's requirements, create a successor spec with `Supersedes: NNN` in its frontmatter. Run `/spec <description>` and add `Supersedes: NNN` to the new spec's header."
   - Do NOT modify the sealed spec file in any way.
   - If this is a Lane A project (`docs/compliance/profile.yaml` absent): skip this check — Lane A specs can always be revised.
### [mechanical] Step 2c — Approved-SHA clear (Spec 089, lane-gated by Spec 344)

When revising a spec that carries an `Approved-SHA:` field in frontmatter, the field is no longer valid against the revised text and must be cleared so the next `/implement` can rewrite it.

# >>> spec-344 lane-gate
LANE-GATE: Spec 089 Approved-SHA mechanism is Lane B only. Read these conditions in order:

1. **Read `Change-Lane:` from the spec's frontmatter.** Possible values: `hotfix`, `small-change`, `standard-feature`, `process-only`, `Lane-B`, missing, or unrecognized.

2. **Read `docs/compliance/profile.yaml`.** If the file is absent: this is a Lane A FORGE-internal project — skip Spec 089's behavior for this Step entirely. No SHA computed, no `Approved-SHA:` written or verified or cleared, no `GATE [spec-integrity]` line, no override prompt. Proceed silently to the next Step.

3. **If `docs/compliance/profile.yaml` is present:** the project declares Lane B usage. Now apply the predicate:
   - If `Change-Lane:` is `Lane-B`: PROCEED with Spec 089's existing behavior verbatim. Compute/verify/clear the SHA per the existing logic.
   - If `Change-Lane:` is `hotfix`, `small-change`, `standard-feature`, or `process-only`: SKIP Spec 089's behavior. No GATE line, no prompt. Proceed silently.
   - If `Change-Lane:` is missing or any other value (e.g., a typo like `Lane_B`): STOP. Do not proceed. Emit `GATE [spec-integrity]: FAIL — Change-Lane missing or unrecognized ('<value>') under a Lane B compliance profile. Set Change-Lane explicitly before proceeding.` HALT. Do not invoke the SHA logic. Do not transition status. Do not proceed to subsequent steps.

This block is load-bearing prose — Claude reads it as instructions and follows the predicate. The fail-closed branch ("STOP. Do not proceed.") is imperative; do not soften the phrasing.

See: docs/process-kit/close-validator-coverage.md § Lane-gate sentinel — canonical source.
# <<< spec-344 lane-gate

If the gate proceeds (Lane B project, `Change-Lane: Lane-B`): remove the `Approved-SHA:` line from the spec's frontmatter and append a Revision Log entry: `YYYY-MM-DD: Approved-SHA cleared by /revise — pending re-write at next /implement.`

If the gate skips (Lane A): no action — the spec doesn't carry an `Approved-SHA:` field.

If the gate halts (fail-closed): operator must set `Change-Lane:` explicitly before /revise can complete.


3. Confirm the change is within the spec's existing scope:
   - If yes: proceed.
   - If no: stop and recommend creating a new spec instead. "This looks like new scope — use `/spec` to create a new spec."
4. State what will change: which sections of the spec body need updating.
5. Make the changes to **spec documents and tracking files only**:
   a. Update the spec body to reflect the corrected state.
   b. Add a dated revision entry: `YYYY-MM-DD: Revised — <description of change>.`
   c. Update `docs/specs/CHANGELOG.md`: `- YYYY-MM-DD: Spec NNN revised — <description>.`
   d. Do NOT edit implementation files (code, command `.md` files in `.claude/commands/`, config). Implementation of revised scope requires `/implement`.
   e. **Refresh `valid-until:` (Spec 363)**: If the spec's `Status:` is `draft`, rewrite the spec's `valid-until:` field to `today + forge.spec.draft_validity_days` (default 90 if the AGENTS.md key is absent). The pre-existing value is replaced, not preserved. If the spec lacks `valid-until:` entirely (pre-backfill state or non-draft status), add it now using the same formula. If `Status:` is anything other than `draft`, skip this sub-step silently — `valid-until:` is a draft-only concern.
   f. **Score-Audit predicted record on score change (Spec 368)**: If this revision modifies any of BV / E / R / SR / TC, append a new `predicted` record to the score-audit log via the shared helper. Do NOT inline JSON here.

      The helper exposes a `next-revise-round` subcommand that derives the next round from the audit log:

      ```bash
      next_round=$(bash .forge/lib/score-audit.sh next-revise-round "$spec_id")
      bash .forge/lib/score-audit.sh record-predicted "$spec_id" "$bv" "$e" "$r" "$sr" "$tc" "$lane" "$kind_tag" "$next_round"
      ```

      (PowerShell parity: invoke `pwsh .forge/lib/score-audit.ps1 record-predicted ...` with the same arguments.)

      If none of BV/E/R/SR/TC changed in this revision, do NOT call `record-predicted` — the audit log only records score-change events. The helper is advisory; failures emit a WARN to stderr but never block `/revise`.

      See: [docs/process-kit/score-calibration-loop.md](../../docs/process-kit/score-calibration-loop.md).
6. **Lane B impact analysis** — if `docs/compliance/profile.yaml` exists (Lane B project):
   a. Read the compliance profile to identify active risk categories (e.g. safety, security, privacy, reliability).
   b. Assess each risk category against the revised spec content:
      - `safety`: changes to safety functions, fail-safe behavior, or critical constraints
      - `security`: changes to authentication, authorization, data handling, or trust boundaries
      - `privacy`: changes to PII handling, data retention, or consent flows
      - `reliability`: changes to SLAs, fault tolerance, or recovery procedures
   c. Identify impacted traceability links: requirements, tests, and evidence items that reference the revised spec sections (cross-reference `/trace` output for the spec).
   d. Determine re-verification triggers: list any gates that must be re-run based on affected risk categories per profile rules.
   e. Classify overall impact: `minor` (no gates triggered) / `moderate` (1–2 non-safety gates) / `major` (3+ gates, or safety/security affected).
   f. Generate impact report `docs/impact-reports/YYYY-MM-DD-NNN-impact.md`:
      ```
      # Impact Report — Spec NNN revision YYYY-MM-DD
      Spec: NNN — <title>
      Change: <description of change>
      Classification: minor | moderate | major

      ## Risk Categories Assessed
      | Category | Affected | Notes |
      |----------|----------|-------|
      | safety   | yes/no   | <why> |
      ...

      ## Impacted Traceability Links
      - <requirement/test/evidence item> → <why affected>

      ## Re-verification Requirements
      - Gates to re-run: <list>
      - Evidence to refresh: <list>
      ```
   - If `docs/compliance/profile.yaml` is absent, skip this step (Lane A project).

7. **Status reset check** — determine if this revision adds new requirements or ACs:
   - If **new requirements/ACs added** AND spec is `implemented`: reset status to `approved`.
     a. Update `Status: approved` in the spec file.
     b. Update the spec's row in `docs/specs/README.md` to `approved`.
     c. Update the spec's row in `docs/backlog.md` to `approved`.
     d. Add a CHANGELOG entry noting the reset.
     e. Add a revision entry: `YYYY-MM-DD: Status reset to approved — new scope requires /implement.`
   - If **clarification only** (typos, wording, no new ACs): do not change status.
8. Report what was changed. If status was reset, remind: "Run `/implement NNN` to deliver the new scope." Otherwise, remind to run `/close NNN`. If a Lane B impact report was generated, include the impact classification and any re-verification requirements in the report.
