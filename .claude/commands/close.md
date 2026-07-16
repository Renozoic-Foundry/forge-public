---
name: close
description: "Framework: FORGE"
workflow_stage: review
---

# Framework: FORGE
# Model-Tier: sonnet
<!-- multi-block mode: serialized — choice blocks fire across distinct mechanical steps; no two blocks present in the same agent message. Each block waits for operator response before the next step proceeds. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->

**Output verbosity (Spec 225)**: read `forge.output.verbosity` from `AGENTS.md` (default `lean`). Lean mode suppresses non-actionable diagnostics (passing-gate confirmations, KPI tables, calibration deltas, MCP pin status, deprecation scans, signal dumps, root-cause groupings, unchanged score-rubric details) — full content goes to its file artifact (session log, `pattern-analysis.md`, etc.) with a one-line chat pointer (or omit if purely informational). Verbose mode emits full detail. **Never suppressed**: choice blocks, FAILed gates, push-confirmation prompts, Review Brief "Needs Your Review" items, operator-input prompts, error/abort messages. See `docs/process-kit/output-verbosity-guide.md`.

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

## [mechanical] Step 0-bl — Batch-lane contract guard (Spec 475)

Before any other step, check for `.forge/state/batch-lane.json` in the current working tree. Skip silently if no marker exists — single-tab and orchestrator sessions proceed normally.

If the marker exists and parses as JSON:
- If `created_at` is older than 24 hours: emit `⚠ Stale batch-lane marker (created <created_at>) — worktree likely abandoned; proceeding. Delete .forge/state/batch-lane.json if this lane is no longer part of a batch.` and proceed to Step 0a (warn-and-proceed — permanent refusal would brick an orphaned tab).
- Otherwise REFUSE: print the marker's `return_instruction` verbatim, then:
  `/close is forbidden inside a batch lane worktree (batch <batch_id>, spec <spec_id>, terminal state: <terminal_state>). /close runs in the orchestrator after merge.`
  STOP — do not proceed to Step 0a or any later step. This is the artifact-binding counterpart of ADR-451 (prose in the orchestrator tab does not bind lane sessions; only worktree-resident artifacts do — SIG-BATCH-A/B).

If the marker exists but is malformed JSON: REFUSE with the generic pointer `/close is forbidden inside a batch lane worktree — marker present but unreadable. Fix or deliberately delete .forge/state/batch-lane.json to override.` (Malformed still signals lane context; fail closed.)

## [mechanical] Step 0a — Evolve Loop Boundary Check (Spec 191)
Read `docs/sessions/context-snapshot.md`. If `## Active evolve loop` exists with `status: in-progress`: stop and report "Evolve loop in progress (started <started>). Solve-loop commands (/implement, /spec, /close) are blocked until the evolve loop completes. Return to the /evolve session and use the exit gate to choose your next action." Do NOT proceed. If absent or `status: complete`: proceed normally.

## [mechanical] Step 0c — Checkpoint resume detection (Spec 123)

After identifying the spec (Step 1), check for `.forge/checkpoint/close-<spec-id>.json`:

1. **Exists**: read it and display:
   ```
   ⚡ CHECKPOINT DETECTED — /close <spec-id>
   Last completed step: <step_number> — <step_description>
   Timestamp: <timestamp>
   Completed outputs: <summary>

   Resume from step <next_step>? (yes to resume, no to start fresh)
   ```
   - `yes`: skip to the step after `last_completed_step` — do not re-execute prior steps.
   - `no`: delete the checkpoint file and start from Step 2.
2. **Does not exist**: proceed normally from Step 2.

**Checkpoint write rule**: after each major step (2, 3, 4, 5, 6, 7, 8), write/update `.forge/checkpoint/close-<spec-id>.json`:
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
After each major step (2, 3, 4, 5, 6, 7, 8, 9), emit a compact progress line at the end of your output:
```
_Progress: Step <current>/9 (<step description>) | Gates: <N>/<total> | PASS: <N>, COND: <N>, FAIL: <N> | Next: <next step>_
```
Update `docs/sessions/context-snapshot.md` `## Active implementation` at steps 2, 3, and 9.

## [mechanical] Step 2 — Read and verify
Read `docs/specs/NNN-*.md` for the given spec. <!-- parallel: also read README.md + backlog.md for status checks -->
Confirm spec status is `implemented`:
- If `implemented`: emit `GATE [status-verification]: PASS — spec is at implemented status, ready to close.`
- If not `implemented`: emit `GATE [status-verification]: FAIL — spec is at '<status>' status. Remediation: run /implement NNN to reach 'implemented' status first.` Stop.

### [mechanical] Step 2 addendum — Spec integrity verification (Spec 089)

# >>> spec-344 lane-gate
LANE-GATE: Spec 089 Approved-SHA mechanism is Lane B only. Read these conditions in order:

1. **Read `Change-Lane:` from the spec's frontmatter.** Possible values: `hotfix`, `small-change`, `standard-feature`, `process-only`, `Lane-B`, missing, or unrecognized.

2. **Read `docs/compliance/profile.yaml`.** Absent → Lane A FORGE-internal project — skip Spec 089's behavior for this Step entirely: no SHA computed, no `Approved-SHA:` written/verified/cleared, no `GATE [spec-integrity]` line, no override prompt. Proceed silently to the next Step.

3. **If `docs/compliance/profile.yaml` is present:** the project declares Lane B usage. Apply the predicate:
   - `Change-Lane:` is `Lane-B`: PROCEED with Spec 089's existing behavior verbatim. Compute/verify/clear the SHA per the existing logic.
   - `Change-Lane:` is `hotfix`, `small-change`, `standard-feature`, or `process-only`: SKIP Spec 089's behavior. No GATE line, no prompt. Proceed silently.
   - `Change-Lane:` is missing or any other value (e.g., a typo like `Lane_B`): STOP. Do not proceed. Emit `GATE [spec-integrity]: FAIL — Change-Lane missing or unrecognized ('<value>') under a Lane B compliance profile. Set Change-Lane explicitly before proceeding.` HALT. Do not invoke the SHA logic. Do not transition status. Do not proceed to subsequent steps.

See: docs/process-kit/close-validator-coverage.md § Lane-gate sentinel — canonical source.
# <<< spec-344 lane-gate

If the spec has an `Approved-SHA:` field in frontmatter:

