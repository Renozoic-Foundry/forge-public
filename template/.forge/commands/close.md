
# Framework: FORGE
# Model-Tier: sonnet
<!-- multi-block mode: serialized — choice blocks fire across distinct mechanical steps; no two blocks present in the same agent message. Each block waits for operator response before the next step proceeds. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->

**Output verbosity (Spec 225)**: At the start of execution, read `forge.output.verbosity` from `AGENTS.md` (default: `lean`). In **lean** mode, suppress non-actionable diagnostic output (passing-gate confirmations, KPI tables, calibration deltas, MCP pin status, deprecation scans, signal-by-signal pattern dumps, root-cause groupings, deferred-scope aging when none aged, score-rubric details when unchanged) — write the full content to its file artifact (session log, `pattern-analysis.md`, etc.) and emit a one-line pointer in chat (or omit entirely if purely informational). In **verbose** mode, emit full detail as before. **Never suppressed in either mode**: choice blocks, FAILed gates, push-confirmation prompts, Review Brief "Needs Your Review" items, operator-input prompts, error/abort messages. See `docs/process-kit/output-verbosity-guide.md` for the full rules and worked examples.

Close a spec: confirm human validation, capture signals, update priorities.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /close — Close a spec. FORGE lifecycle terminal state.
  Usage: /close [spec-number]
  Arguments: spec-number (optional) — inferred from session context if omitted.
  Behavior:
    - Confirms the spec is at `implemented` status
    - Transitions to `closed` (spec file, README, backlog, CHANGELOG)
    - Reviews "Out of scope" items for disposition (promote/backlog/drop)
    - Auto-chains: signal capture → /matrix (priority re-scoring)
    - Pauses at deferred scope review and "pick next" decision points
    - Auto-commits and pushes outstanding changes
  See: AGENTS.md (Evidence Gates), docs/process-kit/human-validation-runbook.md
  ```
  Stop — do not execute any further steps.

---

**Gate Outcome Format**: Read `.forge/templates/gate-outcome-format.md` and emit the structured format at every evidence gate.

---

## [mechanical] Step 0a — Evolve Loop Boundary Check (Spec 191)
Read `docs/sessions/context-snapshot.md`. If a `## Active evolve loop` section exists with `status: in-progress`:
- Stop and report: "Evolve loop in progress (started <started>). Solve-loop commands (/implement, /spec, /close) are blocked until the evolve loop completes. Return to the /evolve session and use the exit gate to choose your next action."
- Do NOT proceed with close.
If the section is absent or `status: complete`: proceed normally.

## [mechanical] Step 0c — Checkpoint resume detection (Spec 123)

After identifying the spec (Step 1), check for an existing checkpoint file at `.forge/checkpoint/close-<spec-id>.json`:

1. If the file **exists**: read it and display:
   ```
   ⚡ CHECKPOINT DETECTED — /close <spec-id>
   Last completed step: <step_number> — <step_description>
   Timestamp: <timestamp>
   Completed outputs: <summary>

   Resume from step <next_step>? (yes to resume, no to start fresh)
   ```
   - On `yes`: skip to the step after `last_completed_step`. All outputs from prior steps are in the checkpoint — do not re-execute them.
   - On `no`: delete the checkpoint file and start from Step 2.
2. If the file **does not exist**: proceed normally from Step 2.

**Checkpoint write rule**: After each major step (2, 3, 4, 5, 6, 7, 8), write/update `.forge/checkpoint/close-<spec-id>.json`:
```json
{
  "spec_id": "<spec-id>",
  "command": "close",
  "last_completed_step": <N>,
  "step_description": "<description>",
  "timestamp": "<ISO 8601>",
  "outputs": { "<step_N>": "<summary of what was produced>" }
}
```

**Checkpoint cleanup**: After Step 9 completes successfully, delete `.forge/checkpoint/close-<spec-id>.json`.

## [mechanical] Step 1 — Identify spec
Identify the spec number from $ARGUMENTS or infer from session context.

## [mechanical] Step 1b — Determine enforcement mode (Spec 160)

After identifying the spec, determine the enforcement mode for this closure:

1. Read AGENTS.md for the project's autonomy level (`default_autonomy`, or spec-level `Autonomy:` override). Read `forge.lane` for Lane A/B.
2. Read `docs/process-kit/gate-categories.md` for the categorization reference.
3. **Assess delegation eligibility** — check ALL of the following:
   - Autonomy level is L3 or L4
   - Every acceptance criterion is machine-verifiable (no "does this look right?", "is this the right approach?", UX changes, external-facing content, physical-world recommendations, or irreversible external actions)
   - No human-judgment-required checks apply to the spec's scope
   - No confidence-gated check scored LOW during validation (check from validator gate)
   - Change lane is not `hotfix` at L3 (hotfixes delegated only at L4)

4. **Select enforcement mode**:
   - If Lane B AND `forge.gate.provider` is `pal`: mode = **PAL**
   - Else if delegation-eligible: mode = **Delegated**
   - Else: mode = **Chat** (default)

5. Report: "Enforcement mode: **<mode>** — <reason>."

6. **If Delegated mode**: Skip human review steps (Step 2d validator still runs mechanically). After all mechanical gates pass, proceed directly to the delegated close path (Step 3 addendum below). Report: "All ACs are machine-verifiable at L<N>. Closing via delegated mode — no human prompt required."

7. **If Chat mode**: Proceed normally — human reviews the Review Brief at Step 3.

8. **If PAL mode**: Proceed normally but deliver Review Brief via NanoClaw for hardware-authenticated approval.

### [mechanical] Current Goal tracking (Spec 091)
After completing each major step (2, 3, 4, 5, 6, 7, 8, 9), emit a compact validation progress line at the END of your output:
```
_Progress: Step <current>/9 (<step description>) | Gates: <N>/<total> | PASS: <N>, COND: <N>, FAIL: <N> | Next: <next step>_
```
Update `docs/sessions/context-snapshot.md` `## Active implementation` at steps 2 (start close), 3 (status transition), and 9 (complete).

## [mechanical] Step 2 — Read and verify
Read `docs/specs/NNN-*.md` for the given spec. <!-- parallel: also read README.md + backlog.md for status checks -->
Confirm spec status is `implemented`:
- If `implemented`: emit `GATE [status-verification]: PASS — spec is at implemented status, ready to close.`
- If not `implemented`: emit `GATE [status-verification]: FAIL — spec is at '<status>' status. Remediation: run /implement NNN to reach 'implemented' status first.` Stop.

### [mechanical] Step 2 addendum — Spec integrity verification (Spec 089)

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

If the spec has an `Approved-SHA:` field in frontmatter:

1. **Extract sections**: Extract the full text of these four sections (each from its `##` heading to the next `##` heading, exclusive):
   - `## Scope`
   - `## Requirements`
   - `## Acceptance Criteria`
   - `## Test Plan`
2. **Combine and normalize**: Concatenate the four extracted sections in order (Scope, Requirements, Acceptance Criteria, Test Plan). Trim leading and trailing whitespace from the combined text.
3. **Compute hash**: Compute the SHA-256 hash of the combined, trimmed text. Produce the 64-character lowercase hex digest.
4. **Compare**: Compare the computed hash to the `Approved-SHA:` value in frontmatter.
5. **Old-format SHA detection**: If the hash does NOT match, check whether the spec was approved under the old format (Scope + ACs only). Extract only the Scope and Acceptance Criteria sections, combine, and compute a SHA-256 of that subset. If this old-format hash matches the stored `Approved-SHA:`, the spec was approved before the extended SHA scope was introduced. Report: "Spec integrity: old-format SHA detected (Scope + ACs only). Recomputing with extended scope (Scope + Requirements + ACs + Test Plan)." Update `Approved-SHA:` to the new four-section hash and log in the revision log: `YYYY-MM-DD: Approved-SHA recomputed from old format (Scope+ACs) to extended format (Scope+Requirements+ACs+TestPlan).` Emit `GATE [spec-integrity]: PASS — old-format SHA migrated and verified.` Continue.
6. **If MATCH**: Report "Spec integrity: verified" and emit `GATE [spec-integrity]: PASS — SHA-256 matches approved hash.` Continue to next step.
6. **If MISMATCH**: HALT. Display:
   - "SPEC INTEGRITY FAILURE — spec was modified after approval"
   - Show a diff of the changed Scope and/or Acceptance Criteria sections (compare current text to what would produce the original hash — since we cannot reverse the hash, show the current sections and note they differ from the approved version)
   - Emit `GATE [spec-integrity]: FAIL — SHA-256 mismatch. Approved: <stored hash>, Current: <computed hash>.`
   - Present choice:
     - **(a) "approve with modified spec"** — Log override in the spec's Revision Log: `YYYY-MM-DD: Spec integrity override — Approved-SHA mismatch accepted. Old: <stored>, New: <computed>.` Update `Approved-SHA:` to the new hash. Continue closing.
     - **(b) "halt"** — Stop closing. Report: "Run /revise NNN to formally revise the spec, then /implement NNN to re-approve."

If no `Approved-SHA:` field exists (legacy spec): skip verification silently.

<!-- module:browser-test -->
## [mechanical] Step 2b2 — Visual evidence gate (Spec 093, conditional)

If browser test evidence exists for this spec (`tmp/evidence/SPEC-NNN-browser-*/manifest.json`):

1. Read the most recent manifest file (by directory date suffix).
2. Check the summary: `passed` vs `total` counts.
3. Gate outcome:
   - All passed → `GATE [browser-evidence]: PASS — <passed>/<total> UI checks passed. Screenshots: <count>, Video: <yes/no>.`
   - Any failed → `GATE [browser-evidence]: CONDITIONAL_PASS — <passed>/<total> UI checks passed, <failed> failed. Human review required for failed steps. Evidence: <dir>.`
   - No manifest found → skip silently (spec may not have UI components).
4. If evidence exists, include the evidence directory path and summary.md link in the spec's Evidence section when updating to `closed`.
<!-- /module:browser-test -->

## [mechanical] Step 2b3 — Shadow validation evidence check (Spec 115, updated by Spec 129)

See: docs/process-kit/shadow-validation-guide.md (strategy selection), docs/process-kit/shadow-validation-checklist.md (execution steps).

Read the spec file's `## Shadow Validation` section:

1. If the section **does not exist** or contains only the template placeholder comments (`<!-- Uncomment ONE strategy`): skip silently — shadow validation is not applicable.
2. If the section exists with a **declared strategy** (an uncommented `**Strategy**:` line):
   a. Check for corresponding evidence: look for a filled `**Evidence**:` field (not "pending" or empty).
   b. **Determine lane**: check if `docs/compliance/profile.yaml` exists (Lane B) or not (Lane A).
   c. **Lane A** (no compliance profile):
      - Evidence present → `GATE [shadow-validation]: PASS — shadow validation evidence found. Strategy: <strategy>.`
      - Evidence missing or "pending" → `GATE [shadow-validation]: CONDITIONAL_PASS — spec declares shadow validation (strategy: <strategy>) but no evidence recorded. This is a non-blocking warning — shadow validation is advisory. Consider running the shadow comparison before closing.`
      - **This gate is non-blocking for Lane A.** CONDITIONAL_PASS does not halt the close workflow.
   d. **Lane B** (compliance profile exists):
      - Evidence present AND reviewer sign-off present (a `**Reviewer sign-off**:` or `Reviewed-by:` line that is not empty/pending) → `GATE [shadow-validation]: PASS — shadow validation evidence found with reviewer sign-off. Strategy: <strategy>.`
      - Evidence present but reviewer sign-off missing → `GATE [shadow-validation]: FAIL — shadow validation evidence found (strategy: <strategy>) but Lane B requires reviewer sign-off. Remediation: add reviewer sign-off per docs/process-kit/shadow-validation-checklist.md.` **This is blocking — halt the close workflow.**
      - Evidence missing or "pending" → `GATE [shadow-validation]: FAIL — spec declares shadow validation (strategy: <strategy>) but no evidence recorded. Lane B requires shadow validation evidence before closing. Remediation: execute the shadow validation checklist (docs/process-kit/shadow-validation-checklist.md) and record evidence.` **This is blocking — halt the close workflow.**

