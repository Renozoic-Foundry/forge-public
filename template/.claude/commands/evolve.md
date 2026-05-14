---
name: evolve
description: "Run the KCS Evolve Loop review"
workflow_stage: review
---

# Framework: FORGE
<!-- multi-block mode: serialized — evolve emits choice blocks at distinct mechanical steps (trust calibration, proposal disposition, scratchpad disposition, exit gate). Each block waits for operator response before the next is presented. Bare numerics work because only one block is ever co-presented at a time. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->

**Output verbosity (Spec 225)**: At the start of execution, read `forge.output.verbosity` from `AGENTS.md` (default: `lean`). In **lean** mode, suppress non-actionable diagnostic output (passing-gate confirmations, KPI tables, calibration deltas, MCP pin status, deprecation scans, signal-by-signal pattern dumps, root-cause groupings, deferred-scope aging when none aged, score-rubric details when unchanged) — write the full content to its file artifact (session log, `pattern-analysis.md`, etc.) and emit a one-line pointer in chat (or omit entirely if purely informational). In **verbose** mode, emit full detail as before. **Never suppressed in either mode**: choice blocks, FAILed gates, push-confirmation prompts, Review Brief "Needs Your Review" items, operator-input prompts, error/abort messages. See `docs/process-kit/output-verbosity-guide.md` for the full rules and worked examples.

Run the KCS Evolve Loop review. Use this after a spec reaches `implemented` or monthly.

