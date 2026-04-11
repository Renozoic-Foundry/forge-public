---
name: evolve
description: "Run the KCS Evolve Loop review"
model_tier: sonnet
workflow_stage: review
---

# Framework: FORGE
Run the KCS Evolve Loop review. Use this after a spec reaches `implemented` or monthly.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /evolve — Run the KCS evolve loop review.
  Usage: /evolve [--auto | --full | --spec NNN]
  Arguments:
    (none)        — interactive: ask which spec triggered this, or periodic review
<!-- module:nanoclaw -->
    --auto        — automated mode: run per config in docs/sessions/evolve-config.yaml;
                    deliver results via NanoClaw if configured; require human approval for actions
<!-- /module:nanoclaw -->
    --full        — force full F1-F4 review regardless of trigger mode
    --spec NNN    — fast-path review triggered by closing spec NNN
  Triggers: after each spec reaches `implemented` (fast path F1+F4),
    or monthly (full F1-F4 with KPI review and score calibration).
  Behavior: Checks AC drift, updates backlog, reviews error/insight patterns.
<!-- module:nanoclaw -->
  Config: docs/sessions/evolve-config.yaml — trigger mode, NanoClaw delivery, approval gate
<!-- /module:nanoclaw -->
  See: docs/process-kit/human-validation-runbook.md (section F), CLAUDE.md (evolve loop)
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 0 — Load config and resolve mode
Read `docs/sessions/evolve-config.yaml` (skip silently if absent — use defaults: trigger=manual, notify_via=log-only).

Determine run mode:
- If `--auto` in $ARGUMENTS: automated mode — check trigger conditions from config:
  a. If `trigger=on_spec_count`: read session logs to count specs closed since `last_evolve_loop_run:` in `docs/sessions/evolve-state.md` (create if absent). If count ≥ `spec_count_threshold`, proceed. Otherwise: report "Auto evolve loop: trigger condition not yet met (N/threshold specs closed)." Stop.
  b. If `trigger=time`: check `last_evolve_loop_run:` date. If days elapsed ≥ `time_interval_days`, proceed. Otherwise: report "Auto evolve loop: N days since last run (threshold: time_interval_days)." Stop.
  c. If `trigger=manual`: report "Auto evolve loop: trigger=manual in config. Skipping automated run." Stop.
- If `--spec NNN`: fast-path mode for spec NNN.
- If `--full`: full F1-F4 review.
- Otherwise: interactive mode — ask which spec was just completed (or confirm periodic review).

### [mechanical] Step 0a — Evolve Loop State Marker (Spec 191)
Write the evolve-loop state marker to `docs/sessions/context-snapshot.md`:
```
## Active evolve loop
status: in-progress
started: YYYY-MM-DD HH:MM
mode: <fast-path|full|interactive>
```
This marker prevents solve-loop commands (/implement, /spec, /close) from executing while the evolve loop is active. The marker is cleared only after the exit gate completes (see "Evolve Loop Exit Gate" below).

### [mechanical] Current Goal tracking (Spec 091)
After completing each numbered section (fast-path steps 3-5, or full-review steps 3-10), emit a review progress block at the END of your output:
```
---
## Review Progress
**Command**: /evolve
**Mode**: fast-path (spec NNN) | full (F1-F4)
**Section**: <current section name>
**Completed**: <comma-separated list of completed sections>
**Remaining**: <comma-separated list of remaining sections>
---
```
Update `docs/sessions/context-snapshot.md` `## Evolve loop status` with review progress at start and completion.

1. (Interactive mode only) Ask which spec was just completed (or confirm this is a periodic review).
2. Read docs/process-kit/human-validation-runbook.md section F.

**If triggered by spec completion (fast path — F1 + F4 only):**
3. Open the just-completed spec and check one acceptance criterion against the code:
   - State the criterion, the file/function it maps to, and whether the code satisfies it
   - Flag any drift as a process defect requiring a new spec
4. Read docs/backlog.md — confirm the completed spec's row is updated to `implemented` and the `Last updated` date is current.
5. Check if any other backlog items are now unblocked by this completion and note them.

**If periodic review (full F1–F4):**
3. Spot-check 2–3 `implemented` or `closed` specs for acceptance criteria drift.
4. <!-- customize: replace with your project's CLI help command -->
   Check docs/README.md CLI commands against actual CLI help output.
