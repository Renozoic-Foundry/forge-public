# Choice-Block Data Schema (Spec 347)

Last updated: 2026-04-27 (Spec 347 Phase 1)

This doc defines the **typed YAML data schema** for choice blocks. Command bodies that adopt the canonical emitter declare choice blocks as fenced YAML data; the renderer protocol (`choice-block-renderer-protocol.md`) describes how that data is rendered into the operator-visible markdown table.

This is one of three companion docs introduced by Spec 347:

- `choice-block-schema.md` (this doc) — data shape
- `choice-block-preconditions.md` — closed vocabulary of named preconditions
- `choice-block-renderer-protocol.md` — emit-time agent protocol

The rendered output remains compatible with Spec 320 v2.0 (column order: `# | Rank | Action | Rationale | What happens`). Operators see no behavior change on the visible interface — only the *source representation* in command files changes.

## Fenced-block syntax

The choice block lives in a markdown code fence labeled `choice-block`:

````markdown
```choice-block
title: <optional one-line title; default omitted>
multi_block: <serialized | discriminated | none>  # optional; default 'none'
discriminator: <single uppercase letter; required when multi_block: discriminated>
rows:
  - key: <operator keyword>
    rationale: <≤80 chars or "—">
    what_happens: <one-line consequence description>
    rank: <"1" | "2" | "3" | "—">
    precondition: <vocabulary name; optional — omitted = always emit>
  - key: ...
```
````

The fence label `choice-block` is what makes Check 6 in `test-choice-block-conventions.sh` recognize the block.

## Top-level fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | optional | Short label shown above the rendered table. Default: omitted (no title). |
| `multi_block` | enum: `serialized` / `discriminated` / `none` | optional | If the host file emits >1 choice block per agent message, this declares the disambiguation mode (per Spec 320 Req 5). Default: `none`. |
| `discriminator` | single uppercase letter | required when `multi_block: discriminated` | The letter used as row prefix (e.g., `A` → rows labeled `A1`, `A2`, …). |
| `rows` | list of row objects | required | The choice-block rows. MUST contain ≥1 row whose `precondition` is omitted (always-emit), so the rendered block is never empty after precondition filtering. |

## Row fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | required | The operator keyword. Lowercase, no spaces (use hyphens). Rendered in backticks. |
| `rationale` | string ≤80 chars | required | One short clause explaining *why* this option is ranked where it is. Use `"—"` if it would echo the Action label. |
| `what_happens` | string | required | One-line description of the consequence (rendered as the final column). |
| `rank` | string | required | Recommendation order: `"1"` = top recommendation; `"2"` = secondary; ...; `"—"` = available but not recommended. Ties allowed (multiple rows at `"1"`). |
| `precondition` | vocabulary name | optional | Name from `choice-block-preconditions.md`. Omitted = always-emit. Renderer evaluates the named precondition; the row is emitted only if it evaluates true. |

## Precondition values

The `precondition` field MUST reference a name listed in `choice-block-preconditions.md`. Free-form expressions are **not** supported (see Spec 347 Constraints — "MUST NOT introduce a runtime expression parser"). The closed vocabulary makes precondition evaluation deterministic and operator-readable.

Examples:

```yaml
precondition: implemented_specs_count_gt_zero    # row emitted when ≥1 spec is `implemented`
precondition: backlog_has_draft_specs            # row emitted when ≥1 draft spec exists
precondition: today_session_log_unsynthesized    # row emitted when session log has unsynthesized entries
# (omitted)                                       # always emit
```

## Worked example — /close exit choice block

Pre-Spec 347 form (Spec 320 v2.0 markdown):

```markdown
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `implement` | Top-of-backlog ready; clean transition | Start /implement next |
> | **2** | 2 | `close NNN` | Drain remaining implemented queue | Close another implemented spec |
> | **3** | — | `brainstorm` | Use when backlog is empty or stale | Generate new spec recommendations |
> | **4** | — | `stop` | Downgraded if today's session log has unsynthesized entries | End session |
```

Spec 347 form (canonical YAML data):

````markdown
```choice-block
title: Pick next
rows:
  - key: implement
    rationale: Top-of-backlog ready; clean transition
    what_happens: Start /implement next (highest-ranked draft)
    rank: "1"
  - key: close NNN
    rationale: Drain remaining implemented queue
    what_happens: Close another implemented spec (type spec number)
    rank: "2"
    precondition: implemented_specs_count_gt_zero
  - key: brainstorm
    rationale: Use when backlog is empty or stale
    what_happens: Generate new spec recommendations
    rank: "—"
    precondition: backlog_has_no_draft_specs
  - key: stop
    rationale: Downgraded if today's session log has unsynthesized entries
    what_happens: End session
    rank: "—"
```
````

