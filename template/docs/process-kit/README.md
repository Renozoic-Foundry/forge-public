# Process Kit

Reference documents for FORGE's spec-driven development workflow. Organized by purpose to help you find what you need.

## Guides

| Document | Description |
|----------|-------------|
| [spec-driven-harness-loop.md](spec-driven-harness-loop.md) | End-to-end spec lifecycle and the harness loop that drives it |
| [context-anchoring-guide.md](context-anchoring-guide.md) | Context continuity patterns across sessions and agent boundaries |
| [context-isolation-guide.md](context-isolation-guide.md) | Isolation strategies for multi-agent and multi-role workflows |
| [implementation-patterns.md](implementation-patterns.md) | Choice blocks, agent parallelism, and implementation patterns |
| [long-running-task-patterns.md](long-running-task-patterns.md) | Spec batching, session handoff, and memory persistence for multi-session work |
| [shadow-validation-guide.md](shadow-validation-guide.md) | Strategy selection for shadow validation of AI-generated work |
| [mcp-setup.md](mcp-setup.md) | MCP documentation server configuration for agents |
| [gate-categories.md](gate-categories.md) | Gate categorization: machine-verifiable, human-judgment, confidence-gated |

## Checklists

| Document | Description |
|----------|-------------|
| [checklists.md](checklists.md) | Pre/post-implementation and process health checklists |
| [devils-advocate-checklist.md](devils-advocate-checklist.md) | Adversarial review checklist for the DA gate |
| [shadow-validation-checklist.md](shadow-validation-checklist.md) | Step-by-step shadow validation execution checklist |
| [dependency-vetting-checklist.md](dependency-vetting-checklist.md) | Checklist for reviewing new project dependencies |
| [human-validation-runbook.md](human-validation-runbook.md) | Section-based validation steps for human review |

## Templates

| Document | Description |
|----------|-------------|
| [AGENTS.template.md](AGENTS.template.md) | AAIF-compliant agent configuration template |
| [spec-index-template.md](spec-index-template.md) | Index format for the spec registry |
| [spec-changelog-template.md](spec-changelog-template.md) | Cross-spec chronological change history format |
| [prd-template.md](prd-template.md) | Product requirements document template |
| [prd-interview.md](prd-interview.md) | Greenfield PRD interview questions for `/interview` |
| [product-spec-template.md](product-spec-template.md) | Canonical product spec template for delta-spec workflows |
| [infographic-brief-template.md](infographic-brief-template.md) | Infographic brief artifact template |

## References

| Document | Description |
|----------|-------------|
| [scoring-rubric.md](scoring-rubric.md) | Priority scoring formula and dimension anchors for `/matrix` |
| [runbook.md](runbook.md) | Operational runbook: kill switch, budgets, escalation procedures |
| [read-audit.md](read-audit.md) | Command file read patterns and optimization analysis |
| [bootstrap-manifest.md](bootstrap-manifest.md) | File list for `/forge init` bootstrapping |
| [activity-log-schema.md](activity-log-schema.md) | JSONL event format for multi-agent activity logging |
| [command-integration-map.md](command-integration-map.md) | Cross-reference of command interactions and integration points |

## Upstream

This process kit ships with the [FORGE framework](https://github.com/bwcarty/forge-public). Adapt freely for your project.
