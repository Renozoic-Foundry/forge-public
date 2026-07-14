---
name: consensus
description: "Run a proposal through all registry roles for structured consensus"
workflow_stage: review
---
# Framework: FORGE
# Model-Tier: sonnet
Run a topic, spec, or proposal through all registry roles for structured multi-perspective consensus.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /consensus — Multi-role structured review producing a consensus decision summary.
  Usage: /consensus <topic | spec-number | ADR-number>
  Arguments:
    topic        — freeform text (e.g. "Should we adopt property-based testing?")
    spec-number  — e.g. /consensus 179 (reviews the spec by all roles)
    ADR-number   — e.g. /consensus ADR-003 (reviews the ADR by all roles)
  Behavior:
    - Reads forge.role_registry from AGENTS.md (or uses default role set)
    - Spawns each role as an isolated read-only sub-agent
    - Each role produces: vote (approve/concern/reject), rationale, key risk
    - Aggregates into a decision summary table with vote tally and divergence signal
  See: .claude/agents/, AGENTS.md (role registry)
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Parse input

Parse $ARGUMENTS to determine the input type:

1. **Spec reference**: If input matches a number (e.g., `179`), read `docs/specs/NNN-*.md` and use the spec's Objective, Scope, and Acceptance Criteria as the review material.
2. **ADR reference**: If input matches `ADR-NNN`, read `docs/decisions/NNN-*.md` and use it as the review material.
3. **Freeform topic**: Otherwise, treat the entire argument string as a freeform topic for review.

If no argument provided: stop and report "Usage: /consensus <topic | spec-number | ADR-number>"

## [mechanical] Step 2 — Resolve role registry

Read AGENTS.md and look for a `forge.role_registry` section or `forge.dispatch_rules` configuration.

**If a role registry is configured**: use the listed roles.

**If no registry is configured** (default): use this default role set, which covers the key review perspectives:
- **Devil's Advocate** (DA) — risk and failure mode analysis
- **Maverick Thinker** (MT) — creative alternatives and unconventional perspectives
- **CTO** — architectural coherence and technical debt
- **COO** — process efficiency and operational impact
- **CISO** — security implications (if topic touches auth/data/access)

Read `.claude/agents/<role>.md` for each role's preamble. If a role instruction file does not exist, skip that role with a note.

## [mechanical] Step 3 — Declare planned_agents and dispatch

### Step 3.0 — Workflow-path capability probe (Spec 524)

Before the prompt-driven dispatch below, branch on Workflow-tool availability:

- **Workflow tool present in this session's toolset** (Claude Code) → use the **Workflow path**:
  invoke the `consensus-fanout` workflow (`.forge/workflows/consensus.workflow.js`) via the Workflow
  tool, passing `args = {specId, reviewMaterial, roster: [{role, agentType, effort?, model?}],
  stageFraming, roundCap}`. `roundCap` is 1 or 2 (the workflow covers rounds 1–2 only; explore F2).
  The workflow returns `{rounds: [{verdicts[], tally, divergence, round_two}], final_divergence,
  recommended_action, role_yield}` — schema-validated verdicts, in-script tally + Spec 391 round-2
  re-vote, NO prose parsing (Req 3). Then **in the main loop** (the workflow performs no repo side
  effects — explore F5): render the Step 5 summary from the return value; apply the Spec 468
  terminal classification (HUMAN-JUDGMENT taxonomy, model-side — never in-script); run Step 4b
  cap/extension prompts and Step 4c Consensus-Close-SHA for round 3+; write the session sidecar
  role-yield from `role_yield`; run the Spec 305 `record-dispatch` calls. MT reframes and
  HUMAN-JUDGMENT still escalate to the operator — never auto-revised (Constraints).
  Per-role effort/model overrides are pinned by role identity inside the workflow
  (`OVERRIDE_BY_ROLE`) and MUST NOT be derived from `$ARGUMENTS`/review content (Req 5; CISO).
- **Workflow tool absent** (Codex/Cursor/Gemini/Aider, or a Claude Code session without it) → use
  the **prompt-driven fallback** below (Steps 3.1–4), the documented cross-runtime contract. This
  is not dead code (Constraints); the two paths produce identical divergence classification and
  recommended action on the same verdict set — the classifier is a single source
  (`.forge/lib/consensus-classifier.js`), byte-verified against the workflow embed by
  `forge-parity.sh --check` Surface 6 (Spec 524 Req 8). Terminal workflow failure mid-run → fall
  back to prompt-driven and inform the operator.

