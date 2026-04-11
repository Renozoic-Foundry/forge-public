# Gate Outcome Format

Emit at every evidence gate using this structured format:

```
GATE [<gate-name>]: <STATUS> — <reason>
```

Where STATUS is one of: `PASS`, `FAIL`, `CONDITIONAL_PASS`.
- `PASS`: criterion fully satisfied.
- `FAIL`: criterion not met. Include the specific criterion that failed and a remediation action.
- `CONDITIONAL_PASS`: criterion partially met with noted risk. Include what condition remains.
