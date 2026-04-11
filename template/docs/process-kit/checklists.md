# Process Checklists (Domain-Neutral v2)

These checklists implement the **KCS double loop**:
- **Inner loop** (Pre → Implementation → Post) runs on every change.
- **Evolve loop** (Process Health) runs monthly.

## Pre-Implementation Checklist (Inner loop — Capture & Reuse)

- [ ] Search existing specs before creating a new one (Reuse first).
- [ ] Target spec ID exists and status is `draft` or `approved`.
- [ ] Change lane selected (`hotfix`, `small-change`, `standard-feature`) and recorded in spec frontmatter.
- [ ] Requested work is in scope; if not, spec revision is appended first.
- [ ] Acceptance criteria are specific and testable.
- [ ] Test plan exists and covers core behavior and edge cases.
- [ ] Risks/dependencies are recorded.
- [ ] Ownership roles identified (author/reviewer/approver/implementation owner).
- [ ] ADR need evaluated for architecture/interface-impacting changes.

## Implementation Checklist (Inner loop — Structure)

- [ ] Work is delivered in small, reviewable slices.
- [ ] Domain-specific logic is isolated behind interfaces.
- [ ] Error handling distinguishes recoverable vs fatal conditions.
- [ ] Added/changed behavior includes tests.
- [ ] Compatibility/deprecation notes captured for contract-affecting changes.

## Post-Implementation Checklist (Inner loop — Improve)

- [ ] Active spec status and revision log updated.
- [ ] `docs/specs/README.md` updated with current spec status.
- [ ] `docs/specs/CHANGELOG.md` updated with status/scope transitions.
- [ ] `README.md` updated if commands, behavior, outputs, or schema changed.
- [ ] Reproduction Commands section filled in spec.
- [ ] Validation evidence recorded in spec `Evidence` section.
- [ ] Has a human reviewed and understood this change?
- [ ] No contradictions across docs and implementation.
- [ ] Human validation runbook steps completed for relevant sections.
- [ ] Session log created at `docs/sessions/YYYY-MM-DD-NNN.md`.
- [ ] Session log process improvement items converted to specs or added to `docs/backlog.md`.
- [ ] `docs/backlog.md` re-scored if new specs were proposed this session.

## Process Health Checklist (Evolve loop — monthly)

- [ ] Review all `implemented` specs for drift vs actual code behavior.
- [ ] Verify spec index (`docs/specs/README.md`) matches files on disk.
- [ ] Confirm no `draft` specs have merged code without approval.
- [ ] Review KPI trends: lead time, escaped defects, hotfix count, doc drift events.
- [ ] Update process templates/checklists if recurring friction identified.
- [ ] Retire or supersede specs that are no longer relevant.
