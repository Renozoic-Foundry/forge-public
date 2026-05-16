# Copier Gotchas — FORGE-Specific Empirical Findings

This doc captures Copier behaviors that have bitten FORGE in practice and the conventions we've adopted to avoid them. Each entry names the spec that established the convention so the empirical provenance is traceable.

## `when: false` strips keys from `.copier-answers.yml` (Spec 090, Spec 434)

**Behavior (Copier 9.14.0)**: A question declared with bare `when: false` in `copier.yml` is correctly suppressed from interactive prompting — but **Copier also strips it from `.copier-answers.yml` on persist, even when the value is supplied via `--data-file`**. The key never lands in the consumer's answers file.

**Why this matters**: any question that's meant to (a) never prompt interactively but (b) accept a non-default value from a baseline / consumer answers file will silently lose that value. Subsequent renders read the answers file, see the key is absent, and fall back to the question's `default:`. Downstream `validator:` predicates that read the value evaluate against `default` — typically `false` — and may emit false-positive failures.

**FORGE history**:
- **Spec 090** introduced the consent flag `accept_security_overrides` with bare `when: false`. Worked at first because no one was setting it from a baseline.
- **Spec 090 (later)** added the `forge_baseline_*` provenance keys also with bare `when: false`. Empirical test on Copier 9.14.0 caught the strip-on-persist behavior. Fixed via the v3.3 self-referential `when:` pattern (see `copier.yml` lines 310–318 for the in-file empirical-provenance comment block).
- **Spec 434** caught the same bug class on `accept_security_overrides` itself — the v3.3 fix was applied to siblings but missed on the consent flag. adc-rag failure 2026-05-15: operator accepted the stoke prompt, `copier update` still aborted.

**The convention — v3.3 self-referential `when:`**:

```yaml
# DON'T — Copier 9.14.0 strips this key from .copier-answers.yml on persist.
some_key:
  type: bool
  default: false
  when: false

# DO — self-referential evaluation persists the key when supplied via --data-file / answers.
some_key:
  type: bool
  default: false
  when: "{{ some_key|default(false) }}"
```

**Mechanics**:
- When the consumer's `.copier-answers.yml` (or `--data-file`) supplies `some_key: true`, the `when:` evaluates to `true` → the question is "active" → Copier persists it.
- When no value is supplied, `default(false)` makes `when:` evaluate `false` → suppressed identically to bare `when: false` → no prompt, no persisted entry. Behavior is preserved for the no-override case.
- For string keys, the convention is `when: "{{ some_key|default('') != '' }}"` (see `forge_baseline_name`, lines 319–322).

**Required for any new security-gated flag**: if you add a new flag that gates `validator:` predicates on other questions, use this pattern. Bare `when: false` is reserved for keys that genuinely never need to persist (rare). The `test_copier_yml_audit.py` static check (Spec 434 AC 7) enforces this on the canonical security-gated keys.

**Empirical Copier-version contract**: verified on Copier 9.14.0. Future Copier releases may change `when:`/answer-persistence semantics; the comment block at `copier.yml:310–318` is the canonical contract anchor. Re-verify after any Copier minor-version bump.

**Static-check limitation**: AC 7's audit-test catches literal `when: false` in `copier.yml`. It does NOT catch dynamic `when:` predicates (e.g., `when: "{{ some_other_var }}"`) that may runtime-evaluate to false — that class would need an integration test rendering against synthetic answers. Out-of-scope of the static audit; documented here for awareness.

## Bootstrap-path consent surface — Spec 437 consent gate

**Status (2026-05-15)**: the bootstrap-path gap noted as a known gap in Spec 434 was closed by Spec 437. Both `copier copy` (fresh bootstrap) and `copier update` invocations (including non-stoke direct CLI/CI invocations) now require an explicit runtime consent token when `accept_security_overrides: true` is supplied. A poisoned `.copier-answers.yml` cannot satisfy the gate.

