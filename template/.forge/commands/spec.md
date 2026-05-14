---
name: spec
description: "Create a new spec from the template"
workflow_stage: planning
---
<!-- multi-block mode: serialized — choice blocks fire at distinct mechanical steps (vague-AC scan Step 6c, behavioral-AC fixture scan Step 6d). Each block waits for operator response before the next mechanical step proceeds. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->

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
    - Drafts get a 90-day validity window (`valid-until:`) — configurable via
      `forge.spec.draft_validity_days` in AGENTS.md. /now reports a count when
      drafts are past validity; /matrix Step 8 absorbs them into strategic-fit triage.
      Renew validity by running /revise on the draft.
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

## [mechanical] Step 0z — Lane-mismatch warning (Spec 353)

If `.forge/state/active-tab-*.json` marker exists for this session, read its `lane` field.

This command's natural lane (per `docs/process-kit/multi-tab-quickstart.md` § Lane choice):

| Command | Lane |
|---------|------|
| /parallel | feature |
| /spec | feature OR process-only (depending on spec subject) |
| /scheduler | feature |
| /forge stoke | process-only |

If `marker.lane` does not match this command's natural lane, emit a one-line warning: `⚠ Action targets <expected> lane; active tab is '<marker.lane>'. Continue?` Soft-gate only — do not refuse. Operator decides whether the mismatch matters.

Skip silently if no marker exists.

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

