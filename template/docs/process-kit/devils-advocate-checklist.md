# Devil's Advocate Gate Checklist

Last updated: 2026-03-13

This checklist is used by the Devil's Advocate role (or the agent in DA mode) to stress-test a spec before implementation begins. Every spec at L2+ autonomy must pass this gate. At L0–L1 it is recommended but optional.

**Instructions:** Review the spec and check each item. Any "No" or "Unclear" answer must be resolved before the spec advances to implementation. Record findings in the spec's Revision Log.

---

## 1. Logic and Completeness

- [ ] **Objective clarity**: Can you state the spec's goal in one sentence without ambiguity?
- [ ] **Scope boundaries**: Are in-scope and out-of-scope items explicitly listed?
- [ ] **Acceptance criteria testability**: Can each AC be verified with a concrete test or observation?
- [ ] **Missing ACs**: Are there obvious behaviors or edge cases the ACs do not cover?
- [ ] **Contradictions**: Do any ACs contradict each other or conflict with existing specs?
- [ ] **Assumptions**: Are all assumptions stated? Are any unstated assumptions risky?

**Challenge prompt:** "What is the simplest scenario that would satisfy all ACs but still produce a wrong or incomplete result?"

---

## 2. Security and Secrets

- [ ] **Credential exposure**: Could the implementation introduce secrets, API keys, or tokens into version control?
- [ ] **Input validation**: Does the spec account for untrusted or malformed input?
- [ ] **Permission boundaries**: Does the implementation stay within the agent's granted autonomy?
- [ ] **Data exposure**: Could the change leak sensitive data in logs, outputs, or error messages?
- [ ] **Dependency risk**: Do any new dependencies have known vulnerabilities or excessive permissions?

**Challenge prompt:** "If a hostile actor controlled the input to this feature, what could they achieve?"

---

## 3. Scope and Blast Radius

- [ ] **File scope**: Are all files to be modified explicitly listed in the spec?
- [ ] **Unintended side effects**: Could changes to shared modules, utilities, or configs affect unrelated features?
- [ ] **Rollback feasibility**: Can this change be fully reverted with a single `git revert`?
- [ ] **Breaking changes**: Does the change alter any public API, schema, CLI interface, or output format?
- [ ] **Cross-spec interference**: Could this spec's changes conflict with any in-progress or planned specs?

**Challenge prompt:** "What is the worst thing that happens if this change has a bug and goes unnoticed for a week?"

---

## 4. Financial and Resource Exposure

- [ ] **Budget alignment**: Is the estimated effort (tokens, cost, time) within the lane's budget ceiling?
- [ ] **External API costs**: Does the implementation call paid APIs? Are costs bounded?
- [ ] **Runaway risk**: Could a loop, retry, or recursive call cause unbounded resource consumption?
- [ ] **Storage growth**: Does the change create files or data that grow without bound?

**Challenge prompt:** "If the agent ran this implementation 100 times by mistake, what would the cost be?"

---

## 5. Test Coverage

- [ ] **Happy path covered**: Does the test plan cover the primary success scenario?
- [ ] **Edge cases covered**: Are boundary conditions, empty inputs, and error paths tested?
- [ ] **Regression risk**: Are existing tests still valid after this change?
- [ ] **Manual validation needed**: Are there aspects that cannot be automatically tested? If so, are they in the human validation runbook?
- [ ] **Test isolation**: Do tests depend on external state (network, filesystem, time) that could cause flakiness?

**Challenge prompt:** "What test would catch a subtle regression introduced by this change?"

---

## 6. Blast Radius Assessment

Rate the overall blast radius and record it in the spec:

| Rating | Criteria | Action |
|--------|----------|--------|
| **Low** | Changes isolated to one module/file, no shared dependencies, full test coverage | Proceed normally |
| **Medium** | Changes touch shared code or config, partial test coverage, affects 2–3 features | Add targeted tests for adjacent features; human spot-check recommended |
| **High** | Changes to core interfaces, schemas, or infrastructure; broad downstream impact | Mandatory human review before implementation; consider splitting spec |

**Blast radius for this spec:** [ Low / Medium / High ] (circle one)

---

## Outcome

- [ ] **PASS** — All items checked, no unresolved concerns. Spec may proceed to implementation.
- [ ] **CONDITIONAL PASS** — Minor concerns noted below; may proceed if addressed during implementation.
- [ ] **FAIL** — Blocking concerns identified. Spec must be revised before implementation.

**Concerns and recommendations:**

> (Record any findings, suggested revisions, or risk mitigations here.)

**Reviewed by:** (agent role or human name)
**Date:** YYYY-MM-DD
