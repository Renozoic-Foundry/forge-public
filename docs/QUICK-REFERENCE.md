# FORGE Quick Reference

## Core Commands

| Command | Purpose |
|---------|---------|
| `/now` | Review project state and get the next recommended action |
| `/spec` | Create or update a spec for a planned change |
| `/implement` | Build a spec end-to-end with evidence gates |
| `/close` | Close a spec: validate, capture signals, update tracking |

**When in doubt, run `/now`.**

## Change Lanes

| Lane | Use when |
|------|----------|
| `hotfix` | Critical fix needed immediately |
| `small-change` | Low-risk tweak, minimal review |
| `standard-feature` | New command, process addition, or cross-cutting change |
| `process-only` | Changes to docs/tracking only (no code) |

## Rules — Every change needs a spec. Every session ends with `/session`.

---

## Command Reference (by stage)

### Session & Orientation

| Command | Purpose | Model Tier |
|---------|---------|------------|
| `/now` | Review project state, validation queue, and next action | haiku |
| `/session` | Create or update the session log with auto-drafted content | haiku |
| `/note` | Quick-capture a thought to the scratchpad | haiku |
| `/insights` | Review error and chat insight logs | haiku |
| `/tab` | Manage multi-tab work claims | sonnet |

### Planning & Discovery

| Command | Purpose | Model Tier |
|---------|---------|------------|
| `/explore` | Pre-spec investigation — produces research artifacts before committing to a full spec | sonnet |
| `/brainstorm` | Discover spec opportunities from signals and roadmap | haiku |
| `/interview` | Socratic elicitation for thinking through problems | sonnet |
| `/spec` | Create a new spec from a description | sonnet |
| `/matrix` | Display and re-rank the backlog priority matrix | haiku |

### Implementation

| Command | Purpose | Model Tier |
|---------|---------|------------|
| `/implement` | Build a spec end-to-end with evidence gates | sonnet |
| `/close` | Validate and close an implemented spec | sonnet |
| `/revise` | Revise a spec after devil's advocate or review findings | sonnet |
| `/trace` | Trace a spec's evidence chain end-to-end | sonnet |
| `/parallel` | Run multiple independent specs simultaneously | sonnet |
| `/scheduler` | Dependency-aware multi-agent parallel execution | sonnet |
| `/test` | Run project test suite with evidence capture | sonnet |

### Lifecycle & Maintenance

| Command | Purpose | Model Tier |
|---------|---------|------------|
| `/forge init` | Bootstrap FORGE into a new or existing project | sonnet |
| `/forge stoke` | Pull upstream FORGE updates and integrate safely | sonnet |
| `/forge status` | Quick project status overview | sonnet |
| `/forge help` | List all available FORGE commands | sonnet |
| `/onboarding` | First-session interactive project configuration (2-interaction fast-path) | sonnet |
| `/configure` | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) | sonnet |
| `/config-change` | Propose a configuration change with impact analysis | sonnet |

### Process & Review

| Command | Purpose | Model Tier |
|---------|---------|------------|
| `/evolve` | Full process review — backlog, signals, watchlist | sonnet |
| `/synthesize` | Synthesize accumulated project artifacts into refined documents | sonnet |
| `/decision` | Record an architecture decision (ADR) | sonnet |
| `/consensus` | Multi-role structured review with vote tally and divergence signal | sonnet |
| `/dependency-audit` | Audit project dependencies for risk | sonnet |

### Typical Workflow

```
/now → /implement next → /close NNN → /session
```

For new projects: `/forge init` → `/onboarding` → `/interview` → `/spec` → `/implement`

---

## Key References

- `CLAUDE.md` — Operating rules and project context (in your bootstrapped project)
- `AGENTS.md` — Agent roles, autonomy levels, evidence gates (in your bootstrapped project)
- `docs/process-kit/` — Scoring rubric, checklists, runbook, templates (in your bootstrapped project)