> Timing guidance: see [session-synthesize-evolve-guide](../../docs/process-kit/session-synthesize-evolve-guide.md) for the canonical comparison of `/session` vs `/synthesize` vs `/evolve` — triggers, cadence, automation class.

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
4. **Backlog state (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --get-backlog --format=json` — confirm the completed spec's row reflects `implemented` (the helper reads frontmatter directly, so freshness is immediate; mode-detection is internal).
5. Check if any other backlog items are now unblocked by this completion and note them.

**If periodic review (full F1–F4):**
3. Spot-check 2–3 `implemented` or `closed` specs for acceptance criteria drift.
4. <!-- customize: replace with your project's CLI help command -->
   Check docs/README.md CLI commands against actual CLI help output.
5. Report KPI trends from session logs: lead time, hotfix count, doc drift events since last review.
6. Score calibration: compare predicted vs actual BV for completed specs — flag if systematic bias found.
6b. **E calibration (Spec 158, simplified per Spec 316)**: For specs closed since last calibration:
   a. If session data exists: compare expected session count (inferred from E score — E=1-2: single session, E=3: 1-2 sessions, E=4-5: 2+ sessions) vs actual sessions from session logs.
   b. Flag systematic E over-prediction (AI handles it easier than estimated — 3+ specs where actual E was lower) or under-prediction (iteration loops not anticipated — 3+ specs where actual E was higher).
   c. If systematic bias detected in either direction: recommend updating E anchor guidance and present specific anchor adjustments.
   d. Token-cost (TC) calibration is qualitative — operator-recall against the cost-feel of recent specs (Spec 316 removed the metrics framework that was documented but never wired).

6b+. **Data-driven score calibration via score-audit log (Spec 368)**: Augment the operator-recall pass in 6b with predicted-vs-observed data from `.forge/state/score-audit.jsonl`. The shared helper at `.forge/lib/score-audit.sh` (PowerShell parity at `.forge/lib/score-audit.ps1`) renders the bias report; do NOT inline JSON parsing here.

   Run the bias report:

   ```bash
   bash .forge/lib/score-audit.sh bias-report "$verbosity_mode"
   ```

   (PowerShell: `pwsh .forge/lib/score-audit.ps1 bias-report "$verbosity_mode"`. `$verbosity_mode` is `lean` or `verbose` per `forge.output.verbosity` in AGENTS.md.)

   The helper:
   - Reads predicted/observed pairs grouped by `lane + kind_tag` (Req 14b cross-tab from day one).
   - Emits an anchor-revision advisory only when **N≥3** specs in the same dimension+lane+kind_tag cell show the same-direction deviation.
   - Suffixes every advisory with the literal `(direction-only; magnitude not measured)` so downstream readers cannot cite the bias as quantitative (Req 14c, AC6).
   - Annotates each advisory `(based on N=<count> closed specs since first record)` (Req 14d, AC6).
   - In **lean** mode, suppresses cells below the N≥3 threshold (Spec 225). In **verbose** mode, renders sub-threshold cells as `insufficient data (N=<count>)` (AC7).

   If the audit log is empty or absent (pre-instrumentation specs only), the helper emits `0 records — calibration deferred until data accumulates`. Continue with operator-recall calibration from Step 6b.

   Note: this report is data, not authority. Anchor revisions still require operator judgment — see `docs/process-kit/score-calibration-loop.md` § Time-blindness mitigation for the principle that durations are derived from shell arithmetic over git timestamps, not model recall.

6c. **CEfO advisory dispatch (Spec 187)**: If `forge.dispatch_rules.enabled` is `true` in AGENTS.md:
   - Read `.claude/agents/cefo.md` for the role preamble.
   - Spawn CEfO as an isolated sub-agent with the bias report from Step 6b+ (data-driven) and the E calibration data from step 6b (operator-recall).
   - Prompt: "Review the E/TC calibration results and the score-audit bias report (predicted vs observed proxies from `.forge/state/score-audit.jsonl`, grouped by lane+kind_tag). Assess whether effort estimates are systematically miscalibrated, token costs are trending unsustainably, or process overhead is disproportionate. Report direction only; do not assert magnitude — observed proxies are direction-only signals (Spec 368 Req 14c, Req 15). Produce your standard review block."
   - Present the CEfO advisory inline after the calibration results:
     ```
     ### CEfO Advisory — Efficiency Review
     <CEfO review block>
     ```
   - If `forge.dispatch_rules.enabled` is `false` or absent: skip silently.
6d. **MCP pin review (Spec 284)**: Read `docs/process-kit/mcp-pinning-policy.md`. Check the `Last verified:` date at the top. For each pin documented in the policy's "What's pinned" section:
   - Compare current `Last verified:` age against the per-package threshold (context7=60 days, fetch=365 days).
   - If stale: emit a one-line advisory: `MCP pin stale: <package> pinned <N> days ago, threshold <T>. Run bump-verification checklist in docs/process-kit/mcp-pinning-policy.md before rotating.`
   - If all pins fresh: emit a one-line confirmation: `MCP pins current: <package1>@<v1> verified <N1>d ago, <package2>@<v2> verified <N2>d ago.`
   - This is an advisory checklist item — does NOT auto-bump pins. Operator executes the bump-verification checklist manually when ready.

6e. **Release-eligible + deprecation surfacing (Spec 291)**: Surface two release-policy signals as part of the periodic review (full F1-F4 mode).

   1. **Release-eligible count**: Read `docs/sessions/signals.md`. Count entries
      matching `^### SIG-[0-9]+-RE`. If count ≥ 1, present:
      ```
      N release-eligible spec(s) pending tag cut.
      Audit: docs/process-kit/v1.0.0-to-next-audit.md
      Tooling: scripts/cut-release.sh (dry-run by default)
      ```
      Recommend the operator review the audit and decide whether to cut now or
      continue accumulating. If the live audit doc is missing, flag it as a
      process defect (release-policy.md § Post-cut disposition expects the doc
      to exist between tag cuts).

   2. **Deprecation surface scan**: Scan `copier.yml` for top-level variables
      with `deprecated: true` and `.claude/commands/*.md` for files with
      `deprecated: true` in YAML frontmatter (or the first 10 lines). For each
      match, present a one-line item:
      ```
      ⚠ Deprecated <surface>: <name> (deprecated_in: <ver>, removed_in: <ver>)
      ```
      If any deprecation has a `removed_in:` ≤ the next likely tag (per the
      live audit's proposed bump), recommend that the audit explicitly note
      the removal as a MAJOR-cut item.

   These signals are advisory — they do NOT block the evolve loop exit gate.


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
   f. **Knowledge consolidation**: If pattern analysis reveals 10+ signals or 3+ recurring themes, recommend running `/synthesize --decisions` to consolidate accumulated knowledge into a refined reference document. Mode hint (Spec 328): `--decisions` is the default for /evolve-context recommendations because it aggregates the full decision history that pattern analysis builds on. Operator can override at invocation (`--postmortem` for general consolidation, `--topic <theme>` for a specific cluster, or `--all` for all four modes).
   g. **Architecture document update** (Spec 228): Check `docs/architecture.md`. If it exists and any of the following changed since its `Last updated` date: new modules added, commands added/removed, agent roles changed, or runtime adapters modified — flag for update: "Architecture document may be stale. Review `docs/architecture.md` and update feature inventory, module list, or integration points as needed."
   h. **Root-cause category grouping (Spec 267)**: In addition to the type-tag + keyword clustering in (b), re-group all signals by their `Root-cause category` field (one of `spec-expectation-gap`, `model-knowledge-gap`, `implementation-error`, `process-defect`, `other`). Signals without this field (pre-Spec-267 entries) are treated as `other`. Append a category-grouping section to the pattern analysis output:
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
      - If the `other` bucket is >40% of signals since the last evolve review, emit an advisory: "Category quality regression — >40% of signals are `other`. Consider reviewing `docs/process-kit/signal-quality-guide.md` for calibration." (This is advisory, not blocking.)
   i. **Gate-coverage gaps (Spec 267)**: Scan all signals for the `Evidence-gate coverage` field. Cluster `missed-by-existing-gate` signals by the named gate (the field is "missed-by-existing-gate — <gate name>"). A cluster qualifies as a **gate-coverage gap** when either:
      - ≥3 `missed-by-existing-gate` signals name the same gate (AC 5 threshold), OR
      - ≥50% of a pattern cluster (from step b) is `missed-by-existing-gate` (Requirement 5 threshold).

      For each qualifying cluster, append to the pattern analysis output:
      ```
      Gate-Coverage Gaps — <date>
      | Gate Named | Missed Count | % of Pattern Cluster | Signal IDs | Recommendation |
      |-----------|--------------|----------------------|------------|----------------|
      | <gate>    | N            | X%                   | SIG-NNN, ... | Review whether <gate> needs extension or a new gate is warranted |
      ```
      If no qualifying clusters exist: emit a single line "Gate-coverage gaps: none detected (N `missed-by-existing-gate` signals, no cluster ≥3 or ≥50%)."

      This output is **advisory** — it does not block the evolve loop. It surfaces systemic evidence-gate gaps so the operator can propose spec-level gate improvements.
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
      These are **recommendations only**:
      > **Choose** — type a number or keyword:
      > | # | Rank | Action | Rationale | What happens |
      > |---|------|--------|-----------|--------------|
      > | **1** | 1 | `apply all` | Trust signals justify all recommended adjustments | Apply all recommended category changes to gate-categories.md |
      > | **2** | 2 | `apply <N>` | Selective acceptance; apply only some adjustments | Apply a specific recommendation (type the row number) |
      > | **3** | — | `defer` | Insufficient data; revisit later | Revisit all recommendations next cycle |
      > | **4** | — | `dismiss` | Recommendations not warranted | Dismiss all — no adjustments warranted |
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
       ```
       > **Choose** — type a number or keyword:
       > | # | Rank | Action | Rationale | What happens |
       > |---|------|--------|-----------|--------------|
       > | **1** | — | `approve all` | Operator-driven; agent has no preference | Approve all N proposals for spec creation |
       > | **2** | — | `approve <N>` | Operator-driven | Approve a specific proposal (type the number) |
       > | **3** | — | `modify <N>` | Operator-driven; refine before commit | Edit a proposal before approving |
       > | **4** | — | `dismiss <N>` | Operator-driven; reason recorded | Dismiss a specific proposal with reason |
       > | **5** | — | `dismiss all` | Operator-driven; clear rejection | Dismiss all proposals |
    e. On `approve <N>` (or `approve all`): run `/spec` with the proposal title and content to create the draft spec.
    f. On `modify <N>`: accept operator edits to the proposal, then run `/spec` with revised content.
    g. On `dismiss <N>` (or `dismiss all`): record dismissal in `docs/sessions/pattern-analysis.md` as `dismissed: YYYY-MM-DD — <reason>`. Suppresses re-proposal for this pattern in subsequent cycles.

    h. **Multi-role vetting**: For high-impact proposals (severity `high` or BV >= 4), recommend running `/consensus <proposal>` to gather structured feedback from all registry roles before approving.
After either path:
- **Deferred scope aging (Spec 199):** Run `.forge/bin/forge-py .forge/lib/derived_state.py --get-backlog --format=json` and scan for any items tagged as deferred scope (status `deferred` or content with deferred-scope markers). For each deferred item, check its origination date. Flag items older than 14 days without disposition:
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
source .forge/lib/safety-config.sh

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


## [mechanical] Tab-lane awareness directive (Spec 351)

Before emitting any next-action choice block in this command, consult the active-tab marker (Spec 353 primitive):

1. Read `.forge/state/active-tab-*.json` (primary). If present, extract `lane`. If `last_command_at` > 30 minutes ago, treat marker as **stale**.
2. If no marker, fall back to `docs/sessions/registry.md` rows with `Status = active` for the current session. Use the row's `Lane` column.
3. If neither yields an active lane: emit the choice block as today. No preamble, no filtering, no annotation. **Skip the rest of this directive.**
4. If an active lane is detected: emit the one-line preamble (`Tab lane: <lane>. Options below filtered to lane scope.` / `... Cross-lane options annotated.` / `... (stale ~Nm)...`) and apply the filter/annotate decision rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules.
5. Filtered rows are struck through with rank `—` (not silently dropped) so the operator can override by typing the keyword directly.

The guide is the single source of truth for which rows filter vs annotate per lane. This directive is intentionally short — the central guide encodes the rules so every emitter stays consistent.