**Single source of truth (Spec 423)**: this step declares `planned_agents` as an explicit list BEFORE any dispatch, and the dispatch narration is **generated from `planned_agents`** — not authored freehand. The same list drives both narration and the Task tool-call loop, so the count and names cannot diverge. This collapses the narration-vs-dispatch defect class that caused /consensus 399 round 3 to silently omit COO. (In the Workflow path the roster array IS the dispatch list — the Spec 423 defect class is eliminated by construction; explore F3.)

1. **Declare `planned_agents`**: Build an explicit list of role identifiers for this round, one entry per role to be spawned. Example:
   ```
   planned_agents = [DA, MT, CTO, COO]
   ```
   Include CISO when Step 2's topic-touches-auth/data/access condition applies. The list is fixed before any Task tool call.

2. **Emit narration generated from `planned_agents`**: Write the dispatch narration line whose count (N) and role names are derived from `planned_agents` — not authored freehand:
   ```
   Spawning N reviewer agents in parallel (R1, R2, ..., RN).
   ```
   N and the role names MUST equal the contents of `planned_agents`. Do not author a count or name that is not in the list. This narration is **generated from `planned_agents`** (Invariant A — Spec 423).

3. **Dispatch — one Task call per list entry, in a single parallel-tool-call block**: Iterate `planned_agents`. For each role, emit exactly one Task tool call in the same response block, passing:
   - The role's instruction preamble (from `.claude/agents/<role>.md`)
   - The review material (spec content, ADR content, or freeform topic)
   - **Stage framing (Spec 543)** — when the review material is a spec, re-read the spec's `Status:` frontmatter at dispatch time and key the framing off it:
     - `draft` (or any pre-implementation status): include this line verbatim in EVERY reviewer's dispatch prompt: "REVIEW STAGE: pre-implement spec-soundness review; implementation is intentionally absent — evaluate the spec (objective, scope, acceptance criteria, test plan, risks), not delivery evidence. Do not cite missing implementation, absent test output, or an empty Evidence section as grounds for rejection."
     - `implemented` (or later): no framing line — current prompt unchanged.
     - Freeform topic / ADR (no spec): no framing line.
   - Instructions to produce a structured assessment:
     ```
     Review the following material from your role's perspective.

     Produce your assessment as a JSON code block:
     {
       "role": "<your role name>",
       "vote": "approve" | "concern" | "reject",
       "rationale": "<1-3 sentences explaining your position>",
       "key_risk": "<the single most important risk from your perspective, or 'none'>"
     }

     Vote meanings:
     - approve: proceed as-is, no significant issues from my perspective
     - concern: proceed with caution, issues noted but not blocking
     - reject: do not proceed, significant issues must be resolved first
     ```

4. Parse each role's JSON response. Record results keyed by role identifier so reconciliation (Step 3b) can match each `planned_agents` entry to a returned result.

5. If a sub-agent fails or produces invalid output, record an explicit dispatch-failure entry: `{ "role": "<name>", "status": "dispatch-failed", "vote": "error", "rationale": "Role assessment failed — <reason>", "key_risk": "unknown" }`. Reconciliation (Step 3b) treats this as accounted-for; failures surface to the operator, no auto-retry.

