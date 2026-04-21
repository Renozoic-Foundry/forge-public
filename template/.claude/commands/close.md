---
name: close
description: "Close a spec: confirm validation, capture signals, update priorities"
model_tier: sonnet
workflow_stage: review
---

# Framework: FORGE
# Model-Tier: sonnet
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
   - If delegation-eligible: mode = **Delegated**
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
   b. Evidence present → `GATE [shadow-validation]: PASS — shadow validation evidence found. Strategy: <strategy>.`
   c. Evidence missing or "pending" → `GATE [shadow-validation]: CONDITIONAL_PASS — spec declares shadow validation (strategy: <strategy>) but no evidence recorded. This is a non-blocking warning — shadow validation is advisory. Consider running the shadow comparison before closing.`
   d. **This gate is non-blocking.** CONDITIONAL_PASS does not halt the close workflow.

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

## [mechanical] Step 2f — Role Registry Review (Spec 167)

After the validator gate (Step 2d), before generating the Review Brief (Step 2e):

1. **Role registry check**: Read `AGENTS.md` for the `forge.role_registry` block. Find all entries with `contexts` containing `close` or `all`.
   - If no registry found, or `.claude/agents/` does not exist: skip this step silently.
2. **Invoke roles**: For each matching entry, read the role instruction file at the listed path. Apply the role's perspective to the spec being closed — use the spec's Objective, Scope, Requirements, and Acceptance Criteria as context. Produce the structured output block defined in each role's "Output Format" section.
3. **Present role reviews**: Display all role output blocks in a "### Role Reviews (Spec 167)" subsection. Include each review in the Review Brief (Step 2e) under "Needs Your Review" if the role recommends REVISE or BLOCK.
4. **Flag BLOCK recommendations**: If any role recommends BLOCK, emit:
   `GATE [role-review/<role-name>]: CONDITIONAL_PASS — <role> recommends BLOCK: <key concern>. Human review required.`

Note: The Validator role's formal AC verification gate is handled by Step 2d. The role registry review supplements it with additional deliberation perspectives (e.g., Devil's Advocate, CTO).

### [mechanical] Step 2d++ — Template/Own-Copy Dual-Check (Spec 188, upgraded by Spec 180)

Before generating the Review Brief, actively verify bidirectional sync:

1. If `.copier-answers.yml` does not exist: skip silently — no template/own-copy duality to check.
2. If `.copier-answers.yml` exists (this project is itself a Copier template):

**Detection logic**: Run `git diff --name-only <spec-baseline>..HEAD` to get the list of files changed by this spec. For each changed file:
- If the file is under `template/.claude/commands/`, `template/.forge/commands/`, `template/.claude/agents/`, `template/docs/process-kit/`, or `template/docs/QUICK-REFERENCE.md`: check if a corresponding own-copy exists at `.claude/commands/`, `.forge/commands/`, `.claude/agents/`, `docs/process-kit/`, or `docs/QUICK-REFERENCE.md` (same filename, ignoring `.jinja` suffix).
- If the file is under `.claude/commands/`, `.forge/commands/`, `.claude/agents/`, `docs/process-kit/`, or is `docs/QUICK-REFERENCE.md`: check if a corresponding template file exists under `template/`.

**Evaluation**:
- If **no dual files found in the changed set**: mark `[x] Template/own-copy dual-check — no dual files changed`. Proceed silently.
- If **dual files found and both sides were changed**: mark `[x] Template/own-copy dual-check — both sides updated`. Proceed silently.
- If **only one side was changed** (drift detected):

  Present:
  ```
  TEMPLATE/OWN-COPY DRIFT DETECTED — The following files were changed on one side but not the other:
  <list of drifted files with which side was changed>

  This drift must be resolved before closing. Template and own-copy command files must stay in sync.
  ```
  > **Choose** — type a number or keyword:
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `sync` | Apply the changes to the missing side now |
  > | **2** | `intentional` | Drift is intentional — document reason and proceed |
  > | **3** | `block` | Block close until drift is fixed manually |

  - If `sync`: for each drifted file, copy the changes to the other side. Re-run the check to confirm sync.
  - If `intentional`: append to the spec's Revision Log: `YYYY-MM-DD: Template/own-copy dual-check: drift noted as intentional for <files> — <reason>.` Proceed.
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
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `sync` | Create `template/docs/<path>` by copying the source `docs/<path>` |
  > | **2** | `whitelist` | Append `docs/<path>` to `scripts/sync-to-public.sh`'s `PUBLIC_DOC_FILES` array |
  > | **3** | `skip` | Record intentional drift in the spec's Revision Log (reason required) |

  - If `sync`: `mkdir -p template/docs/<dirname>` then `cp docs/<path> template/docs/<path>`. Re-verify the target — check passes for this violation.
  - If `whitelist`: edit `scripts/sync-to-public.sh` to add `"docs/<path>"` inside the `PUBLIC_DOC_FILES=( ... )` array block. Re-verify — check passes for this violation.
  - If `skip`: prompt for a one-line reason and append to the spec's Revision Log: `YYYY-MM-DD: Consumer-propagation check: skipped for docs/<path> — <reason>.`

  After iterating all violations:
  - All resolved via `sync` or `whitelist`: emit `GATE [consumer-propagation]: PASS — <N> violation(s) resolved (<sync count> synced, <whitelist count> whitelisted).` Proceed.
  - Any resolved via `skip`: emit `GATE [consumer-propagation]: CONDITIONAL_PASS — <N> violation(s) skipped with documented reason.` Proceed.
  - Any unresolved (operator abandoned choice): emit `GATE [consumer-propagation]: FAIL — <N> unresolved violation(s). Remediation: mirror the doc under template/docs/, add docs/<path> to PUBLIC_DOC_FILES, or explicitly skip with reason.` Stop close.

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
     > | # | Action | What happens |
     > |---|--------|--------------|
     > | **1** | `approve` | Confirm all items reviewed — proceed to close |
     > | **2** | `show <item>` | Expand a Machine-Handled item for inspection |
     > | **3** | `reject` | Halt close — return spec to implemented for rework |
     > | **4** | `consensus` | Defer to /consensus — run structured multi-role review before deciding |
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

