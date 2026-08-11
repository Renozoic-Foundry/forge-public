# Behavioral-AC Fixture Convention

> Last verified: 2026-08-07 (Spec 669)

When an acceptance criterion describes a runtime behavior that the validator subagent cannot directly drive (running a command, observing terminal output, comparing fresh-fixture state, or exercising a UI), pair the AC with a runnable fixture. The fixture turns a previously-DEFER-able AC into a mechanically-verifiable PASS or an explicit SKIP.

## Single pattern source (Spec 540)

The behavioral-AC/browser-verb pattern list lives in exactly one place:
`.forge/lib/ac-pattern-scanner.sh` (+ `.ps1` parity; also shipped at
`template/.forge/lib/ac-pattern-scanner.sh` for Copier consumers). Given a spec
file, it returns (three-state output contract, Spec 618):

```json
{"section_found": true|false, "flagged_acs": [{"ac_number": N, "text": "...", "pattern": "..."}]}
```

- `section_found: true` + empty `flagged_acs` — the AC section was read and contains no
  matches (a genuinely clean spec).
- `section_found: false` — the spec has NO recognized acceptance-criteria heading
  (`## Acceptance Criteria` / `## Definition of done`, any case, trailing parentheticals
  allowed); the scan read nothing and the empty `flagged_acs` means nothing. Gate
  consumers treat this as **could-not-check** — an operator-visible warning, never a
  silent pass (`/close` Step 2b2 emits a blocking `COULD-NOT-CHECK` outcome).
- `runnable` mode output is schema-unchanged (`{"flagged_acs":[...]}` only — Spec 618
  AC6 byte-parity for Spec 548 consumers).

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

Weak tokens (render/show/visible/display) are exclusion-guarded: the Spec 550
whole-AC contexts (copier/renderer/CI/fixture/stdout prose), plus the Spec 618
additions — a weak token matching only inside backticked spans is excluded, and
token-scoped contexts excuse `show` in CLI chains (`az … show`, `git show`),
`visible` adjacent to `output` / in `user-visible … change` prose, and
render-tooling prose (`re-render` forms, `render trigger|pipeline|source`).
Token-scoping means a CLI `show` never excuses an unrelated `displays` in the
same AC; a bare `render` exclusion is deliberately forbidden.

**Backtick-sensitive patterns (Spec 658).** The slash-command pattern
`(running|run|invoke|execute) /[a-z-]+` is neither strong nor weak — it is its
own third class, `BACKTICK_SENSITIVE_PATTERNS`. It is subject to the
backtick-strip re-test **only**: an AC that merely *quotes* a command string as
data, with the verb appearing nowhere outside a backticked span, does not flag.
So this no longer fires:

> the emitted prompt contains the standing rule beginning
> `` `NEVER run /close, git push, gh pr create` `` verbatim

while all three of these still do:

- `the operator can run /close and the gate reports PASS` — verb outside any
  backticked span.
- ``the guide names `run /close` as the trigger, and the operator can run /close
  to see it`` — matched inside **and** outside backticks. The rule is "matched
  ONLY inside backticks", never "contains a backtick".
- `running /close in a fresh fixture reports PASS` — the whole-AC `EXCLUSIONS`
  list is **not** inherited by this class. Adding the pattern to
  `WEAK_PATTERNS` instead would have inherited `\bfixture(s)?\b` and silently
  stopped flagging this AC, which is a false *negative* at a blocking gate. The
  narrower class exists precisely to avoid that.

When writing an AC that quotes a command purely as data, backtick it — that is
now the mechanical signal that distinguishes data from behaviour. Note the
pattern has no third-person alternative: `runs /close`, `invokes /close`, and
`executes /close` do not match it, before or after Spec 658.

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

## Scratch handling (Spec 669)

A fixture that needs a scratch file or directory MUST create it via `mktemp -d`
(or `mktemp`), never at a fixed, hardcoded path under the repo root. Two failure
modes follow from a fixed repo-root scratch path, both observed live in
`.forge/bin/tests/test-spec-659-grep-count-idiom.sh` before Spec 669 fixed it:

1. **Concurrent-run corruption.** Two instances of the same fixture running at
   once (e.g., two `/parallel` lanes, or an operator re-running a suite while a
   CI sweep is also running it) share the fixed path. One instance's cleanup
   (`rm -rf` on that shared path) deletes the other's planted fixtures mid-run.
2. **Blocking-gate poisoning.** If the fixture plants a deliberately-invalid
   file to prove a lint/validation rule fires (a common pattern for testing the
   rule itself), and that file sits inside a directory a blocking gate sweeps
   (e.g., `scripts/validate-bash.sh`'s repo-wide scan), a concurrently-running,
   otherwise-unrelated invocation of that gate can see the deliberately-bad file
   and report a false failure — the fixture's scratch state has leaked into a
   different command's verdict.

**The rule**: never plant a deliberately-invalid file inside a directory a
blocking gate sweeps. A per-run-unique path (`mktemp -d`) fixes failure mode 1
(no more shared path to collide on) but does **not** fix failure mode 2 by
itself — uniqueness stops two instances from deleting each other's files, but
does nothing to stop an unrelated sweep from seeing (and miscounting) a
planted violation while it is live, because a real repo-wide sweep visits
whatever is inside the repo root regardless of which process put it there.

When the behavior under test is itself "does a repo-wide gate detect and
report X," and X must be a real, live file for the gate to have something to
find, run a fresh copy of the gate script against a throwaway root built
entirely under the fixture's own `mktemp -d` — never against the real repo
root. This gives both guarantees at once: the copy still exercises the real
rule logic (it is a byte-identical copy of the production script, not a
reimplementation), the planted violation is visible to that one copy (which
computes its own root from the throwaway location), and it is permanently
invisible to any other, concurrently-running invocation of the real script
(which computes its root from the real repo, a different location entirely).
See `.forge/bin/tests/test-spec-659-grep-count-idiom.sh` for the worked
example: it copies `scripts/validate-bash.sh` into a `mktemp -d`-built mini
repo (with a minimal `.forge/` so the shellcheck stage has something to pass)
and plants its violation there, instead of inside the real `$REPO_ROOT`.

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
