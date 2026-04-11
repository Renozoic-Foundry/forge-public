# Session Log — YYYY-MM-DD-NNN

- Date: YYYY-MM-DD
- Session number: NNN (increment per day)
- Specs touched: <!-- list spec IDs, e.g. 001, 002 -->
- Change lane(s): `hotfix` | `small-change` | `standard-feature` | `process-only`
- Last outer loop review: <!-- YYYY-MM-DD — if today − this date > 30 days, run runbook section F before closing this session -->

---

## Summary

<!-- 2–3 sentences: what was the goal, what was completed, what is deferred. -->

---

## Decisions made

<!-- Concrete choices that affect code, schema, process, or architecture.
     Each entry should be self-contained and searchable. -->

- <!-- decision -->

---

## Process pain points

<!-- Things that slowed this session: unclear instructions, missing tooling, ambiguous specs,
     environment issues, etc. Be specific — vague entries don't improve anything. -->

- <!-- pain point -->

---

## Spec triggers

<!-- New specs that must be created before the next implementation session.
     Copy to docs/backlog.md and create the spec file. -->

- [ ] <!-- Spec NNN — title: reason it was triggered -->

---

## Process improvement items

<!-- Any change to CLAUDE.md, checklists, runbook, templates, or workflow docs.
     Every item here MUST become a spec (even small-change lane) before it is implemented. -->

- [ ] <!-- item — target file — change lane: small-change | standard-feature -->

---

## Error autopsies

<!-- One entry per error found in this session — in chat, in tests, in harness, or in human validation.
     Copy completed entries to docs/sessions/error-log.md.
     Format: EA-NNN where NNN is the next sequential ID in error-log.md. -->

<!--
### EA-NNN: <title>
- Found via: chat discussion | test failure | harness run | code review | human validation
- Error: <what went wrong — specific, not vague>
- Root cause: <why it existed — process gap, missing gate, wrong assumption, etc.>
- Prevention: <what process or code change prevents recurrence>
- Spec: <NNN — title, if a spec was created; or "handled inline — <description>">
-->

---

## Chat insights

<!-- Recommendations, corrections, or process improvements that emerged from conversation this session.
     Capture anything that changed how we work, not just what we built.
     Copy completed entries to docs/sessions/insights-log.md.
     Format: CI-NNN where NNN is the next sequential ID in insights-log.md. -->

<!--
### CI-NNN: <title>
- Source: user question | user correction | agent recommendation | review discussion
- Insight: <what was surfaced — specific and actionable>
- Action: spec created NNN | decision recorded | deferred to backlog as NNN | no action needed
-->

