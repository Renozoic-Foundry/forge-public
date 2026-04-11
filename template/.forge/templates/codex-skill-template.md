---
name: forge-{{COMMAND_NAME}}
description: "{{DESCRIPTION}}. Use when the user wants to {{ACTION}}. Triggers on: {{TRIGGERS}}."
---

# FORGE: {{DISPLAY_NAME}}

{{BODY}}

## Project Context

When inside a FORGE-managed project (has AGENTS.md or .forge/ directory), this command reads project-level configuration:
- AGENTS.md for autonomy levels and enforcement rules
- docs/specs/ for spec files
- docs/sessions/ for session logs and signals
- docs/backlog.md for prioritized work

When NOT inside a FORGE project, this command will note that no project context is available and suggest running `forge install` followed by `/forge init` to set up a project.
