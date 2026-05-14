# FORGE Baseline Format (Spec 090)

A **baseline** is a reusable Copier answer file that pre-fills `copier copy` answers for new FORGE projects. Teams that always build with the same stack (Python FastAPI + PostgreSQL, Java Spring + Tomcat, etc.) can ship a baseline once and skip the repetitive answering for every new project.

This document covers the schema, invocation, security model, migration behavior, and a Jinja-template implementation reference.

## Schema

A baseline is a YAML file that:

1. Lives at `~/.forge/baselines/<name>.yaml` on POSIX, `%USERPROFILE%\.forge\baselines\<name>.yaml` on Windows.
2. Declares three required provenance keys at the top level:
   - `forge_baseline_name` (string) — MUST match the filename stem (e.g., `python-fastapi.yaml` declares `forge_baseline_name: python-fastapi`). Soft-warning at `/forge baselines` listing time if mismatched; no hard validator (filename mismatch is operator-controllable and rarely accidental).
   - `forge_baseline_description` (string) — single-line human-readable summary.
   - `forge_baseline_version` (string, semver) — e.g., `"1.0.0"`. Used by `/forge baselines` discovery.
3. Optionally declares any Copier answer keys for the FORGE template (e.g., `project_description`, `default_owner`, `use_wsl2`).
4. **If overriding any security-relevant answer** (see § Security model), MUST also declare `accept_security_overrides: true`. Otherwise the render fails with a Copier validator error naming the offending key.

The `forge_baseline_*` keys are normal Copier answers — Copier persists them to `.copier-answers.yml` automatically, providing baseline provenance with no additional FORGE machinery.

## Invocation

```bash
# POSIX
copier copy <forge-template> <target> --data-file ~/.forge/baselines/python-fastapi.yaml --defaults
```

```powershell
# Windows
copier copy <forge-template> <target> --data-file "$env:USERPROFILE\.forge\baselines\python-fastapi.yaml" --defaults
```

`--defaults` skips prompting for any answer the baseline does not pre-fill, using FORGE's `copier.yml` defaults. Omit `--defaults` for an interactive session that asks for missing answers.

There is no FORGE wrapper script. Apply happens through Copier directly.

## Discovery

```
/forge baselines
```

Lists every `*.yaml` file in the platform-appropriate baselines directory:
- Well-formed: `<forge_baseline_name> (v<forge_baseline_version>) — <forge_baseline_description>`
- Malformed (missing required key): `<filename> — MALFORMED: missing <key>` (the listing continues; the malformed file does not cause the command to fail).

If the baselines directory does not exist, the command prints a one-line installation hint and exits 0.

## Installation (manual `cp`)

FORGE ships an example baseline at `docs/process-kit/baselines/python-fastapi.yaml`. To use it:

```bash
mkdir -p ~/.forge/baselines
chmod 700 ~/.forge/baselines    # POSIX: restrict permissions for parity with ~/.bashrc trust model
cp docs/process-kit/baselines/python-fastapi.yaml ~/.forge/baselines/
```

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.forge\baselines" | Out-Null
Copy-Item "docs/process-kit/baselines/python-fastapi.yaml" "$env:USERPROFILE\.forge\baselines\"
```

A future spec may add a `/forge baseline install <name>` subcommand if doc-and-cp friction is observed in practice. For now, the manual flow is intentional — keeps the v1 surface small and avoids re-introducing the wrapper layer the v3 reframe deleted.

## Security model

### Trust posture (v1)

The baseline directory is **operator-controlled at OS-permissions level** — same trust model as `~/.bashrc`, `~/.gitconfig`, and `~/.ssh/config`. Baselines are not signed, not registry-verified, not tamper-detected. A future spec may add cryptographic verification if shared baseline distribution becomes common; v1 trusts the operator to keep their HOME directory uncompromised.

**Recommendation**: `chmod 700 ~/.forge/baselines/` on POSIX so the dir is owner-only. Not enforced by FORGE — operator's call.

### Security-relevant Copier answers (the gated set)

The following Copier answers in FORGE's `copier.yml` are gated by `validator:` entries that fail render unless the baseline also sets `accept_security_overrides: true`:

| Key | Why gated |
|-----|-----------|
| `test_command` | Free-text shell string flowing into rendered scripts (injection vector) |
| `lint_command` | Free-text shell string flowing into rendered scripts |
| `harness_command` | Free-text shell string flowing into rendered scripts |
| `include_nanoclaw` | Adds messaging integration (network surface) to rendered project |
| `include_advanced_autonomy` | Lowers the operator-review threshold for agent actions |
| `include_two_stage_review` | Changes the implementation-gating posture from default |

If a baseline overrides any of these without `accept_security_overrides: true`, `copier copy` aborts with:

```
ValueError: Validation error for question '<key>': Spec 090 security gate: <key> override
('<value>') requires accept_security_overrides=true in your baseline. <key> accepts arbitrary
shell strings that flow into rendered scripts.
```

### Single source of truth

The gated set is defined exclusively by the `validator:` entries in `copier.yml` — co-located with each gated question. There is no separate FORGE wrapper allowlist. When a future security-relevant answer is added to `copier.yml`, its `validator:` goes in the same place. This is the structural fix from the v3 Maverick reframe (round 2 consensus exposed that the v2 design's hardcoded allowlist drifted to zero matches against the real `copier.yml`).

### CI-log audit visibility

Even when `accept_security_overrides: true`, FORGE's `_message_after_copy` template emits a one-line summary of which security-relevant keys were overridden. Sample output:

```
Spec 090 — security-relevant overrides recorded (accept_security_overrides=True):
  test_command = pytest -v
  harness_command = <redacted: 24 chars>
  include_nanoclaw = true
