# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in `.forge/commands/`.

**Total commands: 33**

## Session and orientation

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/insights` | sonnet | Mine FORGE process data for cross-session insights |
| `/note` | sonnet | Add a scratchpad note for the next process checkpoint |
| `/now` | sonnet | Review current project state and suggest next action |
| `/session` | sonnet | Create or update the session log |
| `/tab` | sonnet | Initialize or close a multi-tab session for parallel development |

## Planning and discovery

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/brainstorm` | sonnet | Discover spec opportunities from signals and roadmap |
| `/consensus` | sonnet | Run a proposal through all registry roles for structured consensus |
| `/decision` | sonnet | Create a new Architecture Decision Record (ADR) |
| `/explore` | sonnet | Pre-spec investigation — produces research artifacts before committing to a full spec |
| `/interview` | sonnet | Socratic elicitation for thinking through problems |
| `/matrix` | sonnet | Update and present the prioritization matrix |
| `/reconcile` | sonnet | Reconcile git history into the spec corpus — draft stub specs / memory notes for work committed outside FORGE |
| `/revise` | sonnet | Revise an existing spec based on feedback or correction |
| `/spec` | sonnet | Create a new spec from the template |

## Implementation

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/close` | sonnet | <!-- multi-block mode: serialized — choice blocks fire across distinct mechanical steps; no two blocks present in the same agent message. Each block waits for operator response before the next step proceeds. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. --> |
| `/implement` | sonnet | Build a spec end-to-end with evidence gates |
| `/parallel` | sonnet | Run multiple specs in parallel using git worktrees |
| `/scheduler` | sonnet | Run multi-agent scheduler for dependency-aware parallel execution |
| `/test` | sonnet | Run the test suite and report results |
| `/trace` | sonnet | Generate bidirectional traceability matrix from spec annotations |

## Lifecycle and maintenance

| Command | Model tier | Description |
|---------|-----------|-------------|
| `/config-change` | sonnet | Propose and apply changes to agent configuration files |
| `/configure` | sonnet | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) |
| `/forge` | sonnet | Unified FORGE project lifecycle command |
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
| `/signal-to-strategy` | sonnet | Turn external research signals into scored FORGE advantage hypotheses |
| `/synthesize` | sonnet | Synthesize accumulated project artifacts into refined documents |

## Next Steps

See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for detailed usage patterns and workflow sequences.

---

*Last verified against Spec 214.* | STALE: re-verify — Spec 509 changed a slash-command surface (/close 2026-07-02, Spec 509)
