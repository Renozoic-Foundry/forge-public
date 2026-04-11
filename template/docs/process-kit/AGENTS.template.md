# AGENTS.md Template (Domain-Neutral v2)

> **Claude Code users:** Consider creating a `CLAUDE.md` at the repo root instead of (or alongside) `AGENTS.md`. Claude Code natively loads `CLAUDE.md` at the start of every session. Optimize it for terse, imperative instructions with `- [ ]` checkboxes and `[text](path)` clickable links. Keep `AGENTS.md` as the fuller Codex-compatible reference.

This file defines how the coding agent and human developer collaborate in this repository.

## Primary objective

Deliver maintainable software through a spec-first, test-backed, documentation-synchronized workflow.

## Operating principles

- Prefer small, incremental changes.
- Keep outputs deterministic where practical.
- Parsing/integration code should fail gracefully on partial or missing data.
- Keep domain-specific logic behind stable interfaces.
- Start with CLI/library reliability before adding UI complexity.
- Keep this file as a routing and guardrails document; store detailed process docs under `docs/`.

## Workflow map

- Specs index: `docs/specs/README.md`
- Spec changelog: `docs/specs/CHANGELOG.md`
- Working loop: `docs/process-kit/spec-driven-harness-loop.md`

## Spec-driven policy (Spec Gate)

- No implementation changes before a relevant spec exists and is current for the requested scope.
- Before implementation, either:
  - create a new spec in `docs/specs/NNN-*.md`, or
  - append a dated revision entry to an existing active spec.
- If request scope exceeds current approved scope, update/create spec first.
- Every implementation summary must reference a spec ID.

### Change lanes (required)

Choose one lane before implementation and apply the minimum controls for that lane.

- `hotfix`: production-impacting fix; minimal spec update allowed (scope, risk, test evidence) completed in same cycle.
- `small-change`: low-risk behavior change/refactor; full spec sections required but concise.
- `standard-feature`: net-new or cross-cutting behavior; full spec plus explicit risk/dependency notes.

### Pre-implementation checklist

- [ ] Confirm target spec ID and status (`draft` or `approved`).
- [ ] Confirm lane selection (`hotfix`, `small-change`, `standard-feature`) and required controls.
- [ ] Confirm acceptance criteria and test plan are present.
- [ ] Confirm requested behavior is in scope; if not, append a revision first.

## Ownership and accountability

Each active spec should identify:
- author
- reviewer
- approver (may be same as reviewer in lightweight mode)
- implementation owner

When teams are small, one person can hold multiple roles, but the roles should still be explicit.

## Spec history policy (append-only)

- Specs are append-only records; do not silently rewrite prior intent.
- Every spec includes a `Revision Log`.
- Record all scope changes as dated entries.
- If scope changes materially, create a new spec number.
- Track major status/scope transitions in `docs/specs/CHANGELOG.md`.

## Documentation synchronization gate

After implementation, update docs before declaring completion.

### Post-implementation checklist

- [ ] Update active spec status and revision log.
- [ ] Update `docs/specs/README.md` index entry.
- [ ] Update `docs/specs/CHANGELOG.md`.
- [ ] Update top-level `README.md` when behavior/schema/CLI changes.
- [ ] Verify no contradictions between code and docs.
- [ ] If validation artifacts are relevant, save them under `tmp/` and record paths in spec evidence.
- [ ] If architecture or interface boundaries changed, include/update ADR reference.

## Quality gate (baseline)

- Run automated tests for changed behavior.
- Run lint/type checks for changed files or modules.
- Keep failures actionable and non-flaky.
- Distinguish recoverable errors from unrecoverable exits.
- Include explicit compatibility/deprecation notes when contracts/schemas/CLI may change.

## Architecture decisions (ADR-lite)

- Create/update a lightweight ADR when a change impacts:
  - public interfaces
  - data/storage schema
  - system boundaries or major dependencies
- Keep ADRs in `docs/decisions/` and reference them from the related spec.

## Compatibility and deprecation

- Avoid silent breaking changes for external consumers.
- For intentional breakage, document migration guidance and target removal timing.
- Keep compatibility expectations in spec acceptance criteria where applicable.