1. **Extract sections**: extract the full text of `## Scope`, `## Requirements`, `## Acceptance Criteria`, `## Test Plan` (each from its heading to the next `##`, exclusive).
2. **Combine and normalize**: concatenate in order, trim leading/trailing whitespace.
3. **Compute hash**: SHA-256 of the combined text, 64-char lowercase hex digest.
4. **Compare** to the `Approved-SHA:` value in frontmatter.
5. **Old-format SHA detection**: on mismatch, also compute a SHA-256 of Scope+ACs only (the pre-extension format). If that matches the stored hash, the spec predates the extended scope: report "Spec integrity: old-format SHA detected (Scope + ACs only). Recomputing with extended scope (Scope + Requirements + ACs + Test Plan)." Update `Approved-SHA:` to the new hash, log in the revision log: `YYYY-MM-DD: Approved-SHA recomputed from old format (Scope+ACs) to extended format (Scope+Requirements+ACs+TestPlan).` Emit `GATE [spec-integrity]: PASS — old-format SHA migrated and verified.` Continue.
6. **MATCH**: report "Spec integrity: verified", emit `GATE [spec-integrity]: PASS — SHA-256 matches approved hash.` Continue.
6. **MISMATCH**: HALT. Display:
   - "SPEC INTEGRITY FAILURE — spec was modified after approval"
   - Show the current Scope/Acceptance Criteria sections, noting they differ from the approved version (the hash can't be reversed to diff directly)
   - Emit `GATE [spec-integrity]: FAIL — SHA-256 mismatch. Approved: <stored hash>, Current: <computed hash>.`
   - Present choice:
     - **(a) "approve with modified spec"** — log override in the Revision Log: `YYYY-MM-DD: Spec integrity override — Approved-SHA mismatch accepted. Old: <stored>, New: <computed>.` Update `Approved-SHA:` to the new hash. Continue closing.
     - **(b) "halt"** — stop closing. Report: "Run /revise NNN to formally revise the spec, then /implement NNN to re-approve."

No `Approved-SHA:` field (legacy spec): skip verification silently.

<!-- module:browser-test -->
## [mechanical] Step 2b2 — Visual evidence gate (Spec 093, conditional; hard-fail added Spec 540)

**Boundary vs Spec 403 (Step 2b5)**: that gate keys on Test-Plan keywords ("smoke
test", "live dry-run"); this gate keys on Acceptance-Criteria browser verbs
(clicking, hovering, rendering, showing, displaying, scrolling) via the shared
scanner below. Different sections, different signals — no double-fire.

If browser test evidence exists for this spec (`tmp/evidence/SPEC-NNN-browser-*/manifest.json`):

1. Read the most recent manifest file (by directory date suffix).
2. Check the summary: `passed` vs `total` counts.
3. Gate outcome:
   - All passed → `GATE [browser-evidence]: PASS — <passed>/<total> UI checks passed. Screenshots: <count>, Video: <yes/no>.`
   - Any failed → `GATE [browser-evidence]: CONDITIONAL_PASS — <passed>/<total> UI checks passed, <failed> failed. Human review required for failed steps. Evidence: <dir>.`
4. If evidence exists, include the evidence directory path and summary.md link in the spec's Evidence section when updating to `closed`.

4b. **Visual-deliverable detection (Spec 545)**: independent of the AC-verb scan
   below, check whether `## Implementation Summary` / `## Scope` list an HTML or
   other rendered/visual artifact as a deliverable (paths ending `.html`/`.htm`, or
   explicit "visual artifact"/"dashboard"/"report" language) — catches deliverables
   whose ACs don't use a browser verb (e.g., "produces a summary page"). Record the
   matched deliverable(s) as `visual_deliverables` (may be empty).

5. **No manifest found (Spec 540 hard-fail, extended by Spec 545)**: run the shared
   AC-pattern scanner against the spec file:
   ```bash
   ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/ac-pattern-scanner.sh docs/specs/NNN-<slug>.md
   ```
   a. `flagged_acs` and `visual_deliverables` (step 4b) both empty → skip silently.
      Mark `[x] Visual evidence gate (Spec 093) — no browser-verb ACs and no visual
      deliverables detected, no manifest required.` Proceed.
   b. Either non-empty:
      - **`--accept-deferred-acs "<reason>"` present** in `$ARGUMENTS`: append the
        reason verbatim to the spec's Evidence section under a
        `## Operator-accepted deferral` heading (create if absent —
        `- YYYY-MM-DD: <reason>`). Distinct from `--force`: per-gate and
        reason-recorded, not a blunt bypass. Emit
        `GATE [browser-evidence]: PASS — operator accepted deferral for AC(s)/
        deliverable(s) <numbers or names>: "<reason>".` Proceed.
      - **`--force` present** (existing blunt bypass, Step 2d Override): emit
        `GATE [browser-evidence]: PASS — hard-fail bypassed via --force. Flagged
        AC(s)/deliverable(s): <numbers or names>.` Log the same signal format as
        the Step 2d Override:
        `SIG-NNN | process | Browser-evidence hard-fail overridden via --force on
        spec NNN. Flagged criteria: <AC numbers and matched patterns, and/or
        visual deliverables>.` Proceed.
      - **Neither flag present**: prompt for the render-time visual-verification
        gate (Spec 545, docs/process-kit/human-validation-runbook.md section H)
        instead of a bare failure when the trigger is `visual_deliverables`:
        `GATE [browser-evidence]: FAIL — <reason: N acceptance criteria contain
        browser-only verbs (AC <numbers>) and/or this spec's deliverables include
        a visual artifact (<file/name>)> but no browser-evidence manifest exists
        at tmp/evidence/SPEC-NNN-browser-*/manifest.json. Remediation: run
        ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-visual-verify.sh NNN
        <artifact-path> to record a render-time visual check (see runbook
        section H), or re-run /close NNN --accept-deferred-acs "<reason>" to
        explicitly accept the deferral (reason-recorded), or --force to bypass
        outright.` **This is blocking — halt the close workflow. Do not proceed
        to Step 3.**

   One gate, not two: `visual_deliverables` is an additional trigger condition
   feeding the same PASS/FAIL/override logic as `flagged_acs` — non-visual specs
   (both empty) see zero additional friction.
<!-- /module:browser-test -->

## [mechanical] Step 2b3 — Shadow validation evidence check (Spec 115, updated by Spec 129)

See: docs/process-kit/shadow-validation-guide.md (strategy selection), docs/process-kit/shadow-validation-checklist.md (execution steps).

Read the spec file's `## Shadow Validation` section:

1. Section absent, or only template placeholder comments (`<!-- Uncomment ONE strategy`): skip silently — not applicable.
2. Section exists with a **declared strategy** (an uncommented `**Strategy**:` line):
   a. Check for a filled `**Evidence**:` field (not "pending" or empty).
   b. **Determine lane**: `docs/compliance/profile.yaml` exists → Lane B; else Lane A.
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

1. **Detect signal**: search `## Evidence` for `DEPENDENCY_REVIEW_REQUIRED`. Not found → skip silently.

2. **Check for sign-off**: search for:
   - A `### Dependency Sign-off` subsection in `## Evidence` with:
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

## [mechanical] Step 2b5 — Live-smoke evidence gate (Spec 403)

Sibling to the Step 2b3/2b4 evidence checks. `/implement` Step 6e *detects* live-smoke Test-Plan steps and prompts for execution; this gate *enforces* that captured evidence exists before close — closing the synthetic-fixture-blind-spot failure mode (SIG-387-01).

1. **Load the keyword set**: read `forge.implement.live_keywords:` from `AGENTS.md`, default `live dry-run`, `smoke test`, `against the live repo`, `against FORGE-self`, `against the codebase`, `production data sample`.

2. **Scan the Test Plan**: read `## Test Plan` (including `### Cross-platform coverage`). Case-insensitive substring match against the keyword set.
   - No match: skip silently. Mark `[x] Live-smoke evidence gate (Spec 403) — no live-keyword steps in Test Plan`. Proceed.
   - One or more matches: continue to step 3.

3. **Check for captured evidence**: a `### Live-smoke evidence` subsection in `## Evidence` with at least one captured `- Output:` block (not empty, not "pending").

4. **Gate outcome**:
   - Evidence present → `GATE [live-smoke]: PASS — live-smoke evidence found for <N> Test-Plan step(s).` Proceed.
   - Test Plan flagged a live step but no `### Live-smoke evidence` present → `GATE [live-smoke]: FAIL — Test Plan contains a live-smoke step ("<matched text>") but no ### Live-smoke evidence was captured. Remediation: re-run /implement Step 6e and execute the live-smoke step (answer "yes" at the prompt), or record the output manually under ### Live-smoke evidence in the spec's Evidence section.` **This is blocking — halt the close workflow. Do not proceed to Step 3.**

## [mechanical] Step 2b6 — Plugin parity gate (Spec 463, conditional)

Sibling to the Step 2b3/2b4/2b5 evidence gates. Enforces the P1=C two-source parity
contract: the plugin payload source (`.claude/`) and the Copier source
(`template/.claude/`) MUST be byte-identical across `commands/`, `agents/`, `skills/`.

1. **Detect applicability**: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/plugin-parity-check.sh` absent
   (pre-Spec-463 projects) → skip silently. Mark `[x] Plugin parity gate (Spec 463) — not present in this project`. Proceed.

2. **Run the gate**: `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/plugin-parity-check.sh`.
   - Exit 0 → `GATE [plugin-parity]: PASS — plugin payload source and Copier source are byte-identical across the common subset.` Proceed.
   - Exit non-zero → `GATE [plugin-parity]: FAIL — byte-level drift between .claude/ (plugin payload) and template/.claude/ (Copier source). Remediation: re-sync the two sources so they are byte-identical across commands/, agents/, skills/, then re-run /close.` **This is blocking — halt the close workflow. Do not proceed to Step 3.**

<!-- module:compliance -->
## [mechanical] Step 2c — Lane B spec sealing (Spec 052, conditional)
After the status transition to `closed` (Step 3 below), if `docs/compliance/profile.yaml` exists (Lane B):
a. Add `Lane-B-Sealed: YYYY-MM-DD` to frontmatter (after `Last updated:`).
b. Add a revision entry: `YYYY-MM-DD: Spec sealed (Lane B) — content is now an immutable audit record. Future changes require a successor spec with Supersedes: NNN.`
c. Report: "Spec NNN sealed (Lane B). The spec file is now an immutable audit record."
- Absent (Lane A): skip — Lane A specs are not sealed.
- Runs AFTER Step 3, not before.
<!-- /module:compliance -->

<!-- module:compliance -->
## [mechanical] Step 2b — Lane B compliance gate check (conditional)
If `docs/compliance/profile.yaml` exists (Lane B):
a. Load the profile `gate_rules` list.
b. For each rule with `required: true`, check the evidence artifacts (`evidence_required` paths) are present in `docs/`:
   - Present → `GATE [lane-b/<gate-name>]: PASS — <evidence artifact> found.`
   - Missing, `required: true` → `GATE [lane-b/<gate-name>]: FAIL — missing: <evidence artifact>. Remediation: generate required evidence before closing.` (blocking — stop if any Lane B gate FAILs)
   - Missing, `required: false` → `GATE [lane-b/<gate-name>]: CONDITIONAL_PASS — advisory gate: <evidence artifact> missing. Non-blocking.`
c. Check `docs/compliance/profile-verification.md` for valid sign-off:
   - Present, not expired → `GATE [lane-b/profile-verification]: PASS — sign-off valid until <expiry>.`
   - Missing or expired → `GATE [lane-b/profile-verification]: FAIL — profile verification sign-off missing or expired. Remediation: update docs/compliance/profile-verification.md.` (blocking)
- Absent (Lane A): skip this step.
<!-- /module:compliance -->

### [mechanical] Step 2d — Validator Gate (Spec 078, updated by Specs 083, 099)

Before transitioning to closed, spawn an independent validator to verify acceptance criteria.

1. Check AGENTS.md `forge.roles.validator.enabled`. `false`/absent → skip silently.

2. Spec's change-lane in `forge.roles.validator.skip_lanes` → skip with note "Validator skipped for <lane> lane."

2b. **Check `forge.roles.separation`** in AGENTS.md (Spec 099):
   - `context-scoped`/`full`: all validator agents (two-stage and fallback) MUST be spawned as **isolated** sub-agents receiving ONLY the spec file, current codebase, test results, and role/review instructions — no conversation history, implementer reasoning, DA findings, or commit messages (independent judgment, free from confirmation bias). Use `model` from `forge.roles.validator.model` if set.
   - **Side-effect doctrine in every dispatch prompt (Spec 536)**: the validator is read-only including via Bash — accidental writes are restored by content rewrite or surfaced-and-stopped, never via `git checkout --`/`reset`/`restore` (authorization-gated classes; SIG-520-02). The prompt also states the evidence-blind rule: build own fixtures, never inherit the spec's Evidence section as proof.
   - `none` (default): spawn validator agents in the current context.

2c. **Role state file lifecycle (Spec 100)**: before spawning any validator sub-agent, write the role state file to activate hook-enforced write blocking (the PreToolUse hook in `.claude/settings.json` blocks Write/Edit/NotebookEdit while active):
   ```bash
   mkdir -p .forge/state
   cat > .forge/state/active-role.json << 'EOF'
   {"role":"validator","spec":"NNN","started":"<ISO 8601 now>","read_only":true}
   EOF
   ```
   After all validator sub-agents complete (any outcome), delete it to lift restrictions:
   ```bash
   rm -f .forge/state/active-role.json
   ```

3. **Check two-stage review config**: Read AGENTS.md for `forge.review.enabled`.

4. **If `forge.review.enabled` is `true`**: Use the two-stage review protocol as the validator's review method.

   a. **Stage 1 — Spec Compliance Review** (if `spec_compliance` in `forge.review.stages`):
      - Spawn a read-only review agent with: the spec file, the full codebase diff since the spec's `in-progress` date, test results, and instructions from `.forge/templates/review-checklists/spec-compliance.md`.
      - Agent produces structured JSON findings.
      - PASS/WARN: proceed to Stage 2 (WARN also logs findings).
      - FAIL: emit `GATE [validator/spec-compliance]: FAIL — <findings summary>`. Stop (do not proceed to Step 3).

   b. **Stage 2 — Code Quality Review** (if `code_quality` in `forge.review.stages`):
      - Spawn a separate read-only review agent with: changed files (full content), test files, test results, and instructions from `.forge/templates/review-checklists/code-quality.md`. Do NOT provide the spec file (context isolation — Stage 2 reviews code on its own merits).
      - Agent produces structured JSON findings.
      - PASS/WARN: proceed.
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

5. **If `forge.review.enabled` is `false` or absent**: fall back to existing validator behavior.

   a. Read `.claude/agents/validator.md` for the role preamble.

   a2. **Stage-1 scanner pre-check (Spec 540)**: run the shared AC-pattern
       scanner and fold its output into the validator prompt (the validator has
       no Bash tool, so the prompt carries the findings rather than the
       subagent re-deriving them):
       ```bash
       ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/ac-pattern-scanner.sh docs/specs/NNN-<slug>.md
       ```
       For each `flagged_acs` entry, check whether
       `tmp/evidence/SPEC-NNN-browser-*/manifest.json` exists. Build
       `{ac_number, text, pattern, evidence: "verified"|"missing"}`. Empty
       `flagged_acs` → empty list, Stage 1 is a no-op (clean specs see no
       behavior change).

   a3. **Spec-copy redaction (Spec 548)**: produce the redacted spec copy the
       validator receives — implementer-authored proof sections (`## Evidence`,
       `## Disposition Record`, `## Devil's Advocate Findings`) are stripped
       mechanically so the evidence-blind rule no longer depends on prompt
       compliance (SIG-532-04, SIG-535-02):
       ```bash
       mkdir -p tmp/evidence/SPEC-NNN-YYYYMMDD
       ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/spec_redact.py \
         docs/specs/NNN-<slug>.md -o tmp/evidence/SPEC-NNN-YYYYMMDD/NNN-redacted.md
       ```
       The validator prompt below references the REDACTED copy, not the
       original. Also pre-compute the runnable-command AC list (shared matcher
       — the Spec 550 scanner is the single command-detection source):
       ```bash
       ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/ac-pattern-scanner.sh docs/specs/NNN-<slug>.md runnable \
         > tmp/evidence/SPEC-NNN-YYYYMMDD/runnable-acs.json
       ```

   a4. **Orchestrator-run execution evidence (Spec 556)**: the `forge:validator` agent is read-only
       (no Bash — can't execute a suite), so when `runnable-acs.json` is **non-empty** the
       ORCHESTRATOR (this /close context, which holds Bash) runs the command(s) the Test Plan
       names for each flagged AC, **fresh** — never reusing the implementer's reported output (Spec 536
       evidence-blind doctrine: evidence must be freshly derived, never inherited from `## Evidence`).
       Capture exit code + stdout/stderr per AC to
       `tmp/evidence/SPEC-NNN-YYYYMMDD/orchestrator-run.txt`, tagged with the AC number(s):
       ```
       === AC<N>: <command> ===
       <verbatim stdout/stderr>
       exit code: <code>
       ```
       Inject each tagged block into the validator prompt below as authoritative execution evidence
       for that AC. A command that FAILS to run in the orchestrator (missing script, wrong dir, shell
       mismatch) is a close-blocker — surface it and halt, never fall through to "no evidence".
       `runnable-acs.json` empty → skip a4 entirely.

   b. Spawn a validator sub-agent with the following prompt structure:
      ```
      [Role preamble from validator.md]

      You are validating: tmp/evidence/SPEC-NNN-YYYYMMDD/NNN-redacted.md
      (a redacted copy of docs/specs/NNN-<slug>.md — implementer proof sections
      are withheld by design; form your own evidence)

      Stage 1 — Behavioral/browser-verb AC check (Spec 540, pre-computed):
      <flagged-ac-list from step a2, or "none — scanner found no flagged ACs">
      For any AC in this list with evidence: "missing", you MUST hard-FAIL that
      criterion and name its AC number in criteria_results, regardless of any
      other evidence you find — a browser-verb/behavioral AC without a recorded
      browser-evidence manifest is not independently verifiable. For any AC
      with evidence: "verified", report it as PASS with
      `"browser_evidence": "verified"` in that criterion's result object so the
      distinction from an ordinarily-verified AC is visible in the report.

      Orchestrator-run execution evidence (Spec 556, when present):
      <the AC-tagged orchestrator-run blocks from step a4, or "none — no runnable-command ACs">
      These blocks are FRESH orchestrator runs of the commands your runnable-command ACs name.
      Treat the exit-code and pass/fail facts as authoritative (you have no Bash to re-run them).
      For each such AC, copy the matching tagged block's exit code + output excerpt into THAT
      criterion's own `notes` (or `test_output`) field — not a shared report-level field — so the
      execution-evidence post-check can bind the evidence to the specific AC. You MAY still flag
      anomalous or suspicious content within a captured block (it is raw stdout/stderr) rather than
      trusting it blindly — surface any anomaly in the criterion notes.

      Read the spec file's Acceptance Criteria section. For each criterion:
      1. Read the relevant code/files in the codebase
      2. Determine if the criterion is satisfied
      3. Record your finding

      IMPORTANT: You are performing INDEPENDENT validation. You have NO context about how the implementation was done or why. Judge only by what you observe in the spec and codebase.

      IMPORTANT: Do NOT read or consider the `## Evidence` section of the spec file. The Evidence section was written by the implementing agent and could anchor your judgment. Form your own evidence by examining the codebase, running tests, and reading the actual files directly. Base your findings solely on what you observe, not on what the implementer reported.

      IMPORTANT: You are READ-ONLY. You may use Read, Glob, and Grep. You have NO Bash and NO Write/Edit tools — you do NOT run test suites yourself; execution evidence for runnable-command ACs is provided above as fresh orchestrator-run blocks (Spec 556). Do not attempt to modify any file.

      Produce your output as a JSON code block with this structure:
      {
        "validation_result": "PASS" | "FAIL",
        "criteria_results": [
          {"criterion": "AC text", "file": "path", "method": "code review|test|manual", "result": "PASS|FAIL", "notes": "...", "browser_evidence": "n/a|verified|missing"}
        ],
        "test_output": "summary of any test results",
        "summary": "One paragraph assessment"
      }
      ```

   c. Parse the validator's JSON output.

   c2. **Execution-evidence post-check (Spec 548)**: write the parsed report to
       `tmp/evidence/SPEC-NNN-YYYYMMDD/validator-report.json`, then run:
       ```bash
       ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/validator_evidence_postcheck.py \
         --spec docs/specs/NNN-<slug>.md \
         --report tmp/evidence/SPEC-NNN-YYYYMMDD/validator-report.json \
         --scanner-json tmp/evidence/SPEC-NNN-YYYYMMDD/runnable-acs.json
       ```
       - Exit 0: proceed to step d/e on the validator's own verdict.
       - Exit 1: the report PASSes a runnable-command AC without execution evidence
         (or an evidence-blind citation). Emit
         `GATE [validator]: FAIL — execution-evidence post-check: <each failure's ac_number + reason>.`
         (names the AC + missing element so the retry is one-shot per Spec 548 AC5). Treat as a
         validator FAIL (step e) even if `validation_result` was PASS.
       - Exit 2: input error — surface stderr; fall back to the validator verdict with a WARN note.
       Honesty (Spec 548 AC4): the post-check verifies evidence PRESENCE, not truthfulness — a
       lint-level speed bump, not a hard trust boundary. At L3/L4 this stays designed-not-enforced
       until the managed-settings trust root lands (ADR-453 §6.1); evidence-to-tool-call trace
       binding is the named follow-up.

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

After the validator gate completes, check `forge.dispatch_rules.enabled` in AGENTS.md. `false`/absent → skip.

If enabled:
1. **Skip threshold check**: read the spec's E and R scores. E ≤ `skip_threshold.effort` AND R ≤ `skip_threshold.risk` → skip. Report: "Close dispatch: skipped (E=<e>, R=<r> — below threshold)."

2. **Evaluate dispatch conditions** (same rules as /implement Step 2b+): `cross_cutting` → CTO, `security` → CISO, `lane_b` / `high_risk` → CQO, `high_effort` / `process_only` → CEfO.

3. **Dispatch**: for each selected role (1-3 max), spawn an isolated sub-agent with the role preamble and the spec file, in **parallel**. Each produces a closing advisory (3-5 sentences).

4. **Present advisory output**: display role review blocks. Advisory only — does not block close.
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

6. **Role-value instrumentation (Spec 305)**: for each dispatched closing-advisory role, append one `role-dispatch` record to the shared score-audit sink:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh record-dispatch NNN close <role> <recommendation> <confidence> "<key concern>"
   ```
   Map Recommendation (`PROCEED|REVISE|BLOCK`) and Confidence verbatim. Best-effort — the helper always exits 0, never blocks /close. (PowerShell: `pwsh ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.ps1 record-dispatch ...`.) `Detection: active`.

### [mechanical] Step 2d+a — Operator-Acceptance Capture (Spec 305)

After the closing advisory (Step 2d+) and BEFORE the commit, capture whether the operator
acted on the advisory role recommendations fired across this spec's lifecycle (`/spec`,
`/implement`, `/close`, `/consensus`) — a measurable accept/ignore signal
(`score-audit.sh role-audit` rolls it up). Conditional + non-blocking.

1. **Read prior dispatches**: list `role-dispatch` records for this spec —
   `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh read-records NNN | grep '"kind":"role-dispatch"'` — and collect
   the distinct advisory roles that fired (Spec 187 dispatch roles + Review-Router perspectives;
   the DA gate and Validator are gates, not advisories — exclude them).
   - `N` = count of distinct advisory roles with ≥1 dispatch for this spec.
   - **`N = 0`: skip silently.** No prompt, no records (the common case for small specs).

2. **If `N ≥ 1`**, present a single choice block (not one prompt per role):
   ```
   ## Operator-Acceptance Capture (Spec 305)
   N advisory role recommendation(s) fired during Spec NNN's lifecycle:
   <role> (<stage(s)>, last recommendation: <rec>) — key concern: <concern>
   ...
   For each, did you act on it? Mark `accepted | ignored | partial | skip-all`.
   ```
   > **Choose** — type a number or keyword:
   > | # | Rank | Action | Rationale | What happens |
   > |---|------|--------|-----------|--------------|
   > | **1** | 1 | `accepted` | You acted on the recommendations | Record `accepted: true` per role |
   > | **2** | — | `ignored` | You consciously did not act | Record `accepted: false` per role |
   > | **3** | — | `partial` | Acted on some / partially | Record `accepted: null` + a one-line `partial_note` per role |
   > | **4** | — | `skip-all` | No-friction opt-out | Record nothing; proceed (no error) |

   Per-role granularity is allowed (operator may answer e.g. "CTO accepted, CEfO ignored").

3. **Write acceptance records** (single-shot append; latest-entry-wins per R7 — no supersede chain):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh record-acceptance NNN <role> <true|false|null> ["<partial_note>"]
   ```
   One fresh `role-acceptance` record per advisory role (`skip-all` writes nothing). Best-effort — the
   helper always exits 0, so `skip-all` and a non-writable sink both proceed without error. Never a
   blocking gate. (PowerShell: `pwsh ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.ps1 record-acceptance ...`.)
   `Detection: active`.

### [mechanical] Step 2g — Shadow-Mode Gate Comparison (Spec 277, Phase 1)

See `docs/process-kit/gate-comparison-methodology.md` for the shadow-run rationale and the Phase 2 decision criteria. This step silently captures timing, token, and raw-findings data from three review gates — `/ultrareview`, Validator Stage 2 (Code Quality), and the DA role-registry review — for later offline comparison. **Zero user-visible behavior change**: findings never surface in the Review Brief, are never logged to stdout, and never block `/close`.

**Shared instrumentation wrapper** (used in Steps 2d, 2f, and this step): when invoking `/ultrareview`, Validator Stage 2, or the DA role-registry review, wrap the sub-agent call to capture `{duration_s, tokens, severity_counts, raw_output}`. Records metadata only — never alters return values or downstream flow.

1. **Trigger evaluation** — read spec front-matter. Proceed with shadow invocation only if ALL hold:
   - At least one of: `Consensus-Review: true`; OR `BV >= 4` AND spec scope mentions external interface / API / CLI contract; OR `R >= 4`.
   - `Change-Lane:` is NOT `hotfix` and NOT `process-only`.
   - `--skip-ultrareview` flag is NOT present in $ARGUMENTS.
   - Spec has a committed diff since it went `in-progress`.

   Any check fails → record the skip reason (`hotfix`, `process-only`, `operator-skip`, `not-triggered`, `no-diff`) and proceed to step 4 (persistence-only).

2. **Persistence setup** — create `.forge/state/gate-comparison/<spec-id>/` if absent. The parent dir is gitignored.

3. **Silent `/ultrareview` invocation** (only if triggered and not skipped):
   - Invoke Claude Code's built-in `/ultrareview` against the spec's committed diff, wrapped with the shared instrumentation wrapper.
   - **Capture only — do not display.** No `GATE [...]` line, no Review Brief section, no stdout findings.
   - Sub-agent error: record `{skipped: true, skip_reason: "ultrareview-error: <short error>"}` and proceed — errors must not cascade into `/close`. Non-Claude-Code agents where `/ultrareview` is unavailable record `{skipped: true, skip_reason: "ultrareview-error: command-not-available"}` and proceed silently — Validator Stage 2 and DA captures still complete.

4. **Write per-gate persistence files** under `.forge/state/gate-comparison/<spec-id>/`:
   - `ultrareview.json`: `{gate: "ultrareview-shadow", spec_id, timestamp, duration_s, tokens, severity_counts, raw_output}` — or `{gate: "ultrareview-shadow", spec_id, timestamp, skipped: true, skip_reason}` if skipped.
   - `validator-stage2.json`: same schema with `gate: "validator-stage2"`, populated from the Step 2d Validator Stage 2 wrapper capture.
   - `da.json`: same schema with `gate: "da"`, populated from the Step 2f DA role-registry review wrapper capture (or `{skipped: true, skip_reason: "role-registry-absent"}` if Step 2f was a silent skip).

5. **Silent one-line debug note** (debug logs only): `shadow-gate-comparison: spec=<NNN> triggered=<true|false> skip_reason=<reason or "">`. Must not appear in `/close` stdout.

6. **Session sidecar logging** — append to the session JSON sidecar's `gate_outcomes` array a `{gate: "ultrareview-shadow", result: "PASS", duration_s, severity_counts, skipped, skip_reason, comparison_dir: ".forge/state/gate-comparison/NNN/"}` entry. Extend the existing Validator Stage 2 and DA gate entries in-place with `duration_s`/`tokens` from the wrapper capture. Schema: `.forge/templates/session-handoff-schema.json`.

7. **No gate outcome emitted to operator** — silent by design: no `GATE [...]` line, no Review Brief content. AC #3 (Review Brief diff-identical to a non-shadow close) guards this.

**Constraints reminder**:
- MUST NOT surface `/ultrareview` findings in any operator-visible channel in Phase 1.
- MUST NOT block `/close` under any circumstance in Phase 1.
- MUST NOT add or read `Ultrareview:` / `Ultrareview-Blocking:` spec front-matter fields (no such fields exist in Phase 1).

### [mechanical] Step 2d++ — Template/FORGE Dual-Check (Spec 188, upgraded by Spec 180)

Before generating the Review Brief, actively verify bidirectional sync:

**Detection logic**: run `git diff --name-only <spec-baseline>..HEAD`. For each changed file:
- Under `template/.claude/commands/`, `template/.forge/commands/`, `template/.claude/agents/`, `template/docs/process-kit/`, `template/docs/QUICK-REFERENCE.md`, `template/bin/`, or `template/scripts/`: check for a corresponding own-copy at `.claude/commands/`, `.forge/commands/`, `.claude/agents/`, `docs/process-kit/`, `docs/QUICK-REFERENCE.md`, `bin/`, or `scripts/` (same filename, ignoring `.jinja`).
- Under `.claude/commands/`, `.forge/commands/`, `.claude/agents/`, `docs/process-kit/`, `bin/`, `scripts/`, or `docs/QUICK-REFERENCE.md`: check for a corresponding template file.

**Evaluation**:
- No dual files in the changed set: mark `[x] Template/FORGE dual-check — no dual files changed`. Proceed silently.
- Dual files found, both sides changed: mark `[x] Template/FORGE dual-check — both sides updated`. Proceed silently.
- Only one side changed (drift detected):

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

  - `sync`: copy each drifted file's changes to the other side. Re-run the check to confirm sync.
  - `intentional`: append to the Revision Log: `YYYY-MM-DD: Template/FORGE dual-check: drift noted as intentional for <files> — <reason>.` Proceed.
  - `block`: report "Close blocked — resolve template/own-copy drift and re-run /close." Stop.

### [mechanical] Step 2d^2 — Single-source parity gate (Spec 480 / NC-1a)

The repo-root tree is the single canonical source; both the plugin payload (`.claude/commands/`) and the `template/` Copier surface are generated downstream. This gate mechanically enforces that no canonical source was edited without regenerating its downstream surfaces — the machine-checked backstop to the prose dual-check above.

Run `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-parity.sh --check`. Delegates to the two existing sync scripts' `--check` modes (`.claude/commands/` body-equivalence per Spec 329; `template/` mirror byte-equivalence; `.jinja` Copier-var files excluded per Spec 281/390). Bounded runtime — no Copier re-render.

**win32 timeout convention (Spec 554)**: this check measures >2 minutes on win32 Git Bash (spawn-bound; profiled 2026-07-13). Invoke with an explicit generous timeout (≥5 min) or `run_in_background` — never a bare foreground call inheriting the 2-minute default. **Result-check-before-proceed (mandatory)**: a backgrounded run MUST be polled to completion and its exit code read before this gate is evaluated — a non-zero exit is a gate FAIL exactly as if it ran foreground. Never advance with the check still running or its exit code unread.

**Evaluation**:
- Exit 0: mark `[x] Single-source parity — canonical and generated surfaces in sync`. Emit `GATE [single-source-parity]: PASS.` Proceed silently.
- Non-zero: the gate output names the drifted surface(s) (`.claude/commands/` and/or `template/` mirrors). Present:
  ```
  SINGLE-SOURCE PARITY DRIFT — A canonical source file was edited without regenerating its downstream surface(s):
  <drifted surface list from forge-parity.sh --check output>

  Regenerate downstream surfaces from canonical before closing.
  ```
  > **Choose** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `regen` | Restores parity from canonical; safest default | Run `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-parity.sh` (no flags), then re-run `--check` to confirm |
  > | **2** | — | `block` | Manual fix path; use only if regen is unsafe | Block close until parity is restored manually |

  - `regen`: run `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-parity.sh`, then re-run `--check`. Exit 0 → emit `GATE [single-source-parity]: PASS — regenerated.` Proceed.
  - `block`: report "Close blocked — resolve single-source parity drift (run forge-parity.sh) and re-run /close." Stop.

### [mechanical] Step 2d^3 — Autopilot-envelope validation (Spec 531)

Run `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/check-autopilot-envelope.sh`. Always-strict, BLOCKING — the
lint layer of the ADR-531 envelope (declarative surface; the harness authorization list + push guard
remain the enforcement primitives).

**Evaluation**:
- Exit 0: emit `GATE [autopilot-envelope]: PASS.` Proceed silently (also the absent-block
  consumer case — the validator is silent-safe).
- Exit 2 (unparseable block — fail closed), 3 (scheduled enabled without a matching
  `/config-change` audit entry naming `forge.autopilot.scheduled` with `Outcome: applied`),
  or 4 (unknown key / invalid value): emit `GATE [autopilot-envelope]: FAIL — <validator
  stderr>. Remediation: exit 3 → run the 3-step consent runbook in
  authority-constitution-guide.md; exit 4 → new fields require a spec, not a config edit;
  exit 2 → repair the YAML block.` **Stop close** — do not proceed.

### [mechanical] Step 2d+++ — Consumer-Propagation Check (Spec 303)

After the template/FORGE dual-check passes, verify that any documentation referenced from template command files will actually reach consumer projects. Catches the Spec 299 defect class: a new `docs/<path>.md` linked from a `template/.../command.md`, but neither mirrored into `template/docs/` (Copier ships nothing) nor listed in `scripts/sync-to-public.sh`'s `PUBLIC_DOC_FILES` whitelist (forge-public receives nothing) — leaving every consumer with a broken pointer.

**Scope**: runs only when the closing spec's Implementation Summary `Changed files` list contains at least one path matching `template/.claude/commands/*.md` or `template/.forge/commands/*.md`. None found: mark `[x] Consumer-propagation check — no template command files in scope`. Emit `GATE [consumer-propagation]: PASS — no template command files changed.` Proceed silently.

**Detection logic**: for each changed file matching `template/(.claude|.forge)/commands/*.md`:
1. Extract markdown link targets under `docs/` via `\[[^\]]+\]\((docs/[^)#\s]+\.md)(?:#[^)]*)?\)`, stripping any `#anchor` suffix.
2. Deduplicate targets across all scanned template command files.
3. For each target `docs/<path>`:
   a. Check whether `template/docs/<path>` exists.
   b. If not, check whether `docs/<path>` appears in the `PUBLIC_DOC_FILES=( ... )` array in `scripts/sync-to-public.sh` (`grep -F "docs/<path>" scripts/sync-to-public.sh` scoped to the array block).
   c. Neither present: record as a violation, noting the referencing template command file(s).

**Evaluation**:
- No violations: mark `[x] Consumer-propagation check — all doc links propagate`. Emit `GATE [consumer-propagation]: PASS — <N> doc link(s) verified across <M> template command file(s).` Proceed silently.
- Violations found:

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

  - `sync`: `mkdir -p template/docs/<dirname>` then `cp docs/<path> template/docs/<path>`. Re-verify — check passes for this violation.
  - `whitelist`: edit `scripts/sync-to-public.sh` to add `"docs/<path>"` inside the `PUBLIC_DOC_FILES=( ... )` array block. Re-verify — check passes.
  - `skip`: prompt for a one-line reason, append to the Revision Log: `YYYY-MM-DD: Consumer-propagation check: skipped for docs/<path> — <reason>.`

  After iterating all violations:
  - All resolved via `sync`/`whitelist`: emit `GATE [consumer-propagation]: PASS — <N> violation(s) resolved (<sync count> synced, <whitelist count> whitelisted).` Proceed.
  - Any resolved via `skip`: emit `GATE [consumer-propagation]: CONDITIONAL_PASS — <N> violation(s) skipped with documented reason.` Proceed.
  - Any unresolved: emit `GATE [consumer-propagation]: FAIL — <N> unresolved violation(s). Remediation: mirror the doc under template/docs/, add docs/<path> to PUBLIC_DOC_FILES, or explicitly skip with reason.` Stop close.

### [mechanical] Step 2d+++b — Public-doc freshness stamp (Spec 509)

When the closing spec changed a documented public surface (a slash command, an AGENTS.md config block, or an install/distribution path), stamp the mapped public doc's Spec 278 `Last verified:` marker STALE so `/now`'s freshness surfacer flags it and `/evolve` sees chronic deferral. **Signal only** — never blocks close, never prompts, never edits doc content beyond the marker line.

**Scope**: reuse the changed-files list already computed by the Step 2d++/2d+++ detection logic (the Spec 188/303 scan against `<spec-baseline>`) — do NOT run a new traversal. `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/freshness.sh` absent: mark `[x] Doc-freshness stamp — helper absent`. Proceed silently.

**Execution**: pass that same list (as arguments or stdin) to the Spec 278 marker helper, which owns the single machine-readable copy of the Spec 511 canonical surface→doc mapping (validator-side assertions on the same doc set live in `scripts/validate-public-docs.sh` Sections 6–7) — do not re-inline the mapping here:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/freshness.sh stamp --spec <NNN> --baseline <spec-baseline> -- <changed-files list from Step 2d++>
```

**Evaluation** (always exit 0 — no gate outcome, no Review Brief content; surfacing is `/now`'s job):
- Helper printed `STAMPED <doc> — <reason>` line(s): mark `[x] Doc-freshness stamp — <N> public doc(s) stamped stale`. Include the stamped doc file(s) in the close commit's explicit path list.
- Helper printed nothing: mark `[x] Doc-freshness stamp — no documented surface changed`. Proceed silently.

### [mechanical] Step 2d++++ — Gate-mediation drift gate (Spec 444 Req 8a/8c)

When a spec touches `copier.yml` to add a new `validator:`, a new `_tasks:` entry, or a new `secret: true` runtime token, the corresponding gate kind MUST be modeled in `template/.forge/lib/stoke/gates.py` so `/forge stoke` can mediate it in chat (Spec 444). Convention statements alone have a sub-6-month half-life (Specs 427/431 violated mirror-sync conventions inside that window), so this gate enforces it mechanically.

**Scope**: runs only when the closing spec's committed diff against the spec baseline modifies at least one of:
- `copier.yml` (or `template/copier.yml`)
- `template/.forge/lib/stoke/gates.py` (or its `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke/gates.py` own-copy mirror)

Neither file in diff: mark `[x] Gate-mediation drift gate — no copier.yml / gates.py changes in scope`. Emit `GATE [gate-mediation]: PASS — no surface in scope.` Proceed silently.

**Exemption**: `Gate-Mediation-Exempt: <≥30-char rationale>` in the closing spec's frontmatter skips the gate: emit `GATE [gate-mediation]: SKIP — Gate-Mediation-Exempt: <reason snippet>`. Usage is logged for Spec 444 AC 11 telemetry (CTO: ≥2 specs in a 30-day window escalates as a cultural-drift signal).

**Detection logic** (Req 8a):

1. Compute the diff: `git diff <spec-baseline>..HEAD -- copier.yml template/copier.yml`.
2. Scan the added lines for tokens indicating a new gate surface:
   - `^\+\s*validator\s*:` — new validator declaration
   - `^\+\s*-` immediately following a `_tasks:` header in the added range — new task entry
   - `^\+\s*secret\s*:\s*true` — new runtime secret token
3. Apply the YAML-adversarial fixture set (AC 9a) during test runs — anchors (`&anchor`), aliases (`*alias`), and folded scalars (`>`) inside `validator:` declarations MUST be detected as additions. Fixtures: `.forge/tests/test_stoke_gates.py`.
4. Any new-gate token found:
   a. Compute `git diff <spec-baseline>..HEAD -- template/.forge/lib/stoke/gates.py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke/gates.py`.
   b. Empty diff (gates.py NOT modified): emit `GATE [gate-mediation]: FAIL — copier.yml adds a new validator/_tasks/secret surface but template/.forge/lib/stoke/gates.py was not extended. Remediation: extend detect_gates() to model the new gate, OR add 'Gate-Mediation-Exempt: <≥30-char rationale>' to the spec frontmatter.` Stop close.
   c. gates.py WAS modified: proceed to the fixture-rotation check (Req 8c).

**Fixture-rotation check** (Req 8c):

When `gates.py` itself is modified, the smoke-test fixture at `template/.forge/tests/test_stoke_mediation_coverage.py` MUST also update so the deliberately-unmodeled token rotates — otherwise the test decays to tautology (would PASS against a now-modeled gate).

1. Compute `git diff <spec-baseline>..HEAD -- template/.forge/lib/stoke/gates.py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke/gates.py`.
2. If non-empty, also check `git diff <spec-baseline>..HEAD -- template/.forge/tests/test_stoke_mediation_coverage.py .forge/tests/test_stoke_mediation_coverage.py`.
3. `gates.py` changed AND the fixture's `LAST-ROTATED:` marker not updated (absent from the added-lines diff): emit `GATE [gate-mediation]: FAIL — gates.py was modified but test_stoke_mediation_coverage.py's LAST-ROTATED marker was not updated. The smoke-test fixture must rotate to a still-unmodeled token (Spec 444 Req 8c) — otherwise the unknown-validator coverage test decays to tautology. Remediation: update the CURRENT-FIXTURE-TOKEN and LAST-ROTATED comment in test_stoke_mediation_coverage.py.` Stop close.
4. Both files updated in the same spec: emit `GATE [gate-mediation]: PASS — gates.py extended AND fixture rotated.` Proceed.

**Telemetry hook** (AC 11):

Each gate firing records a single JSONL line to `docs/sessions/activity-log.jsonl`:
```json
{"timestamp":"<ISO 8601>","event_type":"gate-mediation-check","spec_id":"<NNN>","decision":"PASS|FAIL|SKIP","exemption_reason":"<empty | reason snippet>"}
```
The `exemption_reason` field is non-empty only when the `Gate-Mediation-Exempt:` exemption was used; `/insights` and `/brainstorm` watchlist scans count occurrences per 30-day window.

## [mechanical] Step 2e — Generate Review Brief (Spec 160)

After all Step 2 gates complete, generate the Review Brief — the primary output for human review.

1. **Collect all gate results** from Steps 2, 2b, 2b2, 2b3, 2b4, 2c, 2d above. Categorize using `docs/process-kit/gate-categories.md`:
   - Machine-verifiable → "Machine-Verified" section
   - Human-judgment-required → "Needs Your Review" section
   - Confidence-gated → by confidence level (HIGH → Machine-Verified; MEDIUM → Machine-Verified with note; LOW → Needs Your Review)

2. **Scan the spec scope** for human-judgment triggers:
   - User-facing commands or onboarding flows → UX judgment item
   - README, articles, or external-facing content → external content item
   - Physical-world recommendations or hardware → Physical Logic Check item
   - Auth, security, or credentials → security review item (always human-judgment, not just confidence-gated)
   - Novel pattern (first time doing something like this) → novel situation item
   - Irreversible external actions (push, publish) → irreversible action item

2b. **LOC proportionality signal** (Spec 252): read the Stage 2 code quality reviewer's metrics (`new_lines_of_code`, `files_modified`, `files_in_scope`) and the spec's E score. Include a proportionality line: "Implementation size: N lines across M files (spec E=X)." If disproportionate to E/scope, escalate to "Needs Your Review": "Review for over-engineering — implementation is larger than expected for E=X." Qualitative judgment, not a mechanical threshold.

3. **Output the four-part operator summary** (Spec 497 — lean by default; honors `forge.output.verbosity`). Replaces the prior three-section Review Brief layout while preserving every fact it carried, plus a value-link and decision pros/cons the old format lacked. See `docs/process-kit/operator-summary-guide.md`.
   ```
   ## Review Brief — Spec NNN

   ### 1. Accomplished & machine-verified
   <one line: what shipped> — <N> gates PASS.
   - [x] <check description> — <gate result>
   (medium-confidence items noted: "(medium confidence — override if concerned)")

   ### 2. Needs human validation
   <bullet checklist — each item is a single tick the human can verify; if nothing needs human judgment, state "Nothing requires human judgment — all ACs machine-verified.">
   - [ ] **[Category]** <what to verify> — Expected: <…>; Actual: <… / file ref>; AI assessment: <why AI can't be certain>
   - [ ] **[Category]** …

   ### 3. Why it matters
   <1-2 lines linking the deliverable to the spec's ## Objective — and to the PRD / security / compliance posture when the scope touches them>

   ### 4. Recommended next actions
   <When a decision is open: ≥2 options, each with pros/cons, then a named recommendation. When no decision is open: the single recommended next step.>
   - Option A — <action>. Pros: <…>. Cons: <…>.
   - Option B — <action>. Pros: <…>. Cons: <…>.
   - **Recommendation**: <named option> — <one-line why>.
   ```

   - **Part 1** is sourced from the machine-verifiable gates in step 1 (plus the LOC-proportionality line from 2b). **Part 2 — "Needs human validation" — is the canonical "Needs Your Review" set**: items 4-7 below populate it; render each as a tick, not prose. **Part 3** ties the close to the spec's `## Objective` (and security/compliance when in scope). **Part 4** carries decision pros/cons + a named recommendation; collapses to a single next step when no decision is open.
   - **Verbosity (AC6)**: `lean` (default) lists Parts 1-2 tersely and Part 4 without expanded sub-detail — machine-handled inventory omitted from chat ("show <item>" expands one). `verbose` expands every machine-handled item inline with the full Expected/Actual/AI-assessment/Verify block per Part-2 item. Both modes carry the same four labeled sections.

4. **Physical Logic Check** (Spec 160, Requirement 13-15): if the spec scope involves physical-world recommendations, real-world actions, hardware interactions, or cause-and-effect chains in the physical world, include a dedicated item in "Needs Your Review":
   ```
   N. **[Physical Logic Check]** (AI reasoning about physical constraints can miss obvious prerequisites)
      - Real-world action: <the recommendation or action>
      - Physical prerequisites identified: <what the AI thinks is needed>
      - AI assessment: AI cannot reliably self-assess physical reasoning accuracy.
      - Verify: Does this make physical/practical sense? Check for missing prerequisites any human would catch.
   ```
   This check is ALWAYS human-judgment-required — cannot be delegated regardless of autonomy level.

5. **Review fatigue management** (Spec 160, Requirements 23-25): if 5+ "Needs Your Review" items:
   a. Prioritize: irreversible actions, LOW confidence items, physical logic checks, UX/aesthetic items, everything else.
   b. Check AGENTS.md for `forge.review.budget`. If set (e.g., "5 minutes"), present only the top-priority items and defer the rest:
      ```
      <N> lower-priority items deferred to respect review budget.
      Say "show all" to review them, or "approve deferred" to accept AI assessment.
      ```
   c. No `forge.review.budget` set: present all items (full review).

6. **Trust signal recording** (Spec 160, Requirement 20): after the human reviews the brief:
   - Human overrides a machine-verified check ("actually, this is wrong" or rejects a machine-verified item): record the check type and correction in `docs/sessions/signals.md` as a trust signal:
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
   - Approval without corrections: no action needed (success is the default).

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

     Wait for response. `approve`: proceed to Step 3. `reject`: stop and report "Close halted by reviewer." `show`: expand the requested item, then re-present the choice block. `consensus`: run /consensus inline for this spec, log the outcome in the session JSON sidecar, then re-present the choice block with consensus outcome.
   - **Delegated mode**: no "Needs Your Review" items (all machine-verifiable) — skip human prompt, proceed directly to Step 3 with the delegated close addendum.
   - **PAL mode**: present the Review Brief, deliver via NanoClaw for hardware-authenticated approval, wait for tap/reject, then proceed to Step 3.

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

After the validator subagent (Step 2-2c) and before close-completion (Step 3), check whether this spec touches a registered safety-config path. Three branches: registry-content match (R2a), bootstrap fallback (R1c), no-match (silent pass). Also enforces the backfill SLA (R6b). Detection is scoped to the spec-under-review's own footprint, not the cumulative window (Spec 542 R1) — see Step 2g.1.

Source the helper library:
```bash
# shellcheck source=/dev/null
source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/safety-config.sh
```

**Step 2g.1 — Detection**:

Determine the baseline commit. `Approved-SHA:` present → use the commit at which the spec was last `/revise`'d (recovered from git history of the spec file). Absent or lookup fails → use the parent of the spec branch's first commit:

```bash
baseline="$(git log --pretty=format:%H -- "docs/specs/NNN-*.md" | tail -1)^"
if ! git rev-parse -q --verify "$baseline" >/dev/null; then
  baseline="$(git rev-list --max-parents=0 HEAD | tail -1)"
fi
```

**Per-spec attribution (Spec 542 R1)**: resolve the diff input to this spec's own changed files — not the cumulative `baseline..HEAD` window, which in multi-spec sessions and deferred-close chaining attributes sibling specs' changes to this spec's gate run. `safety_config_spec_files` tries commits tagged `Spec NNN` first, then the spec's `## Implementation Summary` file list, falling back to the cumulative diff (WARN-annotated) only if neither source is available:

```bash
spec_file=$(ls docs/specs/NNN-*.md 2>/dev/null | head -1)
if diff_source=$(safety_config_spec_files "NNN" "$baseline" HEAD "$spec_file"); then
  attribution="per-spec"
else
  diff_source=$(git diff "$baseline"..HEAD --name-only)
  attribution="cumulative"
  echo "GATE [safety-property]: WARN — per-spec diff attribution unavailable for Spec NNN (no commits tagged 'Spec NNN', no Implementation-Summary file list). Falling back to the cumulative baseline..HEAD diff, which may attribute sibling-spec changes in this window to this gate run."
fi
```

Run the path-match check against the resolved diff source (region-scoped registry entries need `$baseline`/`HEAD` — see Spec 542 R2):
```bash
matched=$(printf '%s\n' "$diff_source" | safety_config_match_diff .forge/safety-config-paths.yaml "$baseline" HEAD)
```

Run the bootstrap-fallback check (R1c) — stays on the cumulative diff regardless of attribution mode, since it detects the registry file's own first-appearance/deletion, not a per-spec safety property:
```bash
bootstrap=0
if git diff "$baseline"..HEAD --name-status | safety_config_bootstrap_fallback; then
  bootstrap=1
fi
```

If `matched` is empty AND `bootstrap` is 0: skip silently. Mark `[x] Safety-property gate — no registered paths in diff`. Proceed to Step 3.

**Step 2g.2 — Override-path short-circuit**:

If the spec's frontmatter has a `Safety-Override:` field, validate via `safety_config_validate_override`. Valid → append the canonical event record to `docs/sessions/activity-log.jsonl`:
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
Skip the prompt and section validation; proceed to Step 2g.5 then Step 3.

**Step 2g.3 — HARD-gate prompt** (R2b):

`matched` non-empty OR `bootstrap` is 1 → emit verbatim:
```
This spec touched <N> file(s) matching the safety-config registry: <comma-separated paths>.
Does this introduce a safety property — a behavior the system relies on for correctness, security, or concurrency?
[y/N]
```
Read the operator's answer.

**No-answer path (R2c)**: answer is `n`, `no`, or empty → append to `docs/sessions/activity-log.jsonl`:
```json
{"event_type":"safety-prompt-no","spec":"NNN","paths":[<matched paths>],"timestamp":"<ISO 8601>"}
```
Mark `[x] Safety-property gate — operator answered no`. Skip Step 2g.4. Proceed to Step 2g.5.

**Step 2g.4 — Yes-answer section validation** (R2d):

Answer `y`/`yes` → the spec body MUST contain a `## Safety Enforcement` section (case-sensitive, top-level, not nested) with all three of:

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

Mark `[x] Safety-property gate (Spec 387) — completed`. Proceed to Step 2g+.

## [mechanical] Step 2g+ — Adoption gate (Spec 402)

After Step 2g and before close-completion (Step 3), check whether this spec ships new machinery — a frontmatter field, a generated-artifact path, a config block, or an annotation format — without any consumer using it (the build-without-adopt failure mode; the broader superset of Spec 387's safety-property subset). The originating spec body counts as a consumer; `Follow-up adoption spec: NNN` defers adoption to a named successor.

**Machine-verifiable** check (`docs/process-kit/gate-categories.md`), runs at /close time only, never retroactively flags already-closed specs.

Source the helper library and run the gate driver:
```bash
# shellcheck source=/dev/null
source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/close-adoption-gate.sh
spec_file="$(ls docs/specs/NNN-*.md | head -1)"
if adoption_gate_check "$spec_file" "$(pwd)"; then
  : # PASS line already printed to stdout
else
  # adoption_gate_check printed the GATE FAIL line (stdout) + remediation (stderr).
  exit 2
fi
```

PowerShell parity:
```powershell
. ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/close-adoption-gate.ps1
$spec = (Get-ChildItem docs/specs -Filter 'NNN-*.md' | Select-Object -First 1).FullName
if (-not (Invoke-AdoptionGateCheck -SpecFile $spec -RepoRoot (Get-Location).Path)) { exit 2 }
```

Gate semantics:
- **Detection**: scans Scope / Requirements / Acceptance Criteria for (a) new frontmatter-field declarations (`New-Field-Name:` not already a known FORGE field), (b) generated-artifact-path declarations (backticked output globs like `docs/compliance/traceability-*.md`), and (c) config-block keys (`forge.*` / `multi_agent.*`).
- **Adoption check**: grep the repo for ≥1 consumer per declaration. The originating spec body counts — a frontmatter field populated in the spec's own frontmatter, or a path/config referenced by any consuming file, satisfies adoption.
- **Escape hatch**: a valid `Follow-up adoption spec: NNN` (must reference an existing spec) defers the gate entirely to the named successor.
- **FAIL**: any declaration with no consumer AND no follow-up field → `GATE [close-adoption]: FAIL — <N> declaration(s) shipped without a consumer: <list>`, exit 2. Remediation: exercise the declaration in the originating spec or a consuming file, or add `Follow-up adoption spec: NNN`.

Does NOT re-check Spec 387–covered safety properties (Step 2g owns those); introduces no new CLI flags or config options.

Mark `[x] Adoption gate (Spec 402) — completed`. Proceed to Step 5d.

See `docs/process-kit/close-adoption-gate-guide.md` for worked examples and the detection-rule reference.

## [mechanical] Step 5d — Session-log EA/CI propagation to persistent logs (Spec 452)

> **Ordering note**: numbered 5d for spec traceability (it belongs to the Step 5/6 signal-capture family) but executes BEFORE Step 3 — a propagation FAIL must block the status transition (Spec 452 Req 1f). Non-monotonic placement has precedent in this file (Step 8b runs before Step 8a).

Propagate today's session-log `## Error autopsies` / `## Chat insights` entries to the persistent logs (`docs/sessions/error-log.md`, `docs/sessions/insights-log.md`) and emit one-line `SIG-NNN-EA-<ID>` / `SIG-NNN-CI-<ID>` stubs to `docs/sessions/signals.md` so `/evolve` pattern analysis sees every session-log signal. The propagation engine is the Spec 452 migration script — one parser shared with the one-shot backfill, so the close-time and migration paths cannot drift:

1. Locate today's session log (`docs/sessions/YYYY-MM-DD-NNN.md`, most recent). None exists, or no `## Error autopsies` / `## Chat insights` sections: skip silently (fresh-project case) and proceed to Step 3.
2. Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py scripts/migrate-spec-452-backfill-orphaned-signals.py --apply --session-only=YYYY-MM-DD-NNN --spec=NNN
   ```
   where `--session-only` names today's session log (filename stem) and `--spec=NNN` is the closing spec — it keys the `SIG-NNN-EA/CI-<ID>` stub IDs.
3. Evaluate the exit code:
   - **0** → emit `GATE [signal-propagation]: PASS — <N> propagated, <M> skipped duplicates.` (counts from the script's `DONE |` summary line). Proceed to Step 3.
   - **2** (malformed EA/CI block) → emit `GATE [signal-propagation]: FAIL — <MALFORMED-BLOCK stderr diagnostic verbatim>. Remediation: fix the malformed EA/CI block in the session log, then re-run /close.` **HALT — do NOT proceed to Step 3.**
   - **1** (write error) → emit `GATE [signal-propagation]: FAIL — <stderr diagnostic>. Remediation: resolve the persistent-log write error, then re-run /close.` **HALT — do NOT proceed to Step 3.**
4. Idempotency (Spec 452 Req 2): the script dedups by entry ID — re-running /close on a previously-closed spec appends nothing (`0 appended` is a normal PASS). Missing persistent logs are created with a header rather than failing.
5. Propagation never rewrites session-log content — it is the source-of-truth; persistent logs are append-only targets.

See `docs/process-kit/signal-capture-conventions.md` for the propagation invariant and remediation guidance.

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

Spec file has `Approved-SHA:` (Lane B): compare current spec-file bytes (not working-tree) to those verified at Step 2. Changed between Step 2 and Step 3:
- Invoke the validator on the full spec file (matches Step 2d behavior).
- Validator FAIL → emit `GATE [spec-344-guard-1]: FAIL — spec file modified between Step 2 verification and Step 3; re-validation FAILed.` STOP. Do not proceed.
- Validator PASS → emit `GATE [spec-344-guard-1]: PASS — spec file modified post-verification; re-validation PASS.` Continue.
No diff: emit `GATE [spec-344-guard-1]: PASS — no pre-Step-3 edits.` Continue.
No `Approved-SHA:` (Lane A): skip silently — no SHA anchor to compare against.

**Guard 2 — Off-limits section restriction (Req 2)**

Any spec-file edit during Step 3 MUST be confined to non-scoped sections: frontmatter (excluding `Status:`, `Closed:`, `Validated:`), `## Implementation Summary`, `## Revision Log`, `## Evidence`, and any closure-logging block. Edits whose changed lines fall inside `## Scope`, `## Requirements`, `## Acceptance Criteria`, or `## Test Plan` MUST be refused with: `GATE [spec-344-guard-2]: FAIL — Step 3 attempted to modify protected section <heading>. Use /revise — these sections are off-limits at /close.` STOP.

This guard applies to ALL lanes — protected sections are off-limits at /close regardless of Approved-SHA.

Permitted Step 3 edits: status transition, Closed/Validated dates, Implementation Summary, Revision Log entries, Evidence section additions, frontmatter metadata.

Genuine post-close corrections (typos, broken links found later) are a separate problem — file a follow-up spec for the optional Pattern A errata-file mechanism (deferred, not implemented today). These guards do not handle post-close corrections.

**Guard 3 — Approved-SHA re-verify post-Step-3 (Req 3)**

After Step 3 completes (sub-steps a-f), if `Approved-SHA:` present (Lane B): recompute the SHA-256 over the four protected sections (Scope + Requirements + AC + Test Plan, per Spec 089's extraction rule) and compare to the stored value.
- Match → emit `GATE [spec-344-guard-3]: PASS — protected sections unchanged post-Step-3.` Continue.
- Mismatch → emit `GATE [spec-344-guard-3]: FAIL — Step 3 modified protected sections (post-Step-3 SHA mismatch). This indicates a path that bypassed Guard 2.` STOP. Do not push. Investigate the Step 3 sub-step that allowed the protected-section edit.

No `Approved-SHA:` (Lane A): skip silently — Guard 3 has no anchor.

See: docs/process-kit/close-validator-coverage.md for the full /close 318 incident motivation, threat-coverage handoff (Spec 003 + 145 + Guards 1+2 cover Lane A), and the Spec 035 ↔ Spec 344 cross-edit invariant.
# <<< spec-344 guards

a. Set `Status: closed` and add `Closed: YYYY-MM-DD` in the spec file.
b. Add a dated revision entry based on enforcement mode:
   - Chat/PAL: `YYYY-MM-DD: Closed via /close (Chat mode). Human confirmed all deliverables.`
   - Delegated: `YYYY-MM-DD: Closed via /close (Delegated mode). All ACs machine-verified at L<N>. Evidence hash: sha256:<first 16 chars>...`
b1. **Write-side mode check (Spec 399)**: run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --skip-canonical-write`. `skip` (split-file mode) → the canonical README/backlog/CHANGELOG writes in c/d/e are SUPPRESSED — the spec frontmatter edit in (a) is the source of truth and the renderer-owned `.generated/` artifacts pick up the new status on next render; the event-stream write in `e1` proceeds unchanged. `proceed` → perform c/d/e (Phase 1 dual-write). Nonzero exit → abort the canonical-write block and surface stderr — do NOT default to either behavior.
c. **README sync (Spec 086)** [proceed mode only]: read the spec's `Status:` field (authoritative), update its row in `docs/specs/README.md` to match exactly (add one if missing).
d. **Backlog sync (Spec 086)** [proceed mode only]: find the spec's row in `docs/backlog.md`.
   - Update the status column to match (e.g., `closed`); change Rank to `✅`.
   - **Duplicate detection**: multiple rows → warn "Duplicate backlog row detected for Spec NNN — consolidating," remove all but the most recent, log as a process defect.
   - No row exists → add one at the bottom with ✅ status.
e. **CHANGELOG entry** [proceed mode only]: `- YYYY-MM-DD: Spec NNN closed via /close.`
e1. **Append spec-closed event (Spec 254 — Approach D)**: append to the per-spec event stream:
   ```bash
   mkdir -p .forge/state/events/NNN
   echo '{"timestamp":"<ISO 8601>","event_type":"spec-closed","payload":{"mode":"<chat|delegated|pal>","message":"<one-line close note>"}}' >> .forge/state/events/NNN/spec-closed.jsonl
   ```
   Append-only; conflict-free. Consumed by `render_changelog.py` for the chronological log. Coexists with the CHANGELOG.md edit above during Phase 1; a Phase 2 spec retires the duplicate canonical write once events burn in.
e2. **Score-Audit observed record (Spec 368)**: append an `observed` record to the score-audit log via the shared helper — do NOT inline JSON here. The helper computes `wallclock_days`, `session_count`, `revise_rounds`, `validator_outcome`, `da_outcome`, `tc_overrun_derived`, and `creation_ts_source` from artifacts (git timestamps, session JSON sidecars, spec body); Claude does NOT compute or transcribe duration values.

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh record-observed "$spec_id"
   ```

   (PowerShell: `pwsh ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.ps1 record-observed "$spec_id"`.)

   Advisory — failures emit `WARN: score-audit append failed (advisory; close continues)` to stderr but never block the close. `tc_overrun_derived` is computed automatically from the proxy mapping in [docs/process-kit/score-calibration-loop.md](../../docs/process-kit/score-calibration-loop.md); no operator prompt is added for this field.
f. **Three-source verification (Spec 086)**: read back spec file `Status:`, README.md row, and Backlog.md row.
   - All match: emit `GATE [status-sync]: PASS — spec file, README, and backlog all show 'closed'.`
   - Mismatch: emit `GATE [status-sync]: FAIL — status drift detected after update. Spec file: <s1>, README: <s2>, Backlog: <s3>. Remediation: manually correct the mismatched source.`

Emit: `GATE [human-confirmation]: PASS — status transition to closed completed, human confirmed deliverables.`

### [mechanical] Step 3 addendum — Delegated close evidence trail (Spec 160, Requirement 7)

If enforcement mode is **Delegated** (from Step 1b):

1. **Layer 1 — Full evidence in spec**: write to `## Evidence`: all gate outcomes with PASS status, test output summary, diff summary (files changed, lines added/removed), and the delegation-eligibility assessment: `{"all_ac_machine_verifiable": true, "no_judgment_checks": true, "no_low_confidence": true, "autonomy_level": "L<N>"}`.

2. **Layer 2 — Content hash in audit log**: compute SHA-256 of the spec's complete `## Evidence` section. Append to `.forge/state/audit-log.jsonl`:
   ```json
   {"event": "delegated-close", "spec": "NNN", "timestamp": "<ISO-8601>", "evidence_hash": "sha256:<64-char-hex>", "ac_results": {"AC1": "pass", "AC2": "pass", ...}, "delegation_criteria": {"all_ac_machine_verifiable": true, "no_judgment_checks": true, "no_low_confidence": true, "autonomy_level": "L<N>"}}
   ```
   Create `.forge/state/` and `audit-log.jsonl` if absent.

3. **Layer 3 — Atomic git commit**: commit the spec file (with evidence) and updated audit log together: "Delegated close: Spec NNN — <title> (L<N>, all ACs machine-verified)".

4. Report: "Spec NNN closed via Delegated mode. Evidence hash: sha256:<first 16 chars>... Three-layer evidence trail recorded."

5. **Verification note**: future root-cause analysis compares the `audit-log.jsonl` evidence hash against the current spec evidence section to verify nothing was modified post-close.

Emit: `GATE [delegated-evidence]: PASS — three-layer evidence trail recorded. Hash: sha256:<first 16 chars>...`

### [mechanical] Step 3+ — Delta merge to canonical product spec (Spec 184)

After the status transition, check whether the spec declares delta markers for the canonical product spec:

1. **Detect deltas**: read `## Delta`. Absent, or all ADDED/MODIFIED/REMOVED lines commented out (`<!-- ... -->`): skip silently. Any uncommented marker present: proceed.

2. **Locate canonical spec**: check `docs/product-spec.md` or any `.md` under `docs/product-specs/` (use the marker's section name to match if multiple exist). None found: warn "No canonical product spec found. Delta markers present but no target. Create one from `docs/process-kit/product-spec-template.md` if needed." Skip merge.

3. **Apply markers** (in order):
   - `ADDED: <section> — <text>`: append a new requirement to the named section, assign the next sequential REQ-ID, add `[Added: Spec NNN, YYYY-MM-DD]`.
   - `MODIFIED: <section>/<REQ-ID> — <text>`: find the REQ-ID and replace its text, add `[Modified: Spec NNN, YYYY-MM-DD]`.
   - `REMOVED: <section>/<REQ-ID> — <reason>`: strike through it: `~~REQ-XXX: <old text>~~ [Removed: Spec NNN, YYYY-MM-DD — <reason>]`.

4. **Update version history**: add a row to the Version History table:
   `| YYYY-MM-DD | NNN | <summary of changes> | operator |`
   Update `Last updated:` and `Last merged from:` in the header.

5. **Conflict detection**: REQ-ID being modified/removed doesn't exist, or current text doesn't match expected state (e.g., already modified by another spec this session): flag for human resolution. Report: "Delta merge conflict: <REQ-ID> — expected <X>, found <Y>. Resolve manually."

6. **Lane enforcement**:
   - **Lane B** (`docs/compliance/profile.yaml` exists): **blocking gate**. Merge fails or conflicts unresolved: `GATE [delta-merge]: FAIL — delta merge could not be applied. Remediation: resolve conflicts in the canonical spec.` Stop.
   - **Lane A** (no compliance profile): **advisory**. Merge fails: `GATE [delta-merge]: CONDITIONAL_PASS — delta merge encountered issues but Lane A does not block on this. Review canonical spec manually.` Proceed.

7. Merge succeeds: `GATE [delta-merge]: PASS — <N> delta(s) applied to canonical product spec.`

### [mechanical] Step 3a — Remove edit-gate sentinel (Spec 145)
Remove the edit-gate sentinel to signal no `/implement` session is active:
```bash
rm -f .forge/state/implementing.json
```
File absent: skip silently.

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
- Script absent: skip silently (consumer projects may not have them).
- `--fix` corrects counts: the updated README.md is included in the /close commit.
- Script fails: proceed (non-blocking, `|| true`).
- **win32 timeout convention (Spec 554)**: run with a generous timeout (≥5 min) or
  `run_in_background` rather than a bare foreground chain; if backgrounded, poll to completion and
  read the exit codes before committing — the `|| true` non-blocking semantics apply to the CHECKED
  result, never an unread one. (Post-554 the counts script runs in ~2s, but chained batches add up.)

<!-- module:compliance -->
## [mechanical] Step 3b — V&V report generation (Spec 039, conditional)
If `docs/compliance/profile.yaml` exists (Lane B):
a. Aggregate evidence: gate outcomes (all `GATE [*]: PASS|FAIL|CONDITIONAL_PASS` entries from the spec's Evidence section and steps 2b/2c), test evidence (spec's Evidence section + `tmp/evidence/SPEC-NNN-*/`), traceability links (spec's "Traceability Links" section), compliance gate evidence (step 2b results), and acceptance criteria (cross-referenced with Evidence).
b. Generate V&V report: create `docs/compliance/reports/YYYY-MM-DD-NNN-vv.md` from `docs/compliance/reports/_template.md`, filling in: metadata fields (spec number, title, revision, profile framework, close date), gate outcomes table, test evidence table, traceability matrix excerpt, compliance gate evidence table (profile gate_rules vs evidence found), AC verification table, and the disclaimer header (required — do not remove).
c. Emit: `GATE [vv-report]: PASS — V&V report generated at docs/compliance/reports/YYYY-MM-DD-NNN-vv.md`
   - Any required gate missing evidence: emit `GATE [vv-report]: CONDITIONAL_PASS — V&V report generated but missing evidence for: <gates>. Remediation: fill in missing evidence before submitting to certification authority.`
- Absent (Lane A): skip this step.
<!-- /module:compliance -->

## [mechanical] Step 3b+ — Active-tab Spec(s) clear (Spec 353)

If `.forge/state/active-tab-*.json` marker exists for this session, locate the registry row whose first column matches the marker's `registry_row_pointer` and clear `<NNN>` (the just-closed spec ID) from the row's `Spec(s)` column — replace with `—` if it held only `<NNN>`, else remove and trim from the comma-separated list. Update the marker file's `spec_id` to empty string and bump `last_command_at` to now.

No marker: skip silently. The registry row remains `active` (tab still open) — only the spec claim is released. Operator runs `/tab close` to release the row itself.

Symmetric counterpart to `/implement` Step 3a (Spec(s) write-back) — together they keep the registry row's `Spec(s)` column current across the lifecycle.

## [mechanical] Step 3b++ — Lane-mismatch warning (Spec 353)

If the active-tab marker exists and `marker.lane` is `process-only`, emit a one-line warning at /close start: `⚠ Closing a feature-lane spec inside a process-only tab. Continue?` Soft-gate only — do not refuse. Operator decides.

## [mechanical] Step 3c — Session log incremental entry (Spec 131)

Append a structured "spec closed" entry to today's session log:

1. Check `docs/sessions/` for today's log; create a stub from `docs/sessions/_template.md` if none.
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

After the spec status transitions to `closed`, scan `## Implementation Summary`
`Changed files` for any path matching one of the four release-policy trigger
paths (per `docs/process-kit/release-policy.md` § Tag-cut triggers):

- `template/**`
- `copier.yml`
- `.claude/commands/**`
- `.forge/templates/project-schema.yaml`

No trigger files present: skip silently. Most specs (process-only docs, test
fixtures, scripts) skip this step.

At least one trigger file present:

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

Consumed by `/now` and `/evolve` (surfacing the count of pending
release-eligible entries — Spec 291 Req 4) and by `scripts/cut-release.sh`
when the operator cuts a tag. The audit doc remains the authoritative
classifier; signal-time PATCH is a conservative default the audit may revise
upward after surface-diff analysis.

`docs/sessions/signals.md` missing: create it with a single `# Signals`
header, then append.



## [mechanical] Step 4 — (auxiliary actions only — see Step 8a for commit and push)

The `git commit` and `git push` actions previously here have moved to **Step 8a — Auto-commit and push** (after Steps 5–8) so the close commit captures all spec-mutating step output in a single atomic commit. See `docs/process-kit/runbook.md` § /close for the rationale (Spec 348).

Step 4 now consists only of the auxiliary subsections 4a/4b/4c below — none of which commit.

## [mechanical] Step 4a — Append artifact relationships (Spec 108)

After the Step 3 status transition, update the cross-artifact relationship index for the just-closed spec (writes are uncommitted at this point and will be captured by the Step 8a commit):

1. Read the just-closed spec file (`docs/specs/NNN-*.md`).
2. Scan for cross-references using the reference patterns from `/trace` Step A2:
   - `Spec NNN`, `SIG-NNN-XX`, `CI-NNN`, `EA-NNN`, `ADR-NNN`, `session YYYY-MM-DD-NNN`
3. Classify each reference's relationship type from surrounding context:
   - `Trigger:` or `triggered by` → `triggered-by`
   - `Depends on` or `Dependencies:` → `depends-on`
   - `Closed in` or `closed via` → `closed-in`
   - Signal source/target → `signal-from`
   - All others → `references`
4. Build link entries: `{ "source": "spec-NNN", "target": "<artifact-id>", "type": "<type>", "context": "<surrounding line>" }`
5. `.forge/state/artifact-links.json` exists: read it, remove any existing `source: spec-NNN` entries (avoid duplicates), append the new link entries, update `generated` timestamp and `total_links`, write back.
6. Does not exist: create `.forge/state/` if needed, write a new index (same format as `/trace` Step A3).

Report: "Artifact index updated: <N> links added for Spec NNN."

No cross-references: skip silently. Read/write error: warn but do not block the close workflow.

## [mechanical] Step 4b — Auto evolve loop check (Spec 043, enhanced by Spec 157)

After the Step 3 status transition, check whether evolve trigger conditions are met (reads CHANGELOG.md, which Step 3 already wrote; the close commit at Step 8a captures the entry):

a. Read `docs/sessions/evolve-config.yaml` (absent → defaults: `auto_fast_path: true`, `spec_count_threshold: 5`, `time_interval_days: 30`).
b. Read `docs/sessions/evolve-state.md` (or last session log's `Last evolve loop review:`) for the last review date.
c. Count specs closed since last review from CHANGELOG.md.
d. **Fast-path auto-trigger** (Spec 157): `auto_fast_path` true AND (spec count ≥ `spec_count_threshold` OR time since last review ≥ `time_interval_days`) → run the evolve fast-path (F1+F4) inline:
   - F1: spot-check one AC from the just-closed spec (already done in Step 7)
   - F4: score calibration check — compare predicted E vs actual for recently closed specs

   Report inline. **Informational only** — no human confirmation needed. Append results to today's session accumulated entries so `/session` captures them.

e. **Full review recommendation**: `time_interval_days` threshold met (≥30 days) → recommend `/evolve --full` but do NOT auto-execute (requires explicit operator invocation):
   ```
   Evolve loop: full review recommended (last review: <date>, <N> days ago).
   Run `/evolve --full` when ready — this is not auto-triggered.
   ```

f. Neither threshold met: report briefly "Evolve loop: N specs since last review (threshold: M). Not yet due."
g. Never blocks the close workflow.

## [mechanical] Step 4c — Ambient status lines (Spec 220)

Two informational one-liners. Silent-skip if data is unavailable; neither blocks execution or prompts.

**Session-log line**: find today's session log, count accumulated structured entries (`###`-level headings or structured entry markers appended by `/implement`, `/close`, etc. this session). Count ≥ 1:
```
Session: N entries captured — run /session when wrapping up.
```
Count 0 or no log for today: skip silently.

**Evolve-status line**: use the Step 4b evolve trigger state (specs-since-last-review vs threshold). Report the trigger closest to its threshold:
```
Evolve: N/M specs since last review (K away from full review trigger).
```
Any trigger already crossed (recommended or auto-triggered in Step 4b):
```
Evolve: triggered — run /evolve when ready.
```
No evolve state computable: skip silently.

## [decision] Step 5 — Deferred Scope Review
Read the just-closed spec's "Out of scope" section. If it contains items:
a. Present each item as a numbered list.
b. For each item, ask: **promote** (create stub spec), **backlog** (add to Deferred Scope section), or **drop** (record in revision log)?
c. For each disposition:
   - **promote**: create a stub spec from `docs/specs/_template.md` with `Origin: Deferred from Spec NNN` in frontmatter. Add to `docs/specs/README.md` and `docs/backlog.md` (scored by human later). Add CHANGELOG entry.
   - **backlog**: add to `docs/backlog.md`'s "Deferred Scope" section: `| <date> | NNN | <item summary> | pending |`
   - **drop**: append to the originating spec's revision log: `YYYY-MM-DD: Deferred scope item dropped — "<item>". Reason: <human-provided reason>.`

No "Out of scope" section, or empty: skip silently and proceed.

## [mechanical] Step 6 — Signal Capture
Run the retrospective signal capture inline for this spec. Four signal categories:
- **Content**: what worked/didn't in the deliverable itself
- **Process**: what worked/didn't in the workflow
- **Architecture**: design insights for future work
- **Positive (Spec 497 — wins-to-keep)**: a win worth keeping or amplifying — a pattern, decision, gate, or tool that paid off. The FORGE signal taxonomy was historically ~54:1 failure-biased with no positive bucket; this captures the success side so `/evolve` reviews wins alongside negatives. Draft a `[positive]` SIG for each genuine win; zero is acceptable. See `docs/process-kit/positive-signal-taxonomy.md`.

### Signal classification (Spec 267)

Before drafting each SIG entry, infer the three Spec 267 classification fields from the implementation and close context:
- **Root-cause category**: one of `spec-expectation-gap`, `model-knowledge-gap`, `implementation-error`, `process-defect`, `other`. Use `other` when genuinely unclear — do not guess. See `docs/process-kit/signal-quality-guide.md`.
- **Wrong assumption** (optional): the specific belief held before the issue surfaced, now known false. Empty if not an assumption failure (e.g., positive signals).
- **Evidence-gate coverage**: one of `caught-by-existing-gate`, `missed-by-existing-gate`, `no-applicable-gate`. If `missed-by-existing-gate`, name the gate that should have caught it.

Then draft each SIG entry in this format:
```
### SIG-NNN-XX — <title>
- Date: YYYY-MM-DD
- Type: [content|process|architecture|trust|positive]
- Spec: NNN
- Impact: <low|medium|high>
- Observation: <what happened>
- Root-cause category: <spec-expectation-gap|model-knowledge-gap|implementation-error|process-defect|other>
- Wrong assumption: <the specific false belief, or empty>
- Evidence-gate coverage: <caught-by-existing-gate|missed-by-existing-gate|no-applicable-gate> [— gate name if missed]
- Recommendation: <what to change>
```

**Positive-signal shape (Spec 497)**: for a `[positive]` entry the three failure-classification fields above do not apply — replace with the positive fields below. `Observation` states the win; `Recommendation` becomes the keep/amplify action.
```
### SIG-NNN-XX — <title>
- Date: YYYY-MM-DD
- Type: [positive]
- Spec: NNN
- Impact: <low|medium|high>
- Observation: <the win — what worked well>
- Why it worked: <the enabling pattern, decision, gate, or tool>
- Keep/amplify: <how to repeat or institutionalize it>
```

**Re-read `docs/sessions/signals.md` now** (Spec 123 — context overflow guard) to avoid collision with concurrent edits, then **auto-append** all drafted entries using the established format (`###` header with date and spec, then categorized entries). Create the file from the signals log header if absent.

Emit one line in chat: `N signals captured to docs/sessions/signals.md`. Do NOT prompt the operator to confirm/edit/skip individual drafts — entries land as-is with classification fields intact. Curation is deferred to `/evolve` pattern analysis (Step 8), where cross-signal context is available and the cost of over-capture is low.

This is a [mechanical] step — do not skip. Absent/empty classification fields are acceptable (treated as `other`/empty/`no-applicable-gate` downstream) — the goal is low-ceremony capture, not field completeness.

### Step 6a — Upstream contribution check (Spec 226)
After capturing process signals, check if any should be contributed upstream:

a. Read `.copier-answers.yml` for `_src_path`. Determine contribution path:
   - Contains `Renozoic-Foundry/forge-public` → **canonical** (direct upstream PR)
   - Contains another remote URL (not local path) → **fork** (contribute to fork maintainer)
   - Local filesystem path → **skip** (FORGE developer, already at source)

b. For each **process signal** just captured (content/architecture signals are project-specific — skip them):
   - Evaluate: does this describe a FORGE workflow improvement that would benefit all FORGE users, not just this project?
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

     - `note`: append to scratchpad: `- [ ] <date>: [upstream] SIG-NNN-XX — <signal summary>. Target: <repo>.`
     - `skip`: proceed silently.

c. `_src_path` is a local path, or `.copier-answers.yml` absent: skip this step silently.

### Step 6b — Runbook amendment check (Spec 107)
After capturing process signals, check if any maps to an existing runbook:
a. Read all `.md` files in `docs/process-kit/`, extract section headings (`##`/`###` lines).
b. For each **process signal**, check keyword overlap with runbook headings (match 2+ non-trivial words, ignoring articles/prepositions).
c. Match found: present a runbook amendment proposal:
   ```
   RUNBOOK MATCH — signal SIG-NNN-XX matches runbook section:
     File: docs/process-kit/<runbook>.md
     Section: ## <heading>
     Signal: <signal text summary>

   Proposed amendment: <suggested edit to the runbook section based on the signal>
   ```
   Present as a choice block: **amend** (apply edit + update `<!-- Last updated: YYYY-MM-DD -->`) | **skip** (no change).
d. `amend`: apply the edit and update the `<!-- Last updated: -->` comment at the top of the runbook file.
e. No matches: skip silently.

Emit: `GATE [retro-completion]: PASS/CONDITIONAL_PASS — <signal count> signals captured.` Use CONDITIONAL_PASS if no signals were identified (unusual but possible).

## [mechanical] Step 7 — Auto-chain /matrix (Evolve Loop fast path)
a. **AC spot-check**: pick one acceptance criterion from the just-closed spec, check the corresponding file/function, state the criterion/file/whether it satisfies. Flag drift as a process defect.
a2. **Trivial-doc exemption audit (Spec 395 AC 6)**: if the spec's frontmatter contained `Consensus-Exempt: trivial-doc — ...`:
   - Compare actual closed diff size to the claim:
     - File count: `git diff --name-only HEAD~1 HEAD | grep -v '^docs/sessions/\|^docs/specs/[0-9]\|^.forge/state/' | wc -l` (count source/test/doc files; exclude session log + spec file + ephemeral state).
     - LOC count: total insertions+deletions from `git diff --shortstat HEAD~1 HEAD` for the same scope.
   - Actual file count > 2 OR LOC > 30: emit `GATE [trivial-doc-audit]: CONDITIONAL_PASS — Trivial-doc exemption was overstated: claimed ≤30 LOC across ≤2 files; actual diff was N LOC across M files. Pattern observed; no /close block (trust-at-gate-verify-at-close design).`
   - Within bounds: emit `GATE [trivial-doc-audit]: PASS — trivial-doc claim within bounds (M files, N LOC).`
   - No `Consensus-Exempt: trivial-doc` in frontmatter: skip silently (most specs).
   - Informational/CONDITIONAL_PASS only — never blocks /close ("trust at gate; verify at close" per Spec 395 Req 2 + AC 6). Repeated overstatements feed the Spec 395 Req 9 sunset review.
b. **Backlog confirmation (Spec 399)**: run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog --format=json`, confirm the closed spec's row shows status `closed` (the helper reads frontmatter directly, reflecting step (a) immediately). Check if any backlog items are now unblocked.
c. Present the current top-3 ranked backlog items.

Emit: `GATE [matrix-completion]: PASS/FAIL — <AC spot-check result, backlog confirmation>`. FAIL if AC spot-check finds drift.

## [mechanical] Step 8 — Session log update (Spec 157, augmented by Spec 371)
Check `docs/sessions/` for today's log; create one from `docs/sessions/_template.md` if none exists. **Re-read the session log file now** before editing (Spec 123 — context overflow guard). Record the just-closed spec.

**Spec 371 — Summary line append (unconditional)**: after recording the structured "spec closed" entry, append exactly one line to today's session log `## Summary` section in this format:

`<HH:MM> Closed Spec NNN — N PASS / M FAIL <gate-summary>`

Where:
- `<HH:MM>`: current local time (24-hour)
- `<NNN>`: the spec just closed
- `N PASS / M FAIL`: count of GATE outcomes from this /close run (Steps 2, 4, 6, 7) classified PASS vs FAIL (`CONDITIONAL_PASS` counts as PASS)
- `<gate-summary>`: comma-joined list of up to 3 most informative non-trivial gate-name→outcome pairs (e.g., `spec-integrity:PASS, retro-completion:CONDITIONAL_PASS, matrix-completion:PASS`); `—` if no gates ran

No `## Summary` section: create one immediately after the H1/title block. The append is unconditional — even N=0/M=0 appends (`0 PASS / 0 FAIL —`) as a presence record. Do NOT rewrite earlier Summary lines — append only.

This Summary line is the structured trace `/session` Step 1c reads when synthesizing the day's narrative summary.

## [mechanical] Step 8b — EA/CI Window Scan (Spec 371)

Port `/implement` Step 8's chat-window EA/CI retrospective pattern to `/close`, with window-bounded dedup so a candidate captured at `/implement` is not double-captured here.

1. **Resolve session id**: read `.forge/state/active-tab-*.json` markers; pick the one whose `spec_id` matches NNN (or most recent `last_command_at` if no spec match) as `<sid>`. No marker: derive from the active tab registry row, or fall back to a deterministic hash of (today's date + spec NNN) — never abort on missing marker.
2. **Determine scan-window start**: read `.forge/state/last-eaci-scan-<sid>.json`'s `timestamp` if it exists; else the time `/close` started.
3. **Run scanner heuristics** against the chat window since the start time, plus structured entries appended since command start (mirrors `/implement` Step 8):
   - Operator corrections: "no, do X instead", "stop", "don't"
   - Implementation friction: "had to revert", "didn't work", "broke"
   - Surprising outcomes: "didn't expect", "turns out", "actually …"
   - Architectural insights: "pattern: …", "principle …", "rule …"
   - Gate-skips: `--no-verify`, `--force`, "skip the gate"
   - Wrong-assumption disclosures: "turns out X is …", "I was wrong about …"
4. **Output zero or more SIG-NNN drafts**, each with all three Spec 267 classification fields populated (empty/sentinel values permitted: `other`, empty string, `no-applicable-gate`). Same draft format as Step 6.
5. **Zero-candidate path — unconditional attestation**: zero drafts → emit verbatim:
   `No EA/CI candidates detected since <HH:MM>. Confirm 'nothing to capture'? [Y/n]`
   Default `y` on bare Enter. Do NOT skip this prompt — it is a forcing function for the operator's read of the chat window. Per Spec 371 Constraint, no conditional-suppression heuristic is permitted here.
6. **Non-zero path**: present each SIG draft (numbered) and auto-append to `docs/sessions/signals.md` inline (no per-draft confirmation — same low-ceremony pattern as Step 6).
7. **Window-bounded dedup write**: regardless of candidate count, write/update the timestamp file:
   ```bash
   mkdir -p .forge/state
   cat > ".forge/state/last-eaci-scan-${sid}.json" <<EOF
   {"timestamp":"<ISO 8601 now>","command":"/close","spec":"NNN"}
   EOF
   ```
   Caps the next /implement-or-/close window at this command's completion time, preventing the same chat range being scanned twice in one session (Spec 371 Constraint).
8. **Watchlist linkage**: a follow-up spec is gated on `docs/sessions/watchlist.md` 4-week telemetry of attestation-y rate. No action here beyond the timestamp write — the watchlist row is checked at `/evolve`, not `/close`.

Skip silently if `forge.roles.devils_advocate.enabled: false` AND `forge.review.enabled: false` (no retrospective surface enabled). Otherwise runs unconditionally.

## [mechanical] Step 8a — Auto-commit and push (Spec 348)

This step captures the close commit AFTER all spec-mutating steps (3, 4a, 5, 6, 6a, 6b, 7, 8) complete, ensuring a single atomic commit covers every mutation.

**Commit guard marker (Spec 257)**: before committing, set the active-close marker so the specless commit guard allows the commit:
```bash
mkdir -p .forge/state
echo "close-NNN" > .forge/state/active-close
```

**Explicit-path staging + pathspec commit (Spec 494)**: do NOT use `git add -A`/`git add -u` or a bare `git commit`. In a chained/parallel session the shared git index may already hold a concurrent lane's staged files, and a bare commit would sweep them into this spec's close commit (Defect C — observed 2026-06-11 when Spec 435's commit captured Spec 421's staged files). Instead:
1. Build the explicit path list `CLOSE_PATHS` = this spec's `## Implementation Summary` `Changed files` ∪ the artifacts `/close` itself wrote this run (the spec file, `docs/.generated/*`, the session log, `docs/sessions/signals.md`, `docs/sessions/activity-log.jsonl`, `.forge/state/events/NNN/*`, and any evidence dir). Run `git status` to confirm the set.
2. Stage them explicitly: `git add -- <CLOSE_PATHS>` — reuses the Spec 432 `_explicit_stage_paths` discipline (verbatim paths through `--`, never `-A`/`-u`).
3. Commit **by explicit pathspec** so only this spec's files are captured even when other paths are staged: `git commit -m "Close Spec NNN — <title>" -- <CLOSE_PATHS>`. A concurrent lane's pre-staged files are left untouched, never committed here. Verified by `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/tests/test-spec-494-staging-collision.sh`.

**Commit guard cleanup (Spec 257)**: after committing (or if none was needed), clear the marker:
```bash
rm -f .forge/state/active-close
```

After committing, push to remote (explicit confirmation required — per AGENTS.md:127, `git push` is a second authorization-required action separate from the `/close` invocation itself):
a. Check for a remote tracking branch: `git rev-parse --abbrev-ref @{upstream}`
b. None: skip silently with "No remote tracking branch — skipping push." Stop here.
c. Tracking branch exists: emit the following prompt verbatim and wait for an explicit operator response:

   > Push to `<remote>/<branch>`? (yes/no)

   **Compaction-boundary rule**: if context compaction occurs between this prompt and the operator's response, re-emit the prompt — no pre-compaction response is valid (per AGENTS.md:130-132).

d. Explicit "yes": run `git push`. Report: "Pushed to <remote>/<branch>."
e. Any other response (including "no", silence, ambiguous input, or a compaction-summary inference): abort with "Push skipped — commit is local-only. Run `git push` manually when ready." Continue with the rest of `/close`.
f. Push fails: report as a warning ("Push failed: <error>. Changes are committed locally.") and continue — never block the rest of `/close`.

## [decision] Step 9 — Pick next
a. **Closing queue**: count of remaining specs at `implemented` status. For each: `Spec NNN — <title>: run /close NNN`.
b. **Next recommended spec**: highest-ranked `draft` spec from backlog — ID, title, score, lane. Read the spec file and extract the first sentence of `## Objective`, displayed below the title as "_<objective>_".
c. **No draft specs in backlog**: run `/brainstorm` inline to generate recommendations from the roadmap, signals, and scratchpad. If unavailable: "Backlog is empty. Run `/brainstorm` or `/spec <description>` to create new specs."
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

The renderer's session-data safety rule applies automatically: `today_session_log_unsynthesized` true → a synthetic `session` row is inserted at rank 1 and `stop` demoted to rank `—`. Only the source representation in this command file is the canonical YAML data.

e. Report: "Spec NNN is now `closed`. Commit: <done/skipped>."

Remind to update `Last evolve loop review:` in today's session log.

## [mechanical] Step 10 — Post-close context compaction (Spec 256)

After Step 9 completes, check whether automatic context compaction should trigger. Runs silently when compaction is not needed.

1. **Read config**: check `forge.context.optimization.level` and `.compact_threshold_pct` in AGENTS.md.
   - Absent or `minimal`: skip — no auto-compaction.
   - `balanced`: proceed to threshold check (step 2).
   - `aggressive`: skip threshold check, proceed directly to compaction (step 3).

2. **Threshold check** (balanced only): estimate whether context usage exceeds `compact_threshold_pct` (default 60%).
   - Below threshold: skip compaction, silently.
   - At or above: proceed to compaction (step 3).

3. **Compaction trigger**:
   a. Display status **before** compaction begins: `Compacting context (optimization: <level>, threshold: <pct>%)...`
   b. Trigger `/compact` to summarize and reduce context.
   c. After compaction, the AGENTS.md context compaction rule applies: all authorization-required commands are treated as unissued.

**Constraints**:
- Runs ONLY after /close has fully completed (all gates passed, commit done, pick-next presented).
- No compaction mid-command or during active spec work.
- `/compact` output preserves key session state: which spec was just closed, the pick-next options, and any pending closing queue items.

---

## Next Action

Spec NNN is now `closed`. Step 9 Choice Block above presents the next options — wait for human input before proceeding to any further work.
