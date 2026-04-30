# Backlog Hygiene Guide — Spec 370

_Documents the two backlog hygiene scans (deprecation, deferral) that `/matrix` runs as a Hygiene Pass between rank refresh and the exit-gate. This file is the single canonical source for the scan rules; the sentinel block below is byte-identical-mirrored into 4 `matrix.md` locations via `scripts/spec-370-sync-matrix-hygiene.sh`._

## Why hygiene lives in `/matrix`

Hygiene = deprecating bottom-of-backlog drafts whose moment has passed, and deferring drafts whose timing is wrong but design is correct. Before Spec 370, hygiene was operator-discretionary: the 2026-04-29 session executed three manual hygiene passes producing CHANGELOG entries for 11 specs touched, each useful but each costing the cognitive load of remembering, framing, and executing.

`/matrix` is the right home because /matrix already iterates the backlog row-by-row for rank/score refresh — the hygiene scans piggyback on that iteration. Other commands fail the placement test:

- `/now` would fire hygiene on every invocation (too noisy)
- `/session` doesn't always touch the backlog (wrong frequency)
- `/evolve` is for process review, not backlog grooming (wrong scope)
- A separate `/hygiene` command would re-introduce the "operator must remember" problem the spec exists to solve

## The two scans

### 1. Deprecation candidates

A `Status: draft` spec qualifies as a deprecation candidate when **both** of the following hold:

- `valid-until:` in frontmatter is **populated AND past today** (Spec 363 surfaces this signal at /matrix already, but only as a count — the hygiene scan names the specs and pairs each with a reason).
- The backlog row's rank has been **≥ 30 for ≥ 30 days** (bottom-of-backlog dwell — empirically `top-of-backlog` is rank ≤ 25 across recent /matrix runs; rank ≥ 30 cleanly separates bottom-of-backlog drafts from active development).

**Both signals are required.** The valid-until-only path is too noisy (legitimately-aging drafts under active revision get false-flagged). The rank-only path is too noisy (bottom-of-backlog drafts whose moment has not yet come get false-flagged). The intersection is high-confidence: a draft past its valid-until window AND parked at rank ≥ 30 for a month is a deprecation candidate.

A third signal — **dependency-driver itself deprecated** — is folded into the candidate description as supporting context (not a primary trigger). The deferral scan handles dependency-driver-deprecated drafts as deferral rather than deprecation, since their design may still be correct once the driver returns.

### 2. Deferral candidates

