# Operational Runbook

Last updated: 2026-04-28

This runbook covers operational procedures for FORGE-managed projects. For human validation of AI-delivered work, see [human-validation-runbook.md](human-validation-runbook.md).

For flipping FORGE foundation gates from `mode: advisory` to `mode: strict` (Specs 327 + 330), see [advisory-to-strict-flip-plan.md](advisory-to-strict-flip-plan.md).

For triaging `GATE [authorization-rule-lint]` (Step 7c) or `GATE [agents-md-drift]` (Step 7d) findings — what each WARN/FAIL means, the prose↔YAML two-sided model, and the alias map — see [agents-md-authorization-model.md](agents-md-authorization-model.md) (Spec 334).

---

## Process-Kit Doc Freshness Convention (Spec 278)

Process-kit guides that reference **external authorities** — Anthropic docs, SDK surfaces, model lists, third-party APIs, pricing pages — carry factual claims whose truth value depends on the upstream source. Without a revalidation signal, hard-coded numbers drift silently and FORGE becomes a vector for outdated guidance.

### The `Last verified:` marker

Guides that cite external sources MUST carry a freshness marker within the **first 10 lines** of the file:

```markdown
<!-- Last verified: YYYY-MM-DD against <source-url> -->
```

- **Date**: the ISO date on which a human or agent last reconciled the guide's factual claims against the linked source.
- **Source URL**: the single most authoritative upstream doc for the guide's claims (e.g., the Anthropic prompt-caching page).

This is distinct from the `Last updated:` marker (which tracks internal edits). A guide can be updated for stylistic reasons without its `Last verified:` date changing — and vice versa (revalidation may confirm no edits are needed).

### When to use

Apply the `Last verified:` marker to any process-kit guide whose correctness depends on an external source. Examples:

- Guides citing Anthropic API semantics (caching, thinking, batch, tool use).
- Guides citing SDK method signatures or configuration keys.
- Guides citing model lists, model tiers, or pricing.
- Guides citing third-party CLI tool flags or output formats.

Guides that are purely FORGE-internal (process descriptions, role definitions, methodology docs) do **not** need the marker — FORGE maintains those continuously.

### Revalidation procedure

1. Open the source URL in a browser (or fetch it via `WebFetch` / the relevant MCP server).
2. Walk each factual claim in the guide (numbers, TTLs, tier names, method names, configuration keys) and compare to the source.
3. If any claim has changed, update the guide. If a claim is no longer present, decide whether to remove it or add a caveat.
4. Update the `<!-- Last verified: -->` marker's date. If the source URL itself changed, update the URL too.
5. Commit the change under an `small-change` lane spec (or as part of the broader spec that triggered the revalidation).

### Staleness signals

`/now` flags guides whose `Last verified:` date is older than the configured threshold (see `forge.process_kit.freshness_threshold_days` in AGENTS.md, default 180 days). Staleness is **advisory only** — it does not block `/close` or `/implement`. The cadence exists to surface silent drift, not to gate delivery.

---

## Kill Switch Procedure

The kill switch is a mandatory safeguard at all autonomy levels. It immediately halts agent activity, preserves state for review, and reverts to L1 (human-gated) autonomy.

### When to Trigger

Trigger the kill switch when any of the following occur:

- **Budget breach**: Agent exceeds lane budget ceiling (tokens, cost, time, or retries)
- **Scope escape**: Agent is modifying files outside the spec's declared scope
- **Unexpected behavior**: Agent output is nonsensical, repetitive, or contradicts instructions
- **Security concern**: Agent appears to be exposing secrets, credentials, or sensitive data
- **Cascading failures**: Agent is in a retry loop or producing compounding errors
- **Human judgment**: Anything feels wrong — the kill switch is zero-cost to trigger

### Procedure

**Step 1 — Halt**

Stop the agent immediately using the most appropriate method:

| Environment | Action |
|-------------|--------|
| Claude Code CLI | `Ctrl+C` to interrupt; close terminal if unresponsive |
| Claude Code IDE | Click "Stop" in the agent panel; close the panel if unresponsive |
| API / automated | Revoke or rotate the API key; cancel pending requests |
| CI/CD pipeline | Cancel the running job; disable the workflow trigger |

**Step 2 — Preserve State**

Before making any changes, capture the current state:

1. **Save the conversation/session**: Copy or export the full agent conversation
2. **Capture git state**: Run `git status`, `git diff`, and `git log --oneline -10` — save output
3. **Screenshot any errors**: Capture terminal output, error messages, or unexpected behavior
4. **Note the trigger**: Record what caused you to pull the kill switch