The renderer (per `choice-block-renderer-protocol.md`) reads this block, evaluates each row's precondition against current session state, and emits the v2.0 markdown table containing only true-precondition rows in rank order.

## Rendered output guarantee

The renderer's output MUST be byte-identical (modulo trailing newline) to a hand-authored Spec 320 v2.0 markdown table for the same true-precondition row set. This guarantees:

- Operator-visible interface stability across the migration.
- Existing tools that scrape choice blocks (e.g., session-log scrapers, telemetry) continue to work unchanged.
- Mirror-parity tests can compare rendered outputs even if source representations differ.

## Coexistence with Spec 320 v2.0

Phase 1 ships only `/close` Step 9 as a fenced YAML block. The other 7 commands (now, evolve, consensus, implement, parallel, spec, session) continue to use literal markdown tables under Spec 320 v2.0. The static convention checks (1–4) in `test-choice-block-conventions.sh` continue to fire on those un-migrated files. Check 6 fires only on files containing a `choice-block` fenced block.

**Mixed-form files are permitted during Phase 1 partial migration.** A file like `/close` has 5+ choice blocks; Phase 1 migrates only one (Step 9) to fenced YAML. The remaining 4 markdown blocks coexist in the same file. Each block is independently single-form: a fenced YAML block is fully Spec 347; a markdown block is fully Spec 320 v2.0. Operators reading the source see both representations side-by-side during Phase 1.

**Phase 2 ends mixed-form.** When Phase 2 migrates a command's remaining choice blocks, the file converges to single-form (all fenced YAML). At that point, the no-mix rule activates and Check 6 fails on any file still containing a Spec 320 v2.0 markdown table.

## Schema validation

Check 6 in `scripts/tests/test-choice-block-conventions.sh` validates files containing `choice-block` fenced blocks for:

1. YAML parses without error.
2. All required fields are present (`key`, `rationale`, `what_happens`, `rank` per row).
3. Every `precondition` value matches a name listed in `choice-block-preconditions.md`.
4. ≥1 row is always-emit (no `precondition` field) — at any rank — so the rendered block is never empty after precondition filtering.
5. Each `rationale` is ≤80 characters.
6. `multi_block: discriminated` requires a `discriminator` field of length 1 (single uppercase letter).
7. `key` values within a single block are unique.

Renderer-time validation (the agent's emit protocol) is documented separately in `choice-block-renderer-protocol.md`. Schema validation is necessary but not sufficient — see that doc for emission-time checks.

## Phase 2 trigger

Per Spec 347 Out-of-scope, the remaining 7 commands migrate in Phase 2. The trigger condition for Phase 2 (recorded here so operators have a forcing function rather than indefinite "later"):

> **Phase 2 trigger**: Phase 2 begins when ANY of the following hold:
> - `/close` has emitted ≥10 fenced-YAML choice blocks across ≥5 distinct sessions without a renderer-drift defect being filed.
> - A defect of the same class as the /close 320 chat-surfaced defect (an emitted row whose precondition was unmet) recurs in any non-migrated command.
> - 90 days have elapsed since Spec 347 closed without either of the above triggering — reverts to /evolve cycle review for "still deferred?" decision.

This mirrors ADR-320's deferral-with-trigger pattern.

## Glossary

- **Always-emit row**: a row with no `precondition` field. Emitted unconditionally.
- **Conditional row**: a row with a `precondition` field. Emitted only when the named precondition evaluates true at emit time.
- **Rendered output**: the operator-visible markdown table the renderer produces from the schema.
- **Source representation**: the fenced YAML block in the command file (this schema).

## See also

- [Spec 347](../specs/347-canonical-choice-block-emitter.md) — this spec
- [docs/decisions/ADR-347](../decisions/ADR-347-canonical-choice-block-emitter.md) — design rationale (cross-linked from ADR-320)
- [docs/process-kit/choice-block-preconditions.md](choice-block-preconditions.md) — closed precondition vocabulary
- [docs/process-kit/choice-block-renderer-protocol.md](choice-block-renderer-protocol.md) — emit-time agent protocol
- [docs/process-kit/implementation-patterns.md § Choice Blocks](implementation-patterns.md) — Spec 320 v2.0 prose convention (still in force for un-migrated commands)
