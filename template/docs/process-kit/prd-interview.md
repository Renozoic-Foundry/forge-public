# PRD Interview — Greenfield Bootstrap

> **For deeper elicitation beyond these bootstrap questions, use `/interview`.** The `/interview` command runs a full Socratic conversation with devil's advocate probing, options analysis, and structured synthesis — then routes output to specs, ADRs, or notes. These bootstrap questions remain the fast path for greenfield project setup.

Used by `/forge init` in greenfield mode. Ask each question, wait for the answer, then proceed to the next. Answers populate the initial CLAUDE.md and first spec.

## Questions

### Q1 — Project name
> What is the project name? (used for CLAUDE.md header and file references)

Example: `my-project`, `acme-api`, `personal-finance-tracker`

### Q2 — Description
> Describe the project in 1–2 sentences.

This becomes the opening paragraph of CLAUDE.md. Be specific about what the software does, not aspirational goals.

### Q3 — Repository URL
> What is the git remote URL? (leave blank if not yet created)

Used for links in generated docs. Can be added later.

### Q4 — Primary stack
> What language/framework is the primary stack?

Used to configure the `/test` command, lint commands, and CLAUDE.md key commands section.

Examples: `Python`, `TypeScript + React`, `Go`, `Rust`, `Python + FastAPI`

### Q5 — Initial features
> What are the 2–3 most important features or goals for the initial version?

Each becomes a candidate for the first spec. Pick concrete, deliverable features — not themes.

### Q6 — Constraints
> Are there any hard constraints?

Examples: must run offline, no external APIs, Windows-only, must support Python 3.10+, no paid dependencies

---

## Output mapping

| Answer | Used in |
|---|---|
| Q1 (name) | CLAUDE.md header, `{{PROJECT_NAME}}` substitution |
| Q2 (description) | CLAUDE.md opening paragraph, `{{PROJECT_DESCRIPTION}}` |
| Q3 (repo URL) | `{{REPO_URL}}` in docs |
| Q4 (stack) | CLAUDE.md key commands, `/test` command configuration |
| Q5 (features) | First spec draft (highest-priority feature) |
| Q6 (constraints) | CLAUDE.md core constraints section |
