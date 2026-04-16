# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in `template/.claude/commands/`.

**Total commands: 29**

## Session and orientation

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/insights` | haiku | Mine FORGE process data for cross-session insights |
| `/note` | haiku | Add a scratchpad note to be reviewed at the next appropriate process checkpoint. |
| `/now` | haiku | Review current project state and suggest next action |
| `/session` | haiku | Create or update the session log |
| `/tab` | sonnet | Initialize or close a multi-tab session for parallel development |

## Planning and discovery

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/brainstorm` | haiku | Discover spec opportunities from signals and roadmap |
| `/consensus` | sonnet | Run a proposal through all registry roles for structured consensus |
| `/decision` | sonnet | Create a new Architecture Decision Record (ADR) |
| `/explore` | sonnet | Pre-spec investigation — produces research artifacts before committing to a full spec |
| `/interview` | sonnet | Socratic elicitation for thinking through problems |
| `/matrix` | haiku | Update and present the prioritization matrix |
| `/revise` | sonnet | Revise an existing spec based on feedback or correction |
| `/spec` | sonnet | Create a new spec from the template |

## Implementation

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/close` | sonnet | Close a spec: confirm validation, capture signals, update priorities |
| `/implement` | sonnet | Build a spec end-to-end with evidence gates |
| `/parallel` | sonnet | Run multiple specs in parallel using git worktrees |
| `/scheduler` | sonnet | Run multi-agent scheduler for dependency-aware parallel execution |
| `/test` | sonnet | Run the test suite and report results |
| `/trace` | sonnet | Generate bidirectional traceability matrix from spec annotations |

## Lifecycle and maintenance

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/config-change` | sonnet | Propose and apply changes to agent configuration files |
| `/forge` | sonnet | Unified FORGE project lifecycle command. Manages bootstrap and upstream sync workflows. |
| `/forge-init` | sonnet | Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch. |
| `/forge-stoke` | sonnet | Pull upstream FORGE updates into this project using Copier. Handles migration from Cruft if needed. |
| `/onboarding` | sonnet | First-session interactive project configuration |

## Process and review

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/configure-nanoclaw` | sonnet | Configure NanoClaw hardware key enrollment and messaging |
| `/dependency-audit` | sonnet | Scan for dependency changes and produce a structured risk report |
| `/evolve` | sonnet | Run the KCS Evolve Loop review |
| `/nanoclaw` | sonnet | Manage the NanoClaw container — start, stop, status, logs |
| `/synthesize` | sonnet | Synthesize accumulated project artifacts into refined documents |

## Next Steps

See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for detailed usage patterns and workflow sequences.

---

*Last verified against Spec 263 on 2026-04-15.*