6. **Role-value instrumentation (Spec 305)** — after parsing each role's response, append one `role-dispatch` record per assessed role to the shared score-audit sink:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.sh record-dispatch <NNN-or-topic-slug> consensus <role> <vote> "" "<key_risk>"
   ```
   Map `vote` → recommendation verbatim (`approve|concern|reject`). For a freeform-topic consensus (no spec id) pass the topic slug as the first arg. Skip dispatch-failed entries (no vote). Best-effort: the helper exits 0 even if the sink is unwritable — never block consensus. (PowerShell: `pwsh ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/score-audit.ps1 record-dispatch ...`.) `Detection: active`.

Run all role assessments in **parallel** where possible (single response block, multiple Task calls).

## [mechanical] Step 3b — Pre-aggregation reconciliation gate (Spec 423)

Before advancing to Step 4 (tally), perform reconciliation against `planned_agents`. This gate is the single mechanical check between dispatch and aggregation.

1. **Reconcile**: for each role in `planned_agents`, verify it has either a returned result OR a recorded dispatch-failure (from Step 3.5).

2. **If reconciliation passes** (every `planned_agents` entry is accounted for): proceed silently to Step 4.

3. **If reconciliation fails — `planned_agents` has entries with no result and no failure record — refuse to advance**: do NOT aggregate, do NOT proceed to Step 4. Emit a structured diagnostic and stop the round:
   ```
   ## Dispatch Reconciliation Failure (Spec 423)
   Round N planned_agents had unaccounted-for entries.
   - planned: [list from planned_agents]
   - returned results: [list of role IDs with results]
   - dispatch failures: [list of role IDs with explicit failure records]
   - missing (no result, no failure): [list of role IDs]

   Halting round before aggregation. Re-dispatch the missing roles or record explicit failures, then re-run /consensus.
   ```
   Operator decides next action (re-dispatch missing roles, or record them as failures and continue). No auto-retry.

## [mechanical] Step 4 — Compute vote tally and divergence

1. **Vote tally**: Count approve, concern, reject, and error votes.

2. **Divergence signal**: Flag significant disagreement. "Aligned" splits into three sub-signals (Spec 301):
   - **Aligned-approve**: All votes are approve.
   - **Aligned-concern**: All votes are concern — no approve, no reject. This is a canonical **Revise** signal (distinct from mild divergence): every role sees systemic issues from its own lens, so the proposal has cross-cutting problems even though no single role rejects it outright.
   - **Aligned-reject**: All votes are reject.
   - **Mild divergence**: Mix of approve and concern (no rejects).
   - **Strong divergence**: At least 1 reject alongside 2+ approves — roles fundamentally disagree.
   - **Blocked**: Majority reject.

3. **Recommended action** based on tally:
   - All approve (aligned-approve) → "Proceed"
   - **All concern (aligned-concern) → "Revise — defer or rework before proceeding"** (each role sees systemic issues from its own lens; treat as a stronger signal than mild divergence)
   - Majority approve, some concern (mild divergence) → "Proceed with noted concerns"
   - Strong divergence → "Discuss — roles fundamentally disagree"
   - Majority concern → "Revise — address concerns before proceeding"
   - Majority reject / aligned-reject → "Do not proceed — significant opposition"

## [policy] Step 4b — Round cap and stop rule (Spec 301; extended by Spec 395)

Consensus rounds show diminishing returns after round 3. Round 4+ tends to surface spec-bloat divergence rather than new root-cause analysis (see pattern-analysis signals CI-173, CI-175). Round ordering matters — architectural reframes surface best in round 1 (CI-174).

**Stop rule**: After round 3 without convergence, escalate to the operator for an explicit decision rather than auto-running round 4+.

Operator options at the 3-round cap:
- **Accept current state** — remaining divergence is implementation-notes, not spec changes. Proceed.
- **Revise out of scope** — reviewed content needs a `/revise` cycle. Stop consensus; revise; re-enter.
- **Defer to follow-up spec** — reviewer concern is valid but orthogonal to this spec's scope. Record it as a follow-up spec candidate; proceed with the current spec.
- **Continue to round 4** — operator authority override (gated; see extension criteria below). Record the rationale in the session log.

This is a policy guideline, not a mechanical gate — round 4+ remains supported via operator choice. Cross-session invocations of `/consensus` on the same topic count toward the round cap (the policy is topic-level, not session-level).

### [mechanical] Round-cap extension prompt (Spec 395, Req 4)

When the round-3 cap is reached and the operator considers `Continue to round 4`, /consensus emits an explicit extension prompt that gates the override on two operator-declarative criteria:

```
Round 3 reached — extend? (R=<n>; does this spec span ≥ 3 distinct subsystems
where concerns differ per subsystem? [y/N])
```

**Extension is allowed when ANY hold**:
- `R ≥ 4` (high-risk specs warrant additional alignment effort), OR
- Operator answers `y` (the spec spans ≥ 3 distinct subsystems where reviewer concerns cluster differently per subsystem).

**Extension is denied otherwise** — operator's `n` (or empty answer; the default is `N`) ends consensus at round 3 per Spec 301 default. The operator must select one of the other three options (Accept / Revise / Defer).

**Why operator-declarative rather than algorithmic**: a prior draft of Spec 395 used `awk '{split($0, parts, "/"); print parts[1]"/"parts[2]}'` to count subsystems by file-path-prefix. This was fragile — it conflated `template/.claude/...` with `tests/...` with root-level files; counted 3 sibling directories as 3 subsystems even when they were one logical concern; and broke entirely on root-level files. Operators know subsystem boundaries better than path-prefix heuristics do, so the criterion is operator-declarative.

The `Round 4` rationale (whichever criterion was met) is recorded in the session log alongside the operator's choice.

When extending past round 3, **Spec 389's Consensus-Close-SHA encoding is no longer applicable** — Step 4c skips SHA writing for `N > 2` because rounds 3+ indicate unresolved divergence. A fresh DA pass is warranted at `/implement` for any spec that required round 4+ to converge.

The maximum extension is to round 5 — operator may extend round 3→4 then 4→5 (each gated by the same criteria), but rounds 6+ are not supported. If round 5 still does not converge, the spec needs `/revise` rather than further consensus.

## [mechanical] Step 4c — Consensus-Close-SHA recording (Spec 389)

When the consensus topic is a spec AND the current round converges (round ≤ 2 with aligned-approve ≥ 4/5), record `Consensus-Close-SHA: $(git rev-parse HEAD)` to the spec's frontmatter. This SHA is the reference point that `/implement` Step 2b's encoded-DA verifier uses to skip a fresh DA subagent spawn for specs annotated with `DA-Encoded-Via: consensus-round-N`.

1. **Topic check**: skip silently if Step 1 resolved input as ADR or freeform topic. The mechanism is spec-only.

2. **Round detection**: parse `$ARGUMENTS` for `--round N` or `round=N`. If absent, **skip silently** with note `Consensus-Close-SHA write skipped: no round number provided. Re-invoke with --round N to enable encoded-DA path on this spec.` This avoids fragile parsing of the Consensus Record. Operators opt in by passing the round explicitly.

3. **Round-cap check**: if `N > 2`, skip silently. Spec 389 limits encoding to rounds 1 and 2 — rounds 3+ indicate unresolved divergence, so a fresh DA pass is warranted at /implement.

4. **Convergence check**: skip silently unless Step 4's divergence signal is `Aligned-approve` with ≥ 4 approve votes.

5. **Operator-exit check**: if Step 4b's 3-round-cap path fired and the operator chose `Accept current state`, `Revise out of scope`, or `Defer to follow-up spec`, do NOT write the SHA. Only convergent (≤ 2 + aligned-approve) rounds write.

6. **Write**: set `Consensus-Close-SHA: <40-char-sha>` in the spec's frontmatter (replace if present from a prior round). Use `git rev-parse HEAD` to obtain the SHA.

7. **Report**: emit `Consensus-Close-SHA recorded: <8-char-prefix> (round N, aligned-approve M/M). /implement Step 2b can now verify DA-Encoded-Via: consensus-round-N for this spec.`

This step is purely additive — specs without `Consensus-Close-SHA` (legacy + non-convergent + opt-out) continue to use fresh DA at `/implement` Step 2b. **/implement MUST NOT write `Consensus-Close-SHA`**; the SHA is exclusively written here at convergent close. See `docs/process-kit/devils-advocate-checklist.md` § DA-Encoded-Via convention for the end-to-end picture.

## [reference] Autonomous consensus batches and the HUMAN-JUDGMENT taxonomy (Spec 468)

> **Provisional — observed once (n=1), revisit at n≥3.** The patterns below were
> validated across a single autonomous consensus batch (2026-06-11; CI-372/373/375).
> They are codified here so the next operator/agent finds them at decision time, NOT
> as settled doctrine. Treat the terminal-state classifier, Path C, and the cap value
> as working defaults to be re-evaluated once two more autonomous batches accumulate.

### Autonomous-batch worked example (`/loop` dynamic mode as a consensus driver)

`/loop` dynamic mode (a Claude Code harness skill — there is no FORGE `/loop` command)
can drive `/consensus` rounds autonomously. When it does, classify each topic's outcome
with this **4-state terminal classifier**:

- **APPROVED** — convergent aligned-approve. **Minimum 2 rounds before APPROVED** is
  permitted (a single-round approve does not terminate the batch — round 1 surfaces the
  architectural reframe, round 2 confirms it held).
- **REVISE-AUTO** — divergence the loop can resolve by applying reviewer concerns as a
  scoped auto-revision, then re-running. Bounded by the auto-revision cap (below).
- **STALEMATE** — rounds exhausted (round-3 cap, Step 4b) with divergence that is
  implementation-notes, not spec changes. Hand to the operator with the Step 4b options.
- **HUMAN-JUDGMENT** — divergence requiring operator judgment a loop must not auto-resolve
  (see taxonomy below). The loop STOPS and escalates rather than auto-revising.

**Auto-revision cap**: an autonomous batch applies at most **8** auto-revisions across its
topics before halting for operator review (CI-375 observed 7 used cleanly, holding under
the cap). Provisional: raise to 10 if batches consistently hit 7–8; lower to 6 if
consistently under 4.

### HUMAN-JUDGMENT trigger taxonomy (5 examples)

A batch classifies a topic HUMAN-JUDGMENT — escalate, do not auto-revise — when any of:

1. **MT structural reframe + mechanical hardenings** — a Maverick-Thinker reframe changes
   the *mechanism* (not just parameters) AND reviewers add mechanical hardenings on top.
   The reframe is a design choice only the operator should ratify. *(This is the canonical
   Path C trigger — see below.)*
2. **Genuine security finding traded against scope** — a CISO/DA critical that can only be
   closed by reducing operator-visible value (BV) or dropping a feature. The value/safety
   tradeoff is an operator call.
3. **Aligned-concern with divergent root causes** — every role votes `concern` (no approve,
   no reject) but each names a *different* systemic issue. No single auto-revision resolves
   all lenses; the operator decides what to cut.
4. **Doctrinal / architectural-principle tension** — a finding conflicts with a stated
   Architectural Principle (e.g., AP4 "Template is the product"). Re-interpreting doctrine
   is operator authority, not a loop's.
5. **Cross-spec scope collision** — the reframe would move scope into (or out of) a sibling
   spec. Re-drawing spec boundaries needs operator sign-off.

### Path C (the provisionally recommended-first resolution)

When a HUMAN-JUDGMENT topic matches trigger #1 (MT structural reframe paired with mechanical
hardenings), **Path C is the operator-preferred resolution observed on 2026-06-11**:

> **Path C** — *one slice: adopt the MT mechanism-level reframe(s), then apply the mechanical
> hardenings on top of the reframed design — in a single revision, not two.*

Path C beat the alternatives observed that session (Path A: ship original + defer reframe;
Path B: split reframe into its own spec) because it captured the better mechanism without a
round-trip. Provisional (n=1): present Path C first when trigger #1 fires, but the operator
chooses.

### `/now` auto-rev surface — descoped (Spec 468)

A live `/now` "auto-rev N/8 used" counter was scoped OUT of this slice: `/loop` persists no
machine-readable batch state for `/now` to read, and this slice adds no new state file.
**Follow-up trigger**: if/when an autonomous-batch driver persists machine-readable batch
state (e.g. an auto-rev counter file), add the `auto-rev N/8` line to `/now`.

## [mechanical] Step 5 — Present consensus summary

Present the structured output:

```
## Consensus Review — <topic summary>

