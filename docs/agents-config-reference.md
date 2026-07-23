<!-- GENERATED FILE — do not hand-edit. Regenerate with: .forge/bin/forge-py scripts/gen-agents-config-reference.py
     Sources: AGENTS.md (live defaults) + scripts/lib/agents-config-reference-content.yaml (descriptions)
     Source content hash: 70fe220f00e9 | FORGE plugin version: 3.3.0
     Drift gate: .forge/bin/forge-parity.sh --check (Surface 7, Spec 571) -->

# AGENTS.md configuration reference

This reference documents every configurable field in your project's AGENTS.md file.

## Overview

AGENTS.md is the AAIF-compliant (Agentic AI Foundation, Linux Foundation, 2025) agent configuration file and the primary surface for controlling AI behavior in a FORGE project. It defines the agent's identity, autonomy level, role dispatch rules, gate enforcement, budget ceilings, and runtime adapter. FORGE bootstraps this file during `copier copy`; operators customize it for their project afterward.

The file is structured as prose sections interspersed with YAML configuration blocks. The YAML blocks under **Runtime Configuration** are parsed by `.forge/lib/config.sh` at runtime.

## Configuration fields

### Top-level context fields

These fields appear in YAML code blocks within the **Project Context** section of AGENTS.md.

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `forge.strategic_scope` | YAML block (multiline string) | YAML block — see AGENTS.md | Defines what the project IS and IS NOT; consumed by `/matrix` when evaluating spec fit. | When present, `/matrix` classifies draft specs as on-mission, borderline, or scope-creep against this definition. When absent, `/matrix` infers scope from the CLAUDE.md project description. |
| `forge.context.session_briefing` | boolean | `true` | Controls whether `/now` includes the "Last time on [project]" continuity brief. | When `true`, `/now` reads recent session logs, signals, and scratchpad to provide a session-start brief. When `false`, the brief is skipped. |
| `forge.context.optimization.level` | enum | `minimal` | Context-compaction aggressiveness. Valid values: `minimal`, `balanced`, `aggressive` (Spec 256). | Compaction fires only after `/close`, never mid-command. `minimal` compacts least; `balanced` uses the threshold below; `aggressive` compacts most. |
| `forge.context.optimization.compact_threshold_pct` | integer (percent) | `60` | Context-window percentage that triggers compaction (`balanced` level only). | When the context window exceeds this percentage after a `/close`, compaction runs. |
| `forge.output.verbosity` | enum | `lean` | Chat output density. Valid values: `lean` (default), `verbose` (Spec 225). | `lean` suppresses non-actionable diagnostics and routes detail to file artifacts with a one-line pointer; choice blocks, FAILed gates, and operator prompts are never suppressed. |
| `forge.process_kit.freshness_threshold_days` | integer (days) | `180` | Staleness threshold for process-kit guide `Last verified:` markers (Spec 278). | `/now` flags guides whose marker is older than this many days. |

### Runtime configuration (`forge:` block)

