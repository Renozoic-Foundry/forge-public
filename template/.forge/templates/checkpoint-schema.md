# Checkpoint Schema (Spec 123)

Checkpoint files are written by `/close` and `/implement` to enable resuming after context overflow.

## File location

`.forge/checkpoint/<command>-<spec-id>.json`

Examples:
- `.forge/checkpoint/close-042.json`
- `.forge/checkpoint/implement-115.json`

## Schema

```json
{
  "spec_id": "042",
  "command": "close",
  "last_completed_step": 6,
  "step_description": "Auto-chain /retro — 5 signals captured",
  "timestamp": "2026-03-27T14:30:00Z",
  "outputs": {
    "2": "Status verified: implemented",
    "3": "Status transitioned to closed",
    "4": "Committed and pushed",
    "5": "Deferred scope: 2 items dispositioned",
    "6": "5 signals captured in signals.md"
  }
}
```

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `spec_id` | string | Spec number (e.g., "042") |
| `command` | string | `"close"` or `"implement"` |
| `last_completed_step` | number/string | Last fully completed step |
| `step_description` | string | Human-readable description of what the step did |
| `timestamp` | string | ISO 8601 timestamp of when the step completed |
| `outputs` | object | Map of step number → summary of what was produced |

## Lifecycle

1. **Created**: after the first major step completes
2. **Updated**: after each subsequent step (overwrites the file)
3. **Deleted**: on successful command completion (final step)
4. **Stale**: if the command is interrupted, the file persists for resume detection

## Gitignore

`.forge/checkpoint/` is in `.gitignore` — checkpoint files are transient and never versioned.
