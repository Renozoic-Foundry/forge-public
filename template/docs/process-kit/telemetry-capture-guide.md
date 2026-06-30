<!-- Last updated: 2026-06-23 -->
# Framework: FORGE
# Telemetry capture guide (Spec 495)

FORGE's process telemetry must be **un-loseable**: every capture has a **reader** and a **gate**,
or it rots silently. This is the lesson of Spec 258 — a write (`consensus_reviews`) shipped with no
schema field, no reader, and no validator, so capture lapsed after 2026-05-15 and nothing noticed.
This guide is the read-side contract: the canonical field names, where they live, and how the
30-day acceptance rate is computed.

## Surfaces

| Surface | Path | Written by | Durable? |
|---|---|---|---|
| Consensus acceptance | session sidecar `consensus_reviews[]` | `/close` (wired by Spec 497) | yes (tracked `docs/sessions/*.json`) |
| Security-gate verdicts | `.forge/state/security-gate.jsonl` | `.forge/lib/telemetry.sh record-security-gate` | yes — **tracked via `!`-negation** in `.gitignore` (the rest of `.forge/state/*` is gitignored) |
| Gate outcomes | session sidecar `gate_outcomes[]` | `/session` + `/close` | yes |

**Why the security ledger needs the negation:** `.forge/state/*` is gitignored. A verdict ledger
left there silently fails to survive a clean clone — defeating "un-loseable." `git check-ignore
.forge/state/security-gate.jsonl` must return **no match** (the binding durability gate; verified by
`scripts/validate-telemetry.sh` and the Spec 495 fixture).

## Canonical field names

- **`consensus_reviews`** (array) — the canonical name (what the `/close` writer emits). Each item:
  `spec_id` (required), `operator_decision` (required), and optional `timestamp`, `round`, `roles`,
  `recommendations`, `tally`, `divergence`. Schema: `.forge/templates/session-handoff-schema.json`.
- **`consensus_outcomes`** — accepted **alias** (the Spec 258 prose name) so historical sidecars
  validate. New writers emit `consensus_reviews`.
- **`operator_decision`** values — the acceptance-rate classifier buckets on the leading token:
  `accepted` | `modified` (accepted-with-revisions) | `rejected` | other (deferred/procedural).

## Acceptance rate (read side — wired by Spec 497)

```
acceptance_rate = accepted / (accepted + modified + rejected)   over a rolling 30-day window
```
Source: `consensus_reviews[].operator_decision` across `docs/sessions/*.json`. Surfaced by **`/now`**
and **`/evolve` F4** (Spec 258 AC#5, delivered in Spec 497). The window date is the sidecar `date`.

## Security-gate ledger shape

Each line of `.forge/state/security-gate.jsonl`:
```json
{"timestamp":"<ISO8601>","gate":"<name>","result":"PASS|FAIL","exit_code":"<n>","sha":"<HEAD>"}
```
The verdict is derived from the gate's **own exit code** by the caller — never from an
operator-writable field (CISO trust boundary).

**Telemetry, not authority.** This ledger is append-by-convention and is **not tamper-evident**
(a row can be hand-edited; the per-row `sha` is unsigned). It is fine as telemetry. It MUST NOT be
promoted to an authority for any "approved/verified" claim without a separate hash-chain or
signed-verdict mechanism. A future reader treating a PASS row as an authorization signal re-opens
this boundary.

## Validator + anti-dormancy

`scripts/validate-telemetry.sh` (advisory) checks (1) ledger durability via `git check-ignore` and
(2) closed-spec sidecars that reference `/consensus` but recorded no decision telemetry (the 258
lapse signature). It runs **advisory** (warn, exit 0) until burn-in. **Anti-dormancy trigger
(Spec 495 Req 7):** the advisory→strict flip and the Spec 497 reader wiring are due by the first
`/evolve` after Spec 497 closes (or 30 days after Spec 495 closes, whichever is first); `/now`
surfaces "telemetry validator still advisory — strict flip due" past that date.

## Reuse, not proliferation

The helper follows the `score-audit.sh` advisory pattern (Spec 368) — it does **not** add a fourth
parallel telemetry sink. Consensus decisions live in the session sidecar (read by `/now`/`/evolve`);
the security ledger is the one net-new durable surface (justified: the auth-lint verdict was
previously written only to gitignored `tmp/evidence/`). `events.py` reuse is valid for non-durable
event records, but note its `append_event` is **not** advisory-exit-0 — wrap it if used for capture.