These fields appear in the `forge:` YAML block under the **Runtime Configuration** section. They are parsed by `.forge/lib/config.sh`.

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `forge.methodology` | enum | `none` | Team methodology label. Valid values: `scrum`, `safe`, `kanban`, `devops`, `safety-critical`, `none`. | Adapts command output language to match the team's methodology. Set during `/onboarding`. Language only; no behavioral change. |
| `forge.lane` | enum | `A` | Active development lane. Currently only `A` is available. | Determines which feature set is active. |
| `forge.gate.provider` | enum | `prompt` | Gate approval mechanism. Valid values: `prompt`, `pal`, `auto`. | `prompt`: chat-based approval. `pal`: hardware-authenticated (YubiKey). `auto`: use PAL if installed, fall back to prompt. |
| `forge.gate.timeout` | integer (seconds) | `1800` | Maximum wait time for a gate approval before timing out. | After this duration, a pending gate approval times out and follows the configured fallback behavior. |
| `forge.roles.separation` | enum | `none` | Role isolation level. Valid values: `none`, `context-scoped`, `full`. | `none` (default): all roles run in the main conversation. `context-scoped`: DA and validator as isolated subagents, implementer in main context. `full`: all roles as isolated subagents (implementer uses worktree). |
| `forge.roles.devils_advocate.enabled` | boolean | `true` | Enables or disables the Devil's Advocate gate globally. | When `false`, the DA review step is skipped across all specs and lanes. |
| `forge.roles.devils_advocate.skip_lanes` | list of strings | `[hotfix]` | Lanes that bypass DA review. | Specs in listed lanes skip the DA gate even when DA is enabled. |
| `forge.roles.devils_advocate.expiry_days` | integer | `7` | Days after which a spec modification triggers DA re-review. | If a spec is modified more than this many days after its last DA review, a new review is required. |
| `forge.roles.devils_advocate.model` | enum | `sonnet` | Model tier for the DA subagent (when separation is not `none`). | Controls cost and capability of the DA review agent. |
| `forge.roles.validator.enabled` | boolean | `true` | Enables or disables the validator gate globally. | When `false`, the independent validation step is skipped. |
| `forge.roles.validator.skip_lanes` | list of strings | `[]` | Lanes that bypass validator review. | Specs in listed lanes skip the validator gate. |
| `forge.roles.validator.model` | enum | `sonnet` | Model tier for the validator subagent. | Controls cost and capability of the validator agent. |
| `forge.roles.implementer.use_worktree` | enum | `auto` | Worktree isolation for implementer agents. Valid values: `auto`, `always`, `never`. | `auto`: uses worktree when running parallel specs. `always`: every implementation runs in a worktree. `never`: all work in the main tree. |
| `forge.roles.implementer.max_parallel` | integer | `3` | Maximum concurrent implementer agents. | Caps the number of parallel `/implement` sessions to prevent resource exhaustion. |
| `forge.roles.implementer.max_retries` | integer | `2` | Retry count on test failure before escalating to the operator. | After this many failed attempts, the implementer stops and reports the failure. |
| `forge.review.enabled` | boolean | `false` | Enables the optional two-stage subagent review. | When `true`, implementation tasks and `/close` validation run spec-compliance and code-quality review stages. Off by default for backward compatibility. |
| `forge.review.stages` | list of strings | `[spec_compliance, code_quality]` | Which review stages to run. | Controls the review pipeline composition. |
| `forge.review.severity_threshold` | enum | `major` | Minimum finding severity that blocks progress. Valid values: `critical`, `major`, `minor`. | Findings below this severity are logged but do not block the implementation. |
| `forge.review.max_retries` | integer | `2` | Fix attempts before escalating to the operator. | After this many failed fix attempts on review findings, the agent stops and escalates. |
| `forge.review.skip_lanes` | list of strings | `[]` | Lanes that skip the two-stage review. | Specs in listed lanes bypass the review entirely. |
| `forge.review.review_model` | enum | `sonnet` | Model tier for review agents. | Controls cost and capability of review subagents. |
| `forge.review.per_task_review` | boolean | `true` | Run review after each implementer task vs. only at `/close`. | `true`: review fires after each task during `/implement`. `false`: review runs only during `/close`. |
| `forge.review.budget` | string or null | `null` | Optional review time budget (e.g., `"5 minutes"`). | When set, `/close` defers lower-priority Review Brief items. `null` means full review. |
| `forge.review_velocity.threshold` | float | `0.6` | Ratio of closed-without-human-evidence to total-closed that triggers a warning. | When the ratio exceeds this value over the review window, `/evolve` surfaces a trust-calibration warning. |
| `forge.review_velocity.window` | integer | `5` | Number of recent sessions to check for closed specs. | Defines the lookback period for review velocity calculation. |
| `forge.triggers.enabled` | boolean | `true` | Enables the context-aware trigger system. | When `false`, no automatic trigger suggestions fire. |
| `forge.triggers.mode` | enum | `suggest` | Trigger behavior. Valid values: `suggest`, `auto`, `off`. | `suggest`: triggers recommend actions. `auto`: triggers execute automatically. `off`: triggers disabled. |
| `forge.triggers.suppress_duplicates` | boolean | `true` | Prevents repeating the same trigger suggestion in a conversation. | Avoids noise from redundant suggestions within a single session. |
| `forge.triggers.check_on_start` | boolean | `true` | Check triggers at conversation start. | When `true`, triggers are evaluated at the beginning of each session. |
| `forge.triggers.trigger_map` | string (path) | `.forge/templates/context-trigger-map.yaml` | Path to the trigger condition map file. | Points to the YAML file defining which conditions activate which triggers. |
| `forge.dispatch_rules.enabled` | boolean | `false` | Enables intelligent role dispatch based on spec characteristics. | When `true`, CxO advisory roles are auto-invoked when spec characteristics match dispatch conditions. |
| `forge.dispatch_rules.skip_threshold.effort` | integer | `1` | Effort score at or below which extra dispatch is skipped. | Low-effort specs matching all threshold conditions use DA only. |
| `forge.dispatch_rules.skip_threshold.risk` | integer | `1` | Risk score at or below which extra dispatch is skipped. | Low-risk specs matching all threshold conditions use DA only. |
| `forge.dispatch_rules.roles` | YAML block | YAML block — see AGENTS.md | Maps CxO roles to trigger conditions. | Defines which conditions (e.g., `cross_cutting`, `security`, `high_risk`) invoke which advisory roles. |
| `forge.dispatch_rules.evolve_loop` | YAML block | YAML block — see AGENTS.md | Roles invoked during `/evolve --full`. | Controls which CxO roles participate in Evolve Loop steps (signal analysis, trust calibration, etc.). |
| `forge.dispatch_rules.touchpoints` | list of strings | `[spec_review, da_gate, close_review, evolve_loop]` | Lifecycle points where dispatch fires. | Determines when in the spec lifecycle advisory roles are consulted. |
| `forge.agents.model_tier_override` | enum or null | `null` | Single-knob global model-tier override for subagent frontmatter. Valid values: `null`, `haiku`, `sonnet`, `opus`, `inherit` (Spec 462). | Operator policy, not enforcement — see the agent-roles guide. `null` keeps each agent file’s own tier. |

