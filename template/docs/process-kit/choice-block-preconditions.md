# Choice-Block Precondition Vocabulary (Spec 347)

Last updated: 2026-04-27 (Spec 347 Phase 1)

This is the **closed vocabulary** of named preconditions that may appear in a `precondition:` field of a choice-block YAML row (per `choice-block-schema.md`). Each name has a deterministic evaluation rule that two agents reading the same session state MUST resolve to the same boolean.

Per Spec 347 Constraints: **MUST NOT introduce a runtime expression parser.** New names require a spec extension that adds a row to this doc. There is no inline / provisional / escape syntax for ad-hoc preconditions in the source representation. **Escape hatch for emergency cases**: a row whose precondition cannot be expressed in this vocabulary MAY be authored with `precondition:` omitted (always-emit) and a comment noting the gap; the gap is then filed as a vocabulary-extension spec at the next /matrix.

## Initial vocabulary (Phase 1)

The names below are operator-extensible via spec. Phase 1 ships these 6 — chosen to cover the demonstrated `/close` defect plus the patterns in the 7 deferred commands so Phase 2 doesn't immediately need vocabulary updates.

### `implemented_specs_count_gt_zero`

- **Description**: True when ≥1 spec in `docs/specs/README.md` has status `implemented`. Used to gate `close NNN` / `close all` rows on closing-queue presence.
- **Evaluation rule**: Read `docs/specs/README.md`. Count occurrences of `status: implemented` (case-sensitive). If count > 0, return true; else false.
- **Bash one-liner**: `[[ "$(grep -c '^- \[.*status: implemented' docs/specs/README.md 2>/dev/null || echo 0)" -gt 0 ]]`
- **Example contexts**:
  - True: README.md contains `- [336-...](./336-...) - status: implemented` for ≥1 spec.
  - False: all spec rows show `closed`, `draft`, or `deferred`.
- **Used by**: `/close` Step 9 (`close NNN` row), `/parallel` post-merge action (`close all` row).

### `backlog_has_draft_specs`

- **Description**: True when ≥1 spec in `docs/backlog.md` has status `draft` (i.e., a draft spec exists in the ranked backlog table, excluding deferred or closed). Used to gate `implement next` rows.
- **Evaluation rule**: Read `docs/backlog.md` ranked-backlog section. Count rows whose status column starts with `draft` (case-insensitive). If count > 0, return true; else false.
- **Bash one-liner**: `[[ "$(grep -cE '\| draft\b|\| draft \(' docs/backlog.md 2>/dev/null || echo 0)" -gt 0 ]]`
- **Example contexts**:
  - True: backlog has `| 1 | 347 | ... | draft (...)` rows.
  - False: every backlog row is closed, deferred, or in-progress.
- **Used by**: `/close` Step 9 (`implement` row), `/now` Step 13 dynamic block, `/session` next-action (`/implement next` row).

### `backlog_has_no_draft_specs`

- **Description**: Negation of `backlog_has_draft_specs`. True when the backlog has zero draft rows. Used to gate `brainstorm` rows that are only useful when the backlog needs replenishing.
- **Evaluation rule**: Inverse of `backlog_has_draft_specs`.
- **Bash one-liner**: `[[ "$(grep -cE '\| draft\b|\| draft \(' docs/backlog.md 2>/dev/null || echo 0)" -eq 0 ]]`
- **Used by**: `/close` Step 9 (`brainstorm` row).

### `today_session_log_unsynthesized`

- **Description**: True when today's session log (`docs/sessions/YYYY-MM-DD-NNN.md`) has ≥1 raw `### Spec NNN — started` or `### Spec NNN — closed` entry **AND** the `## Summary` section is unpopulated (heading absent OR present with empty/whitespace/placeholder body, per Spec 320 Req 4 positive definition). This is the **session-data safety rule** trigger.
- **Evaluation rule**: Use the same logic as `evaluate_safety_rule()` in `scripts/tests/test-choice-block-conventions.sh`: condition (a) ≥1 `^### Spec [0-9]+ — (started|closed)` heading AND condition (b) Summary body absent or contains only whitespace / placeholder text from the documented placeholder list.
- **Bash invocation**: `bash scripts/tests/test-choice-block-conventions.sh --evaluate-safety-rule docs/sessions/$(date +%Y-%m-%d)-*.md` (returns "fires" or "does-not-fire" on stdout).
- **Example contexts**:
  - True (rule fires): session log has `### Spec 347 — started` heading + `## Summary` absent or contains only `<summary goes here>`.
  - False: session log has `## Summary` populated with ≥1 non-placeholder line.