**Threat model**: an attacker with write access to a downstream `.copier-answers.yml` (PR context, compromised clone) could otherwise pre-position `accept_security_overrides: true` + a crafted `test_command`/`lint_command`/`harness_command` value to achieve arbitrary command execution at the consumer's next `forge test`/`forge lint` invocation. The crafted command string would persist into the rendered output via Copier's answer-resolution → render pipeline.

**Mitigation (Spec 437 HYBRID gate)**:

1. **Primary gate — per-question `validator:` on `accept_security_overrides`** (in `copier.yml`). Refuses render when the flag is true and `accept_security_overrides_confirmed` is not also true. The refusal message displays the literal command strings for each non-default security-gated key (e.g., `test_command = rm -rf /`). Cannot be bypassed by `--skip-tasks` (validators are not tasks).

2. **Secondary gate — Python `_tasks:` hook** (`scripts/copier-hooks/forge_consent_gate.py`). Runs FIRST in `_tasks:`. Re-reads the destination's `.copier-answers.yml` at task time and refuses if the consent token is persisted there. Closes Req 1a (answers-file-supplied consent tokens are rejected). `accept_security_overrides_confirmed` is `secret: true` in `copier.yml` so legitimate CLI consent never persists to disk — presence of the key in the destination's answers file = poisoned source.

**Legitimate consent — single-invocation shape (Spec 437 Req 7)**:

```bash
# Fresh bootstrap with security overrides
copier copy gh:Renozoic-Foundry/forge-public my-project --trust \
  --data accept_security_overrides=true \
  --data accept_security_overrides_confirmed=true \
  --data 'test_command=./mvnw test'

# Subsequent updates (same form)
copier update --trust \
  --data accept_security_overrides_confirmed=true
```

The `--data accept_security_overrides_confirmed=true` flag MUST be on the operator's CLI command line at render time. It MUST NOT be persisted to `.copier-answers.yml` (Copier's `secret: true` mechanism prevents this for `copier copy`; the consent gate refuses any persisted instance).

**Documented bypass and threat-model boundary**:

- `--skip-tasks` bypasses the secondary gate (the primary validator still fires for the consent-absent case). The only residual gap under `--skip-tasks` is the poisoned-token-in-answers-file scenario; this is operator-explicit (CLI flag) and outside the spec's threat model.
- An attacker with write access to the operator's invocation (e.g., wrapper scripts, shell history) can inject `--data` flags. This is a separate threat class (operator-environment compromise) and is not addressed by this gate.

**References**:

- Spec 437 — Copier bootstrap-path consent surface for security overrides.
- ADR-028 § 2026-05-15 Amendment — Spec 437 (Copier bootstrap-path consent surface).
- `scripts/copier-hooks/forge_consent_gate.py` — secondary-gate Python hook.
- `copier.yml` near `accept_security_overrides:` — primary validator + `_tasks:` wiring.
- `.forge/tests/test_bootstrap_consent.py` — structural + hook-unit regression tests (13 tests).

## Consent-gate `copier update` old-worker rebuild — Specs 445 + 447

**Two layers, same defect class.** Spec 437's consent gate has TWO enforcement points and BOTH originally fired during copier-update's old-worker rebuild:

- **Script-level secondary check** (`scripts/copier-hooks/forge_consent_gate.py`, wired via `_tasks:`) — fixed by **Spec 445** (returns early when `argv[4] == "update"`).
- **Per-question primary validator** (Jinja `validator:` predicate on the `accept_security_overrides` question in `copier.yml`) — fixed by **Spec 447** (predicate gains `and _copier_operation|default('copy') != 'update'`).

Both fire because copier's `update` operation renders TWICE — once for the old-worker rebuild (reconstructs previous state from `.copier-answers.yml` alone for diff computation), then once for the new-worker apply. Runtime `--data` tokens reach only the new-worker apply. Before 445 + 447, the old-worker rebuild tripped both layers and aborted before any diff was computed.

### Consent-gate `copier update` old-worker rebuild — Spec 445

**Status (2026-05-16)**: `scripts/copier-hooks/forge_consent_gate.py` (Spec 437) skips the "consent absent" secondary check during `copier update` operations. The Req 1a poisoned-token check stays active on both copy and update.

