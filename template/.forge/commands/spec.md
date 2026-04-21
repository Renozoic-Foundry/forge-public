---
name: spec
description: "Create a new spec from the template"
model_tier: sonnet
workflow_stage: planning
---
# Framework: FORGE
# Model-Tier: sonnet
Create a new spec from the template.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /spec — Create a new spec from the template.
  Usage: /spec [description] [--from-explore <topic>]
  Arguments:
    description (optional) — 1–2 sentence change description. If omitted, infer from session context or ask.
    --from-explore <topic>  Pre-populate from docs/research/explore-<topic>.md
  Behavior:
    - Produces a valid FORGE spec in draft status, scored and indexed.
  After saving: review the draft and run /implement, or request edits via /revise.
  See: docs/specs/_template.md, docs/process-kit/scoring-rubric.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 0a — Evolve Loop Boundary Check (Spec 191)
Read `docs/sessions/context-snapshot.md`. If a `## Active evolve loop` section exists with `status: in-progress`:
- Stop and report: "Evolve loop in progress (started <started>). Solve-loop commands (/implement, /spec, /close) are blocked until the evolve loop completes. Return to the /evolve session and use the exit gate to choose your next action."
- Do NOT proceed with spec creation.
If the section is absent or `status: complete`: proceed normally.

## [mechanical] Step 0b — Pre-populate from explore artifact (Spec 197)
If `--from-explore <topic>` is in $ARGUMENTS:
  1. Read `docs/research/explore-<topic>.md`. If the file does not exist, warn: "Explore artifact not found: docs/research/explore-<topic>.md. Proceeding with normal spec creation." and skip to Step 1.
  2. Pre-populate spec sections from the explore artifact:
     - **Objective**: derive from the explore artifact's Question/Hypothesis section
     - **Scope**: derive from the explore artifact's Findings section
     - Add a `## Prior Research` note in the spec: "Based on research in `docs/research/explore-<topic>.md`."
  3. Continue to Step 1 with pre-populated content (the operator can still edit before saving).

---

## [mechanical] Identity Resolution (Spec 133)

Before populating frontmatter, resolve the operator identity:

1. Read `docs/sessions/context-snapshot.md` — look for `## Session identity` section. If found, use the name stored there.
2. If not found: read `.copier-answers.yml` — look for `default_owner`. If found, use that value.
3. If not found: use literal "operator".

Set frontmatter fields:
- **Owner**: resolved identity from above
- **Reviewer**: resolved identity from above
- **Approver**: resolved identity from above
- **Author**: "Claude" (when the AI agent creates the spec). If a human is writing the spec interactively without AI, Author is their session identity.
- **Implementation owner**: leave as `<name>` — set at implementation time by the implementing agent/human.

**NEVER infer, guess, or hallucinate a personal name.** If no identity source is available at any step, use "operator".

---

## [mechanical] Step 0c — `--guided` flag gate (Spec 282)

If $ARGUMENTS contains `--guided`: evaluate whether Spec Kit is configured for this project (AGENTS.md has `spec_kit.enabled: true` AND Spec Kit MCP tools are available in the active tool list).

- If both conditions hold: proceed silently to the addendum section at the end of this file.
- If either condition fails: print exactly this one-line notice, then continue with Step 1 below:

  > `--guided` flag ignored: Spec Kit is not configured for this project. Running standard `/spec` flow. See docs/process-kit/spec-kit-setup.md to enable guided creation.

If $ARGUMENTS does not contain `--guided`: continue with Step 1 below.

---

1. Get the change description from $ARGUMENTS, current session context, or ask if neither is available.
   Determine the trigger: error found in chat | error found in tests | user correction | agent recommendation | evolve loop review | harness failure | backlog promotion | other.

1b. **Authorization scope check (Spec 165)**: If the description or spec title names a new command file (e.g., a new `/push-release`, `/deploy-all`, or similar slash command): prompt — "Does this command name imply modification of external/shared systems? If so, declare explicit scope limits in the opening line of the command file."

2. Read docs/specs/README.md to find the next available spec number.
3. Select template based on lane:
   - If Change-Lane is `process-only` or `small-change`: read `docs/specs/_template-light.md`.
   - Otherwise: read `docs/specs/_template.md`.
