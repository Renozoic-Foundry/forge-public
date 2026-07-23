---
name: evolve
description: "Run the KCS Evolve Loop review"
workflow_stage: review
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->

# Framework: FORGE
<!-- multi-block mode: serialized — evolve emits choice blocks at distinct mechanical steps (trust calibration, proposal disposition, scratchpad disposition, exit gate). Each block waits for operator response before the next is presented. Bare numerics work because only one block is ever co-presented at a time. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->

**Output verbosity (Spec 225)**: read `forge.output.verbosity` from `AGENTS.md` (default `lean`). In **lean** mode, suppress non-actionable diagnostics (passing-gate confirmations, KPI tables, calibration deltas, MCP pin status, deprecation scans, signal-pattern dumps, root-cause groupings, unchanged deferred-scope aging, unchanged score-rubric details) — write full detail to the relevant file artifact and emit a one-line chat pointer (or omit if purely informational). **Verbose** mode emits full detail. **Never suppressed**: choice blocks, FAILed gates, push-confirmation prompts, Review Brief "Needs Your Review" items, operator-input prompts, error/abort messages. Full rules: `docs/process-kit/output-verbosity-guide.md`.

Run the KCS Evolve Loop review. Use this after a spec reaches `implemented` or monthly.

> Timing guidance: see [session-synthesize-evolve-guide](../../docs/process-kit/session-synthesize-evolve-guide.md) for the canonical comparison of `/session` vs `/synthesize` vs `/evolve` — triggers, cadence, automation class.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /evolve — Run the KCS evolve loop review.
  Usage: /evolve [--auto | --full | --spec NNN | --insights [--errors|--friction|--signals|--velocity] [--since YYYY-MM-DD]]
  Arguments:
    (none)        — interactive: ask which spec triggered this, or periodic review
<!-- module:nanoclaw -->
    --auto        — automated mode: run per config in docs/sessions/evolve-config.yaml;
                    deliver results via NanoClaw if configured; require human approval for actions
<!-- /module:nanoclaw -->
    --full        — force full F1-F4 review regardless of trigger mode
    --spec NNN    — fast-path review triggered by closing spec NNN
    --insights    — process-mining mode (folded from /insights, Spec 587): cross-session
                    insights report only; does not run the rest of the evolve loop. Accepts
                    the former /insights sub-flags: --errors, --friction, --signals,
                    --velocity, --since YYYY-MM-DD.
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
Read `docs/sessions/evolve-config.yaml` (skip silently if absent — defaults: trigger=manual, notify_via=log-only).

Determine run mode:
- `--insights`: process-mining mode (Spec 587 fold). Run Step INSIGHTS below with the
  remainder of `$ARGUMENTS` (its former `/insights` sub-flags), then **stop** — do not run
  Step 0-cd or any later step in this file.
- `--auto`: automated mode; admission decided by signal thresholds in Step 0-cd (Spec 500 — supersedes the legacy `trigger=on_spec_count|time|manual` triggers). Proceed to Step 0-cd.
- `--spec NNN`: fast-path mode for spec NNN.
- `--full`: full F1-F4 review.
- Otherwise: interactive — ask which spec was just completed (or confirm periodic review).

### [mechanical] Step INSIGHTS — Insights mode (Spec 587 fold — formerly `/insights`)

Mine all FORGE process data to produce a cross-session, project-scoped insights report. This
mode is fully self-contained — it does not touch the rest of the evolve loop's state (no
backlog rescoring, no trust calibration, no evolve-config.yaml writes).

Parse the mode's arguments (the remainder of `$ARGUMENTS` after `--insights`):
- Set `MODE` = `full` (default), or one of: `errors`, `friction`, `signals`, `velocity` if the matching flag is present.
- Set `SINCE` = the date string after `--since` if provided, else empty.
- If `--errors` → MODE=errors. If `--friction` → MODE=friction. If `--signals` → MODE=signals. If `--velocity` → MODE=velocity.

If `docs/sessions/` does not exist or contains no `.md` files other than `_template.md`:
  Report: "No session data found. Run `/session` to create your first session log."
  Stop.

<!-- parallel: steps I1-I6 are independent reads — run them simultaneously -->

#### [mechanical] Step I1 — Read session logs

Read all `.md` files in `docs/sessions/` excluding `_template.md`, `signals.md`, `error-log.md`, `insights-log.md`, `scratchpad.md`, `context-snapshot.md`, and `registry.md`.

If `SINCE` is set: only include session files whose date prefix (YYYY-MM-DD in filename) is >= SINCE.

From each session log, extract:
- **Pain points / friction items**: lines under "Pain points", "Blockers", or "Process improvement items" sections
- **Spec triggers**: items listed as spec triggers (unchecked or noted)
- **Decisions**: items in any "Decisions" section
- **Date**: from the filename (YYYY-MM-DD)

#### [mechanical] Step I2 — Read error-log.md

Read `docs/sessions/error-log.md`.
Extract each EA-NNN entry: ID, title, root cause category, affected component, date (if present).
If file does not exist: skip silently.

#### [mechanical] Step I3 — Read insights-log.md

Read `docs/sessions/insights-log.md`.
Extract each CI-NNN entry: ID, title, category, date (if present).
If file does not exist: skip silently.

#### [mechanical] Step I4 — Read signals.md

Read `docs/sessions/signals.md`.
Extract each SIG-NNN entry: ID, type (error/insight/decision/feedback), summary, action.
If file does not exist: skip silently.

#### [mechanical] Step I5 — Read scratchpad.md

Read `docs/sessions/scratchpad.md`.
Extract all open notes: their tag (`[spec-trigger]`, `[validate]`, `[evolve]`, untagged), content, and age (date added if present).
If file does not exist: skip silently.

#### [mechanical] Step I6 — Backlog state (Spec 399)

