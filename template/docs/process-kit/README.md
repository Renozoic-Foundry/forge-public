# Process Kit — FORGE Framework

Last updated: 2026-03-13

This folder contains reusable, domain-neutral artifacts for AI-assisted spec-driven development in a repo-first workflow. Part of the [FORGE](https://github.com/Renozoic-Foundry/forge-public) framework (Evidence-Gated Iterative Delivery methodology).

Use this kit when you want:
- clear scope before code
- append-only decision history
- deterministic delivery habits
- lightweight governance that can tighten over time
- explicit lanes for urgent vs planned work
- architecture/compatibility decisions captured early

## Included artifacts

- `scoring-rubric.md`: Priority scoring formula and dimension anchors.
- `human-validation-runbook.md`: Section-based validation for human review.
- `checklists.md`: Pre/post-implementation and process health checklists.
- `implementation-patterns.md`: Choice blocks and agent parallelism patterns.
- `spec-template.md`: Per-change spec template with acceptance criteria and test plan.
- `spec-index-template.md`: Index format for active specs.
- `spec-changelog-template.md`: Cross-spec chronological history.
- `AGENTS.template.md`: AAIF-compliant agent configuration template.
- `bootstrap-manifest.md`: File list for `/forge init` command.
- `prd-interview.md`: Greenfield PRD interview questions.
- `read-audit.md`: Command file read patterns and optimization.
- `release-policy.md`: SemVer contract for `forge-public` releases — three surfaces, deprecation rules, yank policy. Source of truth for `scripts/cut-release.sh`.
- `long-running-task-patterns.md`: Spec batching, session handoff, and memory persistence for multi-session work.
- `context-anchoring-guide.md`: Context continuity patterns across sessions and agent boundaries.
- `dependency-vetting-checklist.md`: Checklist for reviewing new dependencies.
- `shadow-validation-guide.md`: Strategy selection for shadow validation.
- `shadow-validation-checklist.md`: Step-by-step shadow validation execution.
- `mcp-setup.md`: MCP documentation server configuration.
- `devils-advocate-checklist.md`: Adversarial review checklist.

## Upstream

This process kit is maintained in the FORGE framework repo. Improvements discovered in downstream projects should be contributed upstream via the process described in [CONTRIBUTING.md](../../CONTRIBUTING.md).
