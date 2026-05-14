---
name: implement
description: "Build a spec end-to-end with evidence gates"
workflow_stage: implementation
---

# Framework: FORGE
# Model-Tier: sonnet
<!-- multi-block mode: serialized — choice blocks fire at distinct mechanical steps (auto-select prompt, vague-AC scan, cross-platform check, change-lane prompt, command-integration check, update-manifest check, README check, template-sync check, value demo, exit gate). Each block waits for operator response before the next mechanical step proceeds. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->
Implement the specified spec. Usage: /implement <spec-number|next>

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /implement — Implements a spec (FORGE Solve Loop). Auto-approves draft specs inline.
  Usage: /implement <spec-number|next>
  Arguments:
    spec-number — e.g. /implement 021
    next        — auto-picks the highest-ranked draft spec from the backlog and starts immediately
  Behavior:
    - draft spec → auto-approved inline (evidence gate: completeness), then in-progress → implemented
    - in-progress spec → implemented directly
    - implemented / deprecated → stops and reports (already closed)
    - next → reads backlog, selects top-ranked draft, displays spec info, then proceeds without confirmation
  Approval trail: inline approval adds a revision entry + CHANGELOG entry.
  After implementation: presents implementation summary inline, then reminds to /close.
  ```
  Stop — do not execute any further steps.

---

**Gate Outcome Format**: Read `.forge/templates/gate-outcome-format.md` and emit the structured format at every evidence gate.

---

**Step 0a — Evolve Loop Boundary Check (Spec 191)**:
Read `docs/sessions/context-snapshot.md`. If a `## Active evolve loop` section exists with `status: in-progress`:
- Stop and report: "Evolve loop in progress (started <started>). Solve-loop commands (/implement, /spec, /close) are blocked until the evolve loop completes. Return to the /evolve session and use the exit gate to choose your next action."
- Do NOT proceed with implementation.
If the section is absent or `status: complete`: proceed normally.

**Step 0b — Checkpoint resume detection (Spec 123)**:

After resolving the spec number (Step 0 or Step 1), check for an existing checkpoint at `.forge/checkpoint/implement-<spec-id>.json`:

1. If the file **exists**: read it and display:
   ```
   ⚡ CHECKPOINT DETECTED — /implement <spec-id>
   Last completed step: <step_number> — <step_description>
   Timestamp: <timestamp>
   Completed outputs: <summary>

   Resume from step <next_step>? (yes to resume, no to start fresh)
   ```
   - On `yes`: skip to the step after `last_completed_step`.
   - On `no`: delete the checkpoint file and start from Step 1.
2. If the file **does not exist**: proceed normally.

**Checkpoint write rule**: After each major step (1, 2a, 2b, 3, 4, 5), write/update `.forge/checkpoint/implement-<spec-id>.json`:
```json
{
  "spec_id": "<spec-id>",
  "command": "implement",
  "last_completed_step": "<step>",
  "step_description": "<description>",
  "timestamp": "<ISO 8601>",
  "outputs": { "<step>": "<summary>" }
}
```

**Checkpoint cleanup**: After the final step completes successfully (status → `implemented`), delete `.forge/checkpoint/implement-<spec-id>.json`.

**Commit guard cleanup (Spec 257)**: After the final step completes successfully (status → `implemented`), delete `.forge/state/implementing.json` to clear the commit guard marker. This re-enables the specless commit guard — any subsequent `git commit` calls will be blocked until the next `/implement` or `/close` sets its marker.

---

