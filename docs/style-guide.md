# FORGE Documentation Style Guide

This guide locks the voice, terminology, and conventions used across all FORGE public-facing documentation. All content specs (212-217) must conform to these decisions. No Tier 1 content ships without alignment to this guide.

---

## Canonical Description

Use this sentence identically wherever FORGE is introduced:

> FORGE is a project framework that gives AI-assisted development a structured delivery process — spec-driven, evidence-gated, and designed to remain reliable as agent autonomy increases.

---

## Voice and Tone

**Register**: Technical-professional. Precise and plain.

FORGE documentation speaks to working developers who are evaluating whether to adopt a framework. The voice signals reliability and competence — not excitement or novelty.

### Do / Don't Examples

| Do | Don't |
|---|---|
| "FORGE generates a spec from your description." | "FORGE magically creates specs for you!" |
| "Evidence gates require proof at each transition." | "Our revolutionary evidence-gating system ensures quality." |
| "This works with any AI assistant that reads AGENTS.md." | "FORGE is the best framework for AI-assisted development." |
| "Lane B compliance tooling is under development." | "FORGE will transform how regulated industries build software." |
| "The spec process adds structure. For small changes, use the light spec template." | "There's virtually zero overhead — you won't even notice it!" |

### Rules

- No exclamation points in documentation prose.
- No superlatives (best, fastest, most powerful, revolutionary, cutting-edge).
- No startup idioms (disrupt, game-changer, unlock, supercharge, 10x).
- Every factual claim must be defensible under skeptical review.
- Acknowledge limitations honestly. When something is not ready, say so.
- Use active voice. "The operator runs `/implement`" not "the spec is implemented."

---

## Terminology Glossary

These terms are locked. Use them consistently across all documentation. Do not substitute synonyms.

| Term | Definition | Not this |
|---|---|---|
| **spec** | A versioned document with objective, scope, requirements, acceptance criteria, test plan, and revision log. The atomic unit of work in FORGE. | ticket, story, issue, task |
| **operator** | The human running FORGE. Implies agency and accountability — the operator makes decisions, the AI assists. | user (too passive), developer (too narrow) |
| **evidence gate** | A hard stop at a lifecycle transition that requires demonstrable proof before proceeding. Gates produce structured PASS/FAIL outcomes. | checkpoint (implies optional), review (too vague) |
| **Solve Loop** | The per-spec delivery cycle: spec, implement, close. From KCS v6. | inner loop, dev loop |
| **Evolve Loop** | The process improvement cycle: capture signals, analyze patterns, propose changes. From KCS v6. | outer loop, retro loop |
| **EGID** | Evidence-Gated Iterative Delivery. FORGE's underlying methodology. Always expand on first use in a document, then abbreviate. | (no substitutes) |
| **context anchor** | A living document (spec, ADR, or session log) that persists decision context across AI sessions, team changes, and time. | context document, knowledge base |
| **change lane** | The risk category of a change: `hotfix`, `small-change`, `standard-feature`, `process-only`. Determines the level of ceremony. | change type, ticket category |

---

## Canonical Example Project

**Name**: `configlint`

**Description**: A CLI tool that reads a YAML configuration file, validates it against a schema, and reports errors. Language-agnostic in concept — tutorials default to Python for accessibility.

**Why this project**:
- Simple enough to bootstrap and spec in a single session
- Complex enough for a real spec (validation logic, edge cases, error reporting)
- No external dependencies (no database, no API, no cloud services)
- Neutral name — not "forge-demo" (which implies the project only exists for the tutorial)

**Usage across docs**:
- Getting Started (Spec 213): "Add a `--version` flag to configlint"
- First-Spec Example (Spec 215): A complete closed spec from the configlint project
- Future tutorials: extend configlint with new features

---

## Document Template

Every public documentation page follows this skeleton:

```markdown
# Page Title

One-sentence summary of what this page covers and who it is for.

---

[Content goes here]

---

## Next Steps

- [Related page 1](link) — one-line description
- [Related page 2](link) — one-line description

---

*Last verified against Spec NNN on YYYY-MM-DD.*
```

### Rules

- Every page opens with a one-sentence purpose statement.
- Every page ends with "Next Steps" linking to related content.
- Every page includes a "Last verified" footer with the spec number and date.
- Headings use sentence case ("Getting started" not "Getting Started") — except the page title.

---

## Callout Conventions

Use these callout blocks consistently across all documentation. GitHub renders blockquotes with emoji prefixes.

**Note** (informational — additional context):
```markdown
> **Note:** FORGE works with any AI assistant that reads `AGENTS.md`, not just Claude Code.
```

**Warning** (potential issue — something could go wrong):
```markdown
> **Warning:** If your IDE is already open, reload the window after running the install script.
```

**Danger** (destructive or security-critical):
```markdown
> **Danger:** The `--trust` flag allows Copier to execute code from the template repository. Only use with trusted sources.
```

---

## Code Block Conventions

- Every code block must be copy-pasteable and correct. No elided lines (`...`), no placeholder paths.
- Use language-specific syntax highlighting: ` ```bash `, ` ```python `, ` ```yaml `.
- Terminal output blocks use ` ```text ` (no syntax highlighting).
- Commands that the operator types are prefixed with `$` or shown without prefix in a standalone block.
- Output is shown separately from the command, never interleaved.

---

## Numbers and Claims

- Never hardcode a number that will change (spec count, command count, role count, session count) in prose. Use language like "hundreds of specs" or link to the authoritative source.
- If a number must appear (e.g., in a reference table), it must be validated by `scripts/validate-readme-counts.sh` (Spec 211).
- All attributions must include a verifiable source (URL, publication, or organization name with year).

### Temporal claims

- Never state specific time durations ("two minutes", "fifteen minutes", "under an hour") for tasks unless the number comes from measured data. AI-assisted development timelines do not follow traditional development estimates, and fabricated numbers erode trust.
- Use relative comparisons instead: "a fraction of the total task", "a single session", "less overhead than traditional ticket-writing."
- Configuration values with time units (e.g., budget ceiling timeouts) are acceptable — they are settings, not performance claims.
- Session logs and signals may record observed times as data points — these are measurements, not promises.

---

*Last verified against Spec 210 on 2026-04-11.*