2. **Next spec number (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --get-spec-index --format=json`. Parse the stdout as JSON; the next available spec number is one greater than the maximum `spec_id` in the array (treat IDs as zero-padded integers).
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
   - TC is operator-judgment input — calibrate against memory of similar past specs (Spec 316: FORGE no longer collects per-invocation cost data).
6. Write the spec file at `docs/specs/NNN-<slug>.md` by filling in the template:
   - Set `Status: draft`
   - Set `Change-Lane:` based on the description (infer; ask only if genuinely ambiguous)
   - Set `Trigger:` in the frontmatter
   - Set `Token-Cost: $|$$|$$$` in the frontmatter (from step 5)
   - Set `Last updated:` to today (YYYY-MM-DD)
   - Set `valid-until:` to `today + N` where `N` is `forge.spec.draft_validity_days` from AGENTS.md, or 90 if the key is absent (Spec 363 — draft validity window). Format: YYYY-MM-DD.
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
   > | # | Rank | Action | Rationale | What happens |
   > |---|------|--------|-----------|--------------|
   > | **1** | 1 | `rewrite` | Vague ACs cause validation gate disagreement; fix now | Revise each vague criterion before saving |
   > | **2** | — | `skip` | Skip recorded in revision log; accept downstream risk | Save as-is — skip recorded in revision log |
b. If `rewrite`: for each flagged criterion, prompt for a replacement. Rewrite in the draft before saving.
c. If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Acceptance criteria vague-language scan: skipped.`

If no vague language detected: proceed silently.

**Meta-rule (Spec 171)**: New checklist items added to any FORGE command file must include a `Detection:` annotation — values: `active | passive-acceptable | N/A`. If `passive-acceptable`, include a one-line explanation why active detection is not feasible.

---

### [mechanical] Step 6d — Behavioral-AC Fixture Scan (Spec 349)

Sibling pattern to Step 6c. Where Step 6c catches *vague* AC language, Step 6d catches ACs that are specific in language but require driving the system to verify — runtime behaviors the validator subagent cannot directly observe. Such ACs frequently close as DEFER or PARTIAL (Spec 225: 3/8 PARTIAL; Spec 315: 10/16 DEFER) when the validator has no runnable artifact to gate against. Pairing the AC with a fixture turns the AC mechanically-verifiable. See `docs/process-kit/behavioral-ac-fixture-guide.md` for the canonical convention, fixture naming (`.forge/bin/tests/test-spec-NNN-<behavior>.{sh,ps1}`), and PASS/SKIP/FAIL semantic.

After the spec draft is written (and after Step 6c completes), scan each acceptance criterion for behavioral-AC patterns:
- `(running|run|invoke|execute) /[a-z-]+`
- `(fresh|new) (fixture|copy|repo|project)`
- `after <action>, the operator (sees|observes)`

If any acceptance criterion matches:
a. Present a choice block:
   ```
   Behavioral acceptance criteria found — the following ACs describe runtime behavior the validator cannot drive directly:
   - Criterion N: "<text>" — matched pattern: "<pattern>"
   ...
   Pair each behavioral AC with a fixture at `.forge/bin/tests/test-spec-NNN-<behavior>.{sh,ps1}` to graduate it from DEFER to mechanically-verifiable. See docs/process-kit/behavioral-ac-fixture-guide.md.
   ```
   > **Choose** — type a number or keyword:
   > | # | Rank | Action | Rationale | What happens |
   > |---|------|--------|-----------|--------------|
   > | **1** | 1 | `pair` | Behavioral ACs validate poorly without fixtures; pair now | For each flagged AC, prompt for fixture filename and add a Test Plan note |
   > | **2** | — | `skip` | Operator accepts downstream DEFER risk | Save as-is — skip recorded in revision log |
b. If `pair`: for each flagged criterion, prompt for `test-spec-NNN-<behavior>` (filename stem). Append the fixture path to the spec's Test Plan with a note: `Fixture: .forge/bin/tests/test-spec-NNN-<behavior>.{sh,ps1} (authored at /implement)`.
c. If `skip`: append to the spec's Revision Log: `YYYY-MM-DD: Behavioral-AC fixture scan: skipped.`

If no behavioral-AC patterns detected: proceed silently.

Detection: active.

The fixture itself is authored at `/implement` (not `/spec`); this directive only ensures the spec records the intent and the validator at `/close` has a runnable artifact to gate against.

### [mechanical] Step 6e — Score-Audit Predicted Record (Spec 368)

After the spec file is written and scored, append a `predicted` record to the score-audit log so `/evolve` F4 can compare predictions against observed proxies at close time. The helper at `.forge/lib/score-audit.sh` (PowerShell parity at `.forge/lib/score-audit.ps1`) handles JSON formatting, atomic-append bound, and shell-derived timestamps; do NOT inline JSON here.

`kind_tag` is one of: `instrumentation`, `doc`, `command-edit`, `linter`, `template-sync`, `process-defect`, `feature`, `hotfix`, `other`. Default: infer from spec title and lane (e.g., a `process-only` spec touching `template/.claude/commands/` → `command-edit`; a `standard-feature` spec adding a script → `feature`). Operator may override at `/spec`.

```bash
bash .forge/lib/score-audit.sh record-predicted "$spec_id" "$bv" "$e" "$r" "$sr" "$tc" "$lane" "$kind_tag" 0
```

(PowerShell: `pwsh .forge/lib/score-audit.ps1 record-predicted "$spec_id" "$bv" "$e" "$r" "$sr" "$tc" "$lane" "$kind_tag" 0`.)

The helper is advisory — failures emit a WARN to stderr but never block `/spec`. Records land in `${SCORE_AUDIT_FILE:-.forge/state/score-audit.jsonl}`.

See: [docs/process-kit/score-calibration-loop.md](../../docs/process-kit/score-calibration-loop.md) for the proxy mapping and time-blindness mitigation principle.

---

<!-- spec-388-adjacency-scan:start -->
### [mechanical] Step 6f — Adjacency scan (Spec 388)

After the spec file is written and scored (Step 6e complete), scan in-flight drafts for scope adjacency. Surface adjacent drafts as **data**, not as a recommendation; offer fold-via-`/revise` as one option in the spec-creation choice block.

**Inputs**
- The new spec file just written (`docs/specs/NNN-<slug>.md`) — its frontmatter and `## Implementation Summary` `Changed files` list.
- All in-flight drafts: scan `docs/specs/*.md` directly. Do NOT read `docs/backlog.md` for the `Consensus-Review:` field — that field lives in per-spec frontmatter, not in the rendered backlog table (split-file mode, Spec 399).
- Optional thresholds in AGENTS.md (under `forge.spec.adjacency`):
  - `file_overlap_threshold` (default `0.5`)
  - `keyword_threshold` (default `2`)
- Stopword list at `docs/process-kit/stopwords.txt` (lowercase tokens, lines starting with `#` are comments).

**Filter**: include candidate spec when ALL hold:
- `Status: draft` in frontmatter
- One or both of:
  - `Consensus-Review: true` or `Consensus-Review: auto` in frontmatter
  - Revision Log contains a line matching `^- \d{4}-\d{2}-\d{2}: Revised via /revise` (post-/revise marker — the durable signal that survives a future deprecation of the `Consensus-Review:` field per Spec 387's deferred scope)

**Overlap computation** for each candidate:
1. **File overlap** — intersect new-spec `Changed files` with candidate's `Changed files`.
   `ratio = |intersection| / min(|new_files|, |candidate_files|)`. If either side is empty, set `ratio = 0` (skip without erroring).
2. **Keyword overlap** — tokenize Title (first `# Spec NNN — <title>` heading, drop the `Spec NNN —` prefix) plus first paragraph of `## Objective`. Lowercase, split on whitespace and `[/_,.;:()\[\]"'!?]`, strip stopwords, dedupe to a set. `match_count = |new_tokens ∩ candidate_tokens|`.
3. Hit when `ratio ≥ file_overlap_threshold` OR `match_count ≥ keyword_threshold`.

**Ranking**: combined score `ratio × 4 + min(match_count, 3)`. Cap on keyword contribution preserves file-primary intent (max keyword = 3, max file = 4). Sort hits by combined score descending; surface only the top 3.

**Surface**

If 0 hits: proceed silently to Step 7. Choice block emitted by Step 7+ remains unchanged.

If ≥1 hit: emit a data block before the spec-creation choice block:

```
## Adjacent in-flight specs (Spec 388)
The following draft specs overlap the proposed scope. This is data, not a recommendation — you decide.

| Rank | Spec | Title | Files | Keywords | Combined |
|------|------|-------|-------|----------|----------|
| 1 | NNN | <title> | N/M | K | <score> |
| 2 | NNN | <title> | N/M | K | <score> |
| 3 | NNN | <title> | N/M | K | <score> |
```

Then extend the spec-creation choice block to include `fold-via-/revise <NNN>` rows (one per surfaced hit, max 3) alongside `spec-it`, `defer`, `drop`, and `dismiss-overlap`.

**Operator response handling**
- `spec-it` → proceed normally to Step 7.
- `fold N` (N is the row number in the choice block, NOT the spec ID) → resolve N to the corresponding adjacency hit's spec-id, invoke `/revise <spec-id> "Folded from proposed Spec NNN: <one-line summary of new spec objective>"`, and roll back the just-written new spec file (delete it; renderers re-derive on next run).
- `defer` → mark new spec `Status: deferred` and proceed.
- `drop` → delete the just-written new spec file and exit.
- `dismiss-overlap` → suppression scope is **single-invocation only** (the rest of this /spec run); proceed to Step 7 with normal spec-creation. No cross-invocation state.

**Fail-soft**: if ANY of the following errors occur during Step 6f, emit `WARN: adjacency scan skipped — <reason>` and proceed to Step 7 with normal spec-creation. The scan MUST NEVER block /spec on its own failure:
- `docs/process-kit/stopwords.txt` missing or unreadable
- AGENTS.md threshold value present but non-numeric or out of `[0.0, 1.0]` (file ratio) / `[0, 50]` (keyword count)
- Frontmatter parse error on any candidate spec (skip that spec, continue scan unless ≥3 candidates fail in a row → bail)
- Total scan wall time exceeds 5 seconds

Detection: active.

See: docs/specs/388-spec-adjacency-scan.md for rationale, /consensus loop-17 framing, and full AC set.

<!-- spec-388-adjacency-scan:end -->

---

## [mechanical] Steps 7–10

7. **Write-side mode check (Spec 399)**: Before any canonical-table-row write, run `.forge/bin/forge-py .forge/lib/derived_state.py --skip-canonical-write`. Read stdout: if `skip`, the project is in split-file mode — skip steps 7-9 below entirely. The new spec's frontmatter is already on disk; renderers (which the operator runs via `/matrix` or stoke) will reflect the new spec on next render. Event-stream writes (`.forge/state/events/<spec-id>/`) proceed unchanged. If stdout is `proceed`, run steps 7-9 (Phase 1 dual-write). If the helper exits nonzero, abort the canonical-write step and surface stderr — do NOT default to either behavior.
   - In `proceed` mode only:
     7a. Update docs/specs/README.md — add a row for the new spec (sorted by number).
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
**Next spec number (Spec 399)**: Run `.forge/bin/forge-py .forge/lib/derived_state.py --get-spec-index --format=count` (or `--format=json` if you also need IDs). The count + scan of existing IDs tells you the next available number.
Write the spec file at `docs/specs/NNN-<slug>.md` with:
- Status: `draft`
- All sections populated from Spec Kit mapping + FORGE defaults
- `Trigger: spec-kit-guided`
- `Last updated:` today (YYYY-MM-DD)
- `valid-until:` today + `forge.spec.draft_validity_days` (default 90) — Spec 363 draft validity window

### [mechanical] Step F — Finalize via main flow

After Step E, return to the main flow at Step 6b (Review Router) and continue through Steps 7-10 (index, changelog, backlog, report). When reporting completion in Step 10, append: "Created via Spec Kit guided flow."

