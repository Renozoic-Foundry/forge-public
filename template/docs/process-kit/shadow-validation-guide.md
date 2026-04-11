# Shadow Validation Guide

When to run a shadow comparison before closing a spec, and which strategy to use.

## When to Shadow Validate

**Use shadow validation when** the spec **replaces** existing behavior:
- Rewriting a module, function, or algorithm
- Migrating from one library/framework to another
- Refactoring that changes internal structure but should preserve external behavior
- Changing a data pipeline's processing logic

**Skip shadow validation when** the spec is **purely additive**:
- New command, feature, or file
- Documentation or process-only changes
- Configuration additions
- Bug fixes where the old behavior was wrong (no valid reference)

**Rule of thumb**: If you can describe the change as "X should work the same as before, but now Y," shadow validation applies. If you can describe it as "X is new," it doesn't.

## Strategies

### Reference Comparison

Run the new and old implementation on the same inputs. Diff the outputs.

**Best for**: deterministic code — parsers, transformers, formatters, build scripts.

```
Inputs:  same test data or production sample
Run:     old_output = old_impl(inputs), new_output = new_impl(inputs)
Compare: diff old_output new_output
Pass:    outputs are identical (or differences are expected and documented)
```

**Evidence**: include the diff output (or "no differences") in the spec's Evidence section.

### Dual-Run / Shadow Mode

Deploy the new implementation alongside the old one. Both process real inputs; only the old one's output is used. Compare results over time.

**Best for**: services, APIs, data pipelines — anything where real-world input variety matters.

```
Inputs:  live production traffic (read-only for new impl)
Run:     route requests to both old and new, capture both outputs
Compare: automated comparison over N requests/hours/days
Pass:    divergence rate below threshold (e.g., <0.1%)
```

**Evidence**: include the comparison summary (request count, match rate, divergence examples).

### Test Oracle Replay

Record production inputs and outputs. Replay the inputs through the new implementation. Compare against the recorded outputs.

**Best for**: batch processing, offline systems, or when dual-run is impractical.

```
Inputs:  recorded production inputs (sanitized if needed)
Run:     new_output = new_impl(recorded_inputs)
Compare: diff new_output recorded_outputs
Pass:    outputs match (or differences are expected and documented)
```

**Evidence**: include the replay results and any divergence analysis.

## Recording Evidence

In the spec file's `## Shadow Validation` section:

```markdown
**Strategy**: reference-comparison
**Reference**: previous implementation in commit abc1234
**Inputs**: test suite fixtures (tests/fixtures/*)
**Expected**: identical output for all 47 test cases
**Evidence**: 47/47 match — no differences. Diff log: tmp/evidence/SPEC-NNN-shadow/diff.txt
```

`/close` checks for this evidence and emits a non-blocking warning (CONDITIONAL_PASS) if the strategy is declared but evidence is missing. Shadow validation is advisory — it does not block closing.