**Step 3 — Report**

Create a kill switch incident record:

```markdown
## Kill Switch Incident — YYYY-MM-DD

- **Trigger**: (what caused the kill switch)
- **Autonomy level at time**: L_
- **Active spec**: NNN — (spec name)
- **Files modified**: (list from git status)
- **Agent state**: (what the agent was doing when halted)
- **Git state**: (clean / dirty — include diff summary)

### Assessment
- **Damage**: (none / contained / needs revert)
- **Root cause**: (budget breach / scope escape / bug / other)
- **Action taken**: (see Step 4)
```

Save this to the session log (`docs/sessions/YYYY-MM-DD-NNN.md`) or create a new session log if one does not exist.

**Step 4 — Assess and Act**

Evaluate the state and choose an action:

| Situation | Action |
|-----------|--------|
| Work is clean and on-track, just hit a budget ceiling | Extend budget and resume at current level |
| Work is off-scope but salvageable | `git stash` the changes; revise the spec scope; resume at L1 |
| Work is incorrect or harmful | `git checkout -- .` to discard changes; revert to L1; review spec |
| Unclear what happened | `git stash` to preserve; revert to L1; review conversation log |

**Step 5 — Revert Autonomy to L1**

After any kill switch event, the project autonomy resets to L1 (human-gated) regardless of the previous level. To re-escalate:

1. Complete the current spec at L1 successfully
2. Conduct a root-cause review of the kill switch event
3. Document findings in a process improvement spec or signal
4. Re-evaluate graduation criteria before raising autonomy level

---

## Budget Monitoring

### Checking Budget Status

During a session, monitor resource consumption against lane ceilings:

| Metric | How to Check |
|--------|-------------|
| Token usage | Check conversation length; estimate ~4 chars per token |
| Wall-clock time | Note session start time; check elapsed |
| Retry count | Count failed attempts at the same task |
| API cost | Check provider dashboard if available |

### Budget Breach Protocol

1. Agent detects ceiling approach (80% threshold) → warns human
2. Agent hits ceiling → pauses immediately (same as kill switch Step 1)
3. Human reviews work completed so far
4. Human authorizes: extended budget, scope reduction, or session end

---

## Autonomy Escalation

### Requesting a Level Increase

To move from the current autonomy level to a higher one:

1. Verify graduation criteria are met (see AGENTS.md trust model configuration)
2. Review kill switch incident history — any incidents in last 10 specs disqualifies
3. Human explicitly approves the new level in AGENTS.md
4. Document the change in a session log with rationale

### Emergency De-escalation

Any of these conditions trigger automatic de-escalation to L1:

- Kill switch triggered (any reason)
- Escaped defect found in production
- Agent modifies files outside spec scope
- Budget ceiling breached without warning
- Human requests de-escalation (no justification needed)

## /close Commit-Ordering Invariant (Spec 348)

`/close` commits the closing spec's mutations in a single Step 8a commit (no follow-on commit needed). The commit fires AFTER all spec-mutating steps (3, 4a, 5, 6, 6a, 6b, 7, 8) have completed, ensuring deferred-scope dispositions, signal capture, runbook amendments, session-log updates, and artifact-link writes are all captured atomically.

**Why this matters**: A prior version of `/close` ran the commit at Step 4 (before Steps 5–8 mutated state), causing post-Step-4 edits to sit uncommitted until the next `/close` (or get lost if no further `/close` ran in-session). Spec 348 closed this defect after the pattern fired 4 times in a single session (2026-04-28: closes of Specs 225, 297, 315, 332).

**Step 4 is now the auxiliary-actions block only** (4a artifact relationships, 4b auto evolve loop check, 4c ambient status lines) — none commit. The `git commit` and `git push` invocations (with their commit-guard marker bracket and push-confirmation prompt) live exclusively at Step 8a.

**Regression test**: `scripts/tests/test-close-commit-ordering.sh` (with PowerShell parity at `.ps1`) exercises the ordering invariant and asserts the close commit captures both deferred-scope and signal-capture mutations in a single commit.

## Validator Role: Behavioral-AC Fixture Handling (Spec 349)

When the validator subagent at `/close` encounters an acceptance criterion describing a runtime behavior — running a command, observing terminal output, comparing fresh-fixture state — the validator may not be able to drive that behavior directly. Such ACs historically closed as DEFER or PARTIAL (Spec 225: 3/8 PARTIAL; Spec 315: 10/16 DEFER) when the validator had no runnable artifact to gate against.