### Role Assessments

| Role | Vote | Rationale | Key Risk |
|------|------|-----------|----------|
| <role> | <vote> | <rationale> | <risk> |
| ... | ... | ... | ... |

### Vote Tally
- Approve: N
- Concern: N
- Reject: N

### Divergence: <Aligned | Mild divergence | Strong divergence | Blocked>

### Recommended Action: <action>

### Key Concerns (aggregated)
<numbered list of unique risks raised, deduplicated>
```

## [decision] Step 6 — Next action

<!-- safety-rule: session-data — if today's session log has unsynthesized spec activity AND ## Summary is unpopulated, /session is inserted at rank 1 and stop is downgraded to —. See docs/process-kit/implementation-patterns.md § Session-data safety rule. -->

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 2 | `detail <role>` | Drill into one role's reasoning before deciding | Show the full assessment from a specific role |
> | **2** | — | `rerun` | Re-vote after revising; reserve for material changes | Run the consensus again (e.g., after revising the topic) |
> | **3** | 1 | `spec` | Convert consensus into actionable spec; common path | Create a spec from this consensus (if topic warrants it) |
> | **4** | — | `stop` | Downgraded if today's session log has unsynthesized entries | Done — use the consensus output as-is |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

**Session-data safety rule (Spec 320 Req 4)**: Before emitting the choice block, evaluate today's session log per the positive "populated Summary" definition. If the rule fires (unsynthesized spec activity AND Summary unpopulated): **insert `session` at rank 1**, downgrade `stop` to `—`, renumber rows.
