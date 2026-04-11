# Frequently asked questions

FORGE is a project framework that gives AI-assisted development a structured delivery process — spec-driven, evidence-gated, and designed to remain reliable as agent autonomy increases. These questions address the concerns a developer would reasonably raise before adopting it.

## Does this require Claude Code specifically?

No. FORGE works with any AI assistant that reads AGENTS.md and follows markdown-based process instructions. Claude Code has the deepest integration because FORGE's slash commands are native Claude Code features, but the spec files, evidence gates, session logs, and change lanes work with any tool that can read and write project files.

## Does this work with Cursor / Copilot / Windsurf / Cline?

Yes, with varying integration depth. The core workflow — specs, evidence gates, session logs — is IDE-independent and lives in plain markdown files. AI assistants that read project markdown files can follow FORGE's process. You lose the native slash-command experience, but the methodology itself is portable.

## What does FORGE cost per session?

FORGE itself is free and open source (MIT license). The cost is whatever your AI assistant charges for token usage. Spec-driven workflows tend to use tokens more efficiently because the AI has clear objectives and structured context, reducing the back-and-forth that burns tokens on ambiguous tasks.

## How much overhead does the spec process add?

It depends on the change lane and how you work. In AI-assisted development, the spec creation overhead is a fraction of the total task — the AI generates the spec structure from a one-sentence description. The operator reviews and adjusts, then implementation begins. Compared to unstructured AI-assisted development (where the AI drifts, restarts, or delivers the wrong thing), the upfront spec cost typically saves time by eliminating rework and scope creep. Compared to traditional development, FORGE replaces the time spent writing tickets and attending planning meetings with a spec that the AI can actually execute against. The spec also serves as a context anchor for future sessions, so the upfront cost compounds in value across the project lifecycle.

## How is this different from just using a CLAUDE.md file?

CLAUDE.md tells the AI how to behave. FORGE gives it a structured delivery process — specs, evidence gates, lifecycle management, and signal capture. Think of CLAUDE.md as the constitution and FORGE as the operating procedures. A CLAUDE.md file alone does not provide change lanes, traceability, session persistence, or the Evolve Loop that improves the process over time.

## Can I use FORGE on an existing project (brownfield)?

Yes. Run the install script or `copier copy` in an existing repo. FORGE adds its process files (`.forge/`, `docs/`, `CLAUDE.md`, `AGENTS.md`) alongside your code without modifying existing source files. The onboarding flow detects brownfield projects and adapts accordingly.

## Does FORGE work without an AI assistant at all?

The spec format, evidence gates, and session logs work as a manual development process. Several methodologies FORGE synthesizes — Stage-Gate, KCS, Architecture Decision Records — predate AI entirely. The AI assistant accelerates the workflow but is not a runtime dependency.

## How do I keep FORGE updated when the template changes?

Run `/forge stoke` (or `copier update` directly). Copier tracks the template version in `.copier-answers.yml` and merges upstream changes into your project, presenting conflicts for manual resolution. Your customizations are preserved through Copier's standard merge strategy.

## Is the compliance engine (Lane B) production-ready?

No. Lane B compliance tooling is under active development and is not included in the current public release. The roadmap includes IEC 61508 and IEC 62443 support, but these features require additional validation before they ship. The current release focuses on the general-purpose development workflow (Lane A).

## What happens if I outgrow FORGE or want to stop using it?

FORGE is process, not infrastructure. Your code has no FORGE runtime dependency — there are no FORGE imports, no build plugins, no CI lock-in. Remove the `.forge/` and `docs/` process directories and you have a standard project. Specs and session logs remain as useful documentation even after you stop using the framework.

## What FORGE does not do

- **Not a project management tool.** FORGE does not provide Gantt charts, sprint planning, velocity tracking, or time tracking. It structures the delivery process, not the project schedule.
- **Not a certification authority.** FORGE structures evidence and supports traceability, but it does not certify compliance with any standard. Certification decisions remain with qualified assessors.
- **Not an AI model or IDE.** FORGE is a process layer that works alongside your existing AI assistant and development environment. It does not replace either.
- **Not a replacement for human judgment.** Evidence gates require human review by default. FORGE structures the decision points but does not make the decisions.

## Next steps

- [Getting started](getting-started.md) — install FORGE and create your first spec
- [Concept overview](concept-overview.md) — understand the methodology behind FORGE
- [Command reference](command-reference.md) — explore available commands

---

Last verified against Spec 216.