Run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog --format=json`. Parse the stdout as a JSON array; each row has keys `rank, spec_id, title, bv, e, r, sr, score, depends, status`.
Extract:
- All specs with their status and score (cross-reference per-spec frontmatter for `Last updated:` if needed for aging)
- Any stalled specs: status = `draft` or `in-progress` with no movement in > 14 days (read individual spec frontmatter for the `Last updated:` timestamp; helper does not surface that field)
- The `Last evolve loop review:` date is read separately from `docs/sessions/context-snapshot.md` (or the most recent `/evolve` session log) — not surfaced by the helper.

#### [mechanical] Step I7 — Spec index for cross-reference (Spec 399)

Run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-spec-index --format=json`. Parse the stdout as a JSON array; each row has keys `spec_id, slug, status, title`. Collect all spec IDs and titles for cross-referencing.
Build a set: `TRACKED` = all spec titles/descriptions visible in the spec index + scratchpad.md open notes.
This is used in Step I8 to avoid recommending what's already tracked.

#### [mechanical] Step I8 — Analyze

Perform only the dimensions included in MODE (or all if MODE=full):

**A — Error patterns** (skip if MODE != full and MODE != errors)

Group EA-NNN entries by root cause category or affected component.
For each group with 2+ entries:
- Pattern name: inferred common theme (e.g., "shell script path/encoding issues")
- Occurrences: list of EA-NNN IDs
- Severity: `isolated` (1 occurrence) | `recurring` (2–3) | `systemic` (4+)
- Check if this pattern is already tracked in `TRACKED` — if yes, flag "already tracked in Spec NNN"
- Recommended action: `/spec` (if not tracked) or "tracked in Spec NNN" (if tracked)

**B — Process friction** (skip if MODE != full and MODE != friction)

Scan all extracted pain points and friction items from session logs.
Group identical or semantically similar items (e.g., same tool/command appearing in multiple sessions).
For each group with 2+ occurrences:
- Friction label: the recurring pain point (e.g., "heredoc quoting failure")
- Occurrences: list of session file references (YYYY-MM-DD-NNN.md)
- Severity: `isolated` | `recurring` | `systemic`
- Check against `TRACKED`
- Recommended action: `/spec` (if not tracked), `/revise` (if an existing spec needs updating), or "tracked in Spec NNN"

**C — Signal clusters** (skip if MODE != full and MODE != signals)

From signals.md SIG-NNN entries, group by type and common theme.
For each cluster with 2+ signals:
- Cluster label: inferred theme
- Members: SIG-NNN list
- Predominant type: error | insight | decision | feedback
- Check against `TRACKED`
- Recommended action: `/spec`, `/evolve`, or "tracked in Spec NNN"

**D — Spec velocity** (skip if MODE != full and MODE != velocity)

From backlog data:
- List specs stalled at `draft` for > 14 days (flag as stale)
- List specs stalled at `in-progress` for > 7 days (flag as blocked)
- Compute approximate lead time for recently `closed` specs if date data is available
- Flag if the evolve loop review is overdue (> 30 days since `Last evolve loop review:`)

**E — Improvement debt** (always included unless MODE is a single dimension other than full)

From scratchpad.md open notes:
- Flag notes tagged `[spec-trigger]` that have not been converted to specs — these are improvement debt
- Flag notes aged > 14 days (stale scratchpad items)
- Check each against `TRACKED`
- Recommended action: `/spec` (if not tracked) or "tracked in Spec NNN"

#### [decision] Step I9 — Render report

Render the following structured markdown report:

```
# FORGE Insights Report
Generated: YYYY-MM-DD
Sessions analyzed: N  |  Date range: YYYY-MM-DD → YYYY-MM-DD
Findings: N error patterns, N friction clusters, N signal clusters, N velocity flags, N improvement debt items

---

## Error Patterns
(omit section if MODE excludes this dimension or no findings)

### [severity] <Pattern Name>
- **Occurrences (N):** EA-NNN, EA-NNN, ...
- **Severity:** systemic | recurring | isolated
- **Tracking:** already tracked in Spec NNN | ⚠ not tracked
- **Recommended action:** /spec "<suggested title>" | tracked in Spec NNN — no action needed

---

## Process Friction
(omit section if MODE excludes this dimension or no findings)

### [severity] <Friction Label>
- **Occurrences (N):** session YYYY-MM-DD-NNN.md, ...
- **Severity:** systemic | recurring | isolated
- **Tracking:** already tracked in Spec NNN | ⚠ not tracked
- **Recommended action:** /spec "<suggested title>" | /revise NNN | tracked in Spec NNN

---

## Signal Clusters
(omit section if MODE excludes this dimension or no findings)

### <Cluster Label> (N signals, type: error|insight|decision|feedback)
- **Members:** SIG-NNN, SIG-NNN, ...
- **Tracking:** already tracked in Spec NNN | ⚠ not tracked
- **Recommended action:** /spec "<suggested title>" | /evolve | tracked in Spec NNN

---

## Spec Velocity
(omit section if MODE excludes this dimension or no findings)

- Stalled drafts (>14 days): Spec NNN — <title> (stalled N days)
- Blocked in-progress (>7 days): Spec NNN — <title>
- Evolve loop: last review YYYY-MM-DD — [current | ⚠ overdue by N days]

---

## Improvement Debt
(omit section if MODE != full or no findings)

- [spec-trigger] "<note summary>" — added YYYY-MM-DD — ⚠ not converted to spec
- [stale] "<note summary>" — added YYYY-MM-DD — stale (N days)

---

## Summary
<N> findings across <N> sessions. <N> already tracked. <N> new recommendations.
Top recommendation: <single highest-priority actionable item>
```

If a section has no findings, omit it entirely (do not print empty sections).
If no findings at all: report "No patterns detected across the analyzed data. Project process looks clean."

#### [mechanical] Step I10 — Next action

Present a context-aware next action:
- If untracked error patterns or friction clusters found: "Next: run `/spec <suggested title>` to create a spec for the top untracked finding."
- If stalled specs found: "Next: run `/implement next` to resume the highest-ranked stalled spec, or `/now` to review blockers."
- If improvement debt found: "Next: run `/spec <note summary>` to convert the oldest untracked scratchpad trigger to a spec."
- If evolve loop is overdue: "Next: run `/evolve` — last review was N days ago."
- If no actionable findings: "Next: continue current work. Run `/now` for project state."