5. Report KPI trends from session logs: lead time, hotfix count, doc drift events since last review.
6. Score calibration: compare predicted vs actual BV for completed specs — flag if systematic bias found.
6b. **E/TC calibration (Spec 158)**: For specs closed since last calibration:
   a. If `.forge/metrics/command-costs.yaml` exists: read actual token cost data for each spec. Compare `Token-Cost:` frontmatter estimate ($, $$, $$$) against actual tokens consumed. Flag specs where actual diverges significantly from estimate (e.g., $ estimate but $$$ actual cost).
   b. If session data exists: compare expected session count (inferred from E score — E=1-2: single session, E=3: 1-2 sessions, E=4-5: 2+ sessions) vs actual sessions from session logs.
   c. Flag systematic E over-prediction (AI handles it easier than estimated — 3+ specs where actual E was lower) or under-prediction (iteration loops not anticipated — 3+ specs where actual E was higher).
   d. If systematic bias detected in either direction: recommend updating E anchor guidance and present specific anchor adjustments.
   e. If no metrics data exists: report "E/TC calibration: no metrics data available. Calibration will activate when .forge/metrics/ data accumulates."
6c. **CEfO advisory dispatch (Spec 187)**: If `forge.dispatch_rules.enabled` is `true` in AGENTS.md:
   - Read `.claude/agents/cefo.md` for the role preamble.
   - Spawn CEfO as an isolated sub-agent with the E/TC calibration data from step 6b and the regret rate data (if available from metrics).
   - Prompt: "Review the E/TC calibration results and regret rate data. Assess whether effort estimates are systematically miscalibrated, token costs are trending unsustainably, or process overhead is disproportionate. Produce your standard review block."
   - Present the CEfO advisory inline after the calibration results:
     ```
     ### CEfO Advisory — Efficiency Review
     <CEfO review block>
     ```
   - If `forge.dispatch_rules.enabled` is `false` or absent: skip silently.
