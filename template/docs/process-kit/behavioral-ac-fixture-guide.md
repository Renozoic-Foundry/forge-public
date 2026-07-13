# Behavioral-AC Fixture Convention

> Last verified: 2026-07-08 (Spec 540)

When an acceptance criterion describes a runtime behavior that the validator subagent cannot directly drive (running a command, observing terminal output, comparing fresh-fixture state, or exercising a UI), pair the AC with a runnable fixture. The fixture turns a previously-DEFER-able AC into a mechanically-verifiable PASS or an explicit SKIP.

## Single pattern source (Spec 540)

The behavioral-AC/browser-verb pattern list lives in exactly one place:
`.forge/lib/ac-pattern-scanner.sh` (+ `.ps1` parity; also shipped at
`template/.forge/lib/ac-pattern-scanner.sh` for Copier consumers). Given a spec
file, it returns:

```json
{"flagged_acs": [{"ac_number": N, "text": "...", "pattern": "..."}]}
```

Two consumers share this one script — neither hosts its own copy of the regex list:

- **`/spec` Step 6d** (authoring-time nudge, non-blocking): runs the scanner
  against the draft spec and offers to pair each flagged AC with a fixture.
- **`/close` Step 2b2 / the validator subagent Stage 1** (close-time gate,
  blocking): runs the scanner and HARD-FAILs any flagged AC that lacks a
  corresponding browser-evidence manifest (`tmp/evidence/SPEC-NNN-browser-*/manifest.json`),
  unless the operator passes `/close --accept-deferred-acs "<reason>"` (reason
  recorded verbatim in the spec's Evidence section) or the blunt `--force` flag.

The scanner's pattern set covers two origins:
- Spec 349 behavioral phrasing: `(running|run|invoke|execute) /[a-z-]+`,
  `(fresh|new) (fixture|copy|repo|project)`, `after .+, the operator (sees|observes)`.
- Spec 540 browser-verb phrasing: clicking, hovering, rendering, showing,
  visible, displaying, scrolling.

Invoke it plugin-root-relative (Spec 538 convention) so plugin-primary
consumers — who do not vendor `.forge/lib/` separately — resolve the same
script the plugin ships:

```bash
${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/ac-pattern-scanner.sh <spec-file>
```

**Boundary vs Spec 403**: Spec 403's live-smoke gate keys on Test-Plan keywords
("smoke test", "live dry-run"). This scanner keys on Acceptance-Criteria
phrasing. The two scans read different sections for different signals and
never double-fire on the same trigger.

## When to use

Author a fixture when an AC matches any of these patterns:

- "running `/<command>` produces ..."
- "invoke `/<command>` and observe ..."
- "in a fresh fixture / new copy / new repo / new project, ..."
- "after `<some-action>`, the operator sees ..."
- browser-only verbs: clicking, hovering, rendering, showing, displaying, scrolling

A vague-language scan at `/spec` (Step 6c, Spec 171) catches words like *should* and *may*. The behavioral-AC scan is orthogonal: it catches ACs that are specific in language but require driving the system to verify. The authoring-time scan (`/spec` Step 6d) is a nudge; the close-time scan (`/close` Step 2b2, Spec 540) is a gate that can block the close workflow.

If the AC is purely structural — file existence, md5 parity, grep match, exit code — no fixture is needed. The validator subagent can verify those directly.

## Naming and location

Canonical fixture path: `.forge/bin/tests/test-spec-NNN-<behavior>.{sh,ps1}`

Where:
- `NNN` is the spec number authoring the fixture
- `<behavior>` is a short kebab-case label (e.g., `staging-manifest-parity`, `mode-dispatch`, `nudge-dismissal`)
- Both `.sh` (mandatory) and `.ps1` (gated on `command -v pwsh`) are mirrored under `template/.forge/bin/tests/` for consumer projects

Fixtures from prior specs may live at older paths (e.g., `scripts/tests/` for Spec 281's regression sweep). New fixtures use the canonical path; existing fixtures are not relocated.

## PASS / SKIP semantic

A fixture exits with one of three outcomes:

| Outcome | Meaning |
|---------|---------|
| **PASS** (exit 0) | Behavior verified. Validator subagent counts the AC as PASS. |
| **SKIP** (exit 0 with `SKIP:` prefix on stdout) | Fixture cannot be driven in the current environment (e.g., `pwsh` absent, network unreachable, OS-specific path). Validator subagent counts the AC as SKIP — not a failure, but not verified either. Operator decides at /close whether to accept the SKIP or run the fixture in a different environment. |
| **FAIL** (exit non-zero) | Behavior diverged from the documented expectation. Validator subagent counts the AC as FAIL. |

Mirrors Spec 336's parity-test pattern: bash mandatory, PowerShell gated.

## Worked example — Spec 315 AC 12b

Spec 315 (onboarding staged writes) had a behavioral AC the validator could not directly verify:

> **AC 12b — Cross-platform hash parity**: stage one logical file containing `line one\nline two\nline three\n` via the bash flow on a Unix-style fixture (LF-only) AND via the PowerShell flow on a Windows-style fixture (CRLF). Verified by: the manifest's recorded sha256 for the staged file is byte-identical between the two platforms.

The AC describes a runtime behavior across two shells against fixture content the validator cannot synthesize on its own. Spec 315 paired the AC with `.forge/bin/tests/test-staging-manifest-parity.{sh,ps1}`:

- The bash variant stages the file via the bash codepath, computes sha256, and prints it.
- The PowerShell variant stages the file via the PS codepath, computes sha256, and prints it.
- A driver compares the two sha256 values.
- Bash is mandatory; PS gated on `command -v pwsh`.
- Outcomes: both shells produce identical sha256 → PASS. Different sha256 → FAIL. PS unavailable → SKIP (with bash-only PASS still counted).

Result: AC 12b moved from DEFER (validator cannot drive) to mechanically-verifiable. Spec 315 closed with the validator counting AC 12b as PASS based on fixture output, not operator post-merge inspection.

## Authoring workflow

At `/spec` Step 6d (Spec 349 directive), the spec author is prompted when an AC matches a behavioral pattern. The prompt:

1. Lists the matched ACs.
2. Asks whether to author a fixture now or defer.
3. If author: prompt for the fixture filename (`test-spec-NNN-<behavior>.{sh,ps1}`) and add a note to the spec's Test Plan referencing the fixture.

The fixture itself is authored as part of /implement, not /spec. The directive at /spec just ensures the spec records the intent.

## Cross-references

- `/spec` Step 6c — Acceptance Criteria Vague-Language Scan (Spec 171). Sibling pattern; runs first.
- `/spec` Step 6d — Behavioral-AC Fixture Scan (Spec 349). This guide.
- `/close` validator role — when reviewing closed specs, validator counts fixture-paired ACs as PASS/SKIP/FAIL based on fixture output, not deferred to operator inspection.
- Spec 336 — Cross-platform parity test pattern (bash mandatory, PS gated). Adopted here.
- Spec 315 AC 12b — Worked example.
- Spec 324 — Conditional-PASS in-spec disposition pattern.