### Runtime and agent adapters

These fields appear in the `runtime:`, `agent:`, and `isolation:` YAML blocks.

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `runtime.adapter` | enum | `native` | Runtime isolation mode. Valid values: `native`, `oci`. | `native`: git worktree isolation, no container required. `oci`: OCI container isolation (requires an OCI-compatible runtime such as Rancher Desktop, Podman, or Docker Engine). |
| `agent.adapter` | enum | `generic` | Agent integration mode. Valid values: `generic`, `claude-code`. | `generic`: works with any CLI-invokable AI agent via AGENTS.md injection. `claude-code`: optimized for Claude Code CLI with system prompts and tool scoping. |
| `agent.command` | string | `claude` | CLI command for the AI agent. | The shell command used to invoke the agent in scripts and CI pipelines. |
| `isolation.network` | enum | `none` | Network isolation level. Valid values: `none`, `host`. | Controls network access for isolated agent processes. |
| `isolation.resource_limits.memory` | string | `2g` | Memory limit for isolated agent processes. | Caps memory consumption to prevent resource exhaustion. |
| `isolation.resource_limits.cpus` | integer | `2` | CPU limit for isolated agent processes. | Caps CPU usage. |
| `isolation.resource_limits.timeout_seconds` | integer | `600` | Maximum execution time for isolated agent processes. | Kills processes that exceed this duration. |

