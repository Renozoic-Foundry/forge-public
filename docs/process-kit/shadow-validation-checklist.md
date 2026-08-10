# Shadow Validation Checklist

Step-by-step checklist for executing shadow validation during spec close. Use alongside the [shadow-validation-guide.md](shadow-validation-guide.md) for strategy selection.

**Lane distinction**: Lane A specs use shadow validation as advisory (non-blocking). Lane B specs with a declared strategy MUST complete this checklist — shadow validation is a blocking gate for Lane B.

---

## Pre-Validation Setup

- [ ] Spec has a `## Shadow Validation` section with an uncommented `**Strategy**:` line
- [ ] Strategy is one of: `reference-comparison`, `dual-run`, `test-oracle-replay`
- [ ] Reference implementation or baseline is identified and accessible
- [ ] Test inputs are prepared and documented
- [ ] Expected outputs or acceptance thresholds are defined
- [ ] **Lane B only**: Tolerance threshold is declared (default: 100% match for safety-critical)
- [ ] **Lane B only**: Reviewer is identified for sign-off

---

## Strategy 1: Reference Comparison

Use when: deterministic code — parsers, transformers, formatters, build scripts.

### Execution Steps

- [ ] Capture old implementation output: `old_output = old_impl(inputs)`
- [ ] Capture new implementation output: `new_output = new_impl(inputs)`
- [ ] Run diff: `diff old_output new_output`
- [ ] Document any differences found
- [ ] For each difference: classify as expected (document reason) or unexpected (investigate)

### Evidence Capture

```markdown
**Strategy**: reference-comparison
**Reference**: <old implementation identifier, e.g., commit hash, branch, version>
**Inputs**: <description of test inputs used>
**Expected**: <what matching outputs look like, e.g., "identical output for all N test cases">
**Actual**: <actual results, e.g., "N/N match — no differences">
**Divergence analysis**: <if any differences, explain each one>
**Pass/Fail**: PASS | FAIL
**Evidence artifacts**: <path to diff output, e.g., tmp/evidence/SPEC-NNN-shadow/diff.txt>
```

- [ ] **Lane B only**: Reviewer sign-off: `Reviewed-by: <name>, <date>`

---

## Strategy 2: Dual-Run / Shadow Mode

Use when: services, APIs, data pipelines — real-world input variety matters.

### Execution Steps

- [ ] Deploy new implementation alongside old (read-only for new)
- [ ] Route live traffic to both implementations
- [ ] Capture outputs from both over the agreed observation period
- [ ] Run automated comparison on captured outputs
- [ ] Calculate divergence rate

### Evidence Capture

```markdown
**Strategy**: dual-run
**Reference**: <production service identifier, version>
**Inputs**: <traffic description, e.g., "production traffic over 24h, N requests">
**Expected**: <divergence threshold, e.g., "<0.1% divergence rate">
**Actual**: <actual divergence rate, e.g., "0.00% divergence over N requests">
**Divergence analysis**: <if any divergences, categorize and explain>
**Pass/Fail**: PASS | FAIL
**Evidence artifacts**: <path to comparison summary>
```

- [ ] **Lane B only**: Reviewer sign-off: `Reviewed-by: <name>, <date>`

---

## Strategy 3: Test Oracle Replay

Use when: batch processing, offline systems, or when dual-run is impractical.

### Execution Steps

- [ ] Record production inputs (sanitize if needed)
- [ ] Record expected outputs from current implementation
- [ ] Replay recorded inputs through new implementation
- [ ] Diff new outputs against recorded expected outputs
- [ ] Document any divergences

### Evidence Capture

```markdown
**Strategy**: test-oracle-replay
**Reference**: <recorded baseline identifier, e.g., "production outputs recorded YYYY-MM-DD">
**Inputs**: <description of recorded inputs>
**Expected**: <what matching looks like, e.g., "outputs match for all N records">
**Actual**: <actual results>
**Divergence analysis**: <if any differences, explain each one>
**Pass/Fail**: PASS | FAIL
**Evidence artifacts**: <path to replay results>
```

- [ ] **Lane B only**: Reviewer sign-off: `Reviewed-by: <name>, <date>`

---

## Lane B Requirements

Lane B (safety-critical) projects enforce shadow validation as a **blocking gate** at `/close`. The following additional requirements apply:

### Tolerance Thresholds

| Context | Default threshold | Override |
|---------|------------------|----------|
| Safety-critical logic | 100% match (zero divergence) | Requires documented justification and reviewer approval |
| Non-safety peripherals | Configurable via `docs/compliance/profile.yaml` | Set `shadow_validation.tolerance` field |
| Performance metrics | Within documented bounds | Bounds must be declared in spec |

### Evidence Retention

- Shadow validation artifacts (diffs, comparison logs, replay results) MUST be preserved as files, not just summarized in the spec
- Recommended path: `tmp/evidence/SPEC-NNN-shadow/`
- Artifacts must remain available through the spec's audit lifecycle
- Do not delete shadow validation evidence when closing the spec

### Reviewer Sign-Off

Lane B specs require explicit reviewer sign-off on shadow validation evidence:

```markdown
**Reviewer sign-off**: <reviewer name> confirmed shadow validation evidence on <date>.
  Tolerance threshold met: yes/no
  Artifacts reviewed: <list of files reviewed>
```

This sign-off is checked by `/close` as part of the blocking gate. Missing sign-off causes a FAIL.

---

## Post-Validation

- [ ] Evidence fields in spec's `## Shadow Validation` section are filled (not "pending")
- [ ] Evidence artifacts are saved to `tmp/evidence/SPEC-NNN-shadow/` or equivalent
- [ ] **Lane B only**: Reviewer sign-off is recorded in the spec's Shadow Validation section
- [ ] **Lane B only**: Tolerance threshold compliance is documented
- [ ] Ready for `/close`
