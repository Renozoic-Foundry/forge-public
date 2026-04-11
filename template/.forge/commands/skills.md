---
name: skills
description: "DEPRECATED — List all available slash commands grouped by workflow stage"
model_tier: haiku
workflow_stage: configuration
deprecated: true
---
# Framework: FORGE
# DEPRECATED (Spec 131): /skills is replaced by /forge help and bin/forge list.
# Replacement: Run /forge help for command listing, or bin/forge list from the terminal.
# This command still executes for backward compatibility but will be removed in a future release.

List all available slash commands grouped by workflow stage.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /skills — Lists all available slash commands grouped by workflow stage.
  Usage: /skills
  No arguments accepted.
  ```
  Stop — do not execute any further steps.

---

Print the following content exactly.

## Typical Workflow

```
Standard path:  /spec → /implement → /close
Discovery path: /now  → /brainstorm → /spec
```

## Quick Start

- **New to this project?** Run `/onboarding` for a guided walkthrough, or `/now` to see current status.
- **New to FORGE?** Run `/forge init` to bootstrap the spec-driven workflow into a project.

---

## Commands by Stage

### Planning & Discovery
_Explore ideas, define work, and prioritize the backlog._

| Command | Description |
|---------|-------------|
| `/brainstorm` | Generate and explore ideas for a topic or problem |
| `/interview` | Socratic elicitation — think through a problem before committing to specs or decisions |
| `/matrix` | Update and display the full prioritization matrix |
| `/spec` | Create a new spec from the template |
| `/spec-gate` | Enforce the spec gate before making any change |
| `/revise` | Apply a correction or change request to an existing spec |

### Implementation & Testing
_Build, test, and trace changes against specs._

| Command | Description |
|---------|-------------|
| `/implement` | Implement an approved spec end-to-end |
| `/test` | Run the project test suite |
| `/trace` | Trace implementation back to spec requirements |
| `/tab` | Initialize or close a multi-tab coordination session |
| `/parallel` | Run parallel implementation tracks across specs |

### Review & Close
_Validate work, capture learnings, and close out specs._

| Command | Description |
|---------|-------------|
| `/close` | Close a spec — confirm validation, capture signals, update priorities |
| `/retro` | Run a structured retrospective with signal capture |
| `/harvest` | Mid-session signal extraction from conversation |
| `/evolve` | Run the KCS evolve review across specs and process |
| `/handoff` | Display full validation steps when switching context or ending a session |

### Session Management
_Track daily progress, capture notes, and maintain continuity._

| Command | Description |
|---------|-------------|
| `/now` | Review project state and recommend the next action |
| `/session` | Create or update today's session log; mine chat for signals |
| `/note` | Add a scratchpad note for the next process checkpoint |
| `/bug` | File a structured bug report with severity and routing |
| `/insights` | Surface patterns and learnings from session history |

### Project Lifecycle
_Bootstrap, maintain, and evolve the FORGE workflow._

| Command | Description |
|---------|-------------|
| `/forge` | Project lifecycle — `light` (bootstrap), `stoke` (maintain) |
| `/onboarding` | Guided walkthrough for new project contributors |
| `/scheduler` | Plan and schedule upcoming work across specs |
| `/config-change` | Propose and track a configuration change |
<!-- module:nanoclaw -->
| `/configure-nanoclaw` | Set up nanoclaw automated review |
| `/nanoclaw` | Run nanoclaw automated review |
<!-- /module:nanoclaw -->

### Reference
| Command | Description |
|---------|-------------|
| `/skills` | List all available commands — this command |

---

## Notes

- All commands accept `?` or `help` as an argument to print usage without executing: e.g. `/test ?`
- Commands are defined in `.claude/commands/` — each file is a markdown prompt loaded by Claude Code.
- Spec-gated commands (`/implement`) will stop and report if the target spec is not in the correct state.
- Session tracking commands (`/session`, `/note`, `/evolve`) read and write files in `docs/sessions/`.
- Run `/now` at the start of any session to orient yourself.