## [mechanical] Step 3 — Status transition
Perform the `closed` status transition:
a. Set `Status: closed` and add `Closed: YYYY-MM-DD` in the spec file.
b. Add a dated revision entry based on enforcement mode:
   - Chat/PAL: `YYYY-MM-DD: Closed via /close (Chat mode). Human confirmed all deliverables.`
   - Delegated: `YYYY-MM-DD: Closed via /close (Delegated mode). All ACs machine-verified at L<N>. Evidence hash: sha256:<first 16 chars>...`
c. **README sync (Spec 086)**: Read the spec file's `Status:` field (authoritative source). Find the spec's row in `docs/specs/README.md` and update the status to match exactly. If no row exists, add one.
d. **Backlog sync (Spec 086)**: Find the spec's row in `docs/backlog.md`.
   - Update the status column to match the spec file (e.g., `closed`).
   - Change the Rank column to `✅` for closed specs.
   - **Duplicate detection**: If the spec appears in multiple rows, warn: "Duplicate backlog row detected for Spec NNN — consolidating." Remove all but the most recent row (highest rank or most recent status). Log the duplicate as a process defect.
   - If no row exists, add one at the bottom with ✅ status.
e. Add a CHANGELOG entry: `- YYYY-MM-DD: Spec NNN closed via /close.`
f. **Three-source verification (Spec 086)**: After updating, read back all three sources and confirm they agree:
   - Spec file `Status:` field
   - README.md row status
   - Backlog.md row status
   - If all three match: emit `GATE [status-sync]: PASS — spec file, README, and backlog all show 'closed'.`
   - If any mismatch: emit `GATE [status-sync]: FAIL — status drift detected after update. Spec file: <s1>, README: <s2>, Backlog: <s3>. Remediation: manually correct the mismatched source.`

Emit: `GATE [human-confirmation]: PASS — status transition to closed completed, human confirmed deliverables.`

### [mechanical] Activity log event (Spec 134)

Append a `spec-closed` event to `docs/sessions/activity-log.jsonl`:
```
{"timestamp":"<ISO 8601>","agent_id":"<operator or agent ID>","event_type":"spec-closed","spec_id":"<NNN>","message":"Spec NNN closed — <title>","metadata":{"gates_passed":<N>,"gates_failed":<N>,"signals_captured":<N>}}
```
Use the Bash tool with a single `echo '...' >> docs/sessions/activity-log.jsonl` command (append-only).

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

6. **Enforcement**: delta merge is **advisory**. If merge fails: `GATE [delta-merge]: CONDITIONAL_PASS — delta merge encountered issues. Review canonical spec manually.` Proceed.

7. If merge succeeds: `GATE [delta-merge]: PASS — <N> delta(s) applied to canonical product spec.`

### [mechanical] Step 3a — Remove edit-gate sentinel (Spec 145)
Remove the edit-gate sentinel to signal that no `/implement` session is active:
```bash
rm -f .forge/state/implementing.json
```
If the file does not exist, skip silently.