4. Read docs/process-kit/scoring-rubric.md and score the new spec.
   **Input validation (Spec 148)**: Validate that each BV, E, R, SR value is an integer between 1 and 5 inclusive. If any value is outside this range, STOP and report the error: "[dimension] must be 1-5 (got [value])". Do not compute the score with invalid inputs.
5. **Estimate Token Cost (TC)**: Based on the spec's scope, estimate the TC advisory indicator:
   - Count files in the Implementation Summary / scope → 1-5 = `$`, 5-15 = `$$`, 15+ = `$$$`
   - Check verification type → unit test = `$`, integration = `$$`, manual/browser/E2E = `$$$`
   - Check SR score → SR ≥ 4 = `$`, SR = 3 = `$$`, SR ≤ 2 = `$$$`
   - TC = highest applicable indicator (e.g., 3 files but manual verification → `$$`)
   - If `.forge/metrics/command-costs.yaml` exists, check for historical cost data on similar specs to calibrate.
6. Write the spec file at `docs/specs/NNN-<slug>.md` by filling in the template:
   - Set `Status: draft`
   - Set `Change-Lane:` based on the description (infer; ask only if genuinely ambiguous)
   - Set `Trigger:` in the frontmatter
   - Set `Token-Cost: $|$$|$$$` in the frontmatter (from step 5)
   - Fill in all sections: Objective, Scope, Requirements, Acceptance Criteria, Test Plan
   - Set `Priority-Score:` in frontmatter with the scored values
   - Leave Evidence and Reproduction Commands as placeholders

---

## [mechanical] Step 6b — Review Router (Spec 159)

After the spec draft is written but before presenting to the operator for final approval, run the review router:

a. **Select perspectives** based on spec characteristics (select 2-3, cap at 3):

| Spec Characteristic | Perspectives Selected |
|---------------------|----------------------|
| Any spec draft | DA (always) |
| Scope touches auth/security/external APIs, MCP servers, `.mcp.json`, or external dependencies | +CISO |
| Scope touches commands/onboarding/UX | +CXO |
| `BV >= 4` and `E >= 3` | +CFO (high investment), +CTO (architectural risk) |
| `Token-Cost: $$` or `$$$` | +CFO |
| Lane B OR `R >= 3` OR `E >= 3` (testability window at spec-approval, Spec 304) | +CQO |
| Lane B project | +CCO (always — compliance is non-negotiable) |
| Scope touches physical/real-world logic | +DA, note: "Includes physical/practical logic — flag for human validation" |
| `Change-Lane: hotfix` | DA only — speed matters, skip additional perspectives (this rule overrides all others) |

   When multiple rules match, union the selected roles and cap at 3 (prioritize by rule specificity — more specific rules win; the `Change-Lane: hotfix` rule always wins when it applies).

b. **Display selection rationale** (one line per role):
   ```
   Review Router: Selected DA (always), CISO (scope touches auth)
   ```

c. **Allow override**: Operator can add/remove perspectives with `+role` or `-role` syntax before the review runs (e.g., "add CTO" or "-CISO"). If no override within 5 seconds of interactive prompt, proceed with selected roles.

d. **Run selected perspectives**: For each selected role, read its instruction template from `.claude/agents/<role>.md`. Apply the role's key questions to the spec draft. Produce the structured review output (3-5 sentences, recommendation, confidence, key concern).

e. **Present consolidated Review Brief**:
   ```
   ## Perspectives — Spec NNN
   **DA**: [assessment] — Recommendation: PROCEED | Confidence: HIGH | Key concern: none
   **CISO**: [assessment] — Recommendation: REVISE | Confidence: MEDIUM | Key concern: [concern]
   ```

f. If any perspective recommends BLOCK, flag the spec but do NOT auto-block — the operator decides. BLOCK is advisory.

---

### [mechanical] Step 6c — Acceptance Criteria Vague-Language Scan (Spec 171)

After the spec draft is written, scan each acceptance criterion in the `## Acceptance Criteria` section for vague-language patterns: "should", "consider", "might", "may", "approximately", "reasonable", "could", "as needed".

