---
name: implement
description: "Build a spec end-to-end with evidence gates"
model_tier: sonnet
workflow_stage: implementation
---

# Framework: FORGE
# Model-Tier: sonnet
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
  After implementation: presents /handoff checklist inline, then reminds to /close.
  ```
  Stop — do not execute any further steps.

---

**Gate Outcome Format**: Read `.forge/templates/gate-outcome-format.md` and emit the structured format at every evidence gate.

---

## [mechanical] Step 0a — Evolve Loop Boundary Check (Spec 191)
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

---

**Step 0 — Resolve `next` argument**:
If $ARGUMENTS is `next` (case-insensitive):
  a. Read `docs/backlog.md`.
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
     > | # | Action | What happens |
     > |---|--------|--------------|
     > | **1** | `yes` | Implement Spec NNN (auto-selected) |
     > | **2** | `NNN` | Implement a different spec (type spec number) |
     > | **3** | `skip` | Stop — choose manually |
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
     d. Update the spec's row in `docs/specs/README.md` to `in-progress`.
     e. Add a CHANGELOG entry: `- YYYY-MM-DD: Spec NNN approved inline via /implement.`
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

After approval (status is now `in-progress`), compute a SHA-256 integrity hash:

1. **Extract sections**: Extract the full text of the `## Scope` section (from `## Scope` heading to the next `##` heading, exclusive) and the `## Acceptance Criteria` section (from `## Acceptance Criteria` heading to the next `##` heading, exclusive).
2. **Combine and normalize**: Concatenate the two extracted sections (Scope first, then Acceptance Criteria). Trim leading and trailing whitespace from the combined text.
3. **Compute hash**: Compute the SHA-256 hash of the combined, trimmed text. Produce the 64-character lowercase hex digest.
4. **Write to frontmatter**: Add `- Approved-SHA: <64-char hex>` to the spec file's frontmatter, immediately after the `Priority-Score:` line. If `Approved-SHA:` already exists, overwrite it (re-approval scenario).
5. Report: "Spec integrity signature written: Approved-SHA: <first 8 chars>..."

### [mechanical] Step 2b — Devil's Advocate Gate (Spec 078, updated by Spec 099)

Before writing any code, check if this spec has been reviewed by the devil's advocate.

1. Read the spec frontmatter for `DA-Reviewed:` and `DA-Decision:` fields.

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
   > | # | Action | What happens |
   > |---|--------|--------------|
   > | **1** | `rewrite` | Revise each vague criterion before implementing |
   > | **2** | `skip` | Proceed — skip recorded in revision log |
b. If `rewrite`: for each flagged criterion, prompt for a replacement. Rewrite in the spec before proceeding.
c. If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Acceptance criteria vague-language scan: skipped.`

If no vague language detected, or if spec was already `in-progress`/`approved` (not a fresh inline approval): proceed silently.

3. **Multi-tab claim check**: Check `docs/sessions/context-snapshot.md` for active tab status first; if snapshot is missing or stale, read `docs/sessions/registry.md` (if it exists). Check if any row with Status = `active` has claimed this spec number. If so, stop and report: "Spec NNN is claimed by tab '<label>' (started <time>). Run `/tab close` in that tab first, or choose a different spec." If no conflict, and a registry row exists for this session, update `Last active` to now. If no registry exists, skip this step silently.
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
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `add` | Pause to collect PowerShell equivalents and add them to the Test Plan |
  > | **2** | `skip` | Proceed — skip recorded in revision log |

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
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `hotfix` | Set lane to hotfix (critical fix) |
  > | **2** | `small-change` | Set lane to small-change (low-risk tweak) |
  > | **3** | `standard-feature` | Set lane to standard-feature (new feature or cross-cutting change) |
  > | **4** | `process-only` | Set lane to process-only (docs/tracking changes only) |

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
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `add` | Add integration point ACs to the spec now |
  > | **2** | `skip` | Proceed — skip recorded in revision log |

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
    > | # | Action | What happens |
    > |---|--------|--------------|
    > | **1** | `add` | Add missing entries to update-manifest.yaml now |
    > | **2** | `skip` | Proceed — skip recorded in revision log |

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
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `update` | Update README.md now to reflect the changes |
  > | **2** | `skip` | Proceed — README update not needed (reason will be logged) |

  - If `update`: pause implementation to update README.md.
  - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: README update check: skipped — operator confirmed not needed.`

- If **README.md is already in the changed files list**: mark `[x] README.md update check — already updated`. Proceed silently.

### [mechanical] Step 7b — Template/Own-Copy Sync Verification (Spec 180)

Scan the changed files list (from `git diff --name-only` against the spec baseline) for files that exist in both `template/` and the project root (own-copies).

**Detection logic**:
- For each changed file under `template/.claude/commands/`, check if a corresponding file exists at `.claude/commands/` (same filename).
- For each changed file under `template/.forge/commands/`, check if a corresponding file exists at `.forge/commands/` (same filename).
- For each changed own-copy file at `.claude/commands/` or `.forge/commands/`, check if a corresponding file exists under `template/`.
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
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `sync` | Apply the changes to the missing side now |
  > | **2** | `skip` | Proceed — drift is intentional (reason will be logged) |

  - If `sync`: for each drifted file, copy the changes to the other side.
  - If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Template/own-copy sync check: skipped — drift noted as intentional for <files>.`

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
9. **Inline handoff with Review Brief (Spec 160)**: Present the implementation results using the Review Brief format from `docs/process-kit/gate-categories.md`:
   a. Categorize each post-implementation check as machine-verifiable, human-judgment-required, or confidence-gated.
   b. Output the Review Brief:
      - **Machine-Verified**: All mechanical gates that passed (file presence, test execution, cross-reference sync, completeness, lint)
      - **Needs Your Review**: Items requiring human judgment before /close:
        - If spec modified user-facing commands or onboarding → UX judgment item
        - If spec modified README or external-facing content → external content item
        - If spec involves physical-world recommendations → Physical Logic Check (always human-judgment, cannot be delegated)
        - If spec touches auth/security → security review item
        - If spec is a novel pattern → novel situation assessment
      - **Machine-Handled**: Lower-priority machine-verified items not shown in detail
   c. If no human-judgment items are identified: note "This spec appears delegation-eligible at L3+ — all ACs are machine-verifiable."
   d. This is informational — the actual enforcement mode is determined at /close time.
10. Remind me to run `/close NNN` to confirm and transition to `closed`.

---

## Next Action

Implementation complete. **Do not run `/close` automatically.** A human must review the deliverables before closing.

> No agent confirms on your behalf. The human validation gate requires your explicit review.

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `/close NNN` | Validate and close this spec (after your review) |
> | **2** | `/now` | Check project state for other work |
> | **3** | `stop` | End session — review deliverables offline |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_