7. Update `Last score calibration:` in docs/backlog.md.
8. **Signal pattern analysis (Spec 044):** Read `docs/sessions/signals.md`. Apply structured pattern detection:
   a. **Parse**: Extract from each signal entry: type tag (e.g. `[process]`, `[tooling]`, `[template]`), affected component(s), root-cause keywords (words in title/description that could recur).
   b. **Group**: Cluster entries with matching type tags or overlapping root-cause keywords (≥2 keyword overlap = related).
   c. **Score**: For each cluster, compute pattern severity = impact_level × frequency:
      - impact_level: high=3, medium=2, low=1 (use the signal's `Impact:` field if present, else medium)
      - frequency = number of entries in the cluster
      - severity_score = impact_level × frequency
      - Label: score ≥6 → `high`; score 3-5 → `medium`; score 1-2 → `low`
   d. **Report (pattern table)**:
      ```
      Signal Pattern Analysis — <date>
      | Pattern | Type | Occurrences | Severity | Signal IDs | Status |
      |---------|------|-------------|----------|------------|--------|
      | <pattern name> | [type] | N | high/med/low | SIG-NNN, ... | systemic gap → spec recommended |
      ```
      - Patterns with 1 occurrence: list as "isolated — monitor"
      - Patterns with 2+ occurrences at medium+ severity: flag as "systemic gap → spec recommended"
   e. Save the pattern table to `docs/sessions/pattern-analysis.md` (append with date header; create if absent).
   f. **Knowledge consolidation**: If pattern analysis reveals 10+ signals or 3+ recurring themes, recommend running `/synthesize` to consolidate accumulated knowledge into a refined reference document.
8b. **Trust calibration review (Spec 160):** Read `docs/sessions/signals.md` for trust signals (type tag `[trust]`):
   a. **Aggregate corrections by check type**: For each check type that appears in trust signals, count:
      - Total spec closures where this check type was machine-verified (estimate from CHANGELOG close count)
      - Number of human corrections for this check type
   b. **Apply calibration rules** (from `docs/process-kit/gate-categories.md`):
      - 0 corrections over 10+ closures → recommend confirming as machine-verifiable (no change needed)
      - 2+ corrections in 5 closures → recommend escalating to confidence-gated or human-judgment-required
      - Confidence-gated check consistently HIGH with 0 corrections → recommend graduating to machine-verifiable
   c. **Present recommendations** (if any adjustments are warranted):
      ```
      Trust Calibration — <date>
      | Check Type | Closures | Corrections | Current Category | Recommendation |
      |------------|----------|-------------|-----------------|----------------|
      | <check>    | <N>      | <N>         | machine-verifiable | escalate to confidence-gated |
      ```
      These are **recommendations only** — present as a choice block: **apply** (update gate-categories.md) | **defer** (revisit next cycle) | **dismiss**.
   d. If no trust signals exist or no adjustments are warranted: report "Trust calibration: no adjustments needed (N closures reviewed, 0 corrections)."

8c. **CQO advisory dispatch (Spec 187)**: If `forge.dispatch_rules.enabled` is `true` in AGENTS.md:
   - Read `.claude/agents/cqo.md` for the role preamble.
   - Spawn CQO as an isolated sub-agent with the signal pattern analysis results (step 8) and trust calibration results (step 8b).
   - Prompt: "Review the signal pattern analysis and trust calibration data. Assess whether quality gaps are systemic, acceptance criteria rigor is declining, or trust calibration adjustments are warranted. Produce your standard review block."
   - Present the CQO advisory inline after the trust calibration results:
     ```
     ### CQO Advisory — Quality Review
     <CQO review block>
     ```
   - If `forge.dispatch_rules.enabled` is `false` or absent: skip silently.

9. **Deferred signal review:** Identify any signal whose action was "deferred" that is now unblocked by recent completed specs. Promote to spec trigger if appropriate.
10. **Spec proposal generation (Spec 045):** For each systemic gap pattern flagged in step 8 (severity ≥ config `proposal_min_severity`, occurrences ≥ `proposal_min_occurrences`):
    a. Draft a spec proposal:
       ```
       ## PROPOSAL — <pattern name>
       Title: <concise spec title>
       Objective: <1-2 sentences: what gap does this spec close?>
       Scope in: <bullet list of changes needed>
       Scope out: <what is explicitly excluded>
       Score estimate: BV=<N> E=<N> R=<N> SR=<N> → ~<total>
       Signal references: SIG-NNN, SIG-NNN
       ```
    b. Limit proposals to `max_proposals_per_cycle` (default 5) — rank by severity × occurrences, take top N.
    c. **Review Router (Spec 159)**: Before presenting proposals, run the review router on the full set:
       - Select perspectives: **DA** (always — risk check on generated proposals) + **COO** (always — process impact). Add **MT** if proposal count > 3 (are we solving the right problems?).
       - Display selection rationale.
       - Run selected perspectives on the proposal set as a whole.
       - Present the Review Brief before the choice block.
    d. Present all proposals together. For each proposal, include its `Objective:` field in the disposition block so operators can evaluate what each proposal is for without having to re-read the full proposal:
       ```
       SPEC PROPOSALS — <N> generated from signal patterns
       1. <Title> — <Objective (first sentence)>
       2. <Title> — <Objective (first sentence)>
       ...
       > **Choose action for each** — type: approve <N> | modify <N> | dismiss <N>
       ```
    d. On `approve <N>`: run `/spec` with the proposal title and content to create the draft spec.
    e. On `modify <N>`: accept operator edits to the proposal, then run `/spec` with revised content.
    f. On `dismiss <N>`: record dismissal in `docs/sessions/pattern-analysis.md` as `dismissed: YYYY-MM-DD — <reason>`. Suppresses re-proposal for this pattern in subsequent cycles.

    g. **Multi-role vetting**: For high-impact proposals (severity `high` or BV >= 4), recommend running `/consensus <proposal>` to gather structured feedback from all registry roles before approving.
After either path:
- **Metrics rotation** (Spec 102 — skip if `.forge/metrics/` directory does not exist):
  Read `forge.model_router.metrics_retention_days` from AGENTS.md (default: 30).
  Run: `bash .forge/bin/forge-metrics-rotate.sh <retention_days>`
  Report the rotation result (N archived, N retained).
- **Regret rate reporting** (Spec 085 — skip if `forge.model_router.mode` is `static` or `.forge/metrics/command-costs.yaml` does not exist):
  Read `.forge/metrics/command-costs.yaml`. For each command, count total invocations and escalations over the last 30 days. Report:
  ```
  Regret rate (last 30 days):
    /brainstorm: X% (N/M escalated from <tier> → <tier>)
    /implement: X% (N/M escalated)
    ...
    Overall: X%
  ```
  Flag any command with regret rate > 10% and recommend adjusting its baseline tier.
  Save the regret rate table to `docs/sessions/pattern-analysis.md` under a `## Model Router Regret Rate` heading (append with date).
- **Deferred scope aging (Spec 199):** Read `docs/backlog.md` for any items tagged as deferred scope. For each deferred item, check its origination date. Flag items older than 14 days without disposition:
  ```
  DEFERRED SCOPE AGING — The following items are >14 days old without disposition:
  - <date> from Spec NNN: <item summary> (<age> days)
  Action required: promote to spec, drop, or carry forward with justification.
  ```
  If no aged items found: report "Deferred scope: all items current (none >14 days)."
- Check docs/sessions/scratchpad.md for open `[evolve]` (or legacy `[outer-loop]`) notes — report and ask to resolve or convert to a spec.
- Remind me to update the `Last evolve loop review:` field in today's session log.

## [decision] Evolve Loop Exit Gate (Spec 191)

Before returning control to the solve loop, verify all evolve-loop work is complete:

1. **Proposals check**: Confirm all spec proposals from step 10 have been dispositioned (approved, modified, or dismissed). If any proposals are pending: "Undispositioned proposals remain. Resolve before exiting." Do not proceed.

2. **Scratchpad check**: Confirm all `[evolve]` scratchpad notes have been reviewed (resolved, converted to spec, or carried forward). If unreviewed notes remain: list them and ask to resolve or carry forward.

3. **Approved proposals captured**: List all approved proposals as session-log artifacts. These are NOT created as specs inline — they are converted to specs only after the operator exits the evolve loop and explicitly runs `/spec`.
   ```
   ## Approved proposals (pending spec creation)
   - <proposal title> — approved, create via `/spec` after exiting
   ```

4. **Exit choice block**: Present the exit gate:
   ```
   Evolve loop review complete.
   ```
   > **Choose** — type a number or keyword:
   > | # | Action | What happens |
   > |---|--------|--------------|
   > | **1** | `implement next` | Exit evolve loop → `/implement next` |
   > | **2** | `spec <title>` | Exit evolve loop → create spec from approved proposal |
   > | **3** | `stop` | Exit evolve loop → end session |
   >
   > _(No solve-loop commands execute until you choose.)_

5. **Clear state marker**: After the operator chooses, remove the `## Active evolve loop` section from `docs/sessions/context-snapshot.md`. Report: "Evolve loop closed. Solve-loop commands re-enabled."

6. Execute the chosen action.

<!-- module:nanoclaw -->
## [mechanical] Automated delivery (Spec 043 — conditional)
If `--auto` was in $ARGUMENTS and the config `notify_via=nanoclaw`:
a. Compile the evolve loop results into a NanoClaw digest message:
   ```
   🔄 FORGE Evolve Loop — <date>
   Specs reviewed: <count>
   AC drift detected: <yes/no — list if yes>
   Signal patterns: <N new patterns found>
   Score calibration: <adjustments summary>
   Proposed actions (require approval):
   - [ ] <action 1> — approve? (reply "approve <N>" or "skip <N>")
   - [ ] <action 2>
   ```
b. Send via the configured NanoClaw channel (use `mcp__nanoclaw__send_message` or reference `nanoclaw_task_id` from config).
c. **Human approval gate**: Do NOT execute any proposed actions (new specs, score changes, backlog updates) without explicit approval. Wait for the operator's reply before proceeding.
d. Update `docs/sessions/evolve-state.md`: set `last_evolve_loop_run: YYYY-MM-DD` and increment `runs_since_start`.

- If `notify_via=log-only`: append results to today's session log under `## Evolve Loop Run`. No NanoClaw message. Record `last_evolve_loop_run` in `docs/sessions/evolve-state.md`.
- If `docs/sessions/evolve-config.yaml` is absent: treat as `notify_via=log-only`.
<!-- /module:nanoclaw -->