### Multi-agent configuration

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `multi_agent.activity_log` | string (path) | `docs/sessions/activity-log.jsonl` | Path to the JSONL activity log for parallel sessions. | All parallel agents append events to this file for coordination. |
| `multi_agent.agent_tier_rules.write_activity_log` | boolean | `true` | Whether agents append to the activity log. | When `false`, parallel execution loses coordination visibility. |
| `multi_agent.agent_tier_rules.write_session_logs` | boolean | `false` | Whether parallel agents write to session logs. | Must be `false`; the operator synthesizes session logs from the activity log. |
| `multi_agent.agent_tier_rules.write_backlog` | boolean | `false` | Whether parallel agents write to backlog.md. | Must be `false` to prevent merge conflicts in the shared backlog. |
| `multi_agent.agent_tier_rules.write_specs_readme` | boolean | `false` | Whether parallel agents write to specs/README.md. | Must be `false` to prevent merge conflicts in the shared index. |
| `multi_agent.agent_tier_rules.atomic_checkout` | boolean | `true` | Check for existing spec-started before claiming. | Prevents two agents from implementing the same spec concurrently. |

### Evolve, now, routines, reconcile, and implement blocks

These blocks tune signal-driven review, the `/now` dashboard, scheduled routines, git-history reconciliation, and the live-smoke gate. They appear in the `forge:` YAML block under **Runtime Configuration**.

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `forge.now.watch_default_min_delay` | integer (seconds) | `60` | Lower bound for `/loop` dynamic re-runs of `/now --watch`. | Clamps how often a self-paced `/now` watch loop re-fires (upper bound 3600). |
| `forge.now.unclosed_spec_cap` | integer | `3` | Threshold at which `/now` warns about implemented-but-unclosed specs. | When the count exceeds this, `/now` Step 1b flags the deferred-close pile-up (count, IDs, file-overlap pairs). |
| `forge.evolve.signal_thresholds` | YAML block | YAML block — see AGENTS.md | Per-signal counts that admit an `/evolve` review. | Single source read by both `/now` (recommend) and `/evolve --auto` (admit). Keys: `unreviewed_signals` (15), `open_evolve_scratchpad` (4), `error_autopsies` (3), `deferred_scope_items` (5), `spec_velocity` (5). |
| `forge.evolve.admission_hysteresis` | boolean | `true` | Debounce on threshold crossings. | A count hovering at a boundary does not flap admit/skip. |
| `forge.evolve.time_fallback_days` | integer | `30` | Soft time-based nudge for an overdue review. | Recommendation only — never a hard admission block. |
| `forge.evolve.rewake_interval_days` | integer | `1` | `/evolve --auto` heartbeat cadence. | How often the scheduled signal-checking heartbeat re-wakes (`ScheduleWakeup` clamps the lower bound). |
| `forge.evolve.scheduled_rewake` | boolean | `true` | Whether `/evolve` schedules a signal-checking heartbeat. | When `false`, the evolve review is manual-only. |
| `forge.evolve.apply_cool_down_days` | integer | `7` | Minimum days between *applied* self-modifications (ADR-046). | Throttles auto-apply paths; the review itself has no calendar gate. |
| `forge.routines.enabled` | boolean | `false` | Enables scheduled strategy-only routines. | Off by default; opt-in. Routines produce artifacts only — they never advance the lifecycle or expand autonomy. |
| `forge.routines.cadence` | enum | `weekly` | Default routine cadence. | Per-routine overrides live in each `.forge/loops/<name>.contract.yml`. |
| `forge.routines.execution_mode` | enum | `on-box` | Where routines run. Valid values: `on-box`, `remote`. | `on-box`: stays in the org boundary. `remote`: requires InfoSec approval. |
| `forge.reconcile.stub_min_files` | integer | `3` | File-count threshold for `/reconcile` to draft a stub spec. | A git-history cluster touching at least this many distinct files routes to a draft stub spec. |
| `forge.reconcile.stub_min_lines` | integer | `100` | Line-count threshold for `/reconcile` to draft a stub spec. | A cluster changing at least this many total lines routes to a stub spec; smaller clusters become memory notes. |
| `forge.implement.live_keywords` | list of strings | `[live dry-run, smoke test, against the live repo, against FORGE-self, against the codebase, production data sample]` | Test-Plan phrases that flag a live/smoke step. | When a spec's Test Plan matches a keyword, `/implement` Step 6e prompts the operator to execute (or defer) a real run before `/close`. |
| `forge.routines.pausable` | boolean | `true` | Whether scheduled routines can be paused without losing state. | When `true`, a paused routine resumes from its saved state instead of restarting. |