- **Used by**: `/close` Step 9 (insert `session` at rank 1, downgrade `stop`), `/evolve` exit gate, `/parallel` post-merge action, `/implement` exit, `/now` Step 13.

### `consensus_review_true_for_current_spec`

- **Description**: True when the spec being closed/implemented carries `Consensus-Review: true` in its frontmatter and `/consensus` has not yet recorded a round-2 acceptance. Used to gate `consensus` review rows on /implement and /close.
- **Evaluation rule**: Read the active spec file (the spec referenced by the current `/implement` or `/close` invocation). Check frontmatter for `^- Consensus-Review: true$`. Then check the spec's revision log for the most recent `/consensus round` entry: if the latest round shows `accept` / `aligned-approve` / `mild divergence with operator-approved proceed`, return false (consensus complete); else return true (consensus pending).
- **Bash invocation**: `bash scripts/tests/test-choice-block-conventions.sh --evaluate-consensus-pending <spec-file>` (returns "pending" or "complete").
- **Example contexts**:
  - True: spec has `Consensus-Review: true` and no /consensus round logged in revision log.
  - False: spec lacks `Consensus-Review:`, or has it set to false/auto, or has a round-2 acceptance recorded.
- **Used by**: `/close` Review Brief Step 2e (consensus option), `/implement` exit (Step 9e).

### `dirty_working_tree`

- **Description**: True when `git status --porcelain` returns non-empty (uncommitted changes present). Used to gate `commit` rows on /implement, /close, /now.
- **Evaluation rule**: `git status --porcelain` output non-empty. Excludes untracked files in `.gitignore`.
- **Bash one-liner**: `[[ -n "$(git status --porcelain 2>/dev/null)" ]]`
- **Example contexts**:
  - True: working tree has staged or unstaged changes.
  - False: `git status` is clean.
- **Used by**: `/close` finalization (commit confirmation), `/implement` post-implementation (commit prompt), `/now` Step 13 (insert `commit` at rank 2 if dirty).

## Adding a new precondition

A new named precondition requires a spec extension. Process:

1. **Identify the gap**: a command body wants to gate a row on a condition not in this vocabulary. The author SHOULD first check whether an existing precondition can cover the case (renaming or repurposing is preferable to fragmentation).
2. **Author a small-change spec** (`/spec`) with title "Vocabulary extension: <name>" and scope = "Add <name> to choice-block-preconditions.md with deterministic evaluation rule." Include: the use case (which command, which row), the evaluation rule, the bash one-liner, ≥2 example contexts.
3. **Run the spec lifecycle** (/spec → /implement → /close). The doc edit is mechanical; bulk of the spec is the rule and example design.
4. **Vocabulary fragmentation guard**: at /matrix time, if the new name is semantically similar to an existing one (e.g., `has_drafts` vs. `backlog_has_draft_specs`), the matrix maintainer SHOULD consolidate. Vocabulary doc is single source of truth; renames are tracked in revision log.

## Naming conventions

- Names are `snake_case`, lowercase only.
- Predicates are positive booleans (e.g., `implemented_specs_count_gt_zero`, not `no_implemented_specs`). Use a separate negation predicate (`backlog_has_no_draft_specs`) when both polarities are needed by different rows.
- Comparisons in names use `_gt_`, `_lt_`, `_eq_`, `_gte_`, `_lte_` suffixes for explicit thresholds (`implemented_specs_count_gt_zero`).
- Names referencing files use the file's role, not its path (`today_session_log_unsynthesized`, not `docs_sessions_yyyy_mm_dd_nnn_md_unsynthesized`).
- Names are stable: deprecating a name requires a migration spec that renames usages atomically.

## Evaluation determinism

A precondition MUST evaluate identically given the same session state. The evaluation rule is the contract; the bash one-liner is a reference implementation. If the rule and the one-liner disagree for some session state, the rule wins (file an errata spec to fix the one-liner).

The renderer protocol (`choice-block-renderer-protocol.md`) documents how the agent computes preconditions at emission time. The bash one-liners in this doc are the reference implementations the agent SHOULD invoke (not paraphrase).

## See also

- [Spec 347](../specs/347-canonical-choice-block-emitter.md) — this spec
- [docs/process-kit/choice-block-schema.md](choice-block-schema.md) — YAML schema referencing these names
- [docs/process-kit/choice-block-renderer-protocol.md](choice-block-renderer-protocol.md) — how the renderer computes precondition values
- [docs/process-kit/implementation-patterns.md § Session-data safety rule](implementation-patterns.md) — Spec 320 Req 4 (the rule `today_session_log_unsynthesized` operationalizes)
