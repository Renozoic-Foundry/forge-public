# Shadow Validation Checklist

Step-by-step checklist for executing shadow validation during spec close. Use alongside the [shadow-validation-guide.md](shadow-validation-guide.md) for strategy selection.

Shadow validation is advisory (non-blocking). Specs with a declared strategy should complete this checklist for confidence, but it does not block closing.

---

## Pre-Validation Setup

- [ ] Spec has a `## Shadow Validation` section with an uncommented `**Strategy**:` line
- [ ] Strategy is one of: `reference-comparison`, `dual-run`, `test-oracle-replay`
- [ ] Reference implementation or baseline is identified and accessible
- [ ] Test inputs are prepared and documented
- [ ] Expected outputs or acceptance thresholds are defined
- [ ] Tolerance threshold is declared if applicable
- [ ] Reviewer is identified for sign-off (recommended)

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

- [ ] Reviewer sign-off (recommended): `Reviewed-by: <name>, <date>`

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

- [ ] Reviewer sign-off (recommended): `Reviewed-by: <name>, <date>`

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

- [ ] Reviewer sign-off (recommended): `Reviewed-by: <name>, <date>`

---

## Post-Validation

- [ ] Evidence fields in spec's `## Shadow Validation` section are filled (not "pending")
- [ ] Evidence artifacts are saved to `tmp/evidence/SPEC-NNN-shadow/` or equivalent
- [ ] Reviewer sign-off recorded (recommended)
- [ ] Ready for `/close`
