# Lane B Audit Conventions

This doc is the canonical reference for FORGE's Lane B compliance audit conventions — the additional fields, counter-sign rules, and provenance anchors that activate when a project carries `docs/compliance/profile.yaml`.

Lane A projects (no compliance profile) do not use these conventions. Lane B is opt-in via the presence of the compliance profile.

## Activation

A project is Lane B when `docs/compliance/profile.yaml` is present. The profile may declare additional gate rules, evidence requirements, and identity bindings; FORGE commands check for the profile's existence as the Lane A/B switch.

When the profile is present, several FORGE commands extend their default behavior with additional fields and gates. This doc collects those Lane B-specific behaviors.

## Activity log fields — consensus-gate-check (Spec 395 Req 3)

`/implement` Step 0d emits a `consensus-gate-check` event for every spec it processes. Lane A and Lane B differ in the field set:

**Lane A** (no compliance profile):

```json
{
  "timestamp": "<ISO 8601>",
  "event_type": "consensus-gate-check",
  "spec_id": "NNN",
  "decision": "PASS|FAIL|SKIP",
  "gate_path": "SHA|exempt|exempt-trivial-doc|skip-not-qualifying|skip-hotfix|missing",
  "agent_id": "<id>"
}
```

**Lane B** (compliance profile present): the Lane A fields plus:

| Field | Source | When present | Purpose |
|-------|--------|--------------|---------|
| `operator_identity` | `forge.identity` config | Always | Identifies the operator who initiated `/implement` |
| `spec_file_sha` | `sha256sum <spec_file>` | Always | Anchors the exact spec content reviewed at the gate |
| `consensus_close_sha` | Spec frontmatter | When `gate_path=SHA` | Provenance — the consensus round that closed |
| `consensus_exempt_reason` | Spec frontmatter | When `gate_path=exempt` (any flavor) | The 30+ char reason the operator recorded |
| `reviewed_by_identity` | Parsed from `Consensus-Exempt:` value | When counter-sign rule applies (see below) | Second-operator forensic anchor |

The full Lane B record:

```json
{
  "timestamp": "2026-05-09T04:58:45Z",
  "event_type": "consensus-gate-check",
  "spec_id": "395",
  "decision": "PASS",
  "gate_path": "SHA",
  "agent_id": "operator-1",
  "operator_identity": "alice@example.com",
  "spec_file_sha": "a3f5...c2e1",
  "consensus_close_sha": "2de5ec4265023d2ef7cc19791c1f5fa68bde73d0"
}
```

The Lane B fields support Spec 052 immutability sealing — Spec 052 anchors a hash chain across activity-log events, so the additional fields ensure the chain captures *who* operated the gate and *what content* the gate saw, not just *what decision*.

## Counter-sign rule (Spec 395 Req 8)

For Lane B projects, the `Consensus-Exempt: <reason>` bypass is INSUFFICIENT on its own when ALL hold:

- Spec is `consensus-required` per Spec 395 Req 1
- `BV ≥ 4 AND R ≥ 3` (high-stakes safety-relevant range)

In this range, the exemption frontmatter MUST take the form:

```
- Consensus-Exempt: <reason ≥ 30 chars> [reviewed-by: <second-operator-identity>]
```

`/implement` Step 0d parses the `[reviewed-by: ...]` token. If absent and the conditions hold, the gate FAILs:

```
GATE [final-draft-consensus]: FAIL — Lane B Consensus-Exempt requires
[reviewed-by: <identity>] counter-sign for BV≥4 + R≥3 specs
(forensic anchor; prevents audit-laundering composition with vet-pending
+ Spec 052 sealing).
```

The activity log records BOTH `operator_identity` (the spec author who set the exemption) AND `reviewed_by_identity` (the counter-signer). Spec 052 immutability sealing then anchors both signatures.

### Why counter-sign

The composition `Consensus-Exempt + vet-pending status + Spec 052 immutability sealing` would, without a counter-sign rule, allow audit-laundering on Lane B:

1. Operator marks a draft `vet-pending` (legitimate; backfill list)
2. Operator sets `Consensus-Exempt: <reason>` to bypass the gate
3. Spec proceeds through `/implement` and `/close` normally
4. Spec 052 anchors the sealed activity chain

The result: an under-vetted high-stakes spec carries the full audit weight of a properly-reviewed one, with no externally-verifiable distinction. The counter-sign requirement breaks this composition by forcing a second human into the loop on high-stakes exemptions.

### Scope of the rule

| BV | R | Lane | Counter-sign required? |
|----|---|------|------------------------|
| 1-3 | any | A | No (Lane A trust root: 30-char reason) |
| 4-5 | 1-2 | A | No (Lane A trust root) |
| 4-5 | 3-5 | A | No (Lane A trust root) |
| 1-3 | any | B | No (low-stakes range) |
| 4-5 | 1-2 | B | No (high BV but low risk; outside the rule's range) |
| **4-5** | **3-5** | **B** | **Yes** (high-stakes safety-relevant range) |

The rule deliberately scopes to the high-stakes range. Tightening to all Lane B specs would create exemption friction for legitimate low-risk Lane B work; loosening to only R≥4 would miss BV-driven risk. The BV≥4 AND R≥3 compound is the calibrated threshold from Spec 395 R1 CISO concern.

## Reviewer identity provenance

`reviewed_by_identity` is recorded as a free-text identifier (e.g., `alice-sec`, `bob@example.com`). Lane B projects with stricter audit requirements may add identity-validation gates that check the `[reviewed-by: ...]` value against a project-specific identity registry; FORGE itself does not enforce a specific identity scheme.

The intent is that the reviewer can be identified post-hoc during an audit — exact format is project-policy.

## Cross-references

- [consensus-protocol.md](consensus-protocol.md) — the convention this doc extends
- [final-draft-consensus-guide.md](final-draft-consensus-guide.md) — Lane B addendum at the operator level
- Spec 052 — Activity-log immutability sealing
- Spec 395 — Final-draft consensus convention (Req 3 + Req 8)
- Spec 134 — atomic_checkout activity-log primitive