If any acceptance criterion contains one of these patterns:
a. Present a choice block:
   ```
   Vague acceptance criteria found — the following criteria contain language that is hard to test:
   - Criterion N: "<text>" — matched pattern: "<pattern>"
   ...
   Vague acceptance criteria reduce testability and may cause disagreement at the validation gate.
   ```
   > **Choose** — type a number or keyword:
   > | # | Action | What happens |
   > |---|--------|--------------|
   > | **1** | `rewrite` | Revise each vague criterion before saving |
   > | **2** | `skip` | Save as-is — skip recorded in revision log |
b. If `rewrite`: for each flagged criterion, prompt for a replacement. Rewrite in the draft before saving.
c. If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Acceptance criteria vague-language scan: skipped.`

If no vague language detected: proceed silently.

**Meta-rule (Spec 171)**: New checklist items added to any FORGE command file must include a `Detection:` annotation — values: `active | passive-acceptable | N/A`. If `passive-acceptable`, include a one-line explanation why active detection is not feasible.

---

## [mechanical] Steps 7–10

7. Update docs/specs/README.md — add a row for the new spec (sorted by number).
8. Update docs/specs/CHANGELOG.md — add an entry for the new spec.
9. Update docs/backlog.md — insert at the correct rank based on score.
10. Report: "Spec NNN saved. Review and run `/implement NNN`, or `/revise NNN <edits>`."

---

## Addendum: Guided Flow (Spec Kit)

Only execute this section if AGENTS.md contains `spec_kit.enabled: true` AND Spec Kit MCP tools are available in the active tool list AND `--manual` is NOT in $ARGUMENTS. Otherwise, do not read further.

If `--guided` is in $ARGUMENTS but `spec_kit.enabled` is false or MCP tools are unavailable: print "Spec Kit is not configured for this project. Enable `spec_kit.enabled: true` in AGENTS.md and add the MCP server to .mcp.json, then retry with --guided." and stop.

If `spec_kit.enabled: true` but MCP tools are unavailable: check `spec_kit.fallback` (default: `manual`). If `manual`: print "Spec Kit MCP server unavailable. Falling back to main flow. Add Spec Kit MCP to .mcp.json (see AGENTS.md)." and return to the main flow (Step 1). If `error`: print "Spec Kit MCP server unavailable and fallback=error. Add server to .mcp.json or set fallback: manual." and stop.

### [decision] Step A — Run speckit.specify

Run the `speckit.specify` tool with the change description from $ARGUMENTS (or ask for it if not provided).
Allow Spec Kit to conduct its requirements elicitation interview.

### [mechanical] Step B — Run speckit.plan

Run `speckit.plan` using the output from Step A to generate a structured plan with objectives and scope.

### [mechanical] Step C — Run speckit.tasks

Run `speckit.tasks` using the plan output to generate a task breakdown.

### [mechanical] Step D — Map to FORGE template

Map Spec Kit's output to FORGE spec template sections:

| Spec Kit output | FORGE spec section |
|----------------|-------------------|
| Requirements / user stories | `## Requirements` |
| Plan objectives | `## Objective` |
| Plan scope / out-of-scope | `## Scope` |
| Acceptance tests / done criteria | `## Acceptance Criteria` |
| Task breakdown | `## Test Plan` (adapt to test steps) |

Fill any unmapped sections (Change-Lane, Trigger, Priority-Score, Evidence) using standard FORGE logic.

### [mechanical] Step E — Score and write

Read `docs/process-kit/scoring-rubric.md` and score the spec.
**Input validation (Spec 148)**: Validate that each BV, E, R, SR value is an integer between 1 and 5 inclusive. If any value is outside this range, STOP and report the error: "[dimension] must be 1-5 (got [value])". Do not compute the score with invalid inputs.
Read `docs/specs/README.md` for the next spec number.
Write the spec file at `docs/specs/NNN-<slug>.md` with:
- Status: `draft`
- All sections populated from Spec Kit mapping + FORGE defaults
- `Trigger: spec-kit-guided`

### [mechanical] Step F — Finalize via main flow

After Step E, return to the main flow at Step 6b (Review Router) and continue through Steps 7-10 (index, changelog, backlog, report). When reporting completion in Step 10, append: "Created via Spec Kit guided flow."