## [mechanical] Step 2b4 — Dependency sign-off gate (Spec 126)

Check whether the spec has outstanding dependency review requirements:

1. **Detect signal**: Search the spec file's `## Evidence` section for `DEPENDENCY_REVIEW_REQUIRED`.
   - If not found: skip this step silently — no dependency changes require review.

2. **Check for sign-off**: If `DEPENDENCY_REVIEW_REQUIRED` is present, search for a corresponding sign-off:
   - Look for a `### Dependency Sign-off` subsection in `## Evidence` with:
     - A non-empty `Reviewed by:` field
     - A non-empty `Date:` field
     - At least one dependency listed as `APPROVED`
   - OR look for a `### Dependency Gate Skip` subsection with:
     - A non-empty `Reason:` field

3. **Gate outcome**:
   - Sign-off present → `GATE [dependency-review]: PASS — dependency sign-off found. Reviewed by: <reviewer>, Date: <date>.`
   - Gate skip present → `GATE [dependency-review]: PASS — dependency gate skipped with justification: "<reason>".`
   - Neither present → `GATE [dependency-review]: FAIL — DEPENDENCY_REVIEW_REQUIRED signal found but no sign-off or skip justification recorded. Remediation: review dependencies using docs/process-kit/dependency-vetting-checklist.md and add a Dependency Sign-off section to the spec's Evidence, or use --skip-dependency-gate "<reason>" to bypass.`
     - **This is blocking** — halt the close workflow. Do not proceed to Step 3.

4. **Override**: If `--skip-dependency-gate "<reason>"` is present in $ARGUMENTS:
   - Add a `### Dependency Gate Skip` subsection to the spec's Evidence section with the provided reason.
   - Emit: `GATE [dependency-review]: PASS — dependency gate skipped at close with justification: "<reason>".`
   - Proceed normally.

<!-- module:compliance -->
## [mechanical] Step 2c — Lane B spec sealing (Spec 052, conditional)
After completing the status transition to `closed` (Step 3 below), if `docs/compliance/profile.yaml` exists (Lane B project):
a. Add `Lane-B-Sealed: YYYY-MM-DD` to the spec's frontmatter (after `Last updated:`).
b. Add a revision entry: `YYYY-MM-DD: Spec sealed (Lane B) — content is now an immutable audit record. Future changes require a successor spec with Supersedes: NNN.`
c. Report: "Spec NNN sealed (Lane B). The spec file is now an immutable audit record."
- If `docs/compliance/profile.yaml` is absent (Lane A): skip — Lane A specs are not sealed.
- This step runs AFTER Step 3 (status transition), not before.
<!-- /module:compliance -->

<!-- module:compliance -->
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
- Skip this step if `docs/compliance/profile.yaml` is absent (Lane A project).
<!-- /module:compliance -->

### [mechanical] Step 2d — Validator Gate (Spec 078, updated by Specs 083, 099)

Before transitioning to closed, spawn an independent validator to verify acceptance criteria.

1. Check AGENTS.md for `forge.roles.validator.enabled`. If `false` or absent: skip this step silently.

2. Check if the spec's change-lane is in `forge.roles.validator.skip_lanes`. If so: skip with note "Validator skipped for <lane> lane."

2b. **Check `forge.roles.separation`** in AGENTS.md (Spec 099):
   - If `context-scoped` or `full`: All validator agents in this step (both two-stage and fallback) MUST be spawned as **isolated** sub-agents. The agent receives ONLY: the spec file, current codebase, test results, and role/review instructions — NO conversation history, NO implementer reasoning, NO DA findings, NO commit messages. This ensures independent judgment free from confirmation bias. Use `model` from `forge.roles.validator.model` if set.
   - If `none` (default): Spawn validator agents in the current context (existing behavior).

2c. **Role state file lifecycle (Spec 100)**: Before spawning any validator sub-agent, write the role state file to activate hook-enforced write blocking:
   ```bash
   mkdir -p .forge/state
   cat > .forge/state/active-role.json << 'EOF'
   {"role":"validator","spec":"NNN","started":"<ISO 8601 now>","read_only":true}
   EOF
   ```
   This activates the PreToolUse hook in `.claude/settings.json` which blocks Write/Edit/NotebookEdit tool calls while the validator role is active. After all validator sub-agents complete (regardless of outcome), delete the role state file to lift write restrictions:
   ```bash
   rm -f .forge/state/active-role.json
   ```

3. **Check two-stage review config**: Read AGENTS.md for `forge.review.enabled`.

