# Read Pattern Audit — Command Files

Created: 2026-03-13 (FORGE Framework)

Audit of which files each command reads and the read frequency across a typical session.

## Per-command read map

| Command | Files read | Conditional? |
|---------|-----------|-------------|
| `/now` | specs/README.md, backlog.md, sessions/ (latest log), CLAUDE.md, scratchpad.md, registry.md | registry conditional |
| `/implement` | specs/NNN-*.md, specs/README.md, CHANGELOG.md, registry.md | registry conditional |
| `/close` | specs/NNN-*.md, specs/README.md (×2), backlog.md (×2), CHANGELOG.md, sessions/ (today) | README+backlog read twice (step 2 + step 8) |
| `/session` | sessions/ (today), scratchpad.md, error-log.md, insights-log.md, registry.md | registry conditional |
| `/handoff` | specs/NNN-*.md, human-validation-runbook.md, scratchpad.md | — |
| `/matrix` | backlog.md, scoring-rubric.md, specs/README.md, spec frontmatter files | — |
| `/spec` | specs/README.md, specs/_template.md, scoring-rubric.md | — |
| `/revise` | specs/NNN-*.md | — |
| `/note` | scratchpad.md | — |
| `/evolve` | human-validation-runbook.md, specs/NNN-*.md, backlog.md, scratchpad.md | most conditional on fast-path vs monthly |
| `/tab` | registry.md | — |
| `/test` | (none — runs tests) | — |
| `/skills` | (none — prints table) | — |
| `/spec-gate` | specs/ directory, specs/README.md | — |

## Optimization approach

1. **Context-aware reads rule** (CLAUDE.md): Reuse content already in conversation context if unedited.
2. **Session context snapshot** (`/now` → `docs/sessions/context-snapshot.md`): Captures state for display-only lookups.
3. **Within-command dedup**: `/close` consolidated to avoid reading README.md and backlog.md twice.
4. **Static file list**: Files that never change mid-session (rubric, runbook, template) — read at most once.

## Static files (safe to read once per session)

- `docs/process-kit/scoring-rubric.md`
- `docs/process-kit/human-validation-runbook.md`
- `docs/specs/_template.md`
- `docs/process-kit/read-audit.md` (this file)
- `docs/process-kit/bootstrap-manifest.md`
- `docs/process-kit/prd-interview.md`
