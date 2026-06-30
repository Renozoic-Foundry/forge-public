# Framework: FORGE
# Spec NNN - <Title>

- Status: draft
- Change-Lane: `hotfix` | `small-change` | `standard-feature` | `process-only`
- Priority-Score: <!-- BV=? E=? R=? SR=? → score=? (see docs/process-kit/scoring-rubric.md) -->
<!-- - Approved-SHA: (set automatically by /implement — do not edit manually) -->
- Trigger: <!-- error found in chat | error found in tests | user correction | agent recommendation | evolve loop review | harness failure | backlog promotion | other -->
<!-- - Dependencies: NNN, NNN  (spec IDs this spec depends on — omit or "—" if none) -->
<!-- - Consensus-Review: true | auto  (optional -- omit to skip consensus review)
     true: always run /consensus before /close
     auto: trigger consensus when ANY of these criteria are met:
       - spec is in sync manifest as public-facing
       - BV >= 4 with scope touching documentation or external interfaces
       - Change-Lane is standard-feature AND R >= 3
     omitted: no consensus review (default) -->
<!-- - Consensus-Close-SHA: <40-char hex>  (Spec 389 — written by /consensus on convergent close; consumed by /implement Step 0d) -->
<!-- - Consensus-Exempt: <reason ≥ 30 chars>  (Spec 395 — operator escape valve for /implement Step 0d final-draft consensus gate)
     For Lane B + BV ≥ 4 + R ≥ 3, value MUST include [reviewed-by: <second-operator-identity>] counter-sign token.
     For trivial-doc fast-path, format is: `trivial-doc — <30+ char justification>` AND Change-Lane MUST be small-change. -->
<!-- - Consensus-Status: vet-pending  (Spec 395 — backfill marker; advisory in /now and /matrix; does not block /implement) -->
<!-- - Provisional-Until: YYYY-MM-DD  (Spec 395 — sunset review trigger; /now surfaces a reminder starting D-7) -->
- Owner: operator
- Author: <name>
- Reviewer: operator
- Approver: operator
- Implementation owner: <name>
- Last updated: YYYY-MM-DD
- valid-until: YYYY-MM-DD  <!-- Spec 363 — draft validity window. Set by /spec at creation as today + forge.spec.draft_validity_days (default 90). Refreshed by /revise. /now reports a count when past today. -->
<!-- Lane B optional fields — remove if not applicable -->
<!-- - Supersedes: NNN  (successor spec: set when this spec replaces a sealed Lane B spec) -->
<!-- - Lane-B-Sealed: YYYY-MM-DD  (set by /close in Lane B projects — do not edit manually) -->

## Contents