**Why**: during `copier update`, copier renders TWICE — once for the old-worker reconstruction (rebuilds previous project state from `.copier-answers.yml` alone for diff computation), then once for the new-worker apply. Runtime tokens passed via `--data accept_security_overrides_confirmed=true` ONLY reach the new-worker apply. Tripping the secondary check during old-worker rebuild aborts the update before any diff is computed — a category error: the gate is not asking for fresh consent during rebuild, it's reconstructing previously-consented state.

**Threat model alignment**: Spec 437 Req 1a was scoped to the fresh-clone PR-poisoning attack: an adversary modifies `.copier-answers.yml` before the consumer's first `copier copy` to pre-position `accept_security_overrides: true` + a crafted command value. That attack surface does NOT apply to `copier update` of an existing project — the answers file is already part of the consumer's repo, and any modification is visible in PR-review diff before the update runs. The poisoned-token check (rejecting `accept_security_overrides_confirmed` persisted to the answers file) stays active on update as defense-in-depth.

**Mechanism**: `copier.yml`'s `_tasks[0]` invokes the hook with `{{ _copier_operation }}` as argv[4]. The hook returns early when argv[4] equals `"update"` AFTER running the poisoned-token check. Older templates / copier versions where the operation arg is absent default to fresh-copy semantics (current behavior preserved).

**Regression tests**: `.forge/tests/test_consent_gate_update_path.py` covers all four combinations of (operation × consent state) per Spec 445 AC 1-5.

## Bare-copier invocation is power-user only — Spec 444

**Status (2026-05-16)**: `/forge stoke` is the **default operator path** for "update my project from the template." It mediates every consent gate (Copier `--trust`, Spec 090 security overrides, Spec 437 runtime tokens) through chat as yes/no questions. The operator never sees a Python traceback, never types `--data K=V`, never reads a Spec number to know what to do next.

**Bare `copier update`** is supported as a power-user shape for scripting, CI, and edge cases — but it is **NOT the operator default**. If you reach for `copier update` directly, you accept the rough edges:

- Cryptic validator messages naming `--data <flag>=true` rather than operator-shaped questions
- A Python traceback on any validator failure, instead of a translated error
- A separate `--trust` flag plus separate `--data accept_security_overrides=true` plus separate `--data accept_security_overrides_confirmed=true` for the same logical "yes, apply my customizations" intent

**When to use bare `copier update`**:
- CI pipelines that need non-interactive operation (`--defaults`, plus all `--data K=V` flags supplied up front from a vetted config)
- Reproducing a specific incident with full control over every flag
- Debugging FORGE itself when `/forge stoke` is the layer under test

**When NOT to use bare `copier update`**:
- Day-to-day operator updates. Use `/forge stoke`.
- Any session where you'd type a `--data` flag based on a validator error message — that's the chat-mediation surface, not yours to drive manually.

**Threat model note**: bare-copier invocations bypass Spec 444's strict-literal consent parser. The underlying Copier validators are still in place (Spec 090, Spec 437), but the operator-facing UX is the validator-message text rather than FORGE-controlled question text. A future spec (deferred in Spec 444's Deferred Scope) may revise validator messages so they speak operator-language as defense-in-depth.

## Conventions for future Copier-related work

1. Any new security-gated flag MUST use the v3.3 self-referential `when:` pattern. Bare `when: false` is the trap.
2. Any new dynamic `when:` predicate that gates a security-relevant question MUST come with a fixture test that renders against synthetic answers — the static audit-test (`test_copier_yml_audit.py`) can't catch dynamic predicates.
3. After any Copier minor-version bump, re-run the empirical-verification scenarios that established the v3.3 pattern (see `copier.yml:310–318` for the canonical anchor).
4. **Any new `validator:` or `_tasks:` entry MUST extend `template/.forge/lib/stoke/gates.py`** so `/forge stoke` can mediate the new gate in chat (Spec 444 Req 8a). `/close` enforces this mechanically — closing a spec that touches `copier.yml` without updating `gates.py` FAILS unless the spec declares `Gate-Mediation-Exempt: <≥30-char rationale>` in frontmatter.
