# Gate Categories — FORGE Human Gate Redesign (Spec 160)

Every FORGE gate check is categorized along two axes: **what** gets checked (this document) and **how** approval happens (enforcement mode — see AGENTS.md). The **who** axis is governed by L0-L4 autonomy levels.

## Machine-Verifiable

AI verifies these autonomously. No human attention required. These checks have deterministic pass/fail outcomes.

| Check | Description | Used in |
|-------|-------------|---------|
| File presence/absence | Expected files exist at expected paths | /close, /implement |
| Pattern matching | Output contains/excludes expected strings | /close, /implement |
| Cross-reference consistency | Spec, README, backlog, CHANGELOG status agreement | /close (Step 3) |
| Arithmetic validation | Score formula correctness, BV/E/R/SR ranges 1-5 | /spec, /matrix |
| Diff verification | Change matches intended scope, no unintended modifications | /close (validator) |
| Regression detection | Tests that previously passed still pass | /implement, /close |
| Completeness checks | Required spec sections populated, all ACs addressed in evidence | /implement (Step 2) |
| Code quality mechanics | Lint, type check, import verification | /implement (Step 7) |
| Template render verification | Copier copy succeeds, no Jinja artifacts in output | /close, /implement |
| Spec integrity hash | SHA-256 of Scope + ACs matches Approved-SHA | /close (Step 2) |

## Human-Judgment-Required

AI prepares evidence and presents it; human makes the final call. These checks involve subjective assessment, real-world knowledge, or irreversible consequences.

| Check | Description | Used in |
|-------|-------------|---------|
| UX/aesthetic judgment | Does this look/feel/sound right? Commands, onboarding flows, visual output | /close, /handoff |
| Strategic alignment | Is this what we actually want, not just what was specified? | /close (Step 5) |
| Novel situation assessment | First time doing something — has the AI misunderstood the problem? | /implement (DA gate) |
| Tone and voice | User-facing copy, error messages, documentation narrative, naming | /close, /handoff |
| Ethical/legal judgment | Should we do this? Liability, compliance implications, privacy | /close |
| External-facing content | README updates, articles, PR descriptions, publications | /close, /handoff |
| Physical/practical logic | Do real-world recommendations make physical sense? (see below) | /close, /handoff |
| Domain expertise gaps | AI flags uncertainty in regulatory, industry-specific, or hardware domains | /close, /implement |
| Irreversible external actions | git push, publish, send communications, delete production data | /close (Step 4) |

### Physical/Practical Logic Gate

When a spec's scope involves physical-world recommendations, real-world actions, hardware interactions, or cause-and-effect chains in the physical world, the Review Brief includes a dedicated **Physical Logic Check**:

- States the real-world action or recommendation
- States the physical prerequisites the AI identified
- Explicitly asks: "Does this make physical/practical sense? AI reasoning about physical constraints can miss obvious prerequisites that any human would catch."

This check is **always human-judgment-required** — it cannot be delegated regardless of autonomy level. AI does not reliably know when it is wrong about physical logic.

## Confidence-Gated

AI verifies these, but escalates to human review when confidence is low. These are checks where AI is usually right but can have blind spots.

| Check | Description | Confidence Thresholds | Used in |
|-------|-------------|----------------------|---------|
| Test coverage assessment | Are edge cases covered? | HIGH: all branches tested; MEDIUM: core paths tested; LOW: gaps identified | /close (validator) |
| Security review | Implementation-level security (not architecture) | HIGH: no patterns flagged; MEDIUM: common patterns OK; LOW: novel attack surface | /close (validator) |
| Dependency impact | Does this change affect downstream specs or consumer projects? | HIGH: isolated change; MEDIUM: shared file touched; LOW: cross-cutting change | /close (Step 5) |
| Performance implications | Will this change affect token cost or execution time? | HIGH: no perf-sensitive code; MEDIUM: minor changes; LOW: hot path modified | /close |

### Confidence Levels

| Level | Meaning | Review Brief Placement | Delegation Impact |
|-------|---------|----------------------|-------------------|
| **HIGH** | Deterministic check passed (test ran green, lint clean) | Machine-Verified (no qualifier) | Eligible for delegation |
| **MEDIUM** | Heuristic check — likely correct but edge cases possible | Machine-Verified with note: "(medium confidence — override if concerned)" | Eligible for delegation |
| **LOW** | Uncertain — multiple interpretations, incomplete info, first-time pattern | Escalated to "Needs Your Review" with AI reasoning | **Disqualifies** spec from Delegated mode |

## Enforcement Modes (the "how")

Three enforcement modes determine how approval happens. Selection depends on autonomy level and spec characteristics.

| Mode | When Used | Approval Mechanism | Audit Trail |
|------|-----------|-------------------|-------------|
| **Delegated** | L3/L4 autonomy AND all ACs machine-verifiable AND no human-judgment checks apply | None — agent validates and closes autonomously | Immutable evidence: spec evidence + SHA-256 hash in audit-log.jsonl + atomic git commit |
| **Chat** | Default. Human judgment needed but no regulatory burden of proof. | Human reviews Review Brief, approves in conversation. | Session log + spec evidence section. |
| **PAL** | High-trust workflows requiring hardware-authenticated approval. *(Coming soon — see roadmap)* | Review Brief via NanoClaw, hardware key tap, cryptographic signature. | Cryptographic proof of identity + timestamp. Non-repudiable. |

### Enforcement Mode Selection Matrix

| Autonomy Level | Delegation-eligible specs | Judgment-required specs |
|----------------|--------------------------|------------------------|
| L0-L1 | Chat (human gates everything) | Chat |
| L2 | Chat (human approves decisions) | Chat |
| L3 | **Delegated** | Chat (async review) |
| L4 | **Delegated** | Delegated with exception reporting | PAL |

### Delegation Eligibility

A spec is delegation-eligible when ALL of the following are true:
1. Project autonomy level is L3 or L4
2. Every acceptance criterion is machine-verifiable (tests pass/fail, file exists/doesn't, pattern matches/doesn't)
3. No human-judgment-required checks apply (no UX changes, external content, physical logic, irreversible actions, novel situations)
4. No confidence-gated check scored LOW during validation
5. Change lane is not `hotfix` at L3 (hotfixes require human review at L3; delegated at L4 only)

## Trust Calibration

Gate category assignments are not permanent. Trust calibration adjusts categories based on observed accuracy:

| Observation | Recommendation |
|-------------|----------------|
| Check type has 0 human corrections over 10+ spec closures | Confirm as machine-verifiable |
| Check type has 2+ human corrections in 5 closures | Escalate to confidence-gated or human-judgment-required |
| Confidence-gated check consistently scores HIGH with 0 corrections | Graduate to machine-verifiable |

Trust calibration changes are presented as `/evolve` recommendations — never auto-applied. Human corrections to machine-verified checks are recorded as trust signals in `docs/sessions/signals.md`.