- [Objective](#objective) — problem and desired outcome
- [Scope](#scope) — in/out boundaries
- [Requirements](#requirements) — what must be built
- [Acceptance Criteria](#acceptance-criteria) — pass/fail checklist
- [Constraints](#constraints) — what must NOT happen
- [Test Plan](#test-plan) — verification approach
- [Implementation Summary](#implementation-summary) — changed files
- [Evidence](#evidence) — gate results and test output
- [Revision Log](#revision-log) — change history

## Objective

<What problem this solves and desired outcome>

## Scope

In scope:
- <item>

Out of scope:
- <item>

## Requirements

1. <requirement>

## Acceptance Criteria

1. <verifiable outcome>

## Constraints
<!-- Optional — remove this section if no negative constraints apply.
     Negative acceptance criteria: what the implementation must NOT do.
     Example: "This implementation must NOT introduce new CLI flags, configuration options,
     or abstractions beyond what is required to satisfy the ACs above."
     Evaluated by the Stage 1 spec compliance reviewer at /close. -->

## Verification Scope
<!-- Optional — helps reviewers understand what evidence gates do and do not cover.
     Recommended for specs involving security, data integrity, or behavioral correctness.
     The DA gate (domain 1) will prompt for this section when reviewing such specs. -->

<!-- Uncomment and fill in:
(a) What the ACs verify: <what the acceptance criteria and test plan actually check>
(b) What the ACs do NOT verify: <gaps in coverage — things the spec assumes but does not test>
(c) Residual risks after evidence gates pass: <risks that remain even if all gates PASS>
-->

## Test Plan

1. <test>

### Cross-platform coverage
<!-- Detection: active (Spec 171 — /implement Step 4b auto-scans .sh files and prompts for PowerShell coverage) -->
<!-- If this spec modifies .sh scripts, include PowerShell equivalents below. Advisory — not a blocking gate. -->
- bash: `<bash test command>`
- PowerShell: `<equivalent PowerShell command>`

## Compatibility / Deprecation Notes

- <contract/schema/CLI compatibility notes, or "none">

## ADR References

- <path or "none">

## Implementation Summary

- Changed files:
  - `<path>`

<!-- Spec 471 convention: if Changed files ship inactive-by-default functionality
  (e.g. settings.json hook blocks, opt-in features that stay off until an operator
  turns them on), add one entry to `.forge/capabilities.yaml` (+ template mirror) so
  the capability surfaces at /now and activates one-touch via /configure → Capabilities.
  Without a registry entry the feature is undiscoverable except by reading docs/diffing
  files — the exact gap Spec 471 closes. -->

<!-- Spec 444 convention: if Changed files includes `copier.yml` AND the
  change adds a new `validator:`, `_tasks:` entry, or `secret: true` token,
  the spec MUST also extend `template/.forge/lib/stoke/gates.py` so
  `/forge stoke` can mediate the new gate in chat. `/close` enforces this
  mechanically (Step 2d++++ — Gate-mediation drift gate). To opt out,
  add `Gate-Mediation-Exempt: <≥30-char rationale>` to the frontmatter. -->

<!-- ## Safety Enforcement (Spec 387 — optional)
  Required if /close prompts "Does this introduce a safety property?" with a YES answer.
  All three lines must be present and resolvable:
  Enforcement code path: <file>::<symbol>
  Negative-path test: <file>::<test-name>
  Validates <prose, ≥10 chars> describing what unsafe condition is rejected.

  Deferred-enforcement form (R3) — pair with `# UNENFORCED — see Spec NNN` annotation
  in the affected config file:
  Enforcement code path: <file>::<placeholder>
  Negative-path test: <file>::<deferred to Spec NNN>
  Validates <prose>.

  See template/docs/process-kit/safety-property-gate-guide.md.

  This section is excluded from the Approved-SHA hash input (R2f) — code-path corrections
  via /revise do not trigger Spec 365 recompute. -->

<!-- Spec 387 — Safety-Override frontmatter convention (optional)
  Add to frontmatter (above) when the diff matched the registry but you assert the change
  is not a safety property:
  - Safety-Override: <reason text, ≥50 chars, non-trivial — see safety-property-gate-guide.md>
  Frequent overrides (>2/quarter) trigger a /evolve warning. -->

## Reproduction Commands

Commands needed to reproduce the verified state from scratch:

```bash
# Example — replace with actual commands
pytest -q tests/test_<module>.py
```

Human validation steps: see [human-validation-runbook.md](../process-kit/human-validation-runbook.md) sections: <list sections, e.g. A, C>

## Shadow Validation

<!-- Optional — remove this section if the spec is purely additive (new feature, new file, new command).
     Use when the spec REPLACES existing behavior and you need confidence the replacement is equivalent.
     See docs/process-kit/shadow-validation-guide.md for when to use each strategy.
     See docs/process-kit/shadow-validation-checklist.md for step-by-step execution. -->

<!-- LANE B NOTE: If this project has a compliance profile (docs/compliance/profile.yaml),
     shadow validation is a BLOCKING gate at /close for specs that declare a strategy.
     Lane B requires: complete evidence, tolerance threshold compliance, AND reviewer sign-off.
     Lane A projects: shadow validation remains advisory (non-blocking warning at /close). -->

<!-- Uncomment ONE strategy and fill in:
**Strategy**: reference-comparison | dual-run | test-oracle-replay
**Reference**: <what the new implementation is compared against>
**Inputs**: <test inputs or production data sample>
**Expected**: <what matching outputs look like>
**Evidence**: <path to diff/comparison output, or "pending">
-->

<!-- Lane B only — uncomment and fill in after shadow validation execution:
**Actual**: <actual results observed>
**Divergence analysis**: <explanation of any differences, or "none — exact match">
**Pass/Fail**: PASS | FAIL
**Reviewer sign-off**: <reviewer name> confirmed shadow validation evidence on <date>.
-->

## Delta (optional -- for canonical product spec updates)

<!-- If this spec changes the canonical product spec, declare deltas here.
     At /close, these markers are applied to the canonical spec.
     Leave markers commented out if not applicable. -->
<!-- ADDED: <section> -- <new requirement text> -->
<!-- MODIFIED: <section>/<REQ-ID> -- <updated text> -->
<!-- REMOVED: <section>/<REQ-ID> -- <reason> -->

## Evidence

- Tests/lint/output summary:
  - <evidence>

## Traceability Links

<!-- Lane B only — remove this section for Lane A projects -->
<!-- Populate after implementation; used by /trace to generate compliance matrix -->
<!--
requirements:
  - REQ-001: <requirement text or external standard reference (e.g. "IEC 62443-3-3 SR 2.1")>
code:
  - src/path/to/file.py::function_name
tests:
  - tests/test_file.py::test_function_name
evidence:
  - tmp/evidence/SPEC-NNN-YYYYMMDD/test-run.txt
-->

## Revision Log

- YYYY-MM-DD: <revision summary>
