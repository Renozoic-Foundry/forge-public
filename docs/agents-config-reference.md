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
| `forge.strategic_scope` | YAML block (multiline string) | Template-provided scope statement | Defines what the project IS and IS NOT; consumed by `/matrix` when evaluating spec fit. | When present, `/matrix` classifies draft specs as on-mission, borderline, or scope-creep against this definition. When absent, `/matrix` infers scope from the CLAUDE.md project description. |
| `forge.context.session_briefing` | boolean | `true` | Controls whether `/now` includes the "Last time on [project]" continuity brief. | When `true`, `/now` reads recent session logs, signals, and scratchpad to provide a session-start brief. When `false`, the brief is skipped. |

### Runtime configuration (`forge:` block)

These fields appear in the `forge:` YAML block under the **Runtime Configuration** section. They are parsed by `.forge/lib/config.sh`.

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `forge.methodology` | enum | `none` | Team methodology label. Valid values: `scrum`, `safe`, `kanban`, `devops`, `safety-critical`, `none`. | Adapts command output language to match the team's methodology. Set during `/onboarding`. Language only; no behavioral change. |
| `forge.lane` | enum | `A` | Active development lane. Currently only `A` is available. | Determines which feature set is active. |
| `forge.gate.provider` | enum | `prompt` | Gate approval mechanism. Valid values: `prompt`, `pal`, `auto`. | `prompt`: chat-based approval. `pal`: hardware-authenticated (YubiKey). `auto`: use PAL if installed, fall back to prompt. |
| `forge.gate.timeout` | integer (seconds) | `1800` | Maximum wait time for a gate approval before timing out. | After this duration, a pending gate approval times out and follows the configured fallback behavior. |
| `forge.roles.separation` | enum | `context-scoped` | Role isolation level. Valid values: `none`, `context-scoped`, `full`. | `none`: all roles in main conversation (development shortcut, not recommended for production). `context-scoped` (default): DA and validator as isolated subagents, implementer in main context. `full`: all roles as isolated subagents (implementer uses worktree). |
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
| `forge.model_router.enabled` | boolean | `true` | Enables the model routing system. | When `false`, all commands use the default model tier. |
| `forge.model_router.mode` | enum | `static` | Routing strategy. Valid values: `static`, `dynamic`. | `static`: uses the tier table from CLAUDE.md. `dynamic`: adjusts tier based on runtime signals. |
| `forge.model_router.safety_floor` | enum | `sonnet` | Minimum model tier for code-modifying commands. | Prevents cost-saving downgrades for commands that edit source code. |
| `forge.model_router.cost_tracking` | boolean | `true` | Log per-command costs to the metrics directory. | Enables cost visibility for `/evolve` regret-rate reporting. |
| `forge.model_router.metrics_dir` | string (path) | `.forge/metrics` | Directory for cost and routing metrics. | Where per-command cost logs are written. |
| `forge.model_router.escalation.auto_detect` | boolean | `true` | Detect poor outcomes and escalate model tier. | When `true`, the router upgrades to a higher tier if the current tier produces low-quality results. |
| `forge.model_router.escalation.max_escalations` | integer | `1` | Maximum tier escalations per command invocation. | Prevents runaway escalation chains within a single command. |
| `forge.model_router.regret_reporting` | boolean | `true` | Include regret rate in `/evolve` reports. | Surfaces how often the router's tier choice was suboptimal. |
| `forge.model_router.metrics_retention_days` | integer | `30` | Days to keep metrics files before archiving. | Older metrics files are archived to prevent unbounded growth. |
| `forge.dispatch_rules.enabled` | boolean | `false` | Enables intelligent role dispatch based on spec characteristics. | When `true`, CxO advisory roles are auto-invoked when spec characteristics match dispatch conditions. |
| `forge.dispatch_rules.skip_threshold.effort` | integer | `1` | Effort score at or below which extra dispatch is skipped. | Low-effort specs matching all threshold conditions use DA only. |
| `forge.dispatch_rules.skip_threshold.risk` | integer | `1` | Risk score at or below which extra dispatch is skipped. | Low-risk specs matching all threshold conditions use DA only. |
| `forge.dispatch_rules.roles` | YAML block | See template | Maps CxO roles to trigger conditions. | Defines which conditions (e.g., `cross_cutting`, `security`, `high_risk`) invoke which advisory roles. |
| `forge.dispatch_rules.evolve_loop` | YAML block | See template | Roles invoked during `/evolve --full`. | Controls which CxO roles participate in Evolve Loop steps (signal analysis, trust calibration, etc.). |
| `forge.dispatch_rules.touchpoints` | list of strings | `[spec_review, da_gate, close_review, evolve_loop]` | Lifecycle points where dispatch fires. | Determines when in the spec lifecycle advisory roles are consulted. |

### Role registry

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `forge.role_registry` | list of objects | See template | Maps role instruction files to command contexts. | Commands read this block to determine which roles to activate. Adding an entry here wires a role into all matching contexts without changing command files. If absent, commands skip role invocation silently. |

Each entry has:
- `path` — relative path to the role instruction file (e.g., `.claude/agents/spec-author.md`)
- `contexts` — list of command names where the role is invoked (e.g., `[spec]`, `[implement, close]`)

#### Competitor role (Spec 274 — opt-in)

The **Competitor** role role-plays a fictional rival organization's reaction to the proposal, framed as "leaked competitive intelligence." It provides an **outside-in adversarial perspective** (how would a competitor counter this?) to complement the existing inside-out adversarial roles (Devil's Advocate for risk, Maverick Thinker for convention).

| Field | Value |
|-------|-------|
| Path | `.claude/agents/competitor.md` |
| Contexts | `[brainstorm, spec]` |
| Default state | **OFF** — registry entry is commented out in `template/AGENTS.md.jinja`. Uncomment to enable. |
| Output | Structured JSON: `competitor_posture`, `likely_counter_moves`, `exploitable_weaknesses`, `defensive_recommendations`, `summary` (in the rival's voice). |
| When to invoke | Direction-setting time (proposal commits to pricing, distribution, positioning, or a publicly visible surface). Skip for internal process / refactor specs. |
| Constraints | Stay fictional (no real company names); no fabricated market data; speak *from* the rival, not *about* the rival. |

**Rhetorical framing example.** For a proposal "we're adding a free tier," the Competitor role does NOT write *"the competitor would respond by..."* — it writes *"Team — the threat is strategic. Our pricing-power advantage erodes if we don't act inside the next two quarters. Counter-move: ship our own free tier with a 10× usage cap..."* — speaking from inside the rival's war room.

**Note on dispatch**: as of Spec 274 ship, only `/consensus` iterates `forge.role_registry` to dispatch roles. `/brainstorm` and `/spec` (this role's listed contexts) do not yet read the registry. Wiring those commands is tracked as a deferred-scope follow-up; until that lands, this role can only be invoked manually via Claude Code's agent invocation syntax.

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

### Spec Kit integration

| Field | Type | Default | Description | Behavioral consequence |
|-------|------|---------|-------------|----------------------|
| `spec_kit.enabled` | boolean | `false` | Enables Spec Kit MCP integration for guided spec creation. | When `true`, `/spec` offers guided creation via Spec Kit MCP tools. Requires the Spec Kit MCP server configured in `.mcp.json`. |
| `spec_kit.fallback` | enum | `manual` | Fallback behavior when MCP is unavailable. Valid values: `manual`, `error`. | `manual`: falls back to FORGE template authoring. `error`: fails if MCP is unavailable (strict mode). |

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

Last verified against Spec 263 on 2026-04-15.
