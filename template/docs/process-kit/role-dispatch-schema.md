# Role-Dispatch / Role-Acceptance Schema (Spec 305)

- Last verified: 2026-06-15
- Owner: FORGE process-kit
- Related: Spec 305 (role-value instrumentation), Spec 368 (score-audit calibration loop), Spec 316 / ADR-316 (`.forge/metrics/` removal)

## What this is

Spec 305 instruments FORGE's role dispatch so every role invocation becomes a measurable
event. Two **additive record kinds** are appended to the **shared** score-audit sink
`.forge/state/score-audit.jsonl` — the same file Spec 368 uses for `predicted`/`observed`
score-calibration records. Per Spec 368 Req 20 ("adjacent instrumentation streams share
storage, extend additively"), Spec 305 does **not** create a parallel `.jsonl` file; it adds
two new values of the existing top-level `kind` discriminator.

Records are written exclusively through the shared helper
`.forge/lib/score-audit.{sh,ps1}` via three subcommands:

| Subcommand | Writes | Fired by |
|------------|--------|----------|
| `record-dispatch <spec_id> <stage> <role> <recommendation> [confidence] [key_concern]` | one `role-dispatch` record | `/spec` Step 6b, `/implement` Step 2b+, `/close` Step 2d+, `/consensus` Step 3 |
| `record-acceptance <spec_id> <role> <accepted:true\|false\|null> [partial_note]` | one `role-acceptance` record | `/close` Step 2d+a (operator-acceptance capture) |
| `role-audit [--json]` | nothing (read-only rollup) | operator / `/evolve`, on demand |

## Discriminator

The sink is a heterogeneous JSONL log. Every record carries a top-level **`kind`** field
(NOT `record_type` — the helper has always discriminated on `kind`). Readers filter on it:

- `kind: "predicted"` / `kind: "observed"` — Spec 368 score calibration.
- `kind: "role-dispatch"` — Spec 305 (this doc).
- `kind: "role-acceptance"` — Spec 305 (this doc).

`role-audit` filters to `kind in (role-dispatch, role-acceptance)`. `bias-report`,
`read-records`, and `next-revise-round` ignore unrecognized kinds (and `next-revise-round`
explicitly requires `kind:"predicted"` so role records never pollute revise-round derivation —
Spec 305 DA Pass-2 finding 2).

## `role-dispatch` fields

| Field | Type | Notes |
|-------|------|-------|
| `schema_version` | int | `1` |
| `kind` | string | `"role-dispatch"` |
| `spec_id` | string | spec number (e.g. `"305"`), or a topic slug for freeform `/consensus` |
| `git_sha` | string | HEAD at write time (`unknown` if not a git repo) |
| `iso_ts` | string | UTC ISO-8601, from the shell (time-blindness mitigation) |
| `stage` | string | `spec \| implement \| close \| consensus` |
| `role` | string | role identifier (`DA`, `CTO`, `CISO`, `COO`, `CEfO`, `MT`, …) |
| `recommendation` | string | the role's verdict verbatim: `approve\|concern\|reject` (consensus) or `PROCEED\|REVISE\|BLOCK` (router/dispatch) or a validator-style `PASS\|CONDITIONAL_PASS\|FAIL` |
| `confidence` | string | optional (`HIGH\|MEDIUM\|LOW` or numeric); `""` when not provided |
| `key_concern` | string | optional free text; `_json_escape`d; `""` when none |

## `role-acceptance` fields

| Field | Type | Notes |
|-------|------|-------|
| `schema_version` | int | `1` |
| `kind` | string | `"role-acceptance"` |
| `spec_id` | string | spec number |
| `git_sha` | string | HEAD at write time |
| `iso_ts` | string | UTC ISO-8601 |
| `role` | string | role identifier |
| `accepted` | bool \| null | `true` (operator acted), `false` (consciously ignored), `null` (partial) |
| `partial_note` | string \| null | one-line note when `accepted` is `null`; else `null` |

**Latest-entry-wins (R7)**: acceptance is single-shot append, NOT a `corrects:`-pointer chain.
To answer "did the operator accept role X on spec Y", a reader takes the **latest**
`role-acceptance` record for `(spec_id, role)`. No reconstruction of amended states.

## Worked example

```jsonl
{"schema_version":1,"kind":"role-dispatch","spec_id":"305","git_sha":"73a8549c…","iso_ts":"2026-06-15T18:23:24Z","stage":"consensus","role":"DA","recommendation":"concern","confidence":"0.8","key_concern":"shared sink premise false"}
{"schema_version":1,"kind":"role-dispatch","spec_id":"305","git_sha":"73a8549c…","iso_ts":"2026-06-15T18:23:24Z","stage":"consensus","role":"CTO","recommendation":"approve","confidence":"","key_concern":"rotation risk"}
{"schema_version":1,"kind":"role-acceptance","spec_id":"305","git_sha":"73a8549c…","iso_ts":"2026-06-15T18:25:02Z","role":"DA","accepted":true,"partial_note":null}
{"schema_version":1,"kind":"role-acceptance","spec_id":"305","git_sha":"73a8549c…","iso_ts":"2026-06-15T18:25:02Z","role":"CTO","accepted":false,"partial_note":"ignored rotation note"}
```

`bash .forge/lib/score-audit.sh role-audit` over the above:

```
| Role | Dispatches | Acceptance% | Avg Concerns | Stage Distribution | Most Common Concern |
|------|-----------|-------------|--------------|--------------------|---------------------|
| CTO | 1 | 0% | 1.0 | consensus:1 | rotation risk |
| DA | 1 | 100% | 1.0 | consensus:1 | shared sink premise false |
```

## Git-tracking: gitignored local-only telemetry

`.forge/state/score-audit.jsonl` is **gitignored** — root `.gitignore` `.forge/state/*`
(line 21, no allowlist exception) and `template/.gitignore` line 54. Confirm with
`git check-ignore .forge/state/score-audit.jsonl` (returns the path = ignored).

This is deliberate and inherited from Spec 368: the sink is **local-only telemetry**. The file
persists on disk between sessions, so cross-session visibility holds **within a single clone**;
it does **not** propagate across clones/machines via git. Spec 305 makes no `.gitignore` change.

## Write semantics: best-effort, never blocks

The helper is advisory (Spec 368 contract): if `_ensure_log_dir` fails (read-only FS,
non-writable `.forge/state/`), `record-dispatch`/`record-acceptance` emit a WARN to stderr and
return 0 with no line written. The logging calls therefore NEVER block `/spec`, `/implement`,
`/close`, or `/consensus`. Spec 305 AC1/AC4 are verified on a writable sink (the normal case).

## Log rotation (tracked follow-up — not yet implemented)

The shared sink grows unbounded. Dispatch records fire far more frequently than Spec 368's
score records (one per role per lifecycle point), so the rotation threshold binds **sooner**
than score-only growth would (CTO consensus, Spec 305). **Planned policy** (deferred to a
tracked near-term follow-up; `_atomic_append` has no rotation hook to inherit):

- Rotate at ~10K lines by renaming `score-audit.jsonl` → `score-audit.1.jsonl`.
- `role-audit` and `bias-report` read the active file only; rolled files are cold archive.

This is a known residual risk (Spec 305 Verification Scope c-ii), surfaced here rather than
left silent.
