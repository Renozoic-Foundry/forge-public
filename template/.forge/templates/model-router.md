# Model Router (Spec 085)

The model router dynamically selects the optimal model tier per command invocation. It is **opt-in** — when `mode: static` (default) in AGENTS.md `forge.model_router`, use the static tier table in CLAUDE.md and skip everything in this file.

When `mode: dynamic`:

## Complexity classification

Before selecting a model tier, classify the command's complexity as a score from 0.0 (trivial) to 1.0 (frontier-hard). Use these fast heuristic signals:

| Signal | Low (0.0–0.3) | Medium (0.4–0.6) | High (0.7–1.0) |
|--------|---------------|-------------------|-----------------|
| Spec file size | < 50 lines | 50–150 lines | > 150 lines |
| Requirement count | 1–3 ACs | 4–7 ACs | 8+ ACs |
| Files in scope | 1–2 files | 3–5 files | 6+ files |
| Security/compliance keywords | None | Mentioned | Central to scope |
| Conversation length | < 10 turns | 10–30 turns | 30+ turns |

Compute the score as the average of the individual signal scores. If a signal is unavailable, omit it from the average.

## Routing rules

Starting from the static tier baseline, apply these overrides:

- **Upgrade to sonnet**: haiku-tier command with complexity > 0.7 (e.g., complex `/brainstorm`)
- **Upgrade to opus**: sonnet-tier command with complexity > 0.8 (e.g., complex multi-file `/implement`)
- **Upgrade to sonnet**: `/now` when `specs_in_progress > 3`
- **No downgrade below sonnet** for code-modifying commands (`/implement`, `/close`, `/spec`, `/forge`, `/spec-gate`, `/parallel`, `/retro`) — this is the **safety floor**

If `tier_override` is set in AGENTS.md config, use that tier for all commands regardless of complexity.

## Escalation protocol

When a command produces poor results at the current tier (truncated output, agent requests more context, tests fail, user says "try again"):

1. Escalate to the next tier up (haiku -> sonnet -> opus)
2. Log the escalation as a "regret" event in `.forge/metrics/command-costs.yaml`
3. Maximum one escalation per command invocation (configurable via `max_escalations`)

## Cost tracking

After each FORGE command invocation, append an entry to `.forge/metrics/command-costs.yaml`:

```yaml
- timestamp: 2026-03-17T14:30:00Z
  command: /implement
  spec: "079"
  tier_baseline: sonnet
  tier_actual: sonnet
  complexity_score: 0.6
  input_tokens: 12500
  output_tokens: 8300
  estimated_cost_usd: 0.18
  outcome: success
  escalated: false
```

Token counts and cost are estimates based on conversation context. If exact counts are unavailable, omit those fields but always log the command, tier, and outcome.