## Consensus tracking

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `consensus_tracking.enabled` | boolean | `true` | Logs consensus outcomes in session JSON sidecars. | When `true`, accept/modify/reject outcomes are recorded per session. |
| `consensus_tracking.acceptance_rate.formula` | string | `accepted / (accepted + modified + rejected)` | How the acceptance rate is computed. | Surfaced in `/evolve` and `/now`; never auto-escalates autonomy. |
| `consensus_tracking.acceptance_rate.window_days` | integer | `30` | Lookback window for the acceptance rate. | Defines the rolling window over `docs/sessions/*.json`. |
| `consensus_tracking.acceptance_rate.data_source` | string (glob) | `docs/sessions/*.json` | Where consensus outcomes are read from for the acceptance-rate rollup. | The rate is computed over session JSON sidecars matching this glob. |

## Autonomy levels

FORGE defines five autonomy levels that govern how much latitude the AI agent has during a session. The default is L1. Levels can be overridden per lane or per spec by adding `Autonomy: LN` to spec frontmatter.

| Level | Name | Human role | AI behavior | Prerequisites |
|-------|------|-----------|-------------|---------------|
| L0 | Full Manual | Human performs all work | Agent advises only: answers questions, suggests approaches, reviews code. Does not edit files, run commands, or create specs. | None |
| L1 | Human-Gated | Human approves every gate transition | Agent writes specs, implements code, runs tests. Every state transition, push, PR, and deploy requires explicit human confirmation. | None (default) |
| L2 | Supervised Autonomy | Human approves at decision points only | Agent auto-chains mechanical steps (update index, run tests, update changelog). Pauses at decision points (spec approval, validation, priority selection). | None |
| L3 | Trusted Autonomy | Human reviews asynchronously | Agent completes full spec cycles without waiting at each gate. Human reviews async via `/close`. Devil's Advocate gate is mandatory. Budget ceilings enforced. | NanoClaw (for async gate delivery) |
| L4 | Full Autonomy | Human intervenes on exception only | Agent creates specs, implements, validates, and closes end-to-end. Kill switch and budget ceilings are the only hard stops. | NanoClaw, mature signal history, high test coverage, established trust |

### Claude Code permission mode mapping

FORGE autonomy levels map to Claude Code's native permission modes. This mapping is applied during `/onboarding` and can be updated via `/config-change`.

| FORGE level | Claude Code mode | Rationale |
|-------------|-----------------|-----------|
| L0-L1 | `default` | Human approves every tool call |
| L2 | `auto` | Agent auto-executes safe tools; human approves risky ones |
| L3-L4 | `bypassPermissions` | Agent operates freely within budget and kill-switch bounds |

### Push-authorization gate across autonomy levels

The close/push human-authorization boundary is backstopped by a `git push` permission-prompt gate: every push raises an in-session approval prompt, and chained delivery never pushes until the human `/close` gate. **At L0–L2 this gate is hard-enforced** — the approval prompt is the operator-provenance primitive and the agent cannot self-authorize a push.

At **L3–L4**, the same controls are configured but the registration is editable by an agent operating at that level, so the hard guarantee is **designed, not yet enforced** — it lands fully when the server-managed trust root ships (a roadmap item). Until then, deferred-close chaining that removes the per-spec checkpoint is restricted to L1–L2. This is a known roadmap boundary, not an open hole: the ≤L2 enforcement, the approval-prompt forcing function, and the no-push-until-`/close` contract all ship today.

