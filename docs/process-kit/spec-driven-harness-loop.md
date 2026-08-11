# Spec-Driven Harness Loop

Last updated: 2026-04-07

## Why this exists

This workflow keeps AI-assisted development fast while reducing regressions and documentation drift. It follows a **KCS double loop** pattern: an inner loop for every change, and an evolve loop for evolving the process itself.

## Inner loop — per change (Capture → Structure → Reuse → Improve)

0. **Explore (optional)**: For topics needing investigation before committing to a spec, run `/explore <topic>` to produce a research artifact at `docs/research/explore-<topic>.md`. This creates a `proposed` state artifact. Specs can still start directly at `draft` — exploration is not mandatory.
1. **Reuse first**: Search `docs/specs/` for an existing spec before creating a new one.
2. **Capture at point of need**: Write or update the spec now — not retroactively after code is committed.
3. **Structure**: Fill all template sections; select and record `Change-Lane:` in spec frontmatter.
4. **Capture ADR-lite context** if architecture or interface boundaries are affected → `docs/decisions/`.
5. **Implement** in small vertical slices.
6. **Validate**: Run tests, lint, and validation artifacts where applicable.
7. **Improve the knowledge base**: Update spec Evidence, index, changelog, README before closing.
8. **Hand off for human validation**: Walk through [human-validation-runbook.md](human-validation-runbook.md).

## Evolve loop — periodic (Evolve the process)

1. Review specs for drift vs implementation (are `implemented` specs still accurate?).
2. Evaluate process KPIs (lead time, escaped defects, hotfix rate, doc drift events).
3. Update templates and checklists if recurring friction patterns are found.
4. Retire or deprecate stale specs.

## Validation checkpoints

<!-- customize: replace with your project's validation/harness commands -->
Required checks:
- changed behavior has tests
- changed modules pass lint/type checks where feasible
- compatibility/deprecation notes added when contracts or schema may change

## Artifact conventions

- Keep temporary validation artifacts under `tmp/`.
- Use explicit names, e.g. `tmp/validation/report.json`.
- For milestone-level changes, capture artifact path(s) in the related spec `Evidence` section.

## Agent instruction hygiene

- `AGENTS.md` is a routing map and guardrail list, not a full handbook.
- Put detailed process docs under `docs/process-kit/` and reference them from `AGENTS.md`.
- Avoid duplicating authoritative rules in multiple places unless one points to the source of truth.

## Process KPI scorecard

Track at a regular cadence (for example monthly):
- lead time from spec draft to implemented
- escaped defects/regressions
- hotfix frequency
- flaky test rate
- documentation drift incidents
