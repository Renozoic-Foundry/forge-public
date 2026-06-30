# Lane B Gates for /close

These steps only apply when `docs/compliance/profile.yaml` exists (Lane B project).
Lane A projects skip all steps in this file.

## [mechanical] Step 2b — Lane B compliance gate check (conditional)

If `docs/compliance/profile.yaml` exists (Lane B project):
a. Load the profile `gate_rules` list.
b. For each gate rule with `required: true`, check that the required evidence artifacts are present in `docs/` (paths specified in `evidence_required`):
   - Evidence present → `GATE [lane-b/<gate-name>]: PASS — <evidence artifact> found.`
   - Evidence missing and `required: true` → `GATE [lane-b/<gate-name>]: FAIL — missing: <evidence artifact>. Remediation: generate required evidence before closing.` (blocking — stop if any Lane B gate FAILs)
   - Evidence missing and `required: false` → `GATE [lane-b/<gate-name>]: CONDITIONAL_PASS — advisory gate: <evidence artifact> missing. Non-blocking.`
c. Check `docs/compliance/profile-verification.md` for valid sign-off:
   - Sign-off present and not expired → `GATE [lane-b/profile-verification]: PASS — sign-off valid until <expiry>.`
   - Sign-off missing or expired → `GATE [lane-b/profile-verification]: FAIL — profile verification sign-off missing or expired. Remediation: update docs/compliance/profile-verification.md.` (blocking)

## [mechanical] Step 2c — Lane B spec sealing (Spec 052)

After completing the status transition to `closed`, if Lane B:
a. Add `Lane-B-Sealed: YYYY-MM-DD` to the spec's frontmatter (after `Last updated:`).
b. Add a revision entry: `YYYY-MM-DD: Spec sealed (Lane B) — content is now an immutable audit record. Future changes require a successor spec with Supersedes: NNN.`
c. Report: "Spec NNN sealed (Lane B). The spec file is now an immutable audit record."
- This step runs AFTER Step 3 (status transition), not before.

## [mechanical] Step 3b — V&V report generation (Spec 039)

If Lane B:
a. Aggregate evidence for the V&V report from the spec file:
   - Gate outcomes: collect all `GATE [*]: PASS|FAIL|CONDITIONAL_PASS` entries from the spec's Evidence section and from steps 2b/2c above.
   - Test evidence: collect test outputs from spec's Evidence section and `tmp/evidence/SPEC-NNN-*/`.
   - Traceability links: read the spec's "Traceability Links" section.
   - Compliance gate evidence: collect from step 2b gate check results.
   - Acceptance criteria: read spec's Acceptance Criteria section, cross-reference with Evidence.
b. Generate V&V report: create `docs/compliance/reports/YYYY-MM-DD-NNN-vv.md` from `docs/compliance/reports/_template.md`, filling in:
   - All metadata fields (spec number, title, revision, profile framework, close date)
   - Gate outcomes table (all gates from this spec's lifecycle)
   - Test evidence table
   - Traceability matrix excerpt
   - Compliance gate evidence table (profile gate_rules vs evidence found)
   - AC verification table
   - Disclaimer header (required — do not remove)
c. Emit: `GATE [vv-report]: PASS — V&V report generated at docs/compliance/reports/YYYY-MM-DD-NNN-vv.md`
   - If any required gate has no evidence: emit `GATE [vv-report]: CONDITIONAL_PASS — V&V report generated but missing evidence for: <gates>. Remediation: fill in missing evidence before submitting to certification authority.`
