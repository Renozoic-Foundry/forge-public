# Activity Log Schema — JSONL Event Format

Spec 134 — Multi-Agent Concurrent Session Model

The activity log (`docs/sessions/activity-log.jsonl`) is an append-only JSONL file that records structured events from agent and operator sessions. It serves as the single source of truth for what happened across concurrent agent executions.

## Event schema

Each line is a self-contained JSON object with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | string (ISO 8601) | yes | When the event occurred, e.g. `2026-04-06T14:30:00Z` |
| `agent_id` | string | yes | Identifier for the agent or operator, e.g. `operator`, `agent-1`, `worktree-spec-134` |
| `event_type` | enum | yes | One of: `spec-started`, `spec-closed`, `signal`, `gate-passed`, `gate-failed`, `error` |
| `spec_id` | string | no | Spec number if event relates to a spec, e.g. `134` |
| `message` | string | yes | Human-readable description of the event |
| `metadata` | object | no | Additional structured data (gate names, signal IDs, error details) |

## Event types

### `spec-started`
Appended by `/implement` when beginning implementation of a spec.

```json
{"timestamp":"2026-04-06T14:30:00Z","agent_id":"operator","event_type":"spec-started","spec_id":"134","message":"Beginning implementation of Spec 134 — Multi-Agent Concurrent Session Model","metadata":{"lane":"standard-feature","score":30}}
```

### `spec-closed`
Appended by `/close` when a spec transitions to `closed`.

```json
{"timestamp":"2026-04-06T15:45:00Z","agent_id":"operator","event_type":"spec-closed","spec_id":"134","message":"Spec 134 closed — all gates passed","metadata":{"gates_passed":5,"gates_failed":0,"signals_captured":3}}
```

### `signal`
Appended when a retro signal is captured during `/close` or `/retro`.

```json
{"timestamp":"2026-04-06T15:46:00Z","agent_id":"operator","event_type":"signal","spec_id":"134","message":"SIG-134-P1: Activity log append-only pattern validated","metadata":{"signal_type":"process","signal_id":"SIG-134-P1"}}
```

### `gate-passed` / `gate-failed`
Appended when an evidence gate is evaluated.

```json
{"timestamp":"2026-04-06T15:44:00Z","agent_id":"operator","event_type":"gate-passed","spec_id":"134","message":"GATE [test-execution]: PASS","metadata":{"gate_name":"test-execution"}}
```

### `error`
Appended when an error autopsy is recorded.

```json
{"timestamp":"2026-04-06T15:50:00Z","agent_id":"operator","event_type":"error","spec_id":"134","message":"EA-032: Missing .copier-answers.yml","metadata":{"error_id":"EA-032","severity":"high"}}
```

## Concurrency safety

- **Append-only**: Agents only append lines. No read-modify-write, no truncation.
- **POSIX**: Appending short lines (< 4KB) to a file is atomic on POSIX systems.
- **Windows**: Short appends are generally safe, but not guaranteed atomic. For maximum safety, agents should write the full JSON line in a single write operation.
- **Validation**: Each line must be independently parseable as JSON. Use `jq -c '.' < activity-log.jsonl` to validate.

## Atomic spec checkout (Requirement 11)

Before starting implementation of a spec, an agent MUST check the activity log for an existing `spec-started` event for that spec ID with no corresponding `spec-closed` event. If found, the agent MUST abort:

```
Spec NNN is already claimed by agent <agent_id>.
```

This prevents two agents from implementing the same spec simultaneously.

## Agent vs operator tiers

| Tier | Can write to activity log | Can write to session logs / backlog / README | Reads activity log |
|------|--------------------------|---------------------------------------------|--------------------|
| **Agent** (parallel execution) | Yes (append-only) | No — operator synthesizes | No (write-only) |
| **Operator** (interactive) | Yes | Yes (full access) | Yes (via /now, /session) |

Agent tier restrictions are behavioral rules documented in AGENTS.md. Hook enforcement is available via Spec 100.
