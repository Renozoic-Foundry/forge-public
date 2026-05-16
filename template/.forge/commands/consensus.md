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

**Single source of truth (Spec 423)**: this step declares `planned_agents` as an explicit list BEFORE any dispatch, and the dispatch narration is **generated from `planned_agents`** — not authored freehand. The same list drives both narration and the Task tool-call loop, so the count and names cannot diverge. This collapses the narration-vs-dispatch defect class that caused /consensus 399 round 3 to silently omit COO.

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