```

This message renders **after copy** (not before — `_message_before_copy` empirically runs before `--data-file` answers are applied; `_message_after_copy` is the correct primitive). Operators in CI grep for `Spec 090 — security-relevant overrides recorded` to detect any baseline that bypassed the security gate.

### Redaction format (free-text shell-string keys)

For `test_command` / `lint_command` / `harness_command`, the rendered value uses this rule:

- If the value contains **only** characters from the allowlist `[A-Za-z0-9_./= +:,@~ -]` (ASCII letters, digits, underscore, dot, slash, equals, space, plus, colon, comma, at-sign, tilde, hyphen), it is echoed verbatim.
- If the value contains any character outside the allowlist, it is replaced with the literal token `<redacted: N chars>` where N is the character count of the original value.

Operators who need the exact value can read `.copier-answers.yml` directly (which is what they would do anyway for verification).

The redaction allowlist is defined as a literal string of all 73 expanded characters in `copier.yml`'s `_message_after_copy` template (`ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./=+:,@~ -`). Pure-Jinja implementation; no regex; no SHA computation; renders identically across Copier installations.

### Future-overlay path allowlist (reserved)

This spec does NOT ship overlay-file copy (use Copier's `_subdirectory`, `_tasks`, and `_extends` for stack-specific files). If a future spec adds overlay-file copy, it MUST enforce this path allowlist:

- Reject absolute paths.
- Reject any path containing `..`.
- Reject paths under `.git/`, `.github/workflows/`, `CLAUDE.md`, `AGENTS.md`, and `.forge/scripts/`.

This allowlist exists in writing now so a future implementer cannot re-introduce the trust gap that aligned-rejected the v1 Spec 090 design.

## Migration (`copier update` for pre-Spec-090 consumers)

**Spec 090 is a small breaking change for existing consumers.** If your project's `.copier-answers.yml` carries a non-default value for any of the six gated security-relevant keys (`test_command`, `lint_command`, `harness_command`, `include_nanoclaw`, `include_advanced_autonomy`, `include_two_stage_review`), your next `copier update` will fail with a Copier validator error like:

```
ValueError: Validation error for question 'test_command': Spec 090 security gate:
test_command override ('npm test') requires accept_security_overrides=true in your
baseline. test_command accepts arbitrary shell strings that flow into rendered scripts.
```

### One-line fix

Open `.copier-answers.yml` in your project and add this line:

```yaml
accept_security_overrides: true
```

Then re-run `copier update`. That's it.

### Why this is a manual fix (and not auto-migration)

The original v3.1 spec proposed a Copier `_migrations:` entry that would auto-inject `accept_security_overrides: true` for pre-existing overrides, treating prior persisted answers as prior operator consent. Empirical test on Copier 9.14.0 proved that approach incompatible with Copier's phase ordering: `_migrations:` runs at the `before` stage but does NOT refresh Copier's in-memory answer state, so the script's disk-mutation is invisible to the validator phase that follows, which then aborts the entire `copier update` exit 1 — exactly the breakage the migration was designed to prevent.

The four-of-five-role `/consensus 090` round 4 vote favored Option A (drop the auto-migration; document a one-line manual fix) on three grounds:

1. **The validator's existing error message is FORGE-authored and names the exact remediation** — the failure itself teaches you what to do, no separate documentation lookup required for the discovery.
2. **Manual consent IS the security primitive** — the original gate's purpose is to make security-relevant overrides EXPLICIT and AUDITABLE. Auto-consent (whether via `_migrations:` or a helper script) launders the security signal exactly as the original `_migrations:` design did. The CISO disposition was unambiguous: forcing the operator to open `.copier-answers.yml`, read each overridden value (including any tampered `test_command`/`harness_command` injected by an attacker with file-write access), and type explicit consent IS the security action — not a friction to engineer around.
3. **"Minimal by default"** — the auto-migration was the only piece of Spec 090 introducing custom helper code, pinned-default constants, and coupling to Copier's internal phase ordering, all of which the empirical breakage just proved fragile.

### Maverick's Option D (watchlist)

A scope-aware validator that fires only at greenfield `copier copy` (where `--data-file` baselines are the real threat) and NOT on `copier update` (where persisted answers represent prior consent) would eliminate the breaking-change footprint entirely. Empirical test on Copier 9.14.0 proved this not currently feasible — Copier does not expose `_copier_conf.operation` or per-answer source provenance to validator Jinja context. Tracked on `docs/sessions/watchlist.md` for future revisit when Copier exposes the required API.

### Optional stricter posture

Operators who want stricter posture can manually inspect each gated key's value, revert any unwanted overrides to their defaults, and only then add `accept_security_overrides: true` (or omit the consent line entirely if all values are now defaults). The validator only fires when at least one gated key differs from its default.

## Implementation reference

### `_message_after_copy` Jinja skeleton

```yaml
_message_after_copy: |-
  {%- set allowlist_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./=+:,@~ -' -%}
  {%- set ns = namespace(lines=[]) -%}
  {%- if test_command != 'pytest -q' -%}
  {%-   if test_command | reject('in', allowlist_chars) | list | length > 0 -%}
  {%-     set _ = ns.lines.append('  test_command = <redacted: ' ~ test_command|length ~ ' chars>') -%}
  {%-   else -%}
  {%-     set _ = ns.lines.append('  test_command = ' ~ test_command) -%}
  {%-   endif -%}
  {%- endif -%}
  {# ... repeat for lint_command, harness_command (free-text) #}
  {%- if include_nanoclaw -%}{%- set _ = ns.lines.append('  include_nanoclaw = true') -%}{%- endif -%}
  {# ... repeat for include_advanced_autonomy, include_two_stage_review (booleans) #}
  {%- if ns.lines -%}
  Spec 090 — security-relevant overrides recorded (accept_security_overrides={{ accept_security_overrides }}):
  {{ ns.lines | join('\n') }}
  {%- endif -%}
```

Key Jinja idioms:
- `value | reject('in', allowlist_chars) | list | length > 0` — true if `value` contains any character not in `allowlist_chars`. (The `'in'` test treats `allowlist_chars` as a string of characters; `reject('in', ...)` returns the characters NOT in the allowlist; non-empty result list means out-of-allowlist character present.)
- `namespace(lines=[])` + `ns.lines.append(...)` — workaround for Jinja's lack of in-template list mutation in regular `set` blocks.
- Whitespace control with `{%-` / `-%}` to avoid leading/trailing spaces in the rendered output.

## Testing

End-to-end smoke tests for the Spec 090 mechanism live in the spec's Test Plan. The two empirical Copier-behavior verifications performed during /implement Step 2b (DA disposition):

1. **Validator under `--data-file`**: Copier 9.14.0 confirmed — `validator:` runs against `--data-file`-supplied values and aborts render on non-empty validator output.
2. **`_message_after_copy` under `--defaults`**: Copier 9.14.0 confirmed — `_message_after_copy` renders with the fully-resolved answer values (including those from `--data-file`) and prints to stdout in non-interactive runs. (`_message_before_copy` was empirically broken — runs BEFORE `--data-file` answers are applied; do not use it for override visibility.)

## See also

- `docs/specs/090-shared-team-baselines.md` — full specification, requirements, ACs, test plan, revision log.
- `docs/process-kit/baselines/python-fastapi.yaml` — example baseline.
- `copier.yml` — `validator:` entries on the gated questions; `_message_after_copy` Jinja template; `forge_baseline_*` provenance questions with self-referential `when:` (P2f pattern). Note: the v3.1 `_migrations:` entry for auto-injecting `accept_security_overrides: true` was REMOVED in v3.2 (validator AC 9 FAIL — Copier 9.14.0 `_migrations:` runs before validator phase but does NOT refresh in-memory state). The migration is now manual; see § Migration above for the one-line fix.