**Stop here for `--insights` mode** — do not proceed to Step 0-cd or any later evolve-loop step.

### [mechanical] Step 0-cd — Signal-based admission (Spec 500 / ADR-500 — supersedes the Spec 464 calendar entry-gate)

No calendar cool-down applies to running the review — that lives on *applied* self-modification (Step AS,
ADR-046 Invariant #3). Admission depends on who invoked `/evolve` and, for the automated heartbeat, whether
signals have accumulated. Runs at command entry, before the state marker and before any F1–F4 work.

1. **Explicit human invocation** — if `--auto` is NOT in `$ARGUMENTS` (`/evolve`, `/evolve --full`,
   `/evolve --spec NNN`): **always admit**. Emit `GATE [evolve-admission]: PASS — explicit invocation.` Proceed.
2. **Automated rewake** — if `--auto` IS in `$ARGUMENTS`: admit only when **≥1 signal threshold is crossed**.
   a. Read thresholds from `forge.evolve.signal_thresholds` in `AGENTS.md` (single source, Spec 500 R8; do
      NOT re-inline values here). Keys: `unreviewed_signals`, `open_evolve_scratchpad`, `error_autopsies`,
      `deferred_scope_items`, `spec_velocity`.
   b. Compute the same five signal counts `/now` Step 12 uses, since the last review date
      (`docs/sessions/evolve-state.md` `last_evolve_loop_run:` — single source, Spec 500 R6a;
      `.forge/state/evolve-cool-down.json` is retired and MUST NOT be read).
   c. **Hysteresis (R10)**: if `forge.evolve.admission_hysteresis` is true, require ≥1 new signal since the
      last recorded skip (`evolve-state.md` `last_auto_skip:`) — prevents flapping at a threshold boundary.
   d. If ≥1 threshold is crossed: emit `GATE [evolve-admission]: PASS — auto; thresholds crossed: <list>.` Proceed.
   e. If none crossed: emit `GATE [evolve-admission]: SKIP — auto; no accumulation — skipped (nothing crossed since <date>; signals N/<t>, scratchpad N/<t>, EA N/<t>, deferred N/<t>, velocity N/<t>).` Record `last_auto_skip: <today>` in `evolve-state.md`, reschedule the heartbeat (Step Z), and **exit 0** WITHOUT running F1–F4.
3. **Soft time fallback (R3 — recommendation only, NEVER a block)**: if the last review predates
   `forge.evolve.time_fallback_days` (default 30), include a one-line nudge in the output (also surfaced by
   `/now`). Never blocks or forces admission.

### [mechanical] Step AS — Apply-surface cool-down gate (Spec 500 R4 / ADR-500 / ADR-046 Invariant #3)

This is where the ADR-046 cool-down lives. **EVERY `/evolve` auto-apply write** — any write that modifies
an operating-rule/config/gate file — MUST pass this gate BEFORE writing. Enumerated apply paths (Spec 500
R4b/AC4b — the fixture checks this enumeration):
- Trust-calibration `apply all` / `apply <N>` (Step 8b) → writes `docs/process-kit/gate-categories.md`.
- Score-anchor / E-anchor revisions, if applied inline → writes `docs/process-kit/scoring-rubric.md`.
- Any future `/evolve` auto-apply path that writes an operating-rule/config/gate file.

(Score-calibration *timestamp* writes and proposal drafting are NOT self-modifications and are exempt.)

Gate procedure (shared with `/config-change` — one throttle across both apply surfaces):
1. Read `forge.evolve.apply_cool_down_days` from `AGENTS.md` (default `7`).
2. Read `docs/sessions/config-change-audit.md`; find the most recent `outcome: applied` entry (same source
   `/config-change` Step 2 reads).
3. If that entry's date is within `apply_cool_down_days` of today: **BLOCK**. Emit
   `GATE [evolve-apply-cool-down]: BLOCK — last applied self-modification <date> (<n>d ago); cool-down <N>d. Apply deferred.`
   Record the proposed (un-applied) change in the evolve session log and **continue WITHOUT writing**.
4. Otherwise: **ALLOW**. After writing, append to `docs/sessions/config-change-audit.md`:
   `- date: YYYY-MM-DD | source: /evolve | change: <what was applied> | outcome: applied`
   so the next apply is throttled against it. Emit
   `GATE [evolve-apply-cool-down]: PASS — no applied self-modification within <N>d; apply recorded.`

**Sequencing invariant (Spec 500 R4c)**: this gate ships in the SAME change as the Step 0-cd entry-gate
removal — there is no state where `/evolve` has neither the calendar entry-gate nor this apply-surface
cool-down. The fixture `test-spec-500-apply-surface-cooldown` asserts both the enumeration above and the
no-window invariant.

### [mechanical] Step 0a — Evolve Loop State Marker (Spec 191)
Write the evolve-loop state marker to `docs/sessions/context-snapshot.md`:
```
## Active evolve loop
status: in-progress
started: YYYY-MM-DD HH:MM
mode: <fast-path|full|interactive>
```
This marker blocks solve-loop commands (/implement, /spec, /close) while active; cleared only after the exit gate completes (see "Evolve Loop Exit Gate" below).

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
4. **Backlog state (Spec 399)**: Run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog --format=json` — confirm the completed spec's row reflects `implemented`.
5. Check if any other backlog items are now unblocked by this completion and note them.
6. **Consensus acceptance-rate (F4 read side — Spec 497, closes Spec 258 AC#5)**: run `forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/acceptance_rate.py` and surface its rolling-30-day figure. Surface `n/a` verbatim when no rated decisions exist — same read as the `consensus_tracking` config (AGENTS.md); also surfaced by `/now`.

**If periodic review (full F1–F4):**
3. Spot-check 2–3 `implemented` or `closed` specs for acceptance criteria drift.
4. <!-- customize: replace with your project's CLI help command -->
   Check docs/README.md CLI commands against actual CLI help output.
5. Report KPI trends from session logs: lead time, hotfix count, doc drift events since last review.
6. Score calibration: compare predicted vs actual BV for completed specs — flag if systematic bias found.
6b. **E calibration (Spec 158, simplified per Spec 316)**: for specs closed since last calibration:
   a. Compare expected session count (E=1-2 single, E=3 1-2, E=4-5 2+) vs actual sessions from session logs, if data exists.
   b. Flag systematic over-prediction (3+ specs where actual E was lower) or under-prediction (3+ specs higher).
   c. If bias detected: recommend E anchor guidance updates with specific adjustments.
   d. TC calibration is qualitative — operator-recall against cost-feel of recent specs (Spec 316 removed the unwired metrics framework).

6b+. **Data-driven score calibration via score-audit log (Spec 368)**: Augment the operator-recall pass in 6b with predicted-vs-observed data from `.forge/state/score-audit.jsonl`. The shared helper at `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh` (PowerShell parity at `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.ps1`) renders the bias report; do NOT inline JSON parsing here.

   Run the bias report:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh bias-report "$verbosity_mode"
   ```

   (PowerShell: `pwsh ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.ps1 bias-report "$verbosity_mode"`. `$verbosity_mode` is `lean` or `verbose` per `forge.output.verbosity` in AGENTS.md.)

   The helper:
   - Groups predicted/observed pairs by `lane + kind_tag` (Req 14b cross-tab).
   - Emits an anchor-revision advisory only when **N≥3** specs in the same dimension+lane+kind_tag cell show same-direction deviation.
   - Suffixes every advisory with the literal `(direction-only; magnitude not measured)` (Req 14c, AC6).
   - Annotates each advisory `(based on N=<count> closed specs since first record)` (Req 14d, AC6).
   - Lean mode suppresses cells below the N≥3 threshold (Spec 225); verbose mode renders them as `insufficient data (N=<count>)` (AC7).

   If the audit log is empty/absent (pre-instrumentation specs only): the helper emits `0 records — calibration deferred until data accumulates`. Continue with operator-recall calibration from Step 6b.

   Note: this report is data, not authority — anchor revisions still require operator judgment (`docs/process-kit/score-calibration-loop.md` § Time-blindness mitigation).

6b++. **Consensus acceptance-rate (F4 read side — Spec 497, closes Spec 258 AC#5)**: run `forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/acceptance_rate.py` and surface the rolling-30-day figure (`accepted / (accepted + modified + rejected)` over `docs/sessions/*.json`, per `docs/process-kit/telemetry-capture-guide.md`). When it reports `n/a` (no rated decisions in window), surface that verbatim — never a divide error. A persistently low or sharply dropping rate is a calibration/process signal worth a CEfO/CQO note; the figure is data, not authority.

6c. **CEfO advisory dispatch (Spec 187)**: If `forge.dispatch_rules.enabled` is `true` in AGENTS.md:
   - Read `.claude/agents/cefo.md` for the role preamble.
   - Spawn CEfO with the bias report (Step 6b+, data-driven) and E calibration data (Step 6b, operator-recall).
   - Prompt: "Review the E/TC calibration results and score-audit bias report (predicted vs observed proxies from `.forge/state/score-audit.jsonl`, grouped by lane+kind_tag). Assess whether effort estimates are miscalibrated, token costs are trending unsustainably, or process overhead is disproportionate. Report direction only, not magnitude — observed proxies are direction-only (Spec 368 Req 14c, Req 15). Produce your standard review block."
   - Present inline:
     ```
     ### CEfO Advisory — Efficiency Review
     <CEfO review block>
     ```
   - If `forge.dispatch_rules.enabled` is `false` or absent: skip silently.
6d. **MCP pin review (Spec 284)**: Read `docs/process-kit/mcp-pinning-policy.md`. Check each pin's `Last verified:` age against its threshold (context7=60 days, fetch=365 days).
   - Stale: `MCP pin stale: <package> pinned <N> days ago, threshold <T>. Run bump-verification checklist in docs/process-kit/mcp-pinning-policy.md before rotating.`
   - Fresh: `MCP pins current: <package1>@<v1> verified <N1>d ago, <package2>@<v2> verified <N2>d ago.`
   - Advisory only — does not auto-bump; operator runs the checklist manually.

6e. **Release-eligible + deprecation surfacing (Spec 291)**, full F1-F4 mode:

   1. **Release-eligible count**: count `docs/sessions/signals.md` entries matching `^### SIG-[0-9]+-RE`. If ≥1:
      ```
      N release-eligible spec(s) pending tag cut.
      Audit: docs/process-kit/v1.0.0-to-next-audit.md
      Tooling: scripts/cut-release.sh (dry-run by default)
      ```
      Recommend the operator review the audit and decide whether to cut now or keep accumulating. Missing audit doc = process defect (release-policy.md § Post-cut disposition expects it between cuts).

   2. **Deprecation surface scan**: scan `copier.yml` and `.claude/commands/*.md` frontmatter for `deprecated: true`. For each match:
      ```
      ⚠ Deprecated <surface>: <name> (deprecated_in: <ver>, removed_in: <ver>)
      ```
      If `removed_in:` ≤ the next likely tag, recommend the audit flag the removal as a MAJOR-cut item.

   Both signals are advisory — do NOT block the evolve loop exit gate.


7. Update `Last score calibration:` in docs/backlog.md.
8. **Signal pattern analysis (Spec 044):** Read `docs/sessions/signals.md`. Apply structured pattern detection:
   a. **Parse**: extract type tag, affected component(s), and root-cause keywords from each signal entry.
   b. **Group**: cluster entries sharing a type tag or ≥2 overlapping root-cause keywords.
   c. **Score**: severity = impact_level (high=3, medium=2, low=1; use the signal's `Impact:` field, else medium) × frequency (cluster size). Label: score ≥6 → `high`; 3-5 → `medium`; 1-2 → `low`.
   d. **Report (pattern table)**:
      ```
      Signal Pattern Analysis — <date>
      | Pattern | Type | Occurrences | Severity | Signal IDs | Status |
      |---------|------|-------------|----------|------------|--------|
      | <pattern name> | [type] | N | high/med/low | SIG-NNN, ... | systemic gap → spec recommended |
      ```
      - Patterns with 1 occurrence: "isolated — monitor"
      - Patterns with 2+ occurrences at medium+ severity: "systemic gap → spec recommended"
   e. Save the pattern table to `docs/sessions/pattern-analysis.md` (append with date header; create if absent).
   f. **Knowledge consolidation**: 10+ signals or 3+ recurring themes → recommend `/synthesize --decisions` (default mode; operator can override with `--postmortem`, `--topic <theme>`, or `--all`).
   g. **Architecture document update** (Spec 228): if `docs/architecture.md` exists and modules/commands/roles/adapters changed since its `Last updated` date, flag: "Architecture document may be stale. Review `docs/architecture.md` and update feature inventory, module list, or integration points as needed."
   h. **Root-cause category grouping (Spec 267)**: re-group signals by `Root-cause category` (`spec-expectation-gap`, `model-knowledge-gap`, `implementation-error`, `process-defect`, `other`; pre-Spec-267 entries default to `other`). Append:
      ```
      Root-cause Category Grouping — <date>
      | Category | Occurrences | Signal IDs | Notes |
      |----------|-------------|------------|-------|
      | spec-expectation-gap   | N | SIG-NNN, ... | <1-line summary of theme if any> |
      | model-knowledge-gap    | N | SIG-NNN, ... | ... |
      | implementation-error   | N | SIG-NNN, ... | ... |
      | process-defect         | N | SIG-NNN, ... | ... |
      | other                  | N | SIG-NNN, ... | (pre-267 entries + uncategorized) |
      ```
      - `other` >40% of signals since last review: advisory "Category quality regression — >40% of signals are `other`. Consider reviewing `docs/process-kit/signal-quality-guide.md` for calibration." (advisory, not blocking)
   i. **Gate-coverage gaps (Spec 267)**: cluster `missed-by-existing-gate` signals (field: "missed-by-existing-gate — <gate name>") by named gate. Qualifies as a gap when ≥3 signals name the same gate (AC5) OR ≥50% of a pattern cluster (step b) is `missed-by-existing-gate` (Req 5). For each qualifying cluster, append:
      ```
      Gate-Coverage Gaps — <date>
      | Gate Named | Missed Count | % of Pattern Cluster | Signal IDs | Recommendation |
      |-----------|--------------|----------------------|------------|----------------|
      | <gate>    | N            | X%                   | SIG-NNN, ... | Review whether <gate> needs extension or a new gate is warranted |
      ```
      If none qualify: "Gate-coverage gaps: none detected (N `missed-by-existing-gate` signals, no cluster ≥3 or ≥50%)." Advisory — does not block the evolve loop.
8j. **Positive-signal review (Spec 497):** reviews the success side so wins are reinforced, not just failures fixed. Read `docs/sessions/signals.md` for `[positive]` entries since the last review.
   a. Group by `Why it worked` factor (same ≥2-keyword clustering as (b)).
   b. Append:
      ```
      Positive-Signal Review — <date>
      | Win pattern | Occurrences | Signal IDs | Keep/amplify recommendation |
      |-------------|-------------|------------|-----------------------------|
      | <enabling factor> | N | SIG-NNN, ... | <how to repeat or institutionalize> |
      ```
   c. A win recurring ≥2 times: recommend graduating it into project memory or a strategy/process-kit doc (`docs/process-kit/positive-signal-taxonomy.md`).
   d. No `[positive]` entries since last review: "Positive signals: none captured since last review — consider whether wins are going unrecorded (the taxonomy was historically ~54:1 failure-biased)." Advisory only.
8b. **Trust calibration review (Spec 160):** Read `docs/sessions/signals.md` for `[trust]` signals.
   a. **Aggregate by check type**: count machine-verified closures (estimate from CHANGELOG close count) and human corrections, per check type.
   b. **Apply calibration rules** (`docs/process-kit/gate-categories.md`):
      - 0 corrections over 10+ closures → confirm machine-verifiable (no change)
      - 2+ corrections in 5 closures → escalate to confidence-gated or human-judgment-required
      - Confidence-gated check consistently HIGH with 0 corrections → graduate to machine-verifiable
   c. **Present recommendations** (if any adjustments are warranted):
      ```
      Trust Calibration — <date>
      | Check Type | Closures | Corrections | Current Category | Recommendation |
      |------------|----------|-------------|-----------------|----------------|
      | <check>    | <N>      | <N>         | machine-verifiable | escalate to confidence-gated |
      ```
      These are **recommendations only**:
      > **Choose** — type a number or keyword:
      > | # | Rank | Action | Rationale | What happens |
      > |---|------|--------|-----------|--------------|
      > | **1** | 1 | `apply all` | Trust signals justify all recommended adjustments | Apply all recommended category changes to gate-categories.md |
      > | **2** | 2 | `apply <N>` | Selective acceptance; apply only some adjustments | Apply a specific recommendation (type the row number) |
      > | **3** | — | `defer` | Insufficient data; revisit later | Revisit all recommendations next cycle |
      > | **4** | — | `dismiss` | Recommendations not warranted | Dismiss all — no adjustments warranted |
   c2. **Apply-surface cool-down (Spec 500 R4)**: `apply all`/`apply <N>` writes `gate-categories.md` —
      an applied self-modification. Before writing, pass **Step AS** (apply-surface cool-down). On
      `GATE [evolve-apply-cool-down]: BLOCK`, record the proposed category changes in the session log and
      do NOT write. On PASS, write and append the `outcome: applied` entry.
   d. If no trust signals exist or no adjustments are warranted: report "Trust calibration: no adjustments needed (N closures reviewed, 0 corrections)."

8c. **CQO advisory dispatch (Spec 187)**: If `forge.dispatch_rules.enabled` is `true` in AGENTS.md:
   - Read `.claude/agents/cqo.md` for the role preamble.
   - Spawn CQO with the signal pattern analysis (step 8) and trust calibration results (step 8b).
   - Prompt: "Review the signal pattern analysis and trust calibration data. Assess whether quality gaps are systemic, acceptance criteria rigor is declining, or trust calibration adjustments are warranted. Produce your standard review block."
   - Present inline:
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
    c. **Review Router (Spec 159)**: before presenting, run the router on the full set — **DA** (always, risk check) + **COO** (always, process impact), add **MT** if proposal count > 3. Display selection rationale, run selected perspectives, present the Review Brief before the choice block.
    d. Present all proposals together, each with its `Objective:` field:
       ```
       SPEC PROPOSALS — <N> generated from signal patterns
       1. <Title> — <Objective (first sentence)>
       2. <Title> — <Objective (first sentence)>
       ...
       ```
       > **Choose** — type a number or keyword:
       > | # | Rank | Action | Rationale | What happens |
       > |---|------|--------|-----------|--------------|
       > | **1** | — | `approve all` | Operator-driven; agent has no preference | Approve all N proposals for spec creation |
       > | **2** | — | `approve <N>` | Operator-driven | Approve a specific proposal (type the number) |
       > | **3** | — | `modify <N>` | Operator-driven; refine before commit | Edit a proposal before approving |
       > | **4** | — | `dismiss <N>` | Operator-driven; reason recorded | Dismiss a specific proposal with reason |
       > | **5** | — | `dismiss all` | Operator-driven; clear rejection | Dismiss all proposals |
    e. On `approve <N>`/`approve all`: run `/spec` with the proposal title and content.
    f. On `modify <N>`: accept operator edits, then run `/spec` with revised content.
    g. On `dismiss <N>`/`dismiss all`: record in `docs/sessions/pattern-analysis.md` as `dismissed: YYYY-MM-DD — <reason>`. Suppresses re-proposal for this pattern.

    h. **Multi-role vetting**: for high-impact proposals (severity `high` or BV >= 4), recommend `/consensus <proposal>` before approving.
After either path:
- **Deferred scope aging (Spec 199):** Run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog --format=json` and scan for deferred-scope items. Flag items older than 14 days without disposition:
  ```
  DEFERRED SCOPE AGING — The following items are >14 days old without disposition:
  - <date> from Spec NNN: <item summary> (<age> days)
  Action required: promote to spec, drop, or carry forward with justification.
  ```
  If no aged items found: report "Deferred scope: all items current (none >14 days)."
- Check docs/sessions/scratchpad.md for open `[evolve]` (or legacy `[outer-loop]`) notes. If open notes exist, present them as a numbered list and offer disposition:
  > **Choose** — type a number or keyword:
  > | # | Rank | Action | Rationale | What happens |
  > |---|------|--------|-----------|--------------|
  > | **1** | 1 | `review all` | Per-item disposition; highest care | Walk through each item one at a time for disposition |
  > | **2** | 2 | `batch dispose` | Faster path; AI proposes, operator confirms | Recommend dispositions for all, approve/modify in bulk |
  > | **3** | — | `carry forward` | Defer; fine if items are still ripening | Carry all items forward to next cycle |
- Remind me to update the `Last evolve loop review:` field in today's session log.

## [mechanical] Step S — Safety-config sweep (Spec 387 Component B)

A quarterly deprecation sweep that verifies safety-property enforcement persistence and runs a wide-net grep over non-registered files. Runs on the existing /evolve cadence — no new schedule. Gated by 90-day dormancy threshold.

```bash
# shellcheck source=/dev/null
source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/safety-config.sh

sweep_log=".forge/state/safety-sweep.jsonl"
mkdir -p .forge/state
last_sweep_epoch=0
if [[ -f "$sweep_log" ]]; then
  last_ts=$(tail -1 "$sweep_log" | grep -oE '"timestamp":"[^"]+"' | head -1 | sed -E 's/.*"timestamp":"([^"]+)".*/\1/')
  if [[ -n "$last_ts" ]]; then
    last_sweep_epoch=$(date -u -d "$last_ts" +%s 2>/dev/null || echo 0)
  fi
fi
now_epoch=$(date -u +%s)
ninety_days=$((90*24*60*60))
age=$((now_epoch - last_sweep_epoch))

if (( last_sweep_epoch > 0 && age < ninety_days )); then
  days_until=$(( (ninety_days - age) / 86400 ))
  echo "Safety-config sweep: skipped (last sweep ${days_until} day(s) inside 90-day window)"
else
  echo "Safety-config sweep: running (last sweep > 90 days or absent)"

  # R5b — Enforcement-path verification across closed/implemented specs.
  ep_dormant=0
  for spec_file in docs/specs/[0-9][0-9][0-9]-*.md; do
    [[ -f "$spec_file" ]] || continue
    status=$(grep -E '^- Status: ' "$spec_file" | head -1 | sed -E 's/^- Status: //')
    case "$status" in implemented|closed) : ;; *) continue ;; esac
    sec=$(awk '/^## Safety Enforcement$/{p=1; next} /^## /{p=0} p' "$spec_file")
    [[ -z "$sec" ]] && continue
    ep_file=$(echo "$sec" | grep -E '^Enforcement code path: ' | sed -E 's/^Enforcement code path: ([^:]+)::.*/\1/')
    ep_sym=$(echo  "$sec" | grep -E '^Enforcement code path: ' | sed -E 's/^Enforcement code path: [^:]+::(.*)$/\1/')
    [[ -z "$ep_file" || ! -f "$ep_file" || "$ep_sym" == "<placeholder>" ]] && continue
    if ! grep -qE "(function[[:space:]]+${ep_sym}|^${ep_sym}\(\)|def[[:space:]]+${ep_sym}|^${ep_sym}[[:space:]]*=)" "$ep_file" 2>/dev/null; then
      echo "DORMANT-ENFORCEMENT: ${spec_file##*/} -> ${ep_file}::${ep_sym} (symbol unresolved)"
      ep_dormant=$((ep_dormant+1))
    fi
  done

  # R5c — UNENFORCED-pointer status check.
  ptr_dormant=0
  while IFS=: read -r f line text; do
    [[ -z "$f" ]] && continue
    if [[ "$text" =~ UNENFORCED.*Spec[[:space:]]+([0-9]{3}) ]]; then
      ref="${BASH_REMATCH[1]}"
      ref_file=$(ls "docs/specs/${ref}-"*.md 2>/dev/null | head -1)
      if [[ -z "$ref_file" ]]; then
        echo "DORMANT-POINTER: ${f}:${line} -> Spec ${ref} (does not exist)"
        ptr_dormant=$((ptr_dormant+1))
      else
        ref_status=$(grep -E '^- Status: ' "$ref_file" | head -1 | sed -E 's/^- Status: //')
        if [[ "$ref_status" != "in-progress" && "$ref_status" != "implemented" ]]; then
          echo "DORMANT-POINTER: ${f}:${line} -> Spec ${ref} (status=${ref_status})"
          ptr_dormant=$((ptr_dormant+1))
        fi
      fi
    fi
  done < <(grep -rnE '# UNENFORCED' --include='*.md' --include='*.yaml' --include='*.jinja' . 2>/dev/null || true)

  # R5d — Wide-net grep on non-registered files.
  registered_patterns=$(safety_config_load .forge/safety-config-paths.yaml | tr '\n' '|' | sed 's/|$//; s/|/\\|/g')
  wide_flagged=0
  while IFS=: read -r f line text; do
    [[ -z "$f" ]] && continue
    # Skip if file matches any registered pattern.
    skip=0
    while IFS= read -r pat; do
      bp="${pat//\*\*/\*}"
      # shellcheck disable=SC2053
      if [[ "${f#./}" == $bp ]]; then skip=1; break; fi
    done < <(safety_config_load .forge/safety-config-paths.yaml)
    (( skip )) && continue
    # Skip vendored content
    case "$f" in *node_modules*|*.git/*|*.venv/*|*tmp/*) continue ;; esac
    # Check whether the matched token is referenced in any spec's Safety Enforcement section.
    if ! grep -lE 'Enforcement code path: '"${f#./}"'::' docs/specs/*.md >/dev/null 2>&1; then
      echo "WIDE-NET: ${f}:${line}: ${text}"
      wide_flagged=$((wide_flagged+1))
    fi
  done < <(grep -rnE '(safe|safety|enforce|require|validate|guard|prevent|reject)_[a-zA-Z_]+' \
    --include='*.sh' --include='*.ps1' --include='*.py' --include='*.md' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.venv \
    . 2>/dev/null | head -50 || true)

  # R5e — Registry-curation drift check.
  prior=".forge/state/safety-config-paths-prior.yaml"
  if [[ -f "$prior" ]]; then
    if ! diff -q .forge/safety-config-paths.yaml "$prior" >/dev/null 2>&1; then
      removed=$(comm -23 <(sort "$prior") <(sort .forge/safety-config-paths.yaml) || true)
      if [[ -n "$removed" ]]; then
        echo "REGISTRY-DRIFT: pattern(s) removed since last sweep:"
        printf '  %s\n' "$removed"
      fi
    fi
  fi
  cp .forge/safety-config-paths.yaml "$prior"

  # R5f — 7-metric output.
  log="docs/sessions/activity-log.jsonl"
  if [[ -f "$log" ]]; then
    quarter_ago=$(date -u -d "90 days ago" +%Y-%m-%d 2>/dev/null || date -u -v-90d +%Y-%m-%d)
    quarter_log=$(awk -v cutoff="$quarter_ago" 'index($0, "\"timestamp\":\"" cutoff) > 0 || $0 > cutoff' "$log" || true)
    specs_prompted=$(echo "$quarter_log" | grep -cE '"event_type":"safety-prompt-(yes|no)"' || true)
    yes_answers=$(echo "$quarter_log" | grep -cE '"event_type":"safety-prompt-yes"' || true)
    overrides_used=$(echo "$quarter_log" | grep -cE '"event_type":"safety-override"' || true)
  else
    specs_prompted=0; yes_answers=0; overrides_used=0
  fi
  no_rate="0.0"
  if (( specs_prompted > 0 )); then
    no_rate=$(awk -v y="$yes_answers" -v p="$specs_prompted" 'BEGIN{printf "%.3f", (p-y)/p}')
  fi
  deferred_unenforced=$(grep -l '# UNENFORCED' docs/specs/*.md 2>/dev/null | wc -l)

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"timestamp":"%s","specs_prompted":%d,"yes_answers":%d,"no_rate":%s,"deferred_with_unenforced":%d,"overrides_used":%d,"dormant_found":%d,"wide_net_flagged":%d}\n' \
    "$ts" "$specs_prompted" "$yes_answers" "$no_rate" "$deferred_unenforced" "$overrides_used" \
    "$((ep_dormant + ptr_dormant))" "$wide_flagged" >> "$sweep_log"

  # R5g — Threshold-to-action mappings.
  if awk -v r="$no_rate" 'BEGIN{exit !(r > 0.5)}'; then
    echo "WARNING: Registry over-firing (no_rate=$no_rate > 0.5) — consider tightening pattern set or operator habituation review"
  fi
  if (( overrides_used > 2 )); then
    echo "WARNING: Override frequency above threshold (overrides_used=$overrides_used > 2 this quarter) — pattern audit recommended"
  fi
  if (( ep_dormant + ptr_dormant > 0 )); then
    echo "WARNING: $((ep_dormant + ptr_dormant)) dormant declaration(s) — per-item disposition required (delete, annotate UNENFORCED, or file enforcement spec)"
  fi
  if (( wide_flagged > 0 )); then
    echo "WARNING: ${wide_flagged} new safety-named token(s) outside registry — consider expanding .forge/safety-config-paths.yaml"
  fi
  if (( specs_prompted > 0 )); then
    sn_ratio=$(awk -v y="$yes_answers" -v p="$specs_prompted" 'BEGIN{printf "%.3f", y/p}')
    if awk -v r="$sn_ratio" 'BEGIN{exit !(r < 0.05)}'; then
      echo "WARNING: Prompt firing without yields (signal-to-noise=$sn_ratio < 0.05) — recheck registry coverage"
    fi
  fi

  echo "Safety-config sweep: complete. Metrics appended to $sweep_log."
fi
```

## [decision] Evolve Loop Exit Gate (Spec 191)

Before returning control to the solve loop, verify all evolve-loop work is complete:

1. **Proposals check**: confirm all step-10 proposals are dispositioned (approved, modified, or dismissed). Pending proposals: "Undispositioned proposals remain. Resolve before exiting." Do not proceed.

2. **Scratchpad check**: confirm all `[evolve]` scratchpad notes are reviewed (resolved, converted to spec, or carried forward). Unreviewed notes remain: list them and ask to resolve or carry forward.

3. **Approved proposals captured**: list all approved proposals as session-log artifacts. Not created as specs inline — converted only after the operator exits and explicitly runs `/spec`.
   ```
   ## Approved proposals (pending spec creation)
   - <proposal title> — approved, create via `/spec` after exiting
   ```

4. **Exit choice block**: Present the exit gate:
   ```
   Evolve loop review complete.
   ```
   <!-- safety-rule: session-data — if today's session log has unsynthesized spec activity AND ## Summary is unpopulated, /session is inserted at rank 1 and stop is downgraded to —. See docs/process-kit/implementation-patterns.md § Session-data safety rule. -->
   > **Choose** — type a number or keyword:
   > | # | Rank | Action | Rationale | What happens |
   > |---|------|--------|-----------|--------------|
   > | **1** | 1 | `implement next` | Resume solve loop with top-of-backlog | Exit evolve loop → `/implement next` |
   > | **2** | 2 | `spec <title>` | Convert one approved proposal now | Exit evolve loop → create spec from approved proposal |
   > | **3** | 2 | `spec all` | Convert all approved proposals together | Exit evolve loop → create all approved proposals as specs |
   > | **4** | — | `stop` | Downgraded if today's session log has unsynthesized entries | Exit evolve loop → end session |
   >
   > _(No solve-loop commands execute until you choose.)_

   **Session-data safety rule (Spec 320 Req 4)**: Before emitting the choice block, evaluate today's session log per the positive "populated Summary" definition (heading present + ≥1 non-placeholder body line). If the rule fires (unsynthesized spec activity AND Summary unpopulated): **insert `/session` at rank 1**, downgrade `stop` to `—`, renumber rows.

5. **Clear state marker**: After the operator chooses, remove the `## Active evolve loop` section from `docs/sessions/context-snapshot.md`. Report: "Evolve loop closed. Solve-loop commands re-enabled."

6. Execute the chosen action.

<!-- module:nanoclaw -->
## [mechanical] Automated delivery (Spec 043 — conditional)
If `--auto` was in $ARGUMENTS and the config `notify_via=nanoclaw`, compile results into a NanoClaw digest and send via the configured channel:
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
Use `mcp__nanoclaw__send_message` or the `nanoclaw_task_id` from config. **Human approval gate**: do NOT execute proposed actions (new specs, score changes, backlog updates) without explicit approval — wait for the operator's reply. Update `docs/sessions/evolve-state.md`: `last_evolve_loop_run: YYYY-MM-DD`, increment `runs_since_start`.

- If `notify_via=log-only`: append results to today's session log under `## Evolve Loop Run`. No NanoClaw message. Record `last_evolve_loop_run` in `docs/sessions/evolve-state.md`.
- If `docs/sessions/evolve-config.yaml` is absent: treat as `notify_via=log-only`.
<!-- /module:nanoclaw -->

## [mechanical] Step Z — Heartbeat reschedule (Spec 500 — replaces the Spec 464 cool-down-delay rewake; runs at command exit)

No review cool-down state to write — admission is signal-based (Step 0-cd). The single last-review source
`docs/sessions/evolve-state.md` `last_evolve_loop_run:` is updated by the Automated-delivery/log-only branch
above (Spec 500 R6a). `.forge/state/evolve-cool-down.json` is **retired** — do NOT write or read it.

1. **Schedule the heartbeat** (gated): read `forge.evolve.scheduled_rewake` from `AGENTS.md` (default `true`).
   - If `false`: schedule **nothing** — identical to a manual `/evolve`. Log that `scheduled_rewake` is
     `false` so the opt-out is audit-visible (CISO R2).
   - If `true`: invoke `ScheduleWakeup` with `delay = forge.evolve.rewake_interval_days × 86400` (default
     `1` day; clamps to its own bounds) and `prompt = /evolve --auto` (exactly; no extra args — CISO R1).
     A recurring **signal-check heartbeat**, NOT a cool-down timer (Spec 500 R9).

   The heartbeat re-invokes `/evolve --auto`; Step 0-cd's signal-admission check (R2) decides whether the
   review runs. MUST NOT reintroduce any day-count reject.

2. **Safe fallback (Spec 500 R7)**: if `ScheduleWakeup` is unavailable (degrades to a `CronCreate`-backed
   no-op per the Spec 464 Step-0 finding), do NOT hard-block — `/now`'s signal-based recommendation
   (`now.md` Step 12) covers the surfacing. Log that the heartbeat could not be scheduled and exit cleanly.


## [mechanical] Tab-lane awareness directive (Spec 351)

Before emitting any next-action choice block in this command, consult the active-tab marker (Spec 353 primitive):

1. Read `.forge/state/active-tab-*.json` (primary). If present, extract `lane`. If `last_command_at` > 30 minutes ago, treat marker as **stale**.
2. If no marker, fall back to `docs/sessions/registry.md` rows with `Status = active` for the current session. Use the row's `Lane` column.
3. If neither yields an active lane: emit the choice block as today. No preamble, no filtering, no annotation. **Skip the rest of this directive.**
4. If an active lane is detected: emit the one-line preamble (`Tab lane: <lane>. Options below filtered to lane scope.` / `... Cross-lane options annotated.` / `... (stale ~Nm)...`) and apply the filter/annotate decision rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules.
5. Filtered rows are struck through with rank `—` (not silently dropped) so the operator can override by typing the keyword directly.

The guide is the single source of truth for which rows filter vs annotate per lane. This directive is intentionally short — the central guide encodes the rules so every emitter stays consistent.