### [mechanical] Step 3a+ — README stats auto-update (Spec 235)
Run `validate-readme-stats.sh --fix` to auto-correct spec and session counts in README.md before committing:
```bash
if [[ -f "scripts/validate-readme-stats.sh" ]]; then
  bash scripts/validate-readme-stats.sh --fix || true
fi
```
- If the script is absent: skip silently (consumer projects may not have it).
- If `--fix` corrects counts: the updated README.md is included in the /close commit.
- If the script fails for any reason: proceed (non-blocking, `|| true`).

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

## [mechanical] Step 4 — Auto-commit and push

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


After committing, push to remote:
a. Check if the current branch has a remote tracking branch: `git rev-parse --abbrev-ref @{upstream}`
b. If a tracking branch exists: run `git push`. Report: "Pushed to <remote>/<branch>."
c. If push fails: report as a warning ("Push failed: <error>. Changes are committed locally.") and continue — do not block the rest of `/close`.
d. If no remote tracking branch: skip silently with a note: "No remote tracking branch — skipping push."

## [mechanical] Step 4a — Append artifact relationships (Spec 108)

After committing, update the cross-artifact relationship index for the just-closed spec:

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

After committing, check whether evolve trigger conditions are met:

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

Present draft signal entries. **Re-read `docs/sessions/signals.md` now** (Spec 123 — context overflow guard), then append confirmed entries.

After presenting signals, write confirmed entries to `docs/sessions/signals.md` using the established format (`###` header with date and spec, then categorized signal entries). If the file doesn't exist, create it from the signals log header. This is a [mechanical] step — do not skip.

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
     > | # | Action | What happens |
     > |---|--------|--------------|
     > | **1** | `note` | Add to scratchpad as upstream candidate for later |
     > | **2** | `skip` | Project-specific — not an upstream improvement |

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

### [mechanical] Step 6c — ADR gap detection (Spec 138)

After capturing retro signals, scan for missed ADR opportunities:

1. **Keyword scan**: Search the spec's Objective, Scope, and Requirements sections for ADR indicators: "chose", "alternative", "trade-off", "tradeoff", "migration from", "replaces", "evaluated" (in context of comparing approaches), "compared".
2. **Check ADR References**: Read the `ADR References:` section of the just-closed spec.
3. **Flag condition**: If indicators found AND `ADR References:` says "none" or is empty, add an architecture signal to the retro output:
   ```
   [architecture] SIG-NNN-AX: Architectural decision made without ADR — spec contains decision language ("<indicator>") but ADR References is "none". Consider running /decision retroactively to document the decision rationale.
   ```
   Append this signal to `docs/sessions/signals.md` along with other retro signals.
4. **No-flag conditions**: Skip silently if no ADR indicators are found, or if `ADR References:` already contains a valid reference.
5. This is advisory — does not block the close workflow.

Emit:  Use CONDITIONAL_PASS if no signals were identified (unusual but possible).

## [mechanical] Step 7 — Auto-chain /matrix (Evolve Loop fast path)
a. **AC spot-check**: Pick one acceptance criterion from the just-closed spec. Check the corresponding file/function. State the criterion, file, and whether it satisfies. Flag drift as a process defect.
b. **Backlog confirmation**: **Re-read `docs/backlog.md` now** (Spec 123 — context overflow guard). Confirm the closed spec's row is marked ✅ `closed` and `Last updated` is current. Check if any backlog items are now unblocked.
c. Present the current top-3 ranked items from the backlog.

Emit: `GATE [matrix-completion]: PASS/FAIL — <AC spot-check result, backlog confirmation>`. FAIL if AC spot-check finds drift.

## [mechanical] Step 8 — Session log update
Check `docs/sessions/` for a log file matching today's date. If none exists, create one from `docs/sessions/_template.md`. **Re-read the session log file now** before editing (Spec 123 — context overflow guard). Record the just-closed spec.

## [decision] Step 9 — Pick next
a. **Closing queue**: count of remaining specs at `implemented` status. For each: `Spec NNN — <title>: run /close NNN`.
b. **Next recommended spec**: highest-ranked `draft` spec from backlog — ID, title, score, lane. Read the spec file (`docs/specs/NNN-*.md`) and extract the first sentence of its `## Objective` section — display it below the spec title as: "_<objective>_".
c. **If no draft specs exist in the backlog**: report "Backlog is empty — run `/brainstorm` to surface new spec candidates, or `/interview` if the next problem area needs deeper exploration first."
d. Present a Choice Block (Spec 025, see `docs/process-kit/implementation-patterns.md`):

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `implement` | Start `/implement next` (highest-ranked draft) |
> | **2** | `close NNN` | Close another implemented spec (type spec number) |
> | **3** | `brainstorm` | Generate new spec recommendations |
> | **4** | `interview` | Explore next problem area before speccing (if backlog is empty) |
> | **5** | `consensus` | Defer a decision to /consensus for structured multi-role input |
> | **6** | `stop` | End session |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

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
