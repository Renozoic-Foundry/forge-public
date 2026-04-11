# Spec Backlog

Last updated: <!-- YYYY-MM-DD -->
Last score calibration: <!-- YYYY-MM-DD -->

Scored by Claude using the [prioritization scoring rubric](process-kit/scoring-rubric.md).
Formula: `(BV × 3) + ((6−E) × 2) + ((6−R) × 2) + (SR × 1)` — max 40.

Human review required before any spec moves to `approved`. Claude may re-score as specs mature.

---

## Ranked backlog

| Rank | Spec | Title | BV | E | R | SR | Score | Status |
|------|------|-------|----|---|---|----|-------|--------|

---

## Deferred Scope

Items deferred as "out of scope" during spec closure. Tracked here until promoted to a spec, or intentionally dropped. Reviewed by `/outer-loop` — items older than 5 closed specs or 14 days are flagged as stale.

| Date | From Spec | Item | Status |
|------|-----------|------|--------|

Status values: `pending` (awaiting decision), `promoted → Spec NNN` (stub created), `dropped` (recorded in originating spec's revision log).

---

## Promotion rules

A spec moves from `draft` to `in-progress` when:
- `/implement` auto-approves inline with audit trail
- Change lane is confirmed in spec frontmatter

A spec moves from `implemented` to `closed` when:
- Human runs `/close` and confirms all deliverables
- Status is updated in the spec file, README.md, backlog, and CHANGELOG
- Backlog row changes from `implemented` to ✅ `closed`