**Step 0 — Resolve `next` argument**:
If $ARGUMENTS is `next` (case-insensitive):
  a. **Backlog rows (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --get-backlog --format=json`. Parse the stdout as JSON; the array contains all backlog rows.
  b. Find the highest-ranked row with status `draft`. If multiple rows share the same rank/score, pick the one listed first.
  c. If no `draft` specs exist: report "No draft specs in the backlog. Create one with `/spec <description>`." Stop.
  d. Display the selected spec using a Choice Block (Spec 025, see `docs/process-kit/implementation-patterns.md`):
     Read the selected spec file (`docs/specs/NNN-*.md`) and extract the first sentence of the `## Objective` section.
     ```
     ## Auto-selected from backlog
     Spec NNN — <title>
     Score: <score> | Lane: <lane> | BV=<bv> E=<e> R=<r> SR=<sr>
     Objective: <first sentence from the spec's ## Objective section>
     ```
     > **Choose** — type a number or keyword:
     > | # | Rank | Action | Rationale | What happens |
     > |---|------|--------|-----------|--------------|
     > | **1** | 1 | `yes` | Auto-selected from backlog; default acceptance | Implement Spec NNN (auto-selected) |
     > | **2** | 2 | `NNN` | Override to different spec; intentional pick | Implement a different spec (type spec number) |
     > | **3** | — | `skip` | Stop and choose manually later | Stop — choose manually |
     >
     > _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

     If $ARGUMENTS is exactly `next` (no further arguments): proceed immediately as `yes` — do not pause for confirmation.
     Set the spec number to NNN and proceed to step 1.

  e. **Parallel batch suggestion** (Spec 087): After selecting the top spec, check if other draft specs at the same or adjacent rank are also ready (all dependencies met) and share no files in their `Implementation Summary → Changed files` lists. If so, suggest:
     ```
     Parallel batch available: Specs NNN and NNN are independent and can be implemented simultaneously.
     Run `/parallel NNN NNN` for parallel execution, or continue with single spec.
     ```
     This is informational only — proceed with the selected spec regardless.

### [mechanical] Step 0c — Session log stub and incremental entry (Spec 131)

Before starting implementation, ensure today's session log exists and append a "spec started" entry:

1. Check `docs/sessions/` for a log file matching today's date (`YYYY-MM-DD-NNN.md`).
   - If none exists: create a stub from `docs/sessions/_template.md` with today's date and the next session number (scan existing files to determine NNN). Report: "Created session log: `docs/sessions/YYYY-MM-DD-NNN.md`."
2. Append a structured entry to the active session log:
   ```
   ### Spec NNN — started
   - **Time**: HH:MM
   - **Spec**: NNN — <title>
   - **Lane**: <change-lane>
   - **Action**: Implementation started via /implement
   ```
3. Report: "Session log updated: spec NNN started."

### [mechanical] Step 0d — Final-Draft Consensus Gate (Spec 395)

Before reading the full spec body in Step 1, this gate verifies the spec has either passed final-draft `/consensus` (recorded as `Consensus-Close-SHA:` per Spec 389) or carries an explicit operator exemption. The gate enforces the convention that high-value, non-trivial drafts must be vetted at final-draft stage — not just at proposal stage — before /implement begins.

**Posture**: this gate is **fail-closed** (ENFORCEMENT). Step 2b.0 (Spec 389 encoded-DA verification) is **fail-soft** (OPTIMIZATION). The asymmetry is intentional and load-bearing — optimizers fail soft, enforcers fail closed. See `docs/process-kit/consensus-protocol.md` § Posture asymmetry.

1. **Read spec frontmatter only** (lightweight read; full Step 1 read still happens). Extract:
   - `Status:`
   - `Change-Lane:`
   - `Priority-Score:` HTML comment (BV, E, R, SR)
   - `Consensus-Close-SHA:` (optional — written by `/consensus` per Spec 389)
   - `Consensus-Exempt:` (optional — operator-set)
   - `Consensus-Status:` (optional — e.g., `vet-pending`)

2. **Classification (Req 1)** — spec is `consensus-required` when ALL hold:
   - `Status:` = `draft`
   - `Change-Lane:` ∈ {`standard-feature`, `small-change`}
   - `BV ≥ 4 AND (R ≥ 3 OR E ≥ 3)` — compound rule eliminates the BV=4/E=1/R=1 theater case where /consensus is heavier than the spec.

3. **Exemptions (Req 2)** — consensus NOT required when ANY hold:
   - `Change-Lane:` = `hotfix` (urgency exemption; already excluded by step 2's lane set, restated for operator clarity).
   - `Consensus-Exempt: <reason>` is set with reason ≥ 30 chars.
   - **Trivial-doc fast-path** (operator-attested): `Consensus-Exempt: trivial-doc — <30+ char justification>` AND `Change-Lane:` = `small-change`. /implement does NOT runtime-verify file count or LOC at gate time. `/close` Step 7 audits the closed diff and emits CONDITIONAL_PASS if the trivial-doc claim was overstated (>30 LOC OR >2 files). Pattern: trust-at-gate; verify-at-close.

4. **Lane B counter-sign rule (Req 8)** — when `docs/compliance/profile.yaml` is present:
   - If spec is `consensus-required` AND `BV ≥ 4` AND `R ≥ 3` (high-stakes range): the `Consensus-Exempt: <reason>` value MUST contain a `[reviewed-by: <second-operator-identity>]` token.
   - Parse the value for the `[reviewed-by: ...]` token. If absent under these conditions, FAIL with: "Lane B Consensus-Exempt requires [reviewed-by: <identity>] counter-sign for BV≥4 + R≥3 specs (forensic anchor; prevents audit-laundering composition with vet-pending + Spec 052 sealing)."
   - Lane A (no compliance profile present): single 30-char operator-authored reason remains the trust root; counter-sign rule does NOT apply.

5. **Verify presence**: if `consensus-required` and no exemption applies, verify either `Consensus-Close-SHA:` (40-char hex) OR `Consensus-Exempt:` (≥ 30 chars; Lane B counter-sign per step 4) is present.

6. **Gate outcome**:
   - PASS via SHA: `GATE [final-draft-consensus]: PASS — Consensus-Close-SHA <8-char prefix> present.` Proceed.
   - PASS via exemption: `GATE [final-draft-consensus]: PASS — Consensus-Exempt: <reason snippet>.` Proceed.
   - SKIP not-qualifying (low-priority spec): `GATE [final-draft-consensus]: SKIP — spec does not require consensus (lane=<lane>, BV=<n>, E=<n>, R=<n>).` Proceed silently.
   - SKIP hotfix: `GATE [final-draft-consensus]: SKIP — hotfix lane.` Proceed.
   - FAIL (no SHA, no Exempt): `GATE [final-draft-consensus]: FAIL — Spec NNN requires final-draft consensus before /implement. Run /consensus NNN, or set Consensus-Exempt: <reason ≥ 30 chars> in frontmatter.` HALT — do not proceed to Step 1.
   - FAIL (Exempt reason too short, AC 5): `GATE [final-draft-consensus]: FAIL — Consensus-Exempt reason must be ≥ 30 chars (got: N).` HALT — operator must extend the reason to ≥ 30 characters.

7. **Activity log (Req 3)** — append a single JSONL line to `docs/sessions/activity-log.jsonl` (the canonical activity-log path established by Spec 134; Spec 052 immutability sealing reads from this file):
   - Lane A (no compliance profile):
     ```json
     {"timestamp":"<ISO 8601>","event_type":"consensus-gate-check","spec_id":"NNN","decision":"PASS|FAIL|SKIP","gate_path":"SHA|exempt|exempt-trivial-doc|skip-not-qualifying|skip-hotfix|missing","agent_id":"<id>","consensus_status":"<vet-pending|absent>"}
     ```
     The `consensus_status` field is `vet-pending` when frontmatter contains `Consensus-Status: vet-pending`, `absent` otherwise (Req 5 + AC 11).
   - Lane B (`docs/compliance/profile.yaml` present): include the Lane A fields PLUS `operator_identity` (from `forge.identity` config), `spec_file_sha` (sha256 of spec file), and the applicable provenance field — `consensus_close_sha` (when gate_path=SHA), or `consensus_exempt_reason` + `reviewed_by_identity` (when gate_path=exempt).

8. **Vet-pending advisory passthrough (Req 5)** — if frontmatter contains `Consensus-Status: vet-pending`, the gate behaves identically to the rules above (it is **prompt-not-block**: the gate fires only if `Consensus-Close-SHA` AND `Consensus-Exempt` are both absent). Vet-pending is surfaced as a one-line advisory in `/now` and `/matrix` after the 30-day SLA, not at /implement.

9. **Provisional sunset (Req 9)** — this gate ships PROVISIONAL for 90 days post-Spec-395 close. At sunset, `/evolve` presents trigger-rate, drift recurrence, and operator-friction data; operator decides whether to make permanent, tighten the qualifier, loosen to advisory, or remove. The `Provisional-Until:` field on Spec 395 records the sunset date; `/now` surfaces a reminder starting D-7.

---

1. Read `docs/specs/NNN-*.md` for the given spec number. <!-- parallel: also read README.md + CHANGELOG.md if needed for approval trail -->

### [mechanical] Step 1b — Score verification
Read the spec's `Priority-Score:` frontmatter. Extract BV, E, R, SR values and recompute using the formula in `docs/process-kit/scoring-rubric.md`.
**Input range validation (Spec 148)**: Before recomputing, validate that each BV, E, R, SR value is an integer between 1 and 5 inclusive. If any value is outside this range, display: "WARNING: [dimension] must be 1-5 (got [value]) — score uses invalid inputs." Continue with implementation but flag the warning prominently.
If computed ≠ listed: display "⚠ Score mismatch: listed=X, computed=Y — will auto-correct in backlog on next /matrix run."
Continue regardless — this is a warning, not a gate.

2. Check spec status:
   - If `in-progress` or `approved` (legacy): proceed to step 3.
   - If `draft`: inline-approve before implementing (evidence gate: completeness) —
     a. Verify spec has: Objective, Scope, ACs, Test Plan, Change-Lane. Emit gate outcome:
        - All present → `GATE [completeness]: PASS — all required sections filled`
        - Missing sections → `GATE [completeness]: FAIL — missing: <sections>. Remediation: fill required sections before approval.` Stop.
     b. Update `Status: in-progress` in the spec file.
     c. Add a dated revision entry: `YYYY-MM-DD: Approved inline via /implement. Status → in-progress.`
     d. **Write-side mode check (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --skip-canonical-write`. If stdout is `skip` (split-file mode), skip steps 2d-2e — the spec frontmatter edit in 2b is the source of truth and the renderers will reflect the new status on next render. If stdout is `proceed`, perform 2d and 2e (Phase 1 dual-write):
       2d-i. Update the spec's row in `docs/specs/README.md` to `in-progress`.
       2e-i. Add a CHANGELOG entry: `- YYYY-MM-DD: Spec NNN approved inline via /implement.`
       If the helper exits nonzero, abort the canonical-write step and surface stderr — do NOT default to either skip or proceed.
     f. Then proceed to step 3.
   - If `implemented` or `deprecated` (or legacy `superseded`): stop and report — "Spec NNN is already `<status>` and cannot be re-implemented. Create a new spec or add a revision entry to the existing one."
   - After approval (whether inline or pre-existing), create the edit-gate sentinel:
     ```bash
     mkdir -p .forge/state
     cat > .forge/state/implementing.json << SENTINEL
     {
       "spec": "NNN",
       "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
       "files_in_scope": ["<files from spec Implementation Summary>"]
     }
     SENTINEL
     ```
     This signals to the edit-gate hook that an active `/implement` session is in progress.

### [mechanical] Step 2a — Spec integrity signature (Spec 089)

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

After approval (status is now `in-progress`), compute a SHA-256 integrity hash:

1. **Extract sections**: Extract the full text of these four sections (each from its `##` heading to the next `##` heading, exclusive):
   - `## Scope`
   - `## Requirements`
   - `## Acceptance Criteria`
   - `## Test Plan`
2. **Combine and normalize**: Concatenate the four extracted sections in order (Scope, Requirements, Acceptance Criteria, Test Plan). Trim leading and trailing whitespace from the combined text.
3. **Compute hash**: Compute the SHA-256 hash of the combined, trimmed text. Produce the 64-character lowercase hex digest.
4. **Write to frontmatter**: Add `- Approved-SHA: <64-char hex>` to the spec file's frontmatter, immediately after the `Priority-Score:` line. If `Approved-SHA:` already exists, overwrite it (re-approval scenario).
5. Report: "Spec integrity signature written: Approved-SHA: <first 8 chars>..."

### [mechanical] Step 2b — Devil's Advocate Gate (Spec 078, updated by Spec 099)

Before writing any code, check if this spec has been reviewed by the devil's advocate.

1. Read the spec frontmatter for `DA-Reviewed:`, `DA-Decision:`, `DA-Encoded-Via:`, and `Consensus-Close-SHA:` fields.

### Step 2b.0 — Encoded-DA verification (Spec 389)

**Fast-path no-op**: if `DA-Encoded-Via:` is absent, skip this entire sub-step and proceed to step 2 (existing flow). No parser overhead, no behavioral change for legacy specs.

**Verifier path**: when `DA-Encoded-Via:` is present, run these checks in order. Any FAIL logs the failure mode and falls through to step 2 (fresh DA subagent path); all-PASS skips steps 2–5 entirely.

a. **Value validation**: assert the field value is exactly `consensus-round-1` or `consensus-round-2`. Otherwise FAIL with: `DA-Encoded-Via must be consensus-round-1 or consensus-round-2 (got: <value>)`. Round 3+ encodings are rejected by design — rounds 3+ indicate unresolved divergence.

b. **Consensus-Close-SHA presence**: if `Consensus-Close-SHA:` is absent or empty, FAIL with: `Consensus-Close-SHA required when DA-Encoded-Via is set`.

c. **SHA format validation**: assert 40-character lowercase hex. Otherwise FAIL with: `Consensus-Close-SHA must be 40-char hex (got: <value>)`.

d. **SHA reachability**: run `git cat-file -e <SHA>^{commit}`. If exit non-zero, FAIL with: `Consensus-Close-SHA <8-char-prefix> not reachable from HEAD (rebased or force-pushed?)`. Operator must re-run `/consensus --round N` to refresh the SHA.

e. **Drift check**: run `git log <SHA>..HEAD --name-only -- <Implementation-Summary-files>`. Paths from the spec's `## Implementation Summary` `Changed files` list are passed verbatim as **git pathspecs** (not shell globs) — operators may use git-pathspec patterns like `tests/fixtures/389/*.md` and git interprets them natively. If the output is non-empty, FAIL with: `drift detected: <files>`. Drifted Implementation-Summary files invalidate the encoding because the spec's claimed scope changed since consensus close.

f. **All-PASS** (a–e all clean): skip the fresh DA subagent spawn. Add to spec frontmatter:
   - `DA-Reviewed: YYYY-MM-DD`
   - `DA-Decision: PASS`
   - `DA-Verification: consensus-round-N (SHA <8-char-prefix> + drift-clean)`

   Report: `GATE [devils-advocate]: PASS — encoded via consensus-round-N (verified SHA <prefix> + drift-clean, no subagent spawn).` Skip steps 2–5; proceed to next major step (2b+ Intelligent Role Dispatch).

g. **Any-FAIL** (any of a–e tripped): log the specific failure mode (which check, with values) to operator output AND append to `docs/sessions/agent-file-registry.md`:
   ```
   YYYY-MM-DD HH:MM | devils-advocate | spec-NNN | encoded-FAIL | <failure mode> | mode: verifier
   ```
   Then continue to step 2 below — fresh DA subagent will be spawned via the existing path.

**Trust-model constraint**: **/implement MUST NOT write `Consensus-Close-SHA`**. The SHA is exclusively written by `/consensus` at convergent-round close (see `consensus.md` Step 4c). /implement reads + verifies; never edits the SHA. Operators MUST NOT hand-edit the SHA either — the encoding relies on operator integrity. See `docs/process-kit/devils-advocate-checklist.md` § DA-Encoded-Via convention.

2. **If DA-Reviewed exists and is within 7 days and spec content unchanged since that date**:
   - Report: "Devil's advocate review is current (DA-Decision: <decision>, reviewed: <date>)."
   - If DA-Decision was FAIL: "Previous DA review was FAIL. Run /revise NNN first, or use --skip-da to override (hotfix lane only)." Stop.
   - If DA-Decision was PASS or CONDITIONAL_PASS: proceed to implementation.

3. **If no DA-Reviewed or expired (>7 days or spec modified since review)**:
   - Report: "Spawning devil's advocate review..."
   - Read `.claude/agents/devils-advocate.md` for the role preamble.
   - **Check `forge.roles.separation`** in AGENTS.md (Spec 099):
     - If `context-scoped` or `full`: Spawn an **isolated** sub-agent. The agent receives ONLY the role preamble and the spec file path — NO conversation history, NO implementation plans, NO session context. This ensures independent judgment free from anchoring bias. Use `model` from `forge.roles.devils_advocate.model` if set.
     - If `none` (default): Spawn a sub-agent in the current context (existing behavior).
   - **Role state file lifecycle (Spec 100)**: Before spawning the DA sub-agent, write the role state file to activate hook-enforced write blocking:
     ```bash
     mkdir -p .forge/state
     cat > .forge/state/active-role.json << 'EOF'
     {"role":"devils-advocate","spec":"NNN","started":"<ISO 8601 now>","read_only":true}
     EOF
     ```
     This activates the PreToolUse hook in `.claude/settings.json` which blocks Write/Edit/NotebookEdit tool calls while the DA role is active.
   - Sub-agent prompt structure:
     ```
     [Role preamble from devils-advocate.md]

     You are reviewing: docs/specs/NNN-<slug>.md

     Read the spec file. Evaluate it against your 6-domain checklist.

     IMPORTANT: You are READ-ONLY. You may use Read, Glob, Grep, and Bash (for read-only commands like git log, wc, etc.) ONLY. You do NOT have Write, Edit, or NotebookEdit tools. Do not attempt to modify any file.

     Produce your output as a JSON code block.
     ```
   - **After the DA sub-agent completes** (regardless of outcome): delete the role state file to lift write restrictions:
     ```bash
     rm -f .forge/state/active-role.json
     ```
   - Parse the agent's JSON output (this is **Pass 1**).

   #### Two-Pass Adversarial Review (Spec 181)

   - **If Pass 1 produces any findings** (critical, warning, or info — any severity counts):
     - Report: "**Pass 1**: <count> finding(s) at <severities>. Pass 1 findings present — second-pass sweep skipped."
     - Handle the findings using the standard decision logic below (PASS/CONDITIONAL_PASS/FAIL based on `gate_decision`).

   - **If Pass 1 produces zero findings** (`findings` array is empty):
     - Report: "**Pass 1**: zero findings. Triggering second-pass deep analysis..."
     - Spawn a second DA sub-agent (same role state lifecycle — write `active-role.json` before, delete after) with a **distinct second-pass prompt**:
       ```
       [Role preamble from devils-advocate.md]

       You are performing a SECOND-PASS deep review of: docs/specs/NNN-<slug>.md

       A first-pass review found zero issues. Your job is to look deeper. Focus specifically on:
       1. **Edge cases**: What happens at boundary values, empty inputs, maximum loads, or concurrent access?
       2. **Error handling**: What happens when dependencies fail, networks timeout, or disk is full?
       3. **Security implications**: Are there privilege escalation paths, injection vectors, or information leaks?
       4. **Architectural implications**: Does this change create coupling, make future changes harder, or conflict with existing patterns?
       5. **Unstated assumptions**: What does this spec assume about the environment, user behavior, or system state that isn't explicitly validated?

       IMPORTANT: You are READ-ONLY. Do not attempt to modify any file.
       "Confirmed clean" IS a valid outcome — do not invent findings to justify your existence.

       Produce your output as a JSON object with the same schema as the first pass.
       ```
     - Parse the second-pass JSON output.
     - **If second pass also finds zero findings**: Report: "**Pass 2**: zero findings. **Confirmed clean (two-pass).**" Set `gate_decision` to PASS.
     - **If second pass finds issues**: Report findings prefixed with "**Pass 2**:" and the pass number for each (e.g., "Pass 2: [warning] ..."). Set `gate_decision` based on the second-pass findings.

   #### Standard DA Decision Handling

   - **PASS**: Add `DA-Reviewed: YYYY-MM-DD` and `DA-Decision: PASS` to spec frontmatter. Report findings summary. Proceed.
   - **CONDITIONAL_PASS**: Add frontmatter fields. Add a `## Devil's Advocate Findings` section to the spec with the findings. Report warnings. Proceed.
   - **FAIL**: Add `DA-Decision: FAIL` to frontmatter. Print all findings with severity. Report: "GATE [devils-advocate]: FAIL — <summary>. Remediation: address findings and run /revise NNN, then /implement again." Stop.

4. **Skip conditions**:
   - `--skip-da` flag AND spec change-lane is `hotfix`: Skip DA. Log signal: "SIG-NNN | process | DA review skipped for hotfix spec NNN."
   - `--skip-da` flag AND lane is NOT hotfix: "DA skip is only allowed for hotfix lane. Remove --skip-da or change the spec's change lane." Stop.
   - Check AGENTS.md for `forge.roles.devils_advocate.enabled`. If `false`: skip silently.

5. Log the DA invocation to `docs/sessions/agent-file-registry.md`:
   ```
   YYYY-MM-DD HH:MM | devils-advocate | spec-NNN | <decision> | findings: <count> | mode: <subagent|inline>
   ```

### [mechanical] Step 2b+ — Intelligent Role Dispatch (Spec 187)

After the DA gate completes (or is skipped), check `forge.dispatch_rules.enabled` in AGENTS.md. If `false` or absent: skip this step.

If enabled:
1. **Skip threshold check**: Read the spec's E and R scores from frontmatter. If E ≤ `skip_threshold.effort` AND R ≤ `skip_threshold.risk`: skip dispatch (DA-only review). Report: "Role dispatch: skipped (E=<e>, R=<r> — below threshold)."

2. **Evaluate dispatch conditions** against the spec:
   - `cross_cutting`: count files listed in Implementation Summary. If ≥ 3 files → invoke CTO.
   - `security`: scan spec Scope and Objective for keywords: auth, credential, secret, token, permission, encrypt, certificate, TLS, RBAC. If any match → invoke CISO.
   - `lane_b`: check spec's lane or `forge.lane` in AGENTS.md. If Lane B → invoke CQO.
   - `high_risk`: check spec's R score. If R ≥ 4 → invoke CQO.
   - `high_effort`: check spec's E score. If E ≥ 4 → invoke CEfO.
   - `process_only`: check spec's change-lane. If `process-only` → invoke CEfO.

3. **Dispatch**: For each role selected (1-3 max):
   - Read `.claude/agents/<role>.md` for the role preamble.
   - Spawn the role as an isolated sub-agent (same pattern as DA — read-only, receives only the spec file and role preamble).
   - All dispatched roles run in **parallel** (not serial).
   - Each role produces a structured review block (3-5 sentences, Recommendation, Confidence, Key concern).

4. **Present advisory output**: Display each role's review block. These are **advisory only — not blocking gates**. A REVISE or BLOCK recommendation from a non-DA role is surfaced as a warning but does NOT stop implementation.
   ```
   ## Advisory Role Dispatch (Spec 187)
   Dispatched: <role1>, <role2> (reason: <conditions matched>)

   <role review blocks>

   Advisory summary: <N> PROCEED, <N> REVISE, <N> BLOCK
   Note: Non-DA role recommendations are advisory. Implementation proceeds.
   ```

5. Log each dispatch to `docs/sessions/agent-file-registry.md`:
   ```
   YYYY-MM-DD HH:MM | <role> | spec-NNN | <recommendation> | advisory | mode: dispatch
   ```

### [mechanical] Step 2c — Acceptance Criteria Vague-Language Scan (Spec 171)

When inline-approving a draft spec (status was `draft`), scan each acceptance criterion in the spec's `## Acceptance Criteria` section for vague-language patterns: "should", "consider", "might", "may", "approximately", "reasonable", "could", "as needed".

If any acceptance criterion contains one of these patterns:
a. Present a choice block:
   ```
   Vague acceptance criteria found — the following criteria contain language that is hard to test:
   - Criterion N: "<text>" — matched pattern: "<pattern>"
   ...
   Vague acceptance criteria reduce testability and may cause disagreement at the validation gate.
   ```
   > **Choose** — type a number or keyword:
   > | # | Rank | Action | Rationale | What happens |
   > |---|------|--------|-----------|--------------|
   > | **1** | 1 | `rewrite` | Vague ACs cause validation gate disagreement; fix now | Revise each vague criterion before implementing |
   > | **2** | — | `skip` | Skip recorded in revision log; accept downstream risk | Proceed — skip recorded in revision log |
b. If `rewrite`: for each flagged criterion, prompt for a replacement. Rewrite in the spec before proceeding.
c. If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Acceptance criteria vague-language scan: skipped.`

If no vague language detected, or if spec was already `in-progress`/`approved` (not a fresh inline approval): proceed silently.

3. **Multi-tab claim check**: Check `docs/sessions/context-snapshot.md` for active tab status first; if snapshot is missing or stale, read `docs/sessions/registry.md` (if it exists). Check if any row with Status = `active` has claimed this spec number. If so, stop and report: "Spec NNN is claimed by tab '<label>' (started <time>). Run `/tab close` in that tab first, or choose a different spec." If no conflict, and a registry row exists for this session, update `Last active` to now. If no registry exists, skip this step silently.

3a. **Active-tab Spec(s) write-back (Spec 353)**: If `.forge/state/active-tab-*.json` marker exists for this session, locate the registry row whose first column matches the marker's `registry_row_pointer` and write `<NNN>` (this spec ID) into the row's `Spec(s)` column. Replace any existing value (e.g., `—` placeholder); preserve the rest of the row. Also update the marker file's `spec_id` field and bump `last_command_at` to now. Skip silently if no marker exists (single-tab users see no friction).

3b. **Lane-mismatch warning (Spec 353)**: If the active-tab marker exists and `marker.lane` is NOT `feature` (i.e., the operator opened this tab as `process-only` or `hotfix`), emit a one-line warning: `⚠ Action targets feature lane; active tab is '<lane>'. Continue anyway? Tab claim will absorb a feature-lane spec.` This is **soft-gate only** — do not refuse. Operator decides whether the mismatch matters.
4. Run the pre-implementation checklist:
   - [ ] Spec status verified — see Step 4c (active detection — Spec 180)
   - [ ] Change lane verified — see Step 4d (active detection — Spec 180)
   - [ ] Work is in spec scope (flag scope creep immediately)
   - [ ] Acceptance criteria are specific and testable
   - [ ] Test plan covers core behavior and edge cases
   - [ ] Cross-platform coverage: see Step 4b (active detection — Spec 171)
   - [ ] ADR need evaluated — see Step 4a (Spec 138)
   - [ ] Update-manifest classification verified — see Step 4e (active detection — Spec 180)

### [decision] Step 4a — ADR Detection (Spec 138)

Scan the spec body for architectural decision indicators:

**Keyword scan**: Search the spec's Objective, Scope, and Requirements sections for:
- "chose" paired with "over", "instead of", or "rather than"
- "alternative" (alternative considered, alternative approach)
- "trade-off" or "tradeoff"
- "migration from" or "migrating from"
- "replaces" in the context of replacing one approach with another
- Two or more explicit options compared ("Option A", "Option B"; "approach 1 vs 2")
- "evaluated" or "considered" in the context of comparing approaches

**Check ADR References**: Read the spec's `ADR References:` section.

**Prompt conditions**: Present the prompt if indicators were found AND `ADR References:` says "none" or is empty:

```
ADR DETECTED — This spec involves an architectural decision.
Indicators: <list of matched keywords or phrases>

Create an ADR now?
| # | Action | What happens |
|---|--------|--------------|
| 1 | yes    | Run /decision with pre-populated context from this spec |
| 2 | skip   | Record skip in revision log and proceed |
```

- If **yes**: run `/decision` inline, pre-populating Context from the spec's Objective and Options from decision language in Scope/Requirements.
- If **skip**: append to the spec's Revision Log: `YYYY-MM-DD: ADR prompt skipped — no architectural record created.`
- If **no indicators found**, OR `ADR References:` already contains a valid reference: skip silently. Mark `[x] ADR need evaluated — no indicators / reference already exists`.

### [mechanical] Step 4b — Cross-Platform Active Detection (Spec 171)

Scan the spec's `## Implementation Summary` section for any file path ending in `.sh`:
- If `.sh` files are found AND the spec's `### Cross-platform coverage` section has no `- PowerShell:` entries (or is absent):

  Present:
  ```
  Cross-platform check: this spec modifies .sh scripts but the Test Plan has no PowerShell coverage.
  Files: <list of .sh files>
  Add PowerShell equivalents to the Test Plan?
  ```
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `add` | Cross-platform parity; default for shell-script changes | Pause to collect PowerShell equivalents and add them to the Test Plan |
  > | **2** | — | `skip` | Skip recorded in revision log; accept platform gap | Proceed — skip recorded in revision log |

  - If `add`: for each `.sh` file in scope, prompt for the PowerShell equivalent. Append to the spec's `### Cross-platform coverage` section.
  - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Cross-platform check: skipped — no PowerShell equivalents added.`

- If no `.sh` files in Implementation Summary, or PowerShell coverage already present: proceed silently.

### [mechanical] Step 4c — Spec Status Verification (Spec 180)

Read the spec frontmatter `Status:` field.

- If status is `in-progress` or `approved`: mark `[x] Spec status verified`. Proceed silently.
- If status is `draft`: this should have been caught and updated by Step 2 (inline approval). If it is still `draft` at this point, report: "Spec NNN is still draft — inline approval in Step 2 did not complete. Re-run /implement." Stop.
- If status is `implemented` or `closed` or `deprecated`: report: "Spec NNN is already `<status>` — cannot re-implement." Stop.

If status is valid: proceed silently. No operator prompt needed — this is a mechanical verification.

### [mechanical] Step 4d — Change Lane Verification (Spec 180)

Read the spec frontmatter `Change-Lane:` field.

- If `Change-Lane:` is present and contains a valid lane (`hotfix`, `small-change`, `standard-feature`, `process-only`): mark `[x] Change lane verified`. Proceed silently.
- If `Change-Lane:` is missing or empty:

  Present:
  ```
  CHANGE LANE MISSING — Spec NNN has no Change-Lane in its frontmatter.
  The change lane determines the review rigor and gate requirements.
  ```
  > **Choose** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | — | `hotfix` | Operator picks based on actual change scope | Set lane to hotfix (critical fix) |
  > | **2** | — | `small-change` | Operator picks based on actual change scope | Set lane to small-change (low-risk tweak) |
  > | **3** | — | `standard-feature` | Operator picks based on actual change scope | Set lane to standard-feature (new feature or cross-cutting change) |
  > | **4** | — | `process-only` | Operator picks based on actual change scope | Set lane to process-only (docs/tracking changes only) |

  After selection: update the spec frontmatter with the chosen lane and append to the spec's Revision Log: `YYYY-MM-DD: Change lane set to <lane> via active detection (Spec 180).`

- If `Change-Lane:` contains an unrecognized value: report: "WARNING: Change-Lane `<value>` is not a standard FORGE lane. Proceeding — verify this is intentional."

### [mechanical] Step 4e+ — Command Integration Check (Spec 197)

Scan the spec's `## Implementation Summary` `Changed files` list for any new command file (path matching `.claude/commands/*.md` or `.forge/commands/*.md` with "(new)" annotation):

- If **no new command files**: skip silently.
- If **new command files detected**: check the spec's Acceptance Criteria for integration point coverage:
  - At least one AC requires an existing command to reference the new command (inbound)
  - At least one AC requires the new command to reference other commands (outbound, typically via choice block)

  If integration ACs are **present**: mark `[x] Command integration check — integration ACs found`. Proceed.
  If integration ACs are **missing**:

  Present:
  ```
  NEW COMMAND DETECTED — This spec creates a new command but has no integration point ACs.
  New commands: <list>
  Without integration ACs, this command may become an island (unreachable from the workflow).
  See: docs/process-kit/command-integration-map.md § Integration Point Guidance
  ```
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `add` | Prevents new commands from becoming workflow islands | Add integration point ACs to the spec now |
  > | **2** | — | `skip` | Skip recorded in revision log; accept island risk | Proceed — skip recorded in revision log |

  - If `add`: prompt for which existing commands should reference this one and add ACs.
  - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Command integration check: skipped — no integration ACs added.`

### [mechanical] Step 4e — Update-Manifest Classification Check (Spec 180)

Scan the spec's `## Implementation Summary` `Changed files` list for any path starting with `template/`.

- If **no template/ paths found**: mark `[x] Update-manifest classification verified — no template files in scope`. Proceed silently.
- If **template/ paths found**: read `.forge/modules/update-manifest.yaml` (or `update-manifest.yaml` at the project root if the former does not exist).
  - For each template file in the spec's changed files list, check if it appears in the manifest with a classification (`merge`, `overwrite`, `skip`, etc.).
  - If **all template files are classified**: mark `[x] Update-manifest classification verified`. Proceed silently.
  - If **any template file is missing from the manifest**:

    Present:
    ```
    UPDATE-MANIFEST GAP — The following template files are not classified in update-manifest.yaml:
    <list of unclassified files>

    Each file needs a classification to control how /forge stoke handles updates.
    ```
    > **Choose** — type a number or keyword:
    > | # | Rank | Action | Rationale | What happens |
    > |---|------|--------|-----------|--------------|
    > | **1** | 1 | `add` | Required for /forge stoke to handle updates correctly | Add missing entries to update-manifest.yaml now |
    > | **2** | — | `skip` | Skip recorded in revision log; downstream stoke risk | Proceed — skip recorded in revision log |

    - If `add`: for each missing file, prompt for the classification. Add to `update-manifest.yaml`.
    - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Update-manifest classification check: skipped for <files>.`

5. State: "Beginning implementation of Spec NNN — <title> (Lane: <lane>)." List the files that will be changed.

### [mechanical] Atomic spec checkout and activity log (Spec 134)

a. **Atomic checkout check**: Read `docs/sessions/activity-log.jsonl` (if it exists). Search for any `spec-started` event for this spec ID that has no corresponding `spec-closed` event. If found, abort: "Spec NNN is already claimed by agent `<agent_id>`." If not found, proceed.

b. **Append spec-started event**: Append a single JSONL line to `docs/sessions/activity-log.jsonl`:
   ```
   {"timestamp":"<ISO 8601>","agent_id":"<operator or agent ID>","event_type":"spec-started","spec_id":"<NNN>","message":"Beginning implementation of Spec NNN — <title>","metadata":{"lane":"<lane>","score":<score>}}
   ```
   Use the Bash tool with a single `echo '...' >> docs/sessions/activity-log.jsonl` command (append-only, no read-modify-write).

c. **Append per-spec event stream (Spec 254 — Approach D)**: In parallel with the activity-log append above, write to the per-spec event stream:
   ```bash
   mkdir -p .forge/state/events/NNN
   echo '{"timestamp":"<ISO 8601>","event_type":"spec-started","payload":{"lane":"<lane>","score":<score>,"agent_id":"<id>"}}' >> .forge/state/events/NNN/spec-started.jsonl
   ```
   The activity-log entry is the cross-cutting feed (all events from all agents in chronological order); the per-spec stream is the spec-scoped feed consumed by render_changelog.py. Both are append-only and conflict-free.

### [mechanical] Context snapshot update (Spec 091)
Update `docs/sessions/context-snapshot.md` with the current spec under `## Active implementation`:
```
## Active implementation
Spec: NNN — <title>
Lane: <lane>
Started: YYYY-MM-DD HH:MM
Step: 5 — beginning implementation
```
### [mechanical] Implementer Role Invocation (Spec 078, updated by Spec 099)

When spawning sub-agents for implementation work:

1. Read `.claude/agents/implementer.md` for the role preamble.
2. Prepend the role preamble to each implementer agent's prompt.
3. Include the scoping constraint: "You may WRITE only to files listed in the spec's Implementation Summary. You may NOT modify files in docs/specs/."
4. **Stop boundary**: Include this instruction verbatim in every implementer agent prompt: "IMPORTANT: Do NOT run /close, /validate, or any closing commands. Stop at `implemented` status and return your results. The operator will drive the close process."
5. **Check `forge.roles.separation`** in AGENTS.md (Spec 099):
   - If `full`: Spawn implementer as an **isolated** sub-agent with `isolation: "worktree"`. The agent receives ONLY the role preamble, spec file, and codebase access — NO prior conversation context. Use `model` from `forge.roles.implementer.model` if set.
   - If `context-scoped` or `none`: Implementer runs in the main conversation context (full context is an advantage for implementation quality).
6. When `forge.roles.implementer.use_worktree` is `auto` or `always` (independent of separation level): use `isolation: "worktree"` for implementer agents.
7. Respect `forge.roles.implementer.max_parallel` for concurrent agent count.
8. If implementation fails (tests fail), retry up to `forge.roles.implementer.max_retries` times before escalating.
9. Log each implementer invocation to `docs/sessions/agent-file-registry.md`:
   ```
   YYYY-MM-DD HH:MM | implementer | spec-NNN | files: <count> | tests: pass|fail | mode: <subagent|inline>
   ```

6. Implement the spec. Before each file edit, state the spec ID and file path (spec-gate enforcement).

### [mechanical] Step 6a0 — Dependency change detection (Spec 126)

After implementation, check for dependency manifest changes introduced by this spec:

1. **Detect changes**: Run a diff against the spec's baseline (the commit when status changed to `in-progress`) to find changes in dependency manifest files:
   ```bash
   git diff HEAD --name-only | grep -E "(package\.json|requirements.*\.txt|pyproject\.toml|Cargo\.toml|go\.mod|Gemfile|pom\.xml|build\.gradle(\.kts)?)"
   ```
   If no manifest files changed: skip this step silently.

2. **Run dependency audit**: If manifest changes are detected, run the `/dependency-audit` logic inline (Steps 3-5 from that command) to produce the structured report.

3. **Emit signal**: If any dependency has a `new-dependency` or `major-version-bump` risk flag:
   - Emit: `DEPENDENCY_REVIEW_REQUIRED — <count> dependencies need review (<count> new, <count> major bumps).`
   - Append to the spec's `## Evidence` section:
     ```
     ### Dependency Changes (Spec 126)
     | Ecosystem | Manifest | Package | Old Version | New Version | Risk Flag |
     |-----------|----------|---------|-------------|-------------|-----------|
     | <ecosystem> | <file> | <name> | <old> | <new> | <flag> |
     Signal: DEPENDENCY_REVIEW_REQUIRED
     ```
   - Report: "Dependency changes detected. Review required before `/close`. See `docs/process-kit/dependency-vetting-checklist.md`."

4. **No high-risk changes**: If all changes are `minor-bump` or `patch-bump` only:
   - Report: "Dependency version bumps detected (low risk). No `DEPENDENCY_REVIEW_REQUIRED` signal emitted."
   - Still record the changes in the spec's Evidence section for traceability.

5. **Skip gate option**: If `--skip-dependency-gate "<reason>"` is present in $ARGUMENTS:
   - Do not emit `DEPENDENCY_REVIEW_REQUIRED`.
   - Record in the spec's Evidence section:
     ```
     ### Dependency Gate Skip (Spec 126)
     - Reason: <reason>
     - Dependencies: <list>
     - Skipped by: operator
     ```
   - Report: "Dependency gate skipped — reason recorded in evidence."

### [mechanical] Current Goal tracking (Spec 091)
After completing each numbered step (5, 6, 7, 8, 9), emit a Current Goal block at the END of your output. This keeps the active plan in the model's recent attention span, preventing goal drift in long sessions:
```
---
## Current Goal
**Command**: /implement NNN
**Spec**: NNN — <title>
**Step**: <current> of 10 — <step description>
**Completed**: <comma-separated list of completed steps>
**Remaining**: <comma-separated list of remaining steps>
---
```
Also update `docs/sessions/context-snapshot.md` `## Active implementation` section with the current step number at steps 5, 7, and 9.

<!-- module:browser-test -->
### [mechanical] Step 6a — Browser Test Generation (Spec 093)

After implementation, if the spec's Acceptance Criteria reference UI behavior (keywords: page, screen, button, click, form, input, display, render, navigate, modal, dialog, toast, table, list, menu, tab, panel, view, layout, responsive, viewport):

1. **Detect UI ACs**: Scan the spec's Acceptance Criteria for UI-related keywords. If none found, skip this step silently.

2. **Generate test script**: Create a browser test script at `tmp/evidence/SPEC-NNN-browser-YYYYMMDD/browser-test.js` using the FORGE browser test template (`.forge/templates/browser-test-template.js`). The generated script should:
   - Import the template's `runBrowserTest` function
   - Define test steps that map to each UI-facing acceptance criterion
   - Use `capture()` at each significant interaction point
   - Use `assess()` to record pass/fail for each step

3. **Run browser test** (if a browser automation package is installed):
   ```bash
   bash .forge/bin/forge-browser-test.sh NNN --url <detected-or-default-url>
   ```
   If no browser package is installed, report: "Browser test script generated but not run — install `playwright` or `puppeteer` to execute. Script: `<path>`"

4. **Capture evidence**: If the test ran, report:
   - Screenshot count and paths
   - Video recording path (if captured)
   - Pass/fail summary from the manifest
   - Evidence directory path

5. **Skip conditions**: Skip browser test generation entirely if:
   - No UI-facing ACs detected
   - The spec's change-lane is `process-only`
   - The spec's Compatibility section states "no UI changes"
<!-- /module:browser-test -->

### [mechanical] Step 6b — Two-Stage Subagent Review (Spec 083)

After each implementer task completes (or after all implementation if `per_task_review: false`):

1. **Read review config**: Check AGENTS.md for `forge.review` configuration. If absent or `enabled: false`, skip review entirely (backward compatible).

2. **Stage 1 — Spec Compliance Review** (if `spec_compliance` in `stages`):
   a. Spawn a read-only review agent with:
      - The spec file as context
      - The git diff of changes made
      - Test results (if available)
      - Instructions from `.forge/templates/review-checklists/spec-compliance.md`
   b. Agent produces structured JSON findings
   c. Evaluate result:
      - PASS: proceed to Stage 2
      - WARN: log findings, proceed to Stage 2
      - FAIL: return findings to implementer, request fixes (retry count +1)
        - If retries >= `max_retries`: escalate to human: "Implementer failed spec compliance after N attempts. Findings: <JSON>"

3. **Stage 2 — Code Quality Review** (if `code_quality` in `stages`):
   a. Spawn a separate read-only review agent with:
      - Changed files (full content, not just diff)
      - Test files
      - Test results
      - Instructions from `.forge/templates/review-checklists/code-quality.md`
      - NOTE: do NOT provide the spec file (context isolation — Stage 2 reviews code on its own merits)
   b. Agent produces structured JSON findings
   c. Evaluate result: same PASS/WARN/FAIL logic as Stage 1

4. **Log results**: Append review findings summary to the spec's Evidence section:
   ```
   ## Review Results (Spec 083)
   Stage 1 (Spec Compliance): PASS — 5/5 requirements, 4/4 ACs, 0 scope violations
   Stage 2 (Code Quality): PASS — 0 findings, test ratio 0.53
   ```

5. Emit: `GATE [two-stage-review]: PASS/WARN/FAIL — Stage 1: <result>, Stage 2: <result>`

### [mechanical] Step 6c — Approved-SHA recompute (Spec 365)

After all implementation (Step 6) and any DA-disposition application that may have edited the spec's Scope, Requirements, Acceptance Criteria, or Test Plan sections, recompute the spec's `Approved-SHA:` so the stored hash reflects the finalized text.

This step closes the recurring SHA-pingpong defect class (≥3 occurrences in close history): Step 2a writes the SHA before the DA gate; if DA dispositions edit the protected sections during Step 6, `/close` Step 2 spec-integrity verification then FAILs and forces operator into `approve-modified`.

**Procedure**:
1. Read the spec's frontmatter for the `Approved-SHA:` field.
   - If the field is **absent** (legacy spec without integrity signature): skip this step silently. Mark `[x] Approved-SHA recompute — legacy spec, no signature to update`.
2. Re-extract the four protected sections (`## Scope`, `## Requirements`, `## Acceptance Criteria`, `## Test Plan`), concatenate in that order, trim leading/trailing whitespace, and compute SHA-256 (same procedure as Step 2a).
3. Compare to the stored `Approved-SHA:` value:
   - **If identical**: no-op. The spec's protected sections were unchanged during Step 6; the Step 2a hash is still correct. Skip silently. Mark `[x] Approved-SHA recompute — no change`.
   - **If different**: overwrite the `Approved-SHA:` frontmatter field with the new hash. Append a Revision Log entry: `YYYY-MM-DD: Approved-SHA recomputed post-Step-6 disposition. Previous: <8 chars>... New: <8 chars>...` Report: "Approved-SHA recomputed (DA dispositions edited protected sections): <8 chars>... → <8 chars>..."

**Why end-of-Step-6**: by this point all implementation work is done and any inline DA-disposition edits to Scope/AC have landed. The post-implementation checklist (Step 7) and the `/close` Step 2 verification will both read the recomputed hash. /close's spec-integrity gate (Spec 089) is unchanged — it still verifies against the stored `Approved-SHA:`; the fix moves the *write side* of the timing, not the read side.

7. After implementation, run the post-implementation checklist and emit gate outcomes:
   - [ ] All acceptance criteria satisfied — state which file/function satisfies each
   - [ ] Tests written or updated for changed behavior
   - [ ] Test output is green (run tests via the project's configured test command)
   - [ ] Spec status updated to `implemented`
   - [ ] docs/specs/README.md index updated
   - [ ] docs/specs/CHANGELOG.md entry added
   - [ ] README.md update check — see Step 7a (active detection — Spec 180)
   - [ ] Harness run saved to `tmp/` if harness-relevant behavior changed
   - [ ] Template/own-copy sync verified — see Step 7b (active detection — Spec 180)
   - [ ] Authorization-rule lint gate — see Step 7c (active detection — Spec 327)
   - [ ] AGENTS.md prose↔YAML drift detector — see Step 7d (active detection — Spec 330)

### [mechanical] Step 7a — README Update Detection (Spec 180)

Scan the spec's Scope and Acceptance Criteria sections for indicators that user-facing behavior changed:

**Keyword scan**: Search for:
- "CLI", "command", "argument", "flag", "option", "parameter"
- "output", "format", "schema", "endpoint", "API"
- "adds command", "removes command", "renames", "new option"
- Any mention of changes to command names, outputs, or interfaces

Also scan the changed files list for files matching: `*.md` in root (README.md), `QUICK-REFERENCE.md`, `CONTRIBUTING.md`.

- If **no CLI/command/output indicators found** AND **no doc files in changed list**: mark `[x] README.md update check — no CLI changes detected`. Proceed silently.
- If **indicators found** AND **README.md is NOT in the changed files list**:

  Present:
  ```
  README UPDATE CHECK — This spec appears to change user-facing behavior but README.md was not updated.
  Indicators: <list of matched keywords>
  ```
  > **Choose** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `update` | User-facing change without README update creates docs drift | Update README.md now to reflect the changes |
  > | **2** | — | `skip` | Operator confirms README update not needed | Proceed — README update not needed (reason will be logged) |

  - If `update`: pause implementation to update README.md.
  - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: README update check: skipped — operator confirmed not needed.`

- If **README.md is already in the changed files list**: mark `[x] README.md update check — already updated`. Proceed silently.

### [mechanical] Step 7b — Template/Own-Copy Sync Verification (Spec 180)

Scan the changed files list (from `git diff --name-only` against the spec baseline) for files that exist in both `template/` and the project root (own-copies).

**Detection logic**:
- For each changed file under `template/.claude/commands/`, check if a corresponding file exists at `.claude/commands/` (same filename).
- For each changed file under `template/.forge/commands/`, check if a corresponding file exists at `.forge/commands/` (same filename).
- For each changed file under `template/bin/`, check if a corresponding file exists at `bin/` (same filename).
- For each changed file under `template/scripts/`, check if a corresponding file exists at `scripts/` (same filename).
- For each changed own-copy file at `.claude/commands/`, `.forge/commands/`, `bin/`, or `scripts/`, check if a corresponding file exists under `template/`.
- Exclude files with `.jinja` suffix from exact-match comparison (template files may have `.jinja` suffix while own-copies do not).

- If **no dual files found in the changed set**: mark `[x] Template/own-copy sync verified — no dual files changed`. Proceed silently.
- If **dual files found but both sides were changed**: mark `[x] Template/own-copy sync verified — both sides updated`. Proceed silently.
- If **only one side was changed** (template changed but own-copy not updated, or vice versa):

  Present:
  ```
  TEMPLATE/OWN-COPY DRIFT — The following files were changed on one side but not the other:
  <list of drifted files with which side was changed>

  FORGE requires template and own-copy command files to stay in sync.
  ```
  > **Choose** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `sync` | Restores parity automatically; safest default | Apply the changes to the missing side now |
  > | **2** | — | `skip` | Drift intentional; reason recorded | Proceed — drift is intentional (reason will be logged) |

  - If `sync`: for each drifted file, copy the changes to the other side.
  - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Template/own-copy sync check: skipped — drift noted as intentional for <files>.`

### [mechanical] Step 7c — Authorization-Rule Lint Gate (Spec 327)

If the spec's Implementation Summary `Changed files` list includes any path under `.claude/commands/`, `.forge/commands/`, `template/.claude/commands/`, or `template/.forge/commands/`, run the authorization-rule lint gate against the current command surface.

```bash
bash scripts/validate-authorization-rules.sh --evidence-dir tmp/evidence/SPEC-NNN-YYYYMMDD/
```

(On Windows-only environments without bash, use the PowerShell parity: `pwsh scripts/validate-authorization-rules.ps1 -EvidenceDir tmp/evidence/SPEC-NNN-YYYYMMDD/`.)

The `--evidence-dir` flag (Spec 333) writes a JSON audit artifact (`<dir>/validate-authorization-rules-<timestamp>.json`) capturing input SHA, mode, result, and summary. Failure to write the artifact emits a stderr warning but does NOT fail the gate. The directory is created if it does not exist.

The linter reads the sentinel-delimited YAML block in `AGENTS.md` and scans every command body for authorization-required actions (`git push`, `gh pr create`, `rm -rf`, etc.) that lack a gating token within the configured proximity window.

**Gate result**:
- `GATE [authorization-rule-lint]: PASS` — no violations; proceed.
- `GATE [authorization-rule-lint]: WARN` — violations found in advisory mode (default at first ship per Spec 327 Path B). Continue; the findings feed Spec 326's triage.
- `GATE [authorization-rule-lint]: FAIL` — violations found in strict mode. Address the violations (add a confirmation prompt, or whitelist via `scripts/auth-rules-whitelist.yaml` with an explicit `reason:`), or revert the change.

See: [docs/process-kit/agents-md-authorization-model.md](../../docs/process-kit/agents-md-authorization-model.md) (Spec 334) for the two-sided model, alias-map semantics, and triage decision tree.

**Skip conditions**:
- If the spec's changed-files list contains no command-body paths: skip silently. Mark `[x] Authorization-rule lint gate — no command bodies in scope`.
- If `AGENTS.md` does not contain the sentinel-delimited structured block: report "Authorization-rule lint gate: AGENTS.md missing forge:auth-rules block — gate skipped (file the gap as a follow-up)." Mark `[x]` with a note.

The current default mode at first ship is `advisory`. Operator flips to `strict` (via `mode:` field in the AGENTS.md structured block) after Spec 326's triage of the first-run findings completes.

### [mechanical] Step 7d — AGENTS.md Prose↔YAML Drift Detector (Spec 330)

Sibling check to Step 7c. Where Step 7c lints command BODIES against the YAML block, Step 7d verifies the YAML block itself stays in sync with the operator-readable PROSE bullets that authorize the same actions. Drift between prose and block is itself a defect class: an operator adding a new bullet to the prose without updating the block produces a silent gap in Step 7c's coverage.

If the spec's Implementation Summary `Changed files` list includes any path under `.claude/commands/`, `.forge/commands/`, `template/.claude/commands/`, `template/.forge/commands/`, **or `AGENTS.md`**, run the drift detector:

```bash
bash scripts/validate-agents-md-drift.sh --evidence-dir tmp/evidence/SPEC-NNN-YYYYMMDD/
```

(On Windows-only environments without bash, use the PowerShell parity: `pwsh scripts/validate-agents-md-drift.ps1 -EvidenceDir tmp/evidence/SPEC-NNN-YYYYMMDD/`.)

The `--evidence-dir` flag (Spec 333) writes a JSON audit artifact (`<dir>/validate-agents-md-drift-<timestamp>.json`) capturing input SHA, mode, result, and drift summary. Same warn-but-don't-fail semantics as the auth-rule lint above.

The drift detector compares (a) action names enumerated in the AGENTS.md `### Authorization-required commands` PROSE bullets against (b) action names declared in the sentinel-delimited YAML block. Prose phrasing is normalized via `scripts/agents-md-action-aliases.yaml` (e.g., prose `force push` → block `git_push_force`).

**Gate result**:
- `GATE [agents-md-drift]: PASS` — both sides in sync; proceed.
- `GATE [agents-md-drift]: WARN` — drift found in advisory mode (default at first ship per Spec 327 pattern). Continue; surface findings as input to triage.
- `GATE [agents-md-drift]: FAIL` — drift found in strict mode. Address by adding the missing bullet/action on the side that lacks it, or extend the alias map (`aliases:` for prose phrasings of existing block actions; `ignore_prose:` / `ignore_block:` for entries intentionally not tracked by drift).

See: [docs/process-kit/agents-md-authorization-model.md](../../docs/process-kit/agents-md-authorization-model.md) (Spec 334) — § Triage Decision Tree maps each WARN/FAIL output (`prose-only`, `block-only`, `malformed alias-map`) to a concrete fix.

**Skip conditions**:
- If neither command-body paths NOR `AGENTS.md` are in the spec's changed-files list: skip silently. Mark `[x] AGENTS.md prose↔YAML drift detector — no relevant files in scope`.
- If `AGENTS.md` is missing the sentinel-delimited structured block (linter exits 2 with config error): report "Drift detector: AGENTS.md missing forge:auth-rules block — gate skipped (file the gap as a follow-up)." Mark `[x]` with a note.

The current default mode is `advisory`. Operator flips to `strict` (via `--mode=strict`) after the prose↔block alignment is confirmed clean — this is the prerequisite for flipping Spec 327's mode advisory→strict (per Spec 330 Trigger).

<!-- module:compliance -->
   - [ ] **Lane B compliance gate check** (conditional — skip if `docs/compliance/profile.yaml` absent): Load profile `gate_rules`. Verify required evidence artifacts are present. Emit `GATE [lane-b/<gate>]: PASS/FAIL/CONDITIONAL_PASS` for each gate. FAIL is blocking.
<!-- /module:compliance -->
<!-- module:nanoclaw -->
   - [ ] Evidence artifacts captured (optional — run if NanoClaw async review is enabled):
     ```bash
     source .forge/lib/evidence.sh
     forge_evidence_init "NNN"
     forge_evidence_capture_output "test-run" <test_command>
     forge_evidence_diff_summary
     forge_evidence_ac_checklist "docs/specs/NNN-*.md"
     forge_evidence_attach_format   # paste output into gate message
     ```
     Artifacts saved to `tmp/evidence/SPEC-NNN-YYYYMMDD/` (gitignored).
<!-- /module:nanoclaw -->
   Emit gate outcomes:
   - `GATE [test-execution]: PASS/FAIL — <test results summary>`. On FAIL: `Remediation: fix failing tests before marking implemented.`
   - `GATE [post-implementation]: PASS/FAIL — <checklist summary>`. On FAIL: `Remediation: complete missing checklist items: <items>.`
8. **Implementation retrospective**: Draft SIG-NNN entries for any errors, user corrections, or insights from this cycle. Show drafts, get confirmation, then append to `docs/sessions/signals.md` and update today's session log.

   **Spec 371 — Window-bounded scan timestamp write**: After the retrospective scanner runs (regardless of candidate count, including zero), write/update the per-session scan-timestamp file so `/close` Step 8b can dedup against this window:
   ```bash
   # Resolve session id from active-tab marker; fall back to deterministic hash if absent.
   sid=$(ls .forge/state/active-tab-*.json 2>/dev/null | head -1 | sed -E 's|.*active-tab-([^.]+)\.json|\1|')
   sid="${sid:-default-$(date +%Y%m%d)-NNN}"
   mkdir -p .forge/state
   cat > ".forge/state/last-eaci-scan-${sid}.json" <<EOF
   {"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","command":"/implement","spec":"NNN"}
   EOF
   ```
   This file is the dedup primitive shared with `/close` Step 8b; it is GC'd by `/tab close` Step 3b. Skip silently on write failure (the scan still ran; the dedup is a best-effort optimization).
9. **Implementation summary (Spec 239)**: Present a concise summary of what was implemented. Do NOT present a Review Brief here — the formal Review Brief is generated exclusively at `/close` (Step 2e).
   a. Output the summary:
      ```
      ## Implementation Summary — Spec NNN
      **Changed files**: <bulleted list of files modified>
      **AC status**: <N/N acceptance criteria satisfied — list each AC with pass/fail>
      **Test results**: <test command output summary — pass/fail count>
      ```
   b. If no human-judgment items are likely needed at `/close` (all ACs are machine-verifiable): note "This spec appears delegation-eligible at L3+ — all ACs are machine-verifiable."
   c. This summary is informational — the formal gate review happens at `/close`.
   d. **Append spec-implemented event (Spec 254 — Approach D)**: Append to the per-spec event stream:
      ```bash
      echo '{"timestamp":"<ISO 8601>","event_type":"spec-implemented","payload":{"changed_files":<count>,"ac_pass":<N>,"ac_total":<M>}}' >> .forge/state/events/NNN/spec-implemented.jsonl
      ```
      Append-only; conflict-free. Consumed by `render_changelog.py` to surface the implementation event in the chronological log.

### [mechanical] Step 9d — Post-Implementation Value Demo (Spec 261)

After presenting the implementation summary, check if this spec qualifies for a value demonstration:

**Trigger criteria** (all parsed from spec frontmatter — no free-text scanning):
- `R >= 3` in the `Priority-Score:` field (high-risk spec — value of the fix is worth showing), OR
- `Consensus-Review: true` in frontmatter (external-facing spec — demo aids human review)

If **neither criterion is met**: skip silently. Most specs will skip.

If **criteria met**: append a value demo option to the choice block:
```
## Value Demo Available
This spec qualifies for a before/after value demonstration (R >= 3 or consensus-reviewed).
```
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **demo** | 1 | `demo` | Aids /close human review for high-risk specs | Show 3-5 line before/after comparison |
> | **skip** | 2 | `skip` | Demo not needed; proceed straight to /close reminder | Skip demo — proceed to /close reminder |

If the operator selects **demo**:
- Produce a concise before/after comparison (max 5 lines) drawn from the spec's Objective and scope:
  ```
  ### Before (vulnerability/gap)
  <1-2 lines describing what was broken/missing, from spec Objective>

  ### After (protection/capability)
  <1-2 lines describing what is now protected/fixed, from implementation evidence>
  ```
- Source the "before" content from the spec's Objective/Scope sections (documented state). Source the "after" from the implementation evidence and changed files. Do NOT hallucinate pre-fix states that aren't documented.

If the operator selects **skip**: proceed normally.

### [mechanical] Step 9e — Conditional Consensus Gate (Spec 258)

After the implementation summary and value demo steps, check if this spec requires consensus review before /close:

1. **Read spec frontmatter** for `Consensus-Review:` field.
2. **Evaluate trigger**:
   - If `Consensus-Review: true`: consensus is required.
   - If `Consensus-Review: auto`: evaluate auto-trigger criteria:
     - Spec is listed in the sync manifest as public-facing, OR
     - BV >= 4 with scope touching documentation or external interfaces, OR
     - Change-Lane is `standard-feature` AND R >= 3
     If any auto-trigger criterion is met: consensus is required. Otherwise: skip.
   - If `Consensus-Review:` is absent or any other value: skip silently.

3. **If consensus required**: present a consensus gate notification:
   ```
   CONSENSUS GATE — Spec NNN has Consensus-Review enabled.
   Run /consensus before /close to gather structured multi-role input.
   ```
   Add `consensus` as an option in the Next Action choice block below.

4. **If consensus not required**: skip silently. Most specs will skip.

This gate is advisory — it does NOT block /close. Consensus review is optional but recommended when triggered.

10. Remind me to run `/close NNN` to confirm and transition to `closed`.

---

## Next Action

Implementation complete. **Do not run `/close` automatically.** A human must review the deliverables before closing.

> No agent confirms on your behalf. The human validation gate requires your explicit review.

<!-- safety-rule: session-data — if today's session log has unsynthesized spec activity AND ## Summary is unpopulated, /session is inserted at rank 1 and stop is downgraded to —. See docs/process-kit/implementation-patterns.md § Session-data safety rule. -->

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `/close NNN` | Closure path; default after your review | Validate and close this spec (after your review) |
> | **2** | — | `/consensus NNN` | Heavy review; reserve for genuinely contentious specs | Run structured multi-role consensus review before closing |
> | **3** | 2 | `/now` | Survey state if uncertain about next move | Check project state for other work |
> | **4** | — | `stop` | Downgraded if today's session log has unsynthesized entries | End session — review deliverables offline |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

**Session-data safety rule (Spec 320 Req 4)**: Before emitting the choice block, evaluate today's session log per the positive "populated Summary" definition. If the rule fires (unsynthesized spec activity AND Summary unpopulated): **insert `session` at rank 1**, downgrade `stop` to `—`, renumber rows.


## [mechanical] Tab-lane awareness directive (Spec 351)

Before emitting any next-action choice block in this command, consult the active-tab marker (Spec 353 primitive):

1. Read `.forge/state/active-tab-*.json` (primary). If present, extract `lane`. If `last_command_at` > 30 minutes ago, treat marker as **stale**.
2. If no marker, fall back to `docs/sessions/registry.md` rows with `Status = active` for the current session. Use the row's `Lane` column.
3. If neither yields an active lane: emit the choice block as today. No preamble, no filtering, no annotation. **Skip the rest of this directive.**
4. If an active lane is detected: emit the one-line preamble (`Tab lane: <lane>. Options below filtered to lane scope.` / `... Cross-lane options annotated.` / `... (stale ~Nm)...`) and apply the filter/annotate decision rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules.
5. Filtered rows are struck through with rank `—` (not silently dropped) so the operator can override by typing the keyword directly.

The guide is the single source of truth for which rows filter vs annotate per lane. This directive is intentionally short — the central guide encodes the rules so every emitter stays consistent.

