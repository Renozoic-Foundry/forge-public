# Acknowledgements

FORGE synthesizes established methodologies and research into a cohesive framework. This file acknowledges the foundations and influences.

## Foundational Methodologies

| Methodology | Author / Organization | Year | How FORGE uses it |
|---|---|---|---|
| **Stage-Gate** | Robert G. Cooper | 1986 | Evidence gates at every lifecycle transition |
| **Knowledge-Centered Service (KCS v6)** | Consortium for Service Innovation | 2016 | Double-loop learning: Solve Loop (per-spec) + Evolve Loop (process improvement) |
| **Architecture Decision Records** | Michael Nygard | 2011 | Structured `/decision` command and ADR templates |
| **Context Anchoring** | Martin Fowler | 2026 | Specs as living documents that persist decision context across AI sessions |
| **Agentic AI Foundation (AAIF)** | Linux Foundation | 2025 | `AGENTS.md` bounded autonomy, delegation contracts, and prohibited actions |

## Key Influences

- **Martin Fowler** — Context anchoring, encoding standards, architecture patterns. His 2026 writing independently validated the spec-as-context-anchor pattern FORGE had practiced from the start.
- **Simon Willison** — Daily tech curation and architecture analysis that informed multiple FORGE design decisions.
- **Boris Cherny** — CLAUDE.md token optimization research (Claude Code Study).
- **Todd Orr** — "Comprehension debt" framing that informed the cognitive debt guardrail.
- **Sebastian Raschka** — Harness components for coding agents analysis that maps directly to FORGE patterns.

## Runtime Dependencies

| Tool | License | Purpose |
|---|---|---|
| [Copier](https://copier.readthedocs.io/) | MIT | Template engine and project sync |
| [Python](https://python.org/) | PSF License | Runtime for Copier and scripts |
| [Git](https://git-scm.com/) | LGPL-2.0 | Version control |
| [ShellCheck](https://www.shellcheck.net/) | GPL-3.0 | Bash script linting (optional, not bundled) |

## MCP Servers (Optional Integrations)

| Server | Author / Organization | Purpose |
|---|---|---|
| [Context7](https://github.com/upstash/context7) | Upstash | Versioned library documentation |
| [Fetch](https://github.com/anthropics/fetch-mcp) | Anthropic | URL-to-markdown conversion |
| [Spec Kit](https://github.com/lsendel/spec-kit-mcp) | Lee Sendel (@lsendel) | Guided requirements elicitation |

## License

FORGE is released under the [MIT License](LICENSE).