## Bounded autonomy

AGENTS.md divides agent permissions into three categories that apply regardless of autonomy level.

### Granted (no confirmation needed)

During an active `/implement` execution:
- Edit source code, tests, and configuration within spec scope
- Run tests and linters
- Update spec tracking files (README.md index, CHANGELOG.md, backlog.md)
- Update spec status through lifecycle states
- Create new files required by the spec
- Add entries to signals log, session logs, scratchpad

At any time:
- Read any file in the project
- Search codebase (grep, glob)
- Run non-destructive git commands (status, diff, log, branch)
- Create or update spec documents and session documents

### Requires confirmation

- Destructive git operations (force push, reset --hard, branch deletion)
- Push to remote
- PR creation
- Out-of-scope changes (edits to files not covered by the active spec)
- Schema-breaking changes
- Dependency additions (optional deps exempt during `/implement`)

### Prohibited

- Skip git hooks (`--no-verify`)
- Commit secrets, credentials, or `.env` files
- Modify git config
- Execute destructive shell commands without explicit request

### Authorization-required commands

These commands require explicit operator invocation in the current message and must never be executed based on session summaries, "pending tasks" lists, or "logical next step" inference:

- `/close`
- `/forge stoke`
- `git push` (standalone)
- Destructive git operations (`reset --hard`, `revert`, force push, `branch -D`)

After any context compaction boundary, all authorization-required commands are treated as unissued.

## Budget ceilings

Budget ceilings prevent runaway resource consumption. When breached, the agent pauses, reports current state, and waits for operator authorization.

| Lane | Token limit | Cost ceiling | Time limit | Max retries | Escalation |
|------|------------|-------------|------------|-------------|------------|
| `hotfix` | 50K tokens | $2.00 | 30 min | 3 | Pause and notify |
| `small-change` | 100K tokens | $5.00 | 1 hour | 5 | Pause and notify |
| `standard-feature` | 300K tokens | $15.00 | 4 hours | 10 | Pause and notify |
| `process-only` | 50K tokens | $2.00 | 30 min | 3 | Pause and notify |

## Gate enforcement modes

Three enforcement modes determine how gate approval happens:

| Mode | When used | Approval mechanism |
|------|-----------|-------------------|
| Delegated | L3/L4, all ACs machine-verifiable, no human-judgment checks | Agent validates and closes autonomously with three-layer evidence trail |
| Chat | Default; human judgment needed, no regulatory burden of proof | Human reviews Review Brief in conversation |
| PAL | High-trust workflows requiring hardware-authenticated approval | Review Brief via NanoClaw, hardware key tap, cryptographic signature (roadmap) |

## Next steps

- [Concept overview](concept-overview.md) for foundational FORGE concepts (Solve Loop, Evolve Loop, evidence gates)
- [Getting started](getting-started.md) for initial project setup

---

## Provenance and revision history

This document is **generated** by `scripts/gen-agents-config-reference.py` — defaults are read live from `AGENTS.md`
(descriptions from `scripts/lib/agents-config-reference-content.yaml`; source content hash
`70fe220f00e9`, FORGE plugin v3.3.0). Do not edit it by hand — changes belong in the
sources, then regenerate. Drift fails `.forge/bin/forge-parity.sh --check`.

Recent changes to AGENTS.md:

<!-- forge:gen:volatile:start -->
- 2026-07-20 `308a850` (commit message withheld from public copy — contains private-tier reference)
- 2026-07-08 `141138b` Spec 546 — spec-authoring pitfall-rule ports (verify-before-build, redirect reachability, wireframe)
- 2026-07-08 `6b610d0` Spec 544 — presentation/visualization artifact spec-gate exemption (AGENTS.md + template surfaces)
<!-- forge:gen:volatile:end -->

For the full change record, see `git log -- AGENTS.md` and `docs/specs/CHANGELOG.md`.