4. **If `forge.review.enabled` is `true`**: Use the two-stage review protocol as the validator's review method.

   a. **Stage 1 — Spec Compliance Review** (if `spec_compliance` in `forge.review.stages`):
      - Spawn a read-only review agent with:
        - The spec file as context
        - The full codebase diff since the spec was started (`git diff` from spec's `in-progress` date)
        - Test results (run the project's test command)
        - Instructions from `.forge/templates/review-checklists/spec-compliance.md`
      - Agent produces structured JSON findings
      - PASS: proceed to Stage 2
      - WARN: log findings, proceed to Stage 2
      - FAIL: emit `GATE [validator/spec-compliance]: FAIL — <findings summary>`. Stop (do not proceed to Step 3).

   b. **Stage 2 — Code Quality Review** (if `code_quality` in `forge.review.stages`):
      - Spawn a separate read-only review agent with:
        - Changed files (full content, not just diff)
        - Test files
        - Test results
        - Instructions from `.forge/templates/review-checklists/code-quality.md`
        - NOTE: do NOT provide the spec file (context isolation — Stage 2 reviews code on its own merits)
      - Agent produces structured JSON findings
      - PASS/WARN: proceed
      - FAIL: emit `GATE [validator/code-quality]: FAIL — <findings summary>`. Stop.

   c. **Combined result**: Validator gate result = worst of Stage 1 and Stage 2 (FAIL > WARN > PASS).

   d. **Log results**: Append review findings summary to the spec's Evidence section:
      ```
      ## Review Results (Spec 083)
      Stage 1 (Spec Compliance): <result> — <requirements>/<total> requirements, <ACs>/<total> ACs, <N> scope violations
      Stage 2 (Code Quality): <result> — <N> findings, test ratio <ratio>
      ```

   e. **If combined PASS or WARN**:
      - Emit: `GATE [validator]: PASS — two-stage review passed. Stage 1: <result>, Stage 2: <result>.`
      - Add `Validated: YYYY-MM-DD` to spec frontmatter.
      - Proceed to Step 3 (status transition).

   f. **If combined FAIL**:
      - Emit: `GATE [validator]: FAIL — two-stage review failed. Stage 1: <result>, Stage 2: <result>.`
      - Print findings from the failing stage(s).
      - Report: "Spec NNN failed two-stage validation. Fix the findings with /implement NNN, then run /close NNN again."
      - Stop. Do not proceed to Step 3.

5. **If `forge.review.enabled` is `false` or absent**: Fall back to existing validator behavior.

   a. Read `.claude/agents/validator.md` for the role preamble.

   b. Spawn a validator sub-agent with the following prompt structure:
      ```
      [Role preamble from validator.md]

      You are validating: docs/specs/NNN-<slug>.md

      Read the spec file's Acceptance Criteria section. For each criterion:
      1. Read the relevant code/files in the codebase
      2. Determine if the criterion is satisfied
      3. Record your finding

      IMPORTANT: You are performing INDEPENDENT validation. You have NO context about how the implementation was done or why. Judge only by what you observe in the spec and codebase.

      IMPORTANT: Do NOT read or consider the `## Evidence` section of the spec file. The Evidence section was written by the implementing agent and could anchor your judgment. Form your own evidence by examining the codebase, running tests, and reading the actual files directly. Base your findings solely on what you observe, not on what the implementer reported.

      IMPORTANT: You are READ-ONLY for source files. You may use Read, Glob, Grep, and Bash (for running tests). You do NOT have Write or Edit tools. Do not attempt to modify any file.

      Produce your output as a JSON code block with this structure:
      {
        "validation_result": "PASS" | "FAIL",
        "criteria_results": [
          {"criterion": "AC text", "file": "path", "method": "code review|test|manual", "result": "PASS|FAIL", "notes": "..."}
        ],
        "test_output": "summary of any test results",
        "summary": "One paragraph assessment"
      }
      ```

   c. Parse the validator's JSON output.

   d. **If validation_result is PASS**:
      - Emit: `GATE [validator]: PASS — all <count> acceptance criteria verified independently.`
      - Add `Validated: YYYY-MM-DD` to spec frontmatter.
      - Proceed to Step 3 (status transition).

   e. **If validation_result is FAIL**:
      - Emit: `GATE [validator]: FAIL — <count> acceptance criteria failed independent verification.`
      - Print each failed criterion with the validator's notes.
      - Report: "Spec NNN failed independent validation. Fix the failed criteria with /implement NNN, then run /close NNN again."
      - Stop. Do not proceed to Step 3.

6. **Override**: `--force` flag on /close bypasses validator FAIL. Logged as signal:
   "SIG-NNN | process | Validator FAIL overridden via --force on spec NNN. Failed criteria: <list>"

7. Log the validator invocation to `docs/sessions/agent-file-registry.md`:
   ```
   YYYY-MM-DD HH:MM | validator | spec-NNN | <result> | criteria: <pass>/<total> | mode: <subagent|inline>
   ```

### [mechanical] Step 2d+ — Intelligent Role Dispatch at Close (Spec 187)

After the validator gate completes, check `forge.dispatch_rules.enabled` in AGENTS.md. If `false` or absent: skip this step.

If enabled:
1. **Skip threshold check**: Read the spec's E and R scores. If E ≤ `skip_threshold.effort` AND R ≤ `skip_threshold.risk`: skip. Report: "Close dispatch: skipped (E=<e>, R=<r> — below threshold)."

2. **Evaluate dispatch conditions** (same rules as /implement Step 2b+):
   - `cross_cutting` → CTO, `security` → CISO, `lane_b` / `high_risk` → CQO, `high_effort` / `process_only` → CEfO.

3. **Dispatch**: For each selected role (1-3 max), spawn an isolated sub-agent with the role preamble and the spec file. Roles run in **parallel**. Each produces a closing advisory (3-5 sentences).

4. **Present advisory output**: Display role review blocks. Advisory only — does not block close.
   ```
   ## Closing Advisory (Spec 187)
   Dispatched: <roles> (reason: <conditions>)

   <role review blocks>

   Advisory summary: <N> PROCEED, <N> REVISE, <N> BLOCK
   Note: Non-DA/validator recommendations are advisory. Close proceeds.
   ```

5. Log to `docs/sessions/agent-file-registry.md`:
   ```
   YYYY-MM-DD HH:MM | <role> | spec-NNN | <recommendation> | advisory-close | mode: dispatch
   ```

### [mechanical] Step 2g — Shadow-Mode Gate Comparison (Spec 277, Phase 1)

See `docs/process-kit/gate-comparison-methodology.md` for the shadow-run rationale and the decision criteria consumed by Phase 2. This step silently captures timing, token, and raw-findings data from three review gates — `/ultrareview`, Validator Stage 2 (Code Quality), and the DA role-registry review — for later offline comparison. **Zero user-visible behavior change**: findings are never surfaced in the Review Brief, never logged to stdout as gate output, and never block `/close`.

**Shared instrumentation wrapper** (used in Steps 2d, 2f, and this step): when invoking `/ultrareview`, Validator Stage 2, or the DA role-registry review, wrap the sub-agent call to capture `{duration_s, tokens, severity_counts, raw_output}`. The wrapper is observationally transparent — it records metadata only, never alters return values or downstream flow.

1. **Trigger evaluation** — read spec front-matter. Proceed with shadow invocation only if ALL of the following hold:
   - At least one of: `Consensus-Review: true`; OR `BV >= 4` AND spec scope mentions external interface / API / CLI contract; OR `R >= 4`.
   - `Change-Lane:` is NOT `hotfix` and NOT `process-only`.
   - `--skip-ultrareview` flag is NOT present in $ARGUMENTS.
   - Spec has a committed diff since it went `in-progress`.

   If any check fails, record the skip reason (`hotfix`, `process-only`, `operator-skip`, `not-triggered`, `no-diff`) and proceed to step 4 (persistence-only).

2. **Persistence setup** — create `.forge/state/gate-comparison/<spec-id>/` if it does not exist. The parent `.forge/state/gate-comparison/` is gitignored.

3. **Silent `/ultrareview` invocation** (only if triggered and not skipped):
   - Invoke Claude Code's built-in `/ultrareview` against the spec's committed diff.
   - Wrap with the shared instrumentation wrapper above.
   - **Capture only — do not display.** The wrapped output must never appear in operator-visible channels: no `GATE [...]` line, no Review Brief section, no stdout findings.
   - On `/ultrareview` sub-agent error: record `{skipped: true, skip_reason: "ultrareview-error: <short error>"}` and proceed. Errors must not cascade into `/close`. Non-Claude-Code agents (cursor, copilot, cline) where `/ultrareview` is unavailable record `{skipped: true, skip_reason: "ultrareview-error: command-not-available"}` and proceed silently — Validator Stage 2 and DA captures still complete.

4. **Write per-gate persistence files** under `.forge/state/gate-comparison/<spec-id>/`:
   - `ultrareview.json`: `{gate: "ultrareview-shadow", spec_id, timestamp, duration_s, tokens, severity_counts, raw_output}` — or `{gate: "ultrareview-shadow", spec_id, timestamp, skipped: true, skip_reason}` if skipped.
   - `validator-stage2.json`: same schema with `gate: "validator-stage2"`, populated from the Step 2d Validator Stage 2 wrapper capture.
   - `da.json`: same schema with `gate: "da"`, populated from the Step 2f DA role-registry review wrapper capture (or `{skipped: true, skip_reason: "role-registry-absent"}` if Step 2f was a silent skip).

5. **Silent one-line debug note** (debug logs only — not operator output): `shadow-gate-comparison: spec=<NNN> triggered=<true|false> skip_reason=<reason or "">`. Must not appear in `/close` stdout.

6. **Session sidecar logging** — append to the session JSON sidecar's `gate_outcomes` array a `{gate: "ultrareview-shadow", result: "PASS", duration_s, severity_counts, skipped, skip_reason, comparison_dir: ".forge/state/gate-comparison/NNN/"}` entry. Also extend the existing Validator Stage 2 and DA gate entries in-place with `duration_s` and `tokens` fields from the wrapper capture. Schema: see `.forge/templates/session-handoff-schema.json`.

7. **No gate outcome emitted to operator**. The shadow step is silent by design — emit no `GATE [...]` line and add no Review Brief content. AC #3 (Review Brief diff-identical to a non-shadow close) guards this behavior.

**Constraints reminder**:
- MUST NOT surface `/ultrareview` findings in any operator-visible channel in Phase 1.
- MUST NOT block `/close` under any circumstance in Phase 1.
- MUST NOT add or read `Ultrareview:` / `Ultrareview-Blocking:` spec front-matter fields (no such fields exist in Phase 1).

### [mechanical] Step 2d++ — Template/FORGE Dual-Check (Spec 188, upgraded by Spec 180)

Before generating the Review Brief, actively verify bidirectional sync:

**Detection logic**: Run `git diff --name-only <spec-baseline>..HEAD` to get the list of files changed by this spec. For each changed file:
- If the file is under `template/.claude/commands/`, `template/.forge/commands/`, `template/.claude/agents/`, `template/docs/process-kit/`, `template/docs/QUICK-REFERENCE.md`, `template/bin/`, or `template/scripts/`: check if a corresponding own-copy exists at `.claude/commands/`, `.forge/commands/`, `.claude/agents/`, `docs/process-kit/`, `docs/QUICK-REFERENCE.md`, `bin/`, or `scripts/` (same filename, ignoring `.jinja` suffix).
- If the file is under `.claude/commands/`, `.forge/commands/`, `.claude/agents/`, `docs/process-kit/`, `bin/`, `scripts/`, or is `docs/QUICK-REFERENCE.md`: check if a corresponding template file exists under `template/`.

**Evaluation**:
- If **no dual files found in the changed set**: mark `[x] Template/FORGE dual-check — no dual files changed`. Proceed silently.
- If **dual files found and both sides were changed**: mark `[x] Template/FORGE dual-check — both sides updated`. Proceed silently.
- If **only one side was changed** (drift detected):

  Present:
  ```
  TEMPLATE/FORGE DRIFT DETECTED — The following files were changed on one side but not the other:
  <list of drifted files with which side was changed>

  This drift must be resolved before closing. FORGE requires template and own-copy command files to stay in sync.
  ```
  > **Choose** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `sync` | Restores parity automatically; safest default | Apply the changes to the missing side now |
  > | **2** | 2 | `intentional` | Drift may be intentional; record reason | Drift is intentional — document reason and proceed |
  > | **3** | — | `block` | Manual fix path; use only if sync is unsafe | Block close until drift is fixed manually |

  - If `sync`: for each drifted file, copy the changes to the other side. Re-run the check to confirm sync.
  - If `intentional`: append to the spec's Revision Log: `YYYY-MM-DD: Template/FORGE dual-check: drift noted as intentional for <files> — <reason>.` Proceed.
  - If `block`: report "Close blocked — resolve template/own-copy drift and re-run /close." Stop.

### [mechanical] Step 2d+++ — Consumer-Propagation Check (Spec 303)

After the template/FORGE dual-check passes, verify that any documentation referenced from template command files will actually reach consumer projects. This catches the Spec 299 defect class: a new `docs/<path>.md` is created and linked from a `template/.../command.md`, but the doc itself is neither mirrored into `template/docs/` (so Copier does not ship it) nor listed in `scripts/sync-to-public.sh`'s `PUBLIC_DOC_FILES` whitelist (so forge-public does not receive it) — leaving every consumer with a broken pointer.

**Scope**: runs only when the closing spec's Implementation Summary `Changed files` list contains at least one path matching `template/.claude/commands/*.md` or `template/.forge/commands/*.md`. If no such files: mark `[x] Consumer-propagation check — no template command files in scope`. Emit `GATE [consumer-propagation]: PASS — no template command files changed.` Proceed silently.

**Detection logic**: For each changed file matching `template/(.claude|.forge)/commands/*.md`:
1. Extract all markdown link targets pointing under `docs/` using pattern `\[[^\]]+\]\((docs/[^)#\s]+\.md)(?:#[^)]*)?\)`. Strip any `#anchor` suffix before comparison.
2. Deduplicate targets across all scanned template command files.
3. For each target `docs/<path>`:
   a. Check whether `template/docs/<path>` exists in the working tree.
   b. If not, check whether the literal string `docs/<path>` appears in the `PUBLIC_DOC_FILES=( ... )` array in `scripts/sync-to-public.sh` (use `grep -F "docs/<path>" scripts/sync-to-public.sh` scoped to the array block).
   c. If neither mirror nor whitelist entry is present: record as a violation, noting the referencing template command file(s).

**Evaluation**:
- If **no violations found**: mark `[x] Consumer-propagation check — all doc links propagate`. Emit `GATE [consumer-propagation]: PASS — <N> doc link(s) verified across <M> template command file(s).` Proceed silently.
- If **violations found**:

  Present:
  ```
  CONSUMER-PROPAGATION DRIFT — The following docs are referenced from template command files but will not reach consumer projects:
  <list: "docs/<path>" referenced by "template/<command>.md" — missing template mirror AND sync whitelist entry>

  Consumer projects bootstrap from the template and/or receive the sync-to-public stream. A referenced doc must be reachable via at least one path or the pointer will be broken on their side.
  ```
  > **Choose per violation** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `sync` | Mirrors the doc; consumers receive it via Copier | Create `template/docs/<path>` by copying the source `docs/<path>` |
  > | **2** | 1 | `whitelist` | Sync-to-public path; consumers receive via forge-public stream | Append `docs/<path>` to `scripts/sync-to-public.sh`'s `PUBLIC_DOC_FILES` array |
  > | **3** | — | `skip` | Record intentional drift; reason required | Record intentional drift in the spec's Revision Log (reason required) |

  - If `sync`: `mkdir -p template/docs/<dirname>` then `cp docs/<path> template/docs/<path>`. Re-verify the target — check passes for this violation.
  - If `whitelist`: edit `scripts/sync-to-public.sh` to add `"docs/<path>"` inside the `PUBLIC_DOC_FILES=( ... )` array block. Re-verify — check passes for this violation.
  - If `skip`: prompt for a one-line reason and append to the spec's Revision Log: `YYYY-MM-DD: Consumer-propagation check: skipped for docs/<path> — <reason>.`

  After iterating all violations:
  - All resolved via `sync` or `whitelist`: emit `GATE [consumer-propagation]: PASS — <N> violation(s) resolved (<sync count> synced, <whitelist count> whitelisted).` Proceed.
  - Any resolved via `skip`: emit `GATE [consumer-propagation]: CONDITIONAL_PASS — <N> violation(s) skipped with documented reason.` Proceed.
  - Any unresolved (operator abandoned choice): emit `GATE [consumer-propagation]: FAIL — <N> unresolved violation(s). Remediation: mirror the doc under template/docs/, add docs/<path> to PUBLIC_DOC_FILES, or explicitly skip with reason.` Stop close.

### [mechanical] Step 2d++++ — Gate-mediation drift gate (Spec 444 Req 8a/8c)

When a spec touches `copier.yml` to add a new `validator:`, a new `_tasks:` entry, or a new `secret: true` runtime token, the corresponding gate kind MUST be modeled in `template/.forge/lib/stoke/gates.py` so `/forge stoke` can mediate it in chat (Spec 444). Convention statements alone have a sub-6-month half-life (Specs 427/431 violated mirror-sync conventions inside that window), so this gate enforces the convention mechanically.

**Scope**: runs only when the closing spec's committed diff against the spec baseline modifies at least one of:
- `copier.yml` (or `template/copier.yml`)
- `template/.forge/lib/stoke/gates.py` (or its `.forge/lib/stoke/gates.py` own-copy mirror)

If neither file is in the diff: mark `[x] Gate-mediation drift gate — no copier.yml / gates.py changes in scope`. Emit `GATE [gate-mediation]: PASS — no surface in scope.` Proceed silently.

**Exemption**: if the closing spec's frontmatter contains `Gate-Mediation-Exempt: <≥30-char rationale>`, skip the gate and emit `GATE [gate-mediation]: SKIP — Gate-Mediation-Exempt: <reason snippet>`. The exemption usage is logged for Spec 444 AC 11 telemetry (CTO: ≥2 specs in a 30-day window escalates as a cultural-drift signal).

**Detection logic** (Req 8a):

1. Compute the diff: `git diff <spec-baseline>..HEAD -- copier.yml template/copier.yml`.
2. Scan the added lines for tokens that indicate a new gate surface:
   - `^\+\s*validator\s*:` — new validator declaration
   - `^\+\s*-` immediately following a `_tasks:` header in the added range — new task entry
   - `^\+\s*secret\s*:\s*true` — new runtime secret token
3. Apply the YAML-adversarial fixture set (AC 9a) to the regex during test runs — anchors (`&anchor`), aliases (`*alias`), and folded scalars (`>`) inside `validator:` declarations MUST be detected as additions. Adversarial fixtures live in `.forge/tests/test_stoke_gates.py`.
4. If ANY new-gate token is found:
   a. Compute `git diff <spec-baseline>..HEAD -- template/.forge/lib/stoke/gates.py .forge/lib/stoke/gates.py`.
   b. If the diff is empty (gates.py was NOT modified in this spec): emit `GATE [gate-mediation]: FAIL — copier.yml adds a new validator/_tasks/secret surface but template/.forge/lib/stoke/gates.py was not extended. Remediation: extend detect_gates() to model the new gate, OR add 'Gate-Mediation-Exempt: <≥30-char rationale>' to the spec frontmatter.` Stop close.
   c. If gates.py WAS modified: proceed to the fixture-rotation check (Req 8c).

**Fixture-rotation check** (Req 8c):

When `gates.py` itself is modified by the closing spec, the smoke-test fixture at `template/.forge/tests/test_stoke_mediation_coverage.py` MUST also be updated so the deliberately-unmodeled token rotates. Otherwise the test decays to tautology — it would PASS against a now-modeled gate.

1. Compute `git diff <spec-baseline>..HEAD -- template/.forge/lib/stoke/gates.py .forge/lib/stoke/gates.py`.
2. If non-empty, also check `git diff <spec-baseline>..HEAD -- template/.forge/tests/test_stoke_mediation_coverage.py .forge/tests/test_stoke_mediation_coverage.py`.
3. If `gates.py` changed AND the smoke-test fixture's `LAST-ROTATED:` marker was NOT updated (the marker line does not appear in the added-lines diff): emit `GATE [gate-mediation]: FAIL — gates.py was modified but test_stoke_mediation_coverage.py's LAST-ROTATED marker was not updated. The smoke-test fixture must rotate to a still-unmodeled token (Spec 444 Req 8c) — otherwise the unknown-validator coverage test decays to tautology. Remediation: update the CURRENT-FIXTURE-TOKEN and LAST-ROTATED comment in test_stoke_mediation_coverage.py.` Stop close.
4. If both files are updated in the same spec: emit `GATE [gate-mediation]: PASS — gates.py extended AND fixture rotated.` Proceed.

**Telemetry hook** (AC 11):

Each gate firing records a single JSONL line to `docs/sessions/activity-log.jsonl`:
```json
{"timestamp":"<ISO 8601>","event_type":"gate-mediation-check","spec_id":"<NNN>","decision":"PASS|FAIL|SKIP","exemption_reason":"<empty | reason snippet>"}
```
The `exemption_reason` field is non-empty only when the `Gate-Mediation-Exempt:` exemption was used; `/insights` and `/brainstorm` watchlist scans count occurrences per 30-day window.

## [mechanical] Step 2e — Generate Review Brief (Spec 160)

After all Step 2 gates complete, generate the Review Brief. This is the primary output for human review.

1. **Collect all gate results** from Steps 2, 2b, 2b2, 2b3, 2b4, 2c, 2d above. Categorize each using `docs/process-kit/gate-categories.md`:
   - Machine-verifiable gates → "Machine-Verified" section
   - Human-judgment-required checks → "Needs Your Review" section
   - Confidence-gated checks → placed by confidence level (HIGH → Machine-Verified; MEDIUM → Machine-Verified with note; LOW → Needs Your Review)

2. **Scan the spec scope** for human-judgment triggers:
   - Spec modified user-facing commands or onboarding flows → add UX judgment item
   - Spec modified README, articles, or external-facing content → add external content item
   - Spec involves physical-world recommendations or hardware → add Physical Logic Check item
   - Spec touches auth, security, or credentials → add security review item (always human-judgment, not just confidence-gated)
   - Spec is a novel pattern (first time doing something like this) → add novel situation item
   - Spec includes irreversible external actions (push, publish) → add irreversible action item

2b. **LOC proportionality signal** (Spec 252): Read the Stage 2 code quality reviewer's metrics (`new_lines_of_code`, `files_modified`, `files_in_scope`) and the spec's E score from frontmatter. Include a proportionality line in the Review Brief: "Implementation size: N lines across M files (spec E=X)." If the agent judges the implementation size as disproportionate to the spec's E score and scope, escalate to the "Needs Your Review" section: "Review for over-engineering — implementation is larger than expected for E=X." This is a qualitative signal based on agent judgment, not a mechanical threshold.

3. **Output the Review Brief**:
   ```
   ## Review Brief — Spec NNN

   ### Machine-Verified (no action needed)
   - [x] <check description> — <gate result>
   - [x] <check description> — <gate result>
   (medium confidence items noted with: "(medium confidence — override if concerned)")

   ### Needs Your Review
   <numbered list, prioritized per Step 2e.5>
   1. **[Category]** (why this needs human judgment)
      - Expected: <what the spec says should happen>
      - Actual: <what was produced — rendered output, excerpt, or file reference>
      - AI assessment: <what the AI thinks, and why it can't be certain>
      - Verify: <specific thing the human should check>

   2. **[Category]** ...

   ### Machine-Handled (override if you disagree)
   These were verified by AI and are not presented for review.
   If you want to inspect any, say "show <item>".
   - <list of machine-verified items not shown in detail>
   ```

4. **Physical Logic Check** (Spec 160, Requirement 13-15): If the spec scope involves physical-world recommendations, real-world actions, hardware interactions, or cause-and-effect chains in the physical world, include a dedicated item in "Needs Your Review":
   ```
   N. **[Physical Logic Check]** (AI reasoning about physical constraints can miss obvious prerequisites)
      - Real-world action: <the recommendation or action>
      - Physical prerequisites identified: <what the AI thinks is needed>
      - AI assessment: AI cannot reliably self-assess physical reasoning accuracy.
      - Verify: Does this make physical/practical sense? Check for missing prerequisites any human would catch.
   ```
   This check is ALWAYS human-judgment-required — it cannot be delegated regardless of autonomy level.

5. **Review fatigue management** (Spec 160, Requirements 23-25): If there are 5+ "Needs Your Review" items:
   a. Prioritize in this order:
      1. Irreversible actions
      2. LOW confidence items
      3. Physical logic checks
      4. UX/aesthetic items
      5. Everything else
   b. Check AGENTS.md for `forge.review.budget`. If set (e.g., "5 minutes"), present only the top-priority items and defer the rest:
      ```
      <N> lower-priority items deferred to respect review budget.
      Say "show all" to review them, or "approve deferred" to accept AI assessment.
      ```
   c. If no `forge.review.budget` is set: present all items (full review).

6. **Trust signal recording** (Spec 160, Requirement 20): After the human reviews the brief:
   - If the human overrides a machine-verified check (says "actually, this is wrong" or rejects a machine-verified item): record the check type and correction in `docs/sessions/signals.md` as a trust signal:
     ```
     ### SIG-NNN-XX — Trust correction: <check type>
     - Date: YYYY-MM-DD
     - Type: [trust]
     - Spec: NNN
     - Impact: medium
     - Check: <the specific machine-verified check that was wrong>
     - Correction: <what the human identified>
     - Category recommendation: escalate from machine-verifiable to <confidence-gated|human-judgment-required>
     ```
   - When a human approves without corrections: no action needed (success is the default).

7. **Enforcement mode behavior**:
   - **Chat mode**: Present the Review Brief, then present a choice block:

     > **Review Brief complete** — choose an action:
     > | # | Rank | Action | Rationale | What happens |
     > |---|------|--------|-----------|--------------|
     > | **1** | 1 | `approve` | Validator + DA already passed; default path | Confirm all items reviewed — proceed to close |
     > | **2** | 2 | `show <item>` | Inspect before approving; reversible | Expand a Machine-Handled item for inspection |
     > | **3** | — | `reject` | Use when validator missed a defect; sends back to implementer | Halt close — return spec to implemented for rework |
     > | **4** | — | `consensus` | Heavy review; reserve for genuinely contentious specs | Defer to /consensus — run structured multi-role review before deciding |
     >
     > _(Type the number or keyword directly)_

     Wait for response. On `approve`: proceed to Step 3. On `reject`: stop and report "Close halted by reviewer." On `show`: expand the requested item, then re-present the choice block. On `consensus`: run /consensus inline for this spec, log the outcome in the session JSON sidecar, then re-present the choice block with consensus outcome.
   - **Delegated mode**: The Review Brief has no "Needs Your Review" items (all machine-verifiable). Skip human prompt. Proceed directly to Step 3 with the delegated close addendum.
   - **PAL mode**: Present the Review Brief. Deliver via NanoClaw for hardware-authenticated approval. Wait for tap/reject response. Then proceed to Step 3.

Emit: `GATE [review-brief]: PASS — Review Brief generated. Mode: <mode>. Machine-verified: <N>. Needs review: <N>. Machine-handled: <N>.`

### [mechanical] Consensus outcome logging (Spec 258)

If /consensus was invoked during this /close session (via the "consensus" choice option above), log the outcome to the session JSON sidecar. Find or create the JSON sidecar file at `docs/sessions/<today-date>-NNN.json`. Append a consensus entry:
```json
{
  "consensus_reviews": [
    {
      "spec_id": "NNN",
      "timestamp": "<ISO 8601>",
      "roles": ["<role1>", "<role2>", "..."],
      "recommendations": {"<role>": "<PROCEED|REVISE|BLOCK>"},
      "operator_decision": "accepted|modified|rejected"
    }
  ]
}
```
If no /consensus was invoked: skip silently.

## [mechanical] Step 2g — Safety-property gate (Spec 387)

After the validator subagent (Step 2-2c) and before the close-completion (Step 3), check whether this spec touches a registered safety-config path. The gate has three branches: registry-content match (R2a), bootstrap fallback (R1c), and no-match (silent pass). It also enforces the backfill SLA (R6b).

Source the helper library:
```bash
# shellcheck source=/dev/null
source .forge/lib/safety-config.sh
```

**Step 2g.1 — Detection**:

Determine the baseline commit. If the spec's frontmatter contains `Approved-SHA:`, use the commit at which the spec was last `/revise`'d (recovered from git history of the spec file). If `Approved-SHA:` is absent or the lookup fails, use the parent of the spec branch's first commit:

```bash
baseline="$(git log --pretty=format:%H -- "docs/specs/NNN-*.md" | tail -1)^"
if ! git rev-parse -q --verify "$baseline" >/dev/null; then
  baseline="$(git rev-list --max-parents=0 HEAD | tail -1)"
fi
```

Run the path-match check:
```bash
matched=$(git diff "$baseline"..HEAD --name-only | safety_config_match_diff .forge/safety-config-paths.yaml)
```

Run the bootstrap-fallback check (R1c):
```bash
bootstrap=0
if git diff "$baseline"..HEAD --name-status | safety_config_bootstrap_fallback; then
  bootstrap=1
fi
```

If `matched` is empty AND `bootstrap` is 0: skip silently. Mark `[x] Safety-property gate — no registered paths in diff`. Proceed to Step 3.

**Step 2g.2 — Override-path short-circuit**:

If the spec's frontmatter contains a `Safety-Override:` field, validate it via `safety_config_validate_override`. If valid: append the canonical event record to `docs/sessions/activity-log.jsonl`:
```bash
override_reason="$(grep -E '^- Safety-Override:' docs/specs/NNN-*.md | sed -E 's/^- Safety-Override:\s*//')"
if safety_config_validate_override "$override_reason"; then
  paths_json=$(printf '%s\n' "$matched" | awk 'BEGIN{ORS=""; print "["} NR>1{print ","} {printf "\"%s\"", $0} END{print "]"}')
  printf '{"event_type":"safety-override","spec":"NNN","paths":%s,"reason":%s,"timestamp":"%s"}\n' \
    "$paths_json" "$(printf '%s' "$override_reason" | jq -Rs .)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >> docs/sessions/activity-log.jsonl
  echo "GATE [safety-property]: PASS — Safety-Override accepted (logged to activity-log.jsonl)"
else
  # safety_config_validate_override printed the reject reason to stderr.
  echo "GATE [safety-property]: FAIL — Safety-Override invalid. Remediation: provide a non-trivial reason ≥50 chars."
  exit 2
fi
```
Then skip the prompt and section validation; proceed to Step 2g.5 (backfill SLA check) then Step 3.

**Step 2g.3 — HARD-gate prompt** (R2b):

If `matched` is non-empty OR `bootstrap` is 1, emit verbatim:
```
This spec touched <N> file(s) matching the safety-config registry: <comma-separated paths>.
Does this introduce a safety property — a behavior the system relies on for correctness, security, or concurrency?
[y/N]
```
Read the operator's answer.

**No-answer path (R2c)**: If answer is `n`, `no`, or empty, append to `docs/sessions/activity-log.jsonl`:
```json
{"event_type":"safety-prompt-no","spec":"NNN","paths":[<matched paths>],"timestamp":"<ISO 8601>"}
```
Mark `[x] Safety-property gate — operator answered no`. Skip Step 2g.4. Proceed to Step 2g.5.

**Step 2g.4 — Yes-answer section validation** (R2d):

If answer is `y` or `yes`, the spec body MUST contain a `## Safety Enforcement` section (case-sensitive header, top-level only, not nested) with all three of:

- A line matching `Enforcement code path: <file>::<symbol>` — file must exist; symbol may be `<placeholder>` only when paired with `# UNENFORCED — see Spec NNN` per R3.
- A line matching `Negative-path test: <file>::<test-name>` — test file must exist; test name must match a function/test-block in that file.
- A `Validates`-prefixed prose line of ≥10 characters.

Validation algorithm:

```bash
spec_file="docs/specs/NNN-*.md"
section=$(awk '/^## Safety Enforcement$/{p=1; next} /^## /{p=0} p' "$spec_file")

if [[ -z "$section" ]]; then
  echo "GATE [safety-property]: FAIL — Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md."
  exit 2
fi

ep_line=$(echo "$section" | grep -E '^Enforcement code path: ' || true)
np_line=$(echo "$section" | grep -E '^Negative-path test: ' || true)
val_line=$(echo "$section" | grep -E '^Validates' || true)

if [[ -z "$ep_line" || -z "$np_line" || -z "$val_line" ]]; then
  echo "GATE [safety-property]: FAIL — Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md."
  exit 2
fi

# Validates line ≥10 chars after the prefix
val_text="${val_line#Validates}"
if (( ${#val_text} < 10 )); then
  echo "GATE [safety-property]: FAIL — Validates description too short (<10 chars). Remediation: expand the description."
  exit 2
fi

# File existence checks for code-path and test
ep_file=$(echo "$ep_line" | sed -E 's/^Enforcement code path: ([^:]+)::.*/\1/')
np_file=$(echo "$np_line" | sed -E 's/^Negative-path test: ([^:]+)::.*/\1/')
ep_sym=$(echo  "$ep_line" | sed -E 's/^Enforcement code path: [^:]+::(.*)$/\1/')

# UNENFORCED deferral path (R3): if any line carries "<placeholder>" or "<deferred to Spec NNN>",
# the spec must reference an existing Spec NNN with valid status.
if [[ "$ep_sym" == "<placeholder>" || "$np_line" == *"<deferred to Spec"* ]]; then
  ref=$(echo "$section" | grep -oE 'Spec [0-9]{3}' | head -1)
  if [[ -z "$ref" ]]; then
    echo "GATE [safety-property]: FAIL — placeholder used without 'Spec NNN' reference. Per R3, placeholders require an UNENFORCED-pointer."
    exit 2
  fi
  ref_num=$(echo "$ref" | awk '{print $2}')
  ref_file=$(ls docs/specs/${ref_num}-*.md 2>/dev/null | head -1)
  if [[ -z "$ref_file" ]]; then
    echo "GATE [safety-property]: FAIL — referenced ${ref} does not exist."
    exit 2
  fi
  ref_status=$(grep -E '^- Status: ' "$ref_file" | sed -E 's/^- Status: //')
  case "$ref_status" in
    draft|in-progress|implemented|closed) : ;;  # OK; draft is allowed but flagged in R5
    *)
      echo "GATE [safety-property]: FAIL — referenced ${ref} has invalid status ($ref_status). Per R3c, must be draft/in-progress/implemented/closed."
      exit 2
      ;;
  esac
else
  # Non-placeholder paths must resolve.
  if [[ ! -f "$ep_file" ]]; then
    echo "GATE [safety-property]: FAIL — Enforcement code path file not found: $ep_file"
    exit 2
  fi
  if [[ ! -f "$np_file" ]]; then
    echo "GATE [safety-property]: FAIL — Negative-path test file not found: $np_file"
    exit 2
  fi
fi

# Append yes-answer event
paths_json=$(printf '%s\n' "$matched" | awk 'BEGIN{ORS=""; print "["} NR>1{print ","} {printf "\"%s\"", $0} END{print "]"}')
printf '{"event_type":"safety-prompt-yes","spec":"NNN","paths":%s,"timestamp":"%s"}\n' \
  "$paths_json" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> docs/sessions/activity-log.jsonl

echo "GATE [safety-property]: PASS — Safety Enforcement section validated"
```

**Step 2g.5 — Backfill SLA check** (R6b):

After the prompt path completes (yes/no/override/skip), check the backfill deadline marker:

```bash
deadline_file=".forge/state/safety-backfill-deadline.txt"
if [[ -f "$deadline_file" ]]; then
  deadline=$(cat "$deadline_file")
  now_epoch=$(date -u +%s)
  deadline_epoch=$(date -u -d "$deadline" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$deadline" +%s 2>/dev/null || echo 0)
  if (( now_epoch > deadline_epoch && deadline_epoch > 0 )); then
    # Re-run audit and check list (ii)
    audit_output=$(scripts/safety-backfill-audit.sh --check-only 2>/dev/null || true)
    unenforced_count=$(echo "$audit_output" | grep -cE '^MISSING:' || true)
    if (( unenforced_count > 0 )); then
      echo "GATE [safety-backfill-sla]: FAIL — Safety-backfill SLA expired. ${unenforced_count} declaration(s) still without enforcement or UNENFORCED annotation. Disposition required."
      exit 2
    fi
  fi
fi
echo "GATE [safety-backfill-sla]: PASS — within SLA or audit clean"
```

Mark `[x] Safety-property gate (Spec 387) — completed`. Proceed to Step 3.

## [mechanical] Step 3 — Status transition
Perform the `closed` status transition:

# >>> spec-344 guards
SPEC-344 STEP-3 GUARDS: close the validator-approval-window gap surfaced by /close 318. Read these in order; each guard is independent.

**Off-limits section headings** (canonical list — single source in `docs/process-kit/close-validator-coverage.md` § Guard 2):
- `## Scope`
- `## Requirements`
- `## Acceptance Criteria`
- `## Test Plan`

**Guard 1 — Diff re-validation at Step 3 start (Req 1)**

If the spec file has an `Approved-SHA:` field (Lane B): compare the spec file's current bytes to the bytes that were Approved-SHA-verified at Step 2. The check uses spec-file bytes ONLY (not the working-tree). If the spec file changed between Step 2 and Step 3:
- Invoke the validator on the full spec file (matches Step 2d behavior).
- Validator FAIL → emit `GATE [spec-344-guard-1]: FAIL — spec file modified between Step 2 verification and Step 3; re-validation FAILed.` STOP. Do not proceed.
- Validator PASS → emit `GATE [spec-344-guard-1]: PASS — spec file modified post-verification; re-validation PASS.` Continue.
If no diff: emit `GATE [spec-344-guard-1]: PASS — no pre-Step-3 edits.` Continue.
If no `Approved-SHA:` (Lane A): skip silently — no SHA anchor to compare against.

**Guard 2 — Off-limits section restriction (Req 2)**

Any spec-file edit during Step 3 MUST be confined to non-scoped sections: frontmatter (excluding `Status:` and `Closed:` and `Validated:`), `## Implementation Summary`, `## Revision Log`, `## Evidence`, and any closure-logging block. Edits whose changed lines fall inside the body of `## Scope`, `## Requirements`, `## Acceptance Criteria`, or `## Test Plan` MUST be refused with: `GATE [spec-344-guard-2]: FAIL — Step 3 attempted to modify protected section <heading>. Use /revise — these sections are off-limits at /close.` STOP.

This guard applies to ALL lanes — protected sections are off-limits at /close regardless of whether the spec carries an Approved-SHA.

Permitted Step 3 edits (no guard violation): Status transition, Closed/Validated dates, Implementation Summary, Revision Log entries, Evidence section additions, frontmatter metadata.

Note on genuine post-close corrections (typos, broken links discovered later): those are a SEPARATE problem from /close-time edits. If you hit one, file a follow-up spec for the optional Pattern A errata-file mechanism (deferred follow-up; not implemented today). The guards above do NOT handle post-close corrections.

**Guard 3 — Approved-SHA re-verify post-Step-3 (Req 3)**

After Step 3 completes (sub-steps a-f), if the spec file has an `Approved-SHA:` field (Lane B): recompute the SHA-256 over the four protected sections (Scope + Requirements + AC + Test Plan, per Spec 089's extraction rule). Compare to the stored `Approved-SHA:` value.
- Match → emit `GATE [spec-344-guard-3]: PASS — protected sections unchanged post-Step-3.` Continue.
- Mismatch → emit `GATE [spec-344-guard-3]: FAIL — Step 3 modified protected sections (post-Step-3 SHA mismatch). This indicates a path that bypassed Guard 2.` STOP. Do not push. Investigate the Step 3 sub-step that allowed the protected-section edit.

If no `Approved-SHA:` (Lane A): skip silently — Guard 3 has no anchor.

See: docs/process-kit/close-validator-coverage.md for the full /close 318 incident motivation, threat-coverage handoff (Spec 003 + 145 + Guards 1+2 cover Lane A), and the Spec 035 ↔ Spec 344 cross-edit invariant.
# <<< spec-344 guards

a. Set `Status: closed` and add `Closed: YYYY-MM-DD` in the spec file.
b. Add a dated revision entry based on enforcement mode:
   - Chat/PAL: `YYYY-MM-DD: Closed via /close (Chat mode). Human confirmed all deliverables.`
   - Delegated: `YYYY-MM-DD: Closed via /close (Delegated mode). All ACs machine-verified at L<N>. Evidence hash: sha256:<first 16 chars>...`
b1. **Write-side mode check (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --skip-canonical-write`. Read stdout. If `skip` (split-file mode), the canonical README/backlog/CHANGELOG writes in c, d, e below are SUPPRESSED — the spec frontmatter edit in (a) is the source of truth and the renderer-owned `.generated/` artifacts pick up the new status on next render. The event-stream write in `e1` proceeds unchanged. If stdout is `proceed`, perform c/d/e (Phase 1 dual-write). If the helper exits nonzero, abort the canonical-write block and surface stderr — do NOT default to either behavior.
c. **README sync (Spec 086)** [proceed mode only]: Read the spec file's `Status:` field (authoritative source). Find the spec's row in `docs/specs/README.md` and update the status to match exactly. If no row exists, add one.
d. **Backlog sync (Spec 086)** [proceed mode only]: Find the spec's row in `docs/backlog.md`.
   - Update the status column to match the spec file (e.g., `closed`).
   - Change the Rank column to `✅` for closed specs.
   - **Duplicate detection**: If the spec appears in multiple rows, warn: "Duplicate backlog row detected for Spec NNN — consolidating." Remove all but the most recent row (highest rank or most recent status). Log the duplicate as a process defect.
   - If no row exists, add one at the bottom with ✅ status.
e. **CHANGELOG entry** [proceed mode only]: Add a CHANGELOG entry: `- YYYY-MM-DD: Spec NNN closed via /close.`
e1. **Append spec-closed event (Spec 254 — Approach D)**: Append to the per-spec event stream:
   ```bash
   mkdir -p .forge/state/events/NNN
   echo '{"timestamp":"<ISO 8601>","event_type":"spec-closed","payload":{"mode":"<chat|delegated|pal>","message":"<one-line close note>"}}' >> .forge/state/events/NNN/spec-closed.jsonl
   ```
   Append-only; conflict-free. Consumed by `render_changelog.py` to emit the canonical close event in the chronological log. Continues to coexist with the CHANGELOG.md edit above during Phase 1; Phase 2 spec will retire the duplicate canonical write once events have burned in.
e2. **Score-Audit observed record (Spec 368)**: Append an `observed` record to the score-audit log via the shared helper. Do NOT inline JSON here. The helper computes `wallclock_days`, `session_count`, `revise_rounds`, `validator_outcome`, `da_outcome`, `tc_overrun_derived`, and `creation_ts_source` from artifacts (git timestamps, session JSON sidecars, spec body) — Claude does NOT compute or transcribe duration values.

   ```bash
   bash .forge/lib/score-audit.sh record-observed "$spec_id"
   ```

   (PowerShell: `pwsh .forge/lib/score-audit.ps1 record-observed "$spec_id"`.)

   The helper is advisory — failures emit `WARN: score-audit append failed (advisory; close continues)` to stderr but never block the close. The `tc_overrun_derived` boolean is computed automatically from the proxy mapping documented in [docs/process-kit/score-calibration-loop.md](../../docs/process-kit/score-calibration-loop.md); no operator prompt is added at /close for this field.
f. **Three-source verification (Spec 086)**: After updating, read back all three sources and confirm they agree:
   - Spec file `Status:` field
   - README.md row status
   - Backlog.md row status
   - If all three match: emit `GATE [status-sync]: PASS — spec file, README, and backlog all show 'closed'.`
   - If any mismatch: emit `GATE [status-sync]: FAIL — status drift detected after update. Spec file: <s1>, README: <s2>, Backlog: <s3>. Remediation: manually correct the mismatched source.`

Emit: `GATE [human-confirmation]: PASS — status transition to closed completed, human confirmed deliverables.`

### [mechanical] Step 3 addendum — Delegated close evidence trail (Spec 160, Requirement 7)

If enforcement mode is **Delegated** (determined in Step 1b):

1. **Layer 1 — Full evidence in spec**: Write the complete validation results to the spec's `## Evidence` section:
   - All gate outcomes with PASS status
   - Test output summary
   - Diff summary (files changed, lines added/removed)
   - Delegation-eligibility assessment: `{"all_ac_machine_verifiable": true, "no_judgment_checks": true, "no_low_confidence": true, "autonomy_level": "L<N>"}`

2. **Layer 2 — Content hash in audit log**: Compute SHA-256 of the spec's complete `## Evidence` section content. Append to `.forge/state/audit-log.jsonl`:
   ```json
   {"event": "delegated-close", "spec": "NNN", "timestamp": "<ISO-8601>", "evidence_hash": "sha256:<64-char-hex>", "ac_results": {"AC1": "pass", "AC2": "pass", ...}, "delegation_criteria": {"all_ac_machine_verifiable": true, "no_judgment_checks": true, "no_low_confidence": true, "autonomy_level": "L<N>"}}
   ```
   Create `.forge/state/` directory and `audit-log.jsonl` file if they don't exist.

3. **Layer 3 — Atomic git commit**: The spec file (with evidence) and the updated audit log are committed together in a single atomic commit: "Delegated close: Spec NNN — <title> (L<N>, all ACs machine-verified)".

4. Report: "Spec NNN closed via Delegated mode. Evidence hash: sha256:<first 16 chars>... Three-layer evidence trail recorded."

5. **Verification note**: During future root cause analysis, compare the evidence hash in `audit-log.jsonl` against the current spec evidence section to verify nothing was modified post-close:
   ```bash
   # Extract evidence section from spec, compute hash, compare to audit log
   ```

Emit: `GATE [delegated-evidence]: PASS — three-layer evidence trail recorded. Hash: sha256:<first 16 chars>...`

### [mechanical] Step 3+ — Delta merge to canonical product spec (Spec 184)

After the status transition, check whether the spec declares delta markers for the canonical product spec:

1. **Detect deltas**: Read the spec file's `## Delta` section.
   - If the section does not exist, or all ADDED/MODIFIED/REMOVED lines are commented out (`<!-- ... -->`): skip silently.
   - If any uncommented `ADDED:`, `MODIFIED:`, or `REMOVED:` markers are present: proceed.

2. **Locate canonical spec**: Check for `docs/product-spec.md` or any `.md` file under `docs/product-specs/`. Use the section name in the marker to match the target file if multiple canonical specs exist.
   - If no canonical product spec is found: warn "No canonical product spec found. Delta markers present but no target. Create one from `docs/process-kit/product-spec-template.md` if needed." Skip merge.

3. **Apply markers** (in order):
   - `ADDED: <section> — <text>`: Append a new requirement to the named section. Assign the next sequential REQ-ID. Add attribution: `[Added: Spec NNN, YYYY-MM-DD]`.
   - `MODIFIED: <section>/<REQ-ID> — <text>`: Find the REQ-ID in the named section and replace its text. Add attribution: `[Modified: Spec NNN, YYYY-MM-DD]`.
   - `REMOVED: <section>/<REQ-ID> — <reason>`: Find the REQ-ID and strike through it: `~~REQ-XXX: <old text>~~ [Removed: Spec NNN, YYYY-MM-DD — <reason>]`.

4. **Update version history**: Add a row to the canonical spec's Version History table:
   `| YYYY-MM-DD | NNN | <summary of changes> | operator |`
   Update `Last updated:` and `Last merged from:` in the header.

5. **Conflict detection**: If the REQ-ID being modified or removed does not exist, or if its current text does not match expected state (e.g., already modified by another spec in this session): flag for human resolution. Report: "Delta merge conflict: <REQ-ID> — expected <X>, found <Y>. Resolve manually."

6. **Lane enforcement**:
   - **Lane B** (`docs/compliance/profile.yaml` exists): delta merge is a **blocking gate**. If merge fails or conflicts are unresolved: `GATE [delta-merge]: FAIL — delta merge could not be applied. Remediation: resolve conflicts in the canonical spec.` Stop.
   - **Lane A** (no compliance profile): delta merge is **advisory**. If merge fails: `GATE [delta-merge]: CONDITIONAL_PASS — delta merge encountered issues but Lane A does not block on this. Review canonical spec manually.` Proceed.

7. If merge succeeds: `GATE [delta-merge]: PASS — <N> delta(s) applied to canonical product spec.`

### [mechanical] Step 3a — Remove edit-gate sentinel (Spec 145)
Remove the edit-gate sentinel to signal that no `/implement` session is active:
```bash
rm -f .forge/state/implementing.json
```
If the file does not exist, skip silently.

### [mechanical] Step 3a+ — README stats auto-update (Spec 235, extended by Spec 319)
Run `validate-readme-stats.sh --fix` and `validate-readme-counts.sh --fix` to auto-correct README.md numeric claims before committing. `stats.sh` owns specs+sessions ("N specs across N sessions" prose); `counts.sh` owns commands+roles (and validate-only on specs+sessions to avoid pingpong):
```bash
if [[ -f "scripts/validate-readme-stats.sh" ]]; then
  bash scripts/validate-readme-stats.sh --fix || true
fi
if [[ -f "scripts/validate-readme-counts.sh" ]]; then
  bash scripts/validate-readme-counts.sh --fix || true
fi
```
- If a script is absent: skip silently (consumer projects may not have them).
- If `--fix` corrects counts: the updated README.md is included in the /close commit.
- If a script fails for any reason: proceed (non-blocking, `|| true`).

<!-- module:compliance -->
## [mechanical] Step 3b — V&V report generation (Spec 039, conditional)
If `docs/compliance/profile.yaml` exists (Lane B project):
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
- Skip this step if `docs/compliance/profile.yaml` is absent (Lane A project).
<!-- /module:compliance -->

## [mechanical] Step 3b+ — Active-tab Spec(s) clear (Spec 353)

If `.forge/state/active-tab-*.json` marker exists for this session, locate the registry row whose first column matches the marker's `registry_row_pointer` and clear `<NNN>` (the just-closed spec ID) from the row's `Spec(s)` column. If the column held only `<NNN>`, replace it with the placeholder dash (`—`); if it held a comma-separated list, remove `<NNN>` and trim. Also update the marker file's `spec_id` field to empty string and bump `last_command_at` to now.

Skip silently if no marker exists. The registry row remains `active` (the tab is still open) — only the spec claim is released. Operator runs `/tab close` to release the row itself.

This is the symmetric counterpart to `/implement` Step 3a (Spec(s) write-back). Together they make the registry row's `Spec(s)` column reflect the in-flight spec across the lifecycle.

## [mechanical] Step 3b++ — Lane-mismatch warning (Spec 353)

If the active-tab marker exists and `marker.lane` is `process-only`, emit a one-line warning at /close start: `⚠ Closing a feature-lane spec inside a process-only tab. Continue?` Soft-gate only — do not refuse. Operator decides.

## [mechanical] Step 3c — Session log incremental entry (Spec 131)

Append a structured "spec closed" entry to today's session log:

1. Check `docs/sessions/` for a log file matching today's date. If none exists, create a stub from `docs/sessions/_template.md`.
2. Append a structured entry:
   ```
   ### Spec NNN — closed
   - **Time**: HH:MM
   - **Spec**: NNN — <title>
   - **Lane**: <change-lane>
   - **Action**: Spec closed via /close
   - **Gate outcomes**: <summary of all gates — e.g., "5 PASS, 0 FAIL">
   - **Signals captured**: <count from signal capture step, or "pending">
   ```
3. Report: "Session log updated: spec NNN closed."

### [mechanical] Step 3d — release-eligible signal emission (Spec 291)

After the spec status transitions to `closed`, scan the spec's
`## Implementation Summary` `Changed files` list for any path matching one of
the four release-policy trigger paths (per `docs/process-kit/release-policy.md`
§ Tag-cut triggers):

- `template/**`
- `copier.yml`
- `.claude/commands/**`
- `.forge/templates/project-schema.yaml`

If **no** trigger files are present in the changed-files list: skip silently.
Most specs (process-only docs, test fixtures, scripts) skip this step.

If **at least one** trigger file is present:

1. **Classify surfaces** (one or more of S1/S2/S3 per release-policy.md
   § Versioning contract):
   - `copier.yml` → S1
   - Any `*/commands/*.md` mirror under `.claude/commands/`, `.forge/commands/`,
     `template/.claude/commands/`, or `template/.forge/commands/` → S2
   - `.forge/templates/project-schema.yaml` → S3

2. **Append signal** to `docs/sessions/signals.md`:
   ```
   ### SIG-NNN-RE (release-eligible)
   - **Spec**: NNN
   - **Date**: YYYY-MM-DD
   - **Surfaces affected**: S<n>[, S<n>...]
   - **Proposed bump (initial)**: PATCH — audit (`docs/process-kit/v1.0.0-to-next-audit.md`) is authoritative; may revise upward.
   - **Changed-file basis**: <comma-separated list of trigger-path files>
   ```

3. Emit: `GATE [release-eligible-signal]: PASS — Spec NNN appended to signals.md (surfaces=<list>, proposed_bump=PATCH).`

The signal is consumed by `/now` and `/evolve` (which surface the count of
pending release-eligible entries — Spec 291 Req 4) and by
`scripts/cut-release.sh` when the operator decides to cut a tag. The audit doc
remains the authoritative classifier; signal-time PATCH is a conservative
default that the audit may revise upward to MINOR or MAJOR after surface-diff
analysis.

If `docs/sessions/signals.md` is missing: create it with a single `# Signals`
header, then append.



## [mechanical] Step 4 — (auxiliary actions only — see Step 8a for commit and push)

The `git commit` and `git push` actions previously located here have moved to **Step 8a — Auto-commit and push** (after Steps 5–8 complete) so the close commit captures all spec-mutating step output (deferred-scope dispositions, signal capture, runbook amendments, session-log update, etc.) in a single atomic commit. See `docs/process-kit/runbook.md` § /close for the rationale (Spec 348).

Step 4 now consists only of the auxiliary subsections 4a/4b/4c below — none of which commit.

## [mechanical] Step 4a — Append artifact relationships (Spec 108)

After the spec status transitions in Step 3, update the cross-artifact relationship index for the just-closed spec (writes are uncommitted at this point and will be captured by the Step 8a commit):

1. Read the just-closed spec file (`docs/specs/NNN-*.md`).
2. Scan the spec file for cross-references using the reference patterns defined in `/trace` Step A2:
   - `Spec NNN`, `SIG-NNN-XX`, `CI-NNN`, `EA-NNN`, `ADR-NNN`, `session YYYY-MM-DD-NNN`
3. Classify each reference's relationship type from surrounding context:
   - `Trigger:` or `triggered by` → `triggered-by`
   - `Depends on` or `Dependencies:` → `depends-on`
   - `Closed in` or `closed via` → `closed-in`
   - Signal source/target → `signal-from`
   - All others → `references`
4. Build link entries: `{ "source": "spec-NNN", "target": "<artifact-id>", "type": "<type>", "context": "<surrounding line>" }`
5. If `.forge/state/artifact-links.json` exists:
   a. Read the existing index.
   b. Remove any existing entries where `source` is `spec-NNN` (the just-closed spec) to avoid duplicates.
   c. Append the new link entries.
   d. Update `generated` timestamp and `total_links` count.
   e. Write back to `.forge/state/artifact-links.json`.
6. If `.forge/state/artifact-links.json` does not exist:
   a. Create `.forge/state/` directory if needed.
   b. Write a new index file with the link entries (same format as `/trace` Step A3).

Report: "Artifact index updated: <N> links added for Spec NNN."

If the spec contains no cross-references: skip silently.
If any error occurs reading or writing the index: warn but do not block the close workflow.

## [mechanical] Step 4b — Auto evolve loop check (Spec 043, enhanced by Spec 157)

After the spec status transitions in Step 3, check whether evolve trigger conditions are met (this step reads CHANGELOG.md which Step 3 has already written; the close commit at Step 8a captures the entry):

a. Read `docs/sessions/evolve-config.yaml` (skip silently if absent — use defaults: `auto_fast_path: true`, `spec_count_threshold: 5`, `time_interval_days: 30`).
b. Read `docs/sessions/evolve-state.md` (or last session log's `Last evolve loop review:` field) for the date of the last evolve review.
c. Count specs closed since last review: read CHANGELOG.md for close entries after the last review date.
d. **Fast-path auto-trigger** (Spec 157): If `auto_fast_path` is `true` (default) AND either:
   - Spec count since last review ≥ `spec_count_threshold` (default 5), OR
   - Time since last review ≥ `time_interval_days` (default 30 days)
   
   Then automatically run the evolve fast-path (F1+F4) inline:
   - F1: Spot-check one AC from the just-closed spec (already done in Step 7)
   - F4: Score calibration check — compare predicted E vs actual for recently closed specs
   
   Report results inline. Fast-path results are **informational only** — no human confirmation needed.
   Append results to today's session accumulated entries so `/session` captures them.

e. **Full review recommendation**: If `time_interval_days` threshold is met (≥30 days since last review), recommend `/evolve --full` but do NOT auto-execute it. Full reviews require explicit operator invocation.
   ```
   Evolve loop: full review recommended (last review: <date>, <N> days ago).
   Run `/evolve --full` when ready — this is not auto-triggered.
   ```

f. If neither threshold is met, report briefly: "Evolve loop: N specs since last review (threshold: M). Not yet due."
g. This step never blocks the close workflow.

## [mechanical] Step 4c — Ambient status lines (Spec 220)

Two informational one-liners. Both are silent-skip if data is unavailable. Neither blocks execution or prompts for input.

**Session-log line**: Find today's session log in `docs/sessions/` (file matching today's date pattern). Count accumulated structured entries (sections appended by `/implement`, `/close`, and other commands during this session — look for `###`-level headings or structured entry markers). If count ≥ 1, emit:
```
Session: N entries captured — run /session when wrapping up.
```
If count is 0 or no session log exists for today, skip silently.

**Evolve-status line**: Use the evolve trigger state already computed in Step 4b (specs-since-last-review count vs threshold). Report the trigger closest to its threshold:
```
Evolve: N/M specs since last review (K away from full review trigger).
```
If any trigger already crossed its threshold (i.e., evolve was already recommended or auto-triggered in Step 4b), instead emit:
```
Evolve: triggered — run /evolve when ready.
```
If no evolve state is computable (no evolve-state.md, no CHANGELOG entries, Step 4b skipped), skip silently.

## [decision] Step 5 — Deferred Scope Review
Read the just-closed spec's "Out of scope" section. If it contains any items:
a. Present each item as a numbered list.
b. For each item, ask: **promote** (create stub spec), **backlog** (add to Deferred Scope section), or **drop** (record in revision log)?
c. For each disposition:
   - **promote**: Create a stub spec from `docs/specs/_template.md` with `Origin: Deferred from Spec NNN` in frontmatter. Add to `docs/specs/README.md` and `docs/backlog.md` (scored by human later). Add CHANGELOG entry.
   - **backlog**: Add an entry to the "Deferred Scope" section of `docs/backlog.md` with format: `| <date> | NNN | <item summary> | pending |`
   - **drop**: Append to the originating spec's revision log: `YYYY-MM-DD: Deferred scope item dropped — "<item>". Reason: <human-provided reason>.`

If the spec has no "Out of scope" section or it is empty, skip silently and proceed.

## [mechanical] Step 6 — Signal Capture
Run the retrospective signal capture inline for this spec. Three signal categories:
- **Content**: What worked/didn't in the deliverable itself
- **Process**: What worked/didn't in the workflow
- **Architecture**: Design insights for future work

### Signal classification (Spec 267)

Before drafting each SIG entry, **infer the three Spec 267 classification fields from the implementation and close context**:
- **Root-cause category**: pick one of `spec-expectation-gap`, `model-knowledge-gap`, `implementation-error`, `process-defect`, `other`. Use `other` when categorization is genuinely unclear — do not guess. See `docs/process-kit/signal-quality-guide.md` for the taxonomy and worked examples.
- **Wrong assumption** (optional): the specific belief held before the issue surfaced, now known to be false. Empty string if the signal is not about an assumption failure (e.g., positive-outcome content/architecture signals).
- **Evidence-gate coverage**: pick one of `caught-by-existing-gate`, `missed-by-existing-gate`, `no-applicable-gate`. If `missed-by-existing-gate`, name the gate that should have caught it.

Then draft each SIG entry in this format:
```
### SIG-NNN-XX — <title>
- Date: YYYY-MM-DD
- Type: [content|process|architecture|trust]
- Spec: NNN
- Impact: <low|medium|high>
- Observation: <what happened>
- Root-cause category: <spec-expectation-gap|model-knowledge-gap|implementation-error|process-defect|other>
- Wrong assumption: <the specific false belief, or empty>
- Evidence-gate coverage: <caught-by-existing-gate|missed-by-existing-gate|no-applicable-gate> [— gate name if missed]
- Recommendation: <what to change>
```

**Re-read `docs/sessions/signals.md` now** (Spec 123 — context overflow guard) to avoid collision with concurrent edits, then **auto-append** all drafted entries directly to the file using the established format (`###` header with date and spec, then categorized signal entries). If the file doesn't exist, create it from the signals log header.

Emit a single one-line confirmation in chat: `N signals captured to docs/sessions/signals.md` (where N is the appended count). Do NOT prompt the operator to confirm/edit/skip individual drafts — entries land as-is with their classification fields intact. Curation (dedup, miscategorization correction, scope-trimming) is deferred to `/evolve` pattern analysis (Step 8) where cross-signal context is available and the cost of over-capture is low.

This is a [mechanical] step — do not skip. Absence/empty values for the three Spec 267 classification fields are acceptable (treated as `other` / empty / `no-applicable-gate` downstream) — the goal is to capture signal at low ceremony cost, not block on field completeness.

### Step 6a — Upstream contribution check (Spec 226)
After capturing process signals, check if any should be contributed upstream:

a. Read `.copier-answers.yml` for `_src_path`. Determine contribution path:
   - Contains `Renozoic-Foundry/forge-public` → **canonical** (direct upstream PR)
   - Contains another remote URL (not local path) → **fork** (contribute to fork maintainer)
   - Is a local filesystem path → **skip** (FORGE developer, already at source)

b. For each **process signal** just captured (content and architecture signals are project-specific — skip them):
   - Evaluate: "Does this signal describe a FORGE workflow improvement that would benefit all FORGE users, not just this project?"
   - If yes, present:
     ```
     UPSTREAM CANDIDATE — process signal SIG-NNN-XX may be a framework-level improvement:
       Signal: <signal text>
       Contribution path: <canonical | fork>
       Target: <repo URL>
     ```
     > | # | Rank | Action | Rationale | What happens |
     > |---|------|--------|-----------|--------------|
     > | **1** | 1 | `note` | Cheap to capture; lets /matrix triage later | Add to scratchpad as upstream candidate for later |
     > | **2** | — | `skip` | Project-specific signal; no upstream value | Project-specific — not an upstream improvement |

     - If `note`: append to scratchpad: `- [ ] <date>: [upstream] SIG-NNN-XX — <signal summary>. Target: <repo>.`
     - If `skip`: proceed silently.

c. If `_src_path` is a local path or `.copier-answers.yml` is absent: skip this step silently.

### Step 6b — Runbook amendment check (Spec 107)
After capturing process signals, check if any process signal maps to an existing runbook:
a. Read all `.md` files in `docs/process-kit/`. Extract their section headings (lines starting with `##` or `###`).
b. For each **process signal** just captured, check for keyword overlap between the signal text and runbook section headings (match 2+ non-trivial words, ignoring articles/prepositions).
c. If a match is found, present a runbook amendment proposal:
   ```
   RUNBOOK MATCH — signal SIG-NNN-XX matches runbook section:
     File: docs/process-kit/<runbook>.md
     Section: ## <heading>
     Signal: <signal text summary>

   Proposed amendment: <suggested edit to the runbook section based on the signal>
   ```
   Present as a choice block: **amend** (apply edit + update `<!-- Last updated: YYYY-MM-DD -->`) | **skip** (no change).
d. If user chooses "amend": apply the edit and update the `<!-- Last updated: -->` comment at the top of the runbook file.
e. If no process signals match any runbook headings: skip silently.

Emit: `GATE [retro-completion]: PASS/CONDITIONAL_PASS — <signal count> signals captured.` Use CONDITIONAL_PASS if no signals were identified (unusual but possible).

## [mechanical] Step 7 — Auto-chain /matrix (Evolve Loop fast path)
a. **AC spot-check**: Pick one acceptance criterion from the just-closed spec. Check the corresponding file/function. State the criterion, file, and whether it satisfies. Flag drift as a process defect.
a2. **Trivial-doc exemption audit (Spec 395 AC 6)**: If the just-closed spec's frontmatter contained `Consensus-Exempt: trivial-doc — ...`:
   - Compare actual closed diff size to the trivial-doc claim:
     - File count: `git diff --name-only HEAD~1 HEAD | grep -v '^docs/sessions/\|^docs/specs/[0-9]\|^.forge/state/' | wc -l` (count source/test/doc files; exclude session log + the spec file + ephemeral state).
     - LOC count: total insertions+deletions from `git diff --shortstat HEAD~1 HEAD` for the same scope.
   - If actual file count > 2 OR LOC > 30: emit `GATE [trivial-doc-audit]: CONDITIONAL_PASS — Trivial-doc exemption was overstated: claimed ≤30 LOC across ≤2 files; actual diff was N LOC across M files. Pattern observed; no /close block (trust-at-gate-verify-at-close design).`
   - If actual within bounds: emit `GATE [trivial-doc-audit]: PASS — trivial-doc claim within bounds (M files, N LOC).`
   - If frontmatter does NOT have `Consensus-Exempt: trivial-doc`: skip silently. Most specs skip.
   - This audit is **informational/CONDITIONAL_PASS only — never blocks /close**. The pattern is "trust at gate; verify at close" per Spec 395 Req 2 + AC 6. Repeated overstatements feed the Spec 395 Req 9 sunset review (`/evolve` decision data).
b. **Backlog confirmation (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --get-backlog --format=json` and confirm the closed spec's row in the parsed JSON shows status `closed` (the helper reads frontmatter directly, so the edit from step (a) is reflected immediately regardless of rendering mode). Check if any backlog items are now unblocked.
c. Present the current top-3 ranked items from the backlog.

Emit: `GATE [matrix-completion]: PASS/FAIL — <AC spot-check result, backlog confirmation>`. FAIL if AC spot-check finds drift.

## [mechanical] Step 8 — Session log update (Spec 157, augmented by Spec 371)
Check `docs/sessions/` for a log file matching today's date. If none exists, create one from `docs/sessions/_template.md`. **Re-read the session log file now** before editing (Spec 123 — context overflow guard). Record the just-closed spec.

**Spec 371 — Summary line append (unconditional)**: After recording the structured "spec closed" entry, append exactly one line to today's session log `## Summary` section in this format:

`<HH:MM> Closed Spec NNN — N PASS / M FAIL <gate-summary>`

Where:
- `<HH:MM>`: current local time (24-hour)
- `<NNN>`: the spec just closed
- `N PASS / M FAIL`: count of GATE outcomes from this /close run (Steps 2, 4, 6, 7) classified as PASS vs FAIL. Count `CONDITIONAL_PASS` as PASS.
- `<gate-summary>`: comma-joined list of up to 3 most informative non-trivial gate-name→outcome pairs (e.g., `spec-integrity:PASS, retro-completion:CONDITIONAL_PASS, matrix-completion:PASS`). Use `—` if no gates ran (unusual).

If the session log has no `## Summary` section, create one immediately after the file's H1/title block. The append is unconditional — even when N=0 and M=0, still append (`0 PASS / 0 FAIL —`) as a presence record. Do NOT rewrite earlier Summary lines from this session — append only.

This Summary line is the structured trace `/session` Step 1c reads when synthesizing the day's narrative summary.

## [mechanical] Step 8b — EA/CI Window Scan (Spec 371)

Port `/implement` Step 8's chat-window EA/CI retrospective pattern to `/close`, with window-bounded dedup so a candidate captured at `/implement` is not double-captured here.

1. **Resolve session id**: read `.forge/state/active-tab-*.json` markers; pick the marker whose `spec_id` matches NNN (or whose `last_command_at` is most recent if no spec match). Use that marker's `session_id` as `<sid>`. If no marker exists, derive `<sid>` from the active tab registry row, or fall back to a deterministic hash of (today's date + spec NNN). Never abort on missing marker — fall back silently.
2. **Determine scan-window start**: read `.forge/state/last-eaci-scan-<sid>.json` if it exists. Use its `timestamp` field as the window start. If absent, use the time `/close` command started.
3. **Run scanner heuristics** against the chat window since the start time, plus structured entries appended since command start. Heuristics (mirrors `/implement` Step 8):
   - Operator corrections: "no, do X instead", "stop", "don't"
   - Implementation friction: "had to revert", "didn't work", "broke"
   - Surprising outcomes: "didn't expect", "turns out", "actually …"
   - Architectural insights: "pattern: …", "principle …", "rule …"
   - Gate-skips: `--no-verify`, `--force`, "skip the gate"
   - Wrong-assumption disclosures: "turns out X is …", "I was wrong about …"
4. **Output zero or more SIG-NNN drafts**, each with all three Spec 267 classification fields populated (root-cause category, wrong assumption, evidence-gate coverage). Empty/sentinel values permitted per Spec 267 (`other`, empty string, `no-applicable-gate`). Use the same draft format as Step 6.
5. **Zero-candidate path — unconditional attestation**: if scanner returns zero drafts, emit verbatim:
   `No EA/CI candidates detected since <HH:MM>. Confirm 'nothing to capture'? [Y/n]`
   Default `y` on bare Enter. Operator confirms with one keypress. Do NOT skip this prompt — it is a forcing function for the operator's read of the chat window. Per Spec 371 Constraint, no conditional-suppression heuristic is permitted here.
6. **Non-zero path**: present each SIG draft (numbered) and auto-append to `docs/sessions/signals.md` inline (no per-draft confirmation prompt — same low-ceremony pattern as Step 6).
7. **Window-bounded dedup write**: regardless of candidate count, write/update the timestamp file:
   ```bash
   mkdir -p .forge/state
   cat > ".forge/state/last-eaci-scan-${sid}.json" <<EOF
   {"timestamp":"<ISO 8601 now>","command":"/close","spec":"NNN"}
   EOF
   ```
   This caps the next /implement-or-/close window at this command's completion time, preventing the same chat range from being scanned twice in one session (Spec 371 Constraint).
8. **Watchlist linkage**: a follow-up spec is gated on `docs/sessions/watchlist.md` 4-week telemetry of attestation-y rate. No action here beyond the timestamp write — the watchlist row is checked at `/evolve`, not `/close`.

Skip silently if `forge.roles.devils_advocate.enabled: false` AND `forge.review.enabled: false` (no retrospective surface enabled at all). Otherwise this step runs unconditionally.

## [mechanical] Step 8a — Auto-commit and push (Spec 348)

This step captures the close commit AFTER all spec-mutating steps (3, 4a, 5, 6, 6a, 6b, 7, 8) have completed, ensuring a single atomic commit covers every mutation.

**Commit guard marker (Spec 257)**: Before committing, set the active-close marker so the specless commit guard allows the commit:
```bash
mkdir -p .forge/state
echo "close-NNN" > .forge/state/active-close
```

Run `git status`. If there are outstanding changes, stage relevant files and commit: "Close Spec NNN — <title>".

**Commit guard cleanup (Spec 257)**: After committing (or if no commit was needed), clear the active-close marker:
```bash
rm -f .forge/state/active-close
```

After committing, push to remote (explicit confirmation required — per AGENTS.md:127, `git push` is a second authorization-required action separate from the `/close` invocation itself):
a. Check if the current branch has a remote tracking branch: `git rev-parse --abbrev-ref @{upstream}`
b. If no remote tracking branch: skip silently with a note: "No remote tracking branch — skipping push." Stop here.
c. If a tracking branch exists: emit the following prompt verbatim and wait for an explicit operator response:

   > Push to `<remote>/<branch>`? (yes/no)

   **Compaction-boundary rule**: If a context compaction occurs between this prompt and the operator's response, re-emit the prompt. Do not treat any pre-compaction response as valid (per AGENTS.md:130-132).

d. On explicit "yes": run `git push`. Report: "Pushed to <remote>/<branch>."
e. On any other response (including "no", silence, ambiguous input, or a compaction-summary inference): abort the push with: "Push skipped — commit is local-only. Run `git push` manually when ready." Continue with the rest of `/close`.
f. If the push in step d fails: report as a warning ("Push failed: <error>. Changes are committed locally.") and continue — do not block the rest of `/close`.

## [decision] Step 9 — Pick next
a. **Closing queue**: count of remaining specs at `implemented` status. For each: `Spec NNN — <title>: run /close NNN`.
b. **Next recommended spec**: highest-ranked `draft` spec from backlog — ID, title, score, lane. Read the spec file (`docs/specs/NNN-*.md`) and extract the first sentence of its `## Objective` section — display it below the spec title as: "_<objective>_".
c. **If no draft specs exist in the backlog**: run `/brainstorm` inline to generate spec recommendations from the roadmap, signals, and scratchpad. If `/brainstorm` is not available, report: "Backlog is empty. Run `/brainstorm` or `/spec <description>` to create new specs."
d. Present a Choice Block (Spec 025, see `docs/process-kit/implementation-patterns.md`):

<!-- Spec 347 Phase 1: this choice block is declared as canonical YAML data and rendered per the renderer protocol (docs/process-kit/choice-block-renderer-protocol.md). The agent reads the fenced block, evaluates each row's `precondition` field via the documented bash one-liner from docs/process-kit/choice-block-preconditions.md, drops false-precondition rows, applies the session-data safety rule, sorts by rank, and emits a Spec 320 v2.0 markdown table. The output is byte-identical to a hand-authored v2.0 table for the same row set. -->

```choice-block
title: Pick next
rows:
  - key: implement
    rationale: Top-of-backlog ready; clean transition
    what_happens: Start /implement next (highest-ranked draft)
    rank: "1"
    precondition: backlog_has_draft_specs
  - key: close NNN
    rationale: Drain remaining implemented queue
    what_happens: Close another implemented spec (type spec number)
    rank: "2"
    precondition: implemented_specs_count_gt_zero
  - key: brainstorm
    rationale: Use when backlog is empty or stale
    what_happens: Generate new spec recommendations
    rank: "—"
    precondition: backlog_has_no_draft_specs
  - key: consensus
    rationale: Heavy review; reserve for contentious decisions
    what_happens: Defer a decision to /consensus for structured multi-role input
    rank: "—"
  - key: synthesize --topic NNN
    rationale: Capture this spec's reasoning into refined reference doc (Spec 328)
    what_happens: Run /synthesize --topic NNN where NNN is the just-closed spec ID. Mode hint defaults to --topic for the just-closed spec; if 5+ sessions have passed since the last synthesize, --postmortem is the safer alternative. --all runs all four modes.
    rank: "—"
  - key: stop
    rationale: Downgraded if today's session log has unsynthesized entries
    what_happens: End session
    rank: "—"
```

The renderer's session-data safety rule applies automatically: if `today_session_log_unsynthesized` evaluates true, a synthetic `session` row is inserted at rank 1 and `stop` is demoted to rank `—`. Operators see no change in the visible interface — only the source representation in this command file is the canonical YAML data.

e. Report: "Spec NNN is now `closed`. Commit: <done/skipped>."

Remind to update `Last evolve loop review:` in today's session log.

## [mechanical] Step 10 — Post-close context compaction (Spec 256)

After Step 9 completes, check whether automatic context compaction should trigger. This step runs silently when compaction is not needed.

1. **Read config**: Check AGENTS.md for `forge.context.optimization.level` and `forge.context.optimization.compact_threshold_pct`.
   - If the config block is absent or `level` is `minimal`: skip — no auto-compaction. Current behavior preserved.
   - If `level` is `balanced`: proceed to threshold check (step 2).
   - If `level` is `aggressive`: skip threshold check, proceed directly to compaction (step 3).

2. **Threshold check** (balanced only): Estimate whether current context usage exceeds `compact_threshold_pct` (default 60%) of the model's context window.
   - If context usage is **below** the threshold: skip compaction. Report nothing (silent skip).
   - If context usage is **at or above** the threshold: proceed to compaction (step 3).

3. **Compaction trigger**:
   a. Display status message **before** compaction begins: `Compacting context (optimization: <level>, threshold: <pct>%)...`
   b. Trigger `/compact` to summarize and reduce context.
   c. After compaction completes, the context compaction rule in AGENTS.md applies: all authorization-required commands are treated as unissued.

**Constraints**:
- This step ONLY runs after /close has fully completed (all gates passed, commit done, pick-next presented).
- No compaction occurs mid-command or during active spec work.
- The `/compact` output preserves key session state: which spec was just closed, the pick-next options, and any pending closing queue items.

---

## Next Action

Spec NNN is now `closed`. Step 9 Choice Block above presents the next options — wait for human input before proceeding to any further work.
