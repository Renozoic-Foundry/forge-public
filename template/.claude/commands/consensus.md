---
name: consensus
description: "Run a proposal through all registry roles for structured consensus"
model_tier: sonnet
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

## [mechanical] Step 3 — Gather role assessments

For each role in the registry:

1. **Spawn an isolated read-only sub-agent** with:
   - The role's instruction preamble (from `.claude/agents/`)
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

2. Parse each role's JSON response.

3. If a sub-agent fails or produces invalid output, record: `{ "role": "<name>", "vote": "error", "rationale": "Role assessment failed — <reason>", "key_risk": "unknown" }`

Run all role assessments in **parallel** where possible.

## [mechanical] Step 4 — Compute vote tally and divergence

1. **Vote tally**: Count approve, concern, reject, and error votes.

2. **Divergence signal**: Flag significant disagreement:
   - **Aligned**: All votes are the same category (all approve, all concern, all reject)
   - **Mild divergence**: Mix of approve and concern (no rejects)
   - **Strong divergence**: At least 1 reject alongside 2+ approves — roles fundamentally disagree
   - **Blocked**: Majority reject

3. **Recommended action** based on tally:
   - All approve → "Proceed"
   - Majority approve, some concern → "Proceed with noted concerns"
   - Strong divergence → "Discuss — roles fundamentally disagree"
   - Majority concern → "Revise — address concerns before proceeding"
   - Majority reject → "Do not proceed — significant opposition"

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

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `detail <role>` | Show the full assessment from a specific role |
> | **2** | `rerun` | Run the consensus again (e.g., after revising the topic) |
> | **3** | `spec` | Create a spec from this consensus (if topic warrants it) |
> | **4** | `stop` | Done — use the consensus output as-is |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_