A `Status: draft` spec qualifies as a deferral candidate when its `Dependencies:` field references a spec whose `Status:` is `deferred` or `deprecated` (verified by reading the named dependency spec file's frontmatter directly — not the backlog row, since backlog and spec file may drift).

The inferred re-activation trigger for each deferral candidate is templated as `<dependency-spec-id> closes` or `<dependency-spec-id> reactivated`. The operator can override at the deferral prompt.

**Why dependency-anchor introspection (not text scan)**: The original draft of Spec 370 included a third "schema-coordination" scan based on `Implementation Summary → Changed files` overlap pattern matching across drafts. /consensus 370 round 1 (DA + CEfO convergent concern) found that detection rule under-specified because draft Implementation Summary maturity varies, risking either noise (operator dismisses hygiene as unhelpful) or silent misses. **Schema-coordination is cut to follow-up Spec 370b**; Spec 370 ships only the two well-defined scans built on existing structural fields (`valid-until:`, `Dependencies:`, dependency `Status:`).

## Idempotency rules

Running `/matrix` twice in succession MUST NOT re-surface a candidate the operator just deprecated or deferred:

- **Deprecation idempotency**: filter out specs whose `Status:` is already `deprecated`. (Trivial — once deprecated, the spec is no longer in the active draft pool.)
- **Deferral idempotency**: filter out specs whose Revision Log contains a `Deferred via /matrix hygiene pass` entry within the last 30 days. The 30-day window prevents re-surfacing while still allowing the candidate to return if the deferral becomes stale (e.g., the named dependency moved to deprecated rather than reactivating).

## Overflow handling

If the combined candidate count across both scans exceeds 10, /matrix presents a **summary count line first** before the full candidate inventory:

```
Hygiene Pass: <N> deprecation candidates, <M> deferral candidates — review which?
```

The operator picks a category (or `both`, or `skip`) before facing the full inventory. This absorbs the CXO concern from /consensus 370 round 1 (cognitive load on candidate count when the backlog has accumulated hygiene debt over multiple matrix-skipped sessions).

## Disposition choreography

### Deprecate

For each candidate the operator chooses to deprecate:

1. Update spec frontmatter `Status: deprecated` and add `Closed: <today>`.
2. Append Revision Log entry: `YYYY-MM-DD: Deprecated via /matrix hygiene pass — <reason>.` Reason includes the two trigger signals (e.g., `valid-until past 2025-12-15 AND rank 42 for 47 days`).
3. Update `docs/specs/README.md` row to `deprecated`.
4. Update `docs/backlog.md` row marker to `✅ deprecated`.
5. Append CHANGELOG entry: `- YYYY-MM-DD: Deprecated Spec NNN via /matrix hygiene pass — <one-line reason>.`

### Defer

For each candidate the operator chooses to defer:

1. **Prompt for re-activation trigger.** The default template is `<dependency-spec-id> closes`. The operator can accept the default, edit it, or provide a free-form trigger.
2. **Skip-on-empty default**: if the operator provides empty input or declines to specify a trigger, that candidate's deferral is **skipped** for this batch (other candidates still apply normally). This is operator-discipline framing — the markdown command body cannot hard-gate empty input, but the skip-on-empty default keeps the convention enforceable in practice.
3. On non-empty trigger: append Revision Log entry: `YYYY-MM-DD: Deferred via /matrix hygiene pass — <reason>. Re-activation trigger: <trigger>.`
4. Update `docs/backlog.md` row note column with `(deferred — re-activate when <trigger>)`.
5. **Status stays `draft`** — deferral is timing-driven, not design-driven. The spec design remains valid; only the moment is wrong.

### Re-activation trigger templates

Common templates the operator can adapt at the deferral prompt:

- `<dependency-spec-id> closes` (default — dependency-anchor case)
- `<dependency-spec-id> reactivated` (dependency was deferred; this defers transitively)
- `Lane B project actively under development` (defer until a real Lane B consumer exists)
- `≥30 records in <data-source>.jsonl` (defer until empirical data justifies the design)
- `2nd FORGE-tracked project actively used` (defer cross-project work until cross-project usage is real)
- `Quarterly review` (defer to next /evolve cycle)

## Skip-cleanly default

`skip` is rank `1` in the Hygiene Pass Choice Block. Operators running `/matrix` purely for rank refresh / sprint planning continue to the exit-gate without engaging hygiene. Hygiene candidates surface as informational at every /matrix run; the operator opts in to actually apply.

## Operator engagement signal (per /implement directive 3)

`/close` captures hygiene-step engagement (apply-rate vs skip-rate per category) into `docs/sessions/signals.md` to feed the next `/evolve` cycle. If reflexive-skip dominates (e.g., > 80% skip across 5 /matrix runs), revisit MT's "name only, no apply" reframe (recorded as deferred design alternative — see Spec 370 Scope § Out of scope).

## Cross-edit invariant — sentinel block ↔ canonical doc

**Warning to future maintainers**: edits to the hygiene-pass scan rules require simultaneous re-sync of all 4 mirrored sentinel regions (`.forge/commands/matrix.md`, `.claude/commands/matrix.md`, `template/.forge/commands/matrix.md`, `template/.claude/commands/matrix.md`). A maintainer who edits the canonical block in this guide without re-running `scripts/spec-370-sync-matrix-hygiene.sh` will silently push divergent scan rules into the four mirrors — the prose remains in sync with one mirror but drifts from the other three.

**Mitigation today (doc-only)**: any change to the hygiene-pass scan rules requires:

1. Update the canonical sentinel block below.
2. Run `bash scripts/spec-370-sync-matrix-hygiene.sh` to propagate to all 4 mirrors.
3. Verify byte-identity via `bash scripts/spec-370-sync-matrix-hygiene.sh --check` (AC 7).
4. If a new scan rule is added, also extend the regression test fixtures at `.forge/bin/tests/test-spec-370-hygiene.sh`.

**Future hardening**: Spec 367 (CI parity gate for spec-integrity sentinel regions) extends the same automated md5sum byte-parity assertion to the spec-370 sentinel set. Spec 367 must follow Spec 370 /implement.

## Scope-coordination follow-up — Spec 370b (deferred)

The schema-coordination scan (detect drafts whose `Implementation Summary → Changed files` overlap with another draft's instrumentation file) was cut from Spec 370 at /revise 2026-04-29 round-1. Detection rule under-specified; deferred until detection rules can be made concrete OR a new manual schema-coordination opportunity grounds rule-design empirically. Tracked as **Spec 370b**.

---

### Canonical sentinel block (do not edit without re-syncing 4 mirrors)

```
# >>> spec-370 hygiene-pass
HYGIENE PASS — Two scans for backlog hygiene. Run after rank/score refresh and Step 12a pre-flight, before Step 13 exit-gate. Skip silently if neither scan surfaces candidates.

1. **Deprecation candidates scan**: For each `Status: draft` spec, qualify as a deprecation candidate when **both** signals hold:
   - `valid-until:` in frontmatter is populated AND past today (Spec 363 detector).
   - Backlog row rank has been ≥ 30 for ≥ 30 days (bottom-of-backlog dwell).
   Both signals required to avoid false positives on actively-revised drafts.

2. **Deferral candidates scan**: For each `Status: draft` spec, read `Dependencies:` field. If any named dependency spec's `Status:` is `deferred` or `deprecated` (verified by reading the dependency spec file directly), qualify as a deferral candidate. Inferred re-activation trigger: `<dependency-spec-id> closes` (operator can override).

3. **Idempotency filter**: Exclude:
   - Specs already `Status: deprecated` (deprecation scan).
   - Specs whose Revision Log contains `Deferred via /matrix hygiene pass` within last 30 days (deferral scan).

4. **Overflow handling**: If combined candidate count > 10, emit a summary count line first ("Hygiene Pass: N deprecation, M deferral candidates — review which?") so operator picks a category (or `both`, or `skip`) before facing the full inventory.

5. **Choice Block**: Emit candidates with one row per candidate (max 10 per category, paginated). Operator chooses: `apply all` / `pick <indices>` / `skip` / `view detail <index>`. `skip` is rank 1 by default — operators running /matrix purely for rank refresh continue to the exit-gate.

6. **Disposition (deprecate)**: update spec frontmatter `Status: deprecated` + `Closed: <today>`, append Revision Log "YYYY-MM-DD: Deprecated via /matrix hygiene pass — <reason>." Update README.md status row, backlog.md row marker → ✅ deprecated, append CHANGELOG entry.

7. **Disposition (defer)**: prompt for re-activation trigger; **skip-on-empty default** — if operator provides empty input or declines, that candidate's deferral is skipped (other candidates still apply). On non-empty trigger: append Revision Log "YYYY-MM-DD: Deferred via /matrix hygiene pass — <reason>. Re-activation trigger: <trigger>." Update backlog row note. Status stays `draft`.

8. **Engagement signal**: `/close` captures apply-rate vs skip-rate per category to `docs/sessions/signals.md` for next /evolve cycle.

See: docs/process-kit/backlog-hygiene-guide.md — canonical source.
# <<< spec-370 hygiene-pass
```