Spec 349 documents the canonical fix: pair the AC with a fixture at `.forge/bin/tests/test-spec-NNN-<behavior>.{sh,ps1}` (bash mandatory; PowerShell gated on `command -v pwsh`). The fixture exits PASS / FAIL / SKIP and the validator counts the AC accordingly.

**Validator handling**:
- AC paired with a fixture → run the fixture; PASS/FAIL/SKIP gate the AC. No DEFER.
- AC matches a behavioral pattern but has no paired fixture → flag as DEFER with the note "behavioral AC; fixture not authored at /spec — see docs/process-kit/behavioral-ac-fixture-guide.md".
- Structural ACs (file existence, md5 parity, grep, exit codes) — verified directly by the validator as before. No fixture needed.

**Authoring entry point**: `/spec` Step 6d (Spec 349 directive) prompts the spec author at draft time when a behavioral AC pattern is detected. The fixture itself is authored at `/implement`.

See [behavioral-ac-fixture-guide.md](behavioral-ac-fixture-guide.md) for the full convention, fixture naming, PASS/SKIP semantic, and worked example (Spec 315 AC 12b).

## Backlog Hygiene: Draft Validity Window (Spec 363)

Drafts age. A 35–39-spec backlog with the oldest draft at 42 days is a legitimate signal that some work has lost its moment, but absent an explicit prompt the operator has no surface that says "this draft is stale." Spec 363 introduces a draft-only `valid-until: YYYY-MM-DD` frontmatter field with a configurable window (`forge.spec.draft_validity_days` in AGENTS.md, default 90) and threads it through the existing solve-loop without adding a new periodic-review step.

**End-to-end flow**:

1. **`/spec` sets validity at creation**: every new draft gets `valid-until: today + N` (default N = 90). The field is part of `_template.md` and `_template-light.md` frontmatter.
2. **`/now` surfaces a count when drafts are past validity**: `/now` Step 8d reads all `Status: draft` specs and emits one line — `Aging drafts: N past validity — run /matrix to triage via strategic-fit flow.` — when `N ≥ 1`. Silent on zero. Drafts lacking `valid-until:` (pre-backfill or commented-out) are silent — not counted, not warned.
3. **`/matrix` Step 8 absorbs expired drafts into strategic-fit triage**: Step 8b2 pre-flags expired drafts; the existing keep/deprecate/reclassify flow at Step 8g handles them alongside scope-creep candidates. A new `renew` disposition runs `/revise` to refresh the field. No new disposition table, no new column.
4. **`/revise` refreshes validity automatically**: any `/revise NNN <edit>` against a `Status: draft` spec rewrites `valid-until:` to `today + N`. Explicit operator engagement is the renewal mechanism — there is no `/renew` command and no choice block. The operator can also edit the field directly.

**Backfill**: a one-time script (`scripts/backfill-valid-until.sh`) populated `valid-until:` on all existing drafts at /implement time. The formula `max(source+90d, today+30d) + (spec_id mod 14) days` plus a uniqueness fixup pass guarantees no two backfilled drafts share an identical date — this prevents the flood failure mode where same-source-date cohorts would otherwise expire together. The script is idempotent: re-running produces zero changes when all drafts have `valid-until:` populated, and operator-edited values are never clobbered.

**Recommended drainage sequence (Spec 362)**: When the backlog has accumulated 5+ ready drafts, the optimal flow is (1) **/now** to surface aging-draft count (Spec 363); (2) **/matrix** to plan sprints — Step 11 emits an `execute-all` choice block when ≥2 dependency-clean parallel-safe lanes exist; (3) the operator selects `execute-all`, which constructs a `/parallel --batch '<lane1>' '<lane2>' ...` command spanning all dependency-clean lanes forward in dependency-respecting order; (4) `/parallel` runs each bundle sequentially with its existing per-bundle conflict pre-flight, swarm budget, and post-merge `close all` choice block (which fires once per bundle, preserving per-spec push authorization). This sequence drains the backlog without adding a new orchestrator command — both `/matrix` and `/parallel` stay within their established roles.

**Trade-off**: the field is operator-editable, so aging-evasion via direct edit is possible. This is the same friction trade-off the deprecated Spec 360 `keep` action would have had — but here the operator must touch the spec file, which is the explicit engagement signal. Sustained bulk-renewing without triage would surface as a backlog-overload symptom, not a Spec 363 defect; a future WIP-limit spec could address it if observed.
