# Example spec — closed

This is a complete example of a closed spec from the configlint project, showing every section filled in. Use it as a reference when writing your own specs.

---

# Framework: FORGE
# Spec 003 - Add --version flag to configlint CLI

- Status: closed
- Change-Lane: `standard-feature`
- Priority-Score: <!-- BV=3 E=1 R=1 SR=3 → score=32 (see docs/process-kit/scoring-rubric.md) -->
- Trigger: user correction — operators expect `--version` on any CLI tool; absence causes confusion
- Dependencies: 001
- Owner: operator
- Author: Claude
- Reviewer: operator
- Approver: operator
- Implementation owner: Claude
- Last updated: 2026-02-14

> **Why this matters:** The frontmatter block is machine-readable metadata. Status tracks lifecycle position. Change-Lane determines the review depth: a `hotfix` gets fast-tracked, a `standard-feature` gets full evidence gates. The Priority-Score formula (BV x SR / E x R) makes ranking objective. Always set the Trigger — it answers "why now?" when someone reads this spec months later.

## Objective

Operators using configlint have no way to check which version they are running, which makes bug reports incomplete and upgrade decisions harder. This spec adds a `--version` flag that prints the installed version and exits. The version string is read from `pyproject.toml` so there is a single source of truth.

> **Why this matters:** The objective answers three questions: what is the problem, who has the problem, and what does the solution look like. Keep it to 2-3 sentences. Avoid implementation details here — those belong in Requirements. A common mistake is writing "add feature X" without explaining the problem that feature X solves.

## Scope

In scope:
- `--version` / `-V` flag on the CLI entry point
- Version string sourced from `pyproject.toml` metadata
- Unit test covering the flag output

Out of scope:
- Version check against PyPI (future spec)
- Changelog generation
- Build/release automation

> **Why this matters:** Scope prevents creep during implementation. The out-of-scope list is just as important as the in-scope list — it tells the implementing agent (or operator) where to stop. If you find yourself adding out-of-scope items during implementation, that is a signal to write a new spec.

## Requirements

1. The CLI accepts `--version` and `-V` flags
2. The flag prints the version string from `pyproject.toml` `[project].version` field and exits with code 0
3. The version output format is `configlint <version>` (e.g., `configlint 0.4.1`)
4. The flag takes precedence over all other arguments (if `--version` is present, no validation runs)

> **Why this matters:** Requirements are the contract between the spec author and the implementer. Each requirement should be specific enough to verify. A common mistake is writing vague requirements like "support versioning" — that leaves the implementer guessing and makes acceptance criteria impossible to write.

## Acceptance Criteria

1. `configlint --version` prints `configlint <version>` where `<version>` matches pyproject.toml
2. `configlint -V` produces identical output to `--version`
3. `configlint --version invalid.yaml` prints version and exits 0 (does not attempt validation)
4. `configlint --version` exit code is 0
5. Version string is read from pyproject.toml at runtime, not hardcoded

> **Why this matters:** Acceptance criteria are the spec's definition of done. Each criterion must be testable — either by a script or by a human following a checklist. Write them as assertions: "X produces Y." If you cannot write a test for a criterion, it is too vague. The evidence gate at `/close` checks these criteria against actual output.

## Test Plan

1. Unit test: mock pyproject.toml version, call CLI with `--version`, assert output format
2. Integration test: run `configlint --version` in subprocess, verify exit code 0 and output matches
3. Precedence test: run `configlint --version nonexistent.yaml`, verify no validation error

```bash
# Run the full test suite
pytest tests/test_version.py -v

# Manual smoke test
configlint --version
configlint -V
configlint --version nonexistent.yaml; echo "exit code: $?"
```

### Cross-platform coverage
- bash: `configlint --version`
- PowerShell: `configlint --version`

> **Why this matters:** The test plan bridges the gap between acceptance criteria (what to verify) and evidence (proof it was verified). Include both automated tests and manual smoke tests. The reproduction commands should be copy-pasteable by anyone with the project checked out. Automated tests run at `/implement`; manual tests run at `/close`.

## Compatibility / Deprecation Notes

- No breaking changes. The `--version` flag does not conflict with any existing flags.

## ADR References

- none

## Implementation Summary

- Changed files:
  - `src/configlint/cli.py` — added `--version` flag to argument parser
  - `src/configlint/version.py` — new module, reads version from importlib.metadata
  - `tests/test_version.py` — new test file, 3 test cases
  - `pyproject.toml` — no change (version field already existed)

> **Why this matters:** The implementation summary is filled in after the work is done. It tells future readers what actually changed, which may differ from what the spec originally planned. List every file touched. This section is the entry point for anyone reviewing the commit history.

## Reproduction Commands

```bash
pytest tests/test_version.py -v
configlint --version
```

Human validation steps: see `docs/process-kit/human-validation-runbook.md` sections: A

## Evidence

- Tests/lint/output summary:
  - GATE 1 — spec-exists: PASS (Spec 003 found in docs/specs/)
  - GATE 2 — tests-pass: PASS (3/3 tests passed, 0 failures)
  - GATE 3 — lint-clean: PASS (ruff check: 0 errors, mypy: 0 errors)
  - GATE 4 — AC-verified: PASS (all 5 acceptance criteria verified)
  - GATE 5 — human-validation: PASS (operator confirmed version output on macOS and Windows)

```
$ pytest tests/test_version.py -v
tests/test_version.py::test_version_flag_long PASSED
tests/test_version.py::test_version_flag_short PASSED
tests/test_version.py::test_version_precedence PASSED

3 passed in 0.42s

$ configlint --version
configlint 0.4.1
```

> **Why this matters:** Evidence is what separates EGID from "trust me, it works." Each gate outcome is recorded with PASS or FAIL. Include actual command output, not paraphrased summaries. The evidence section is the primary artifact reviewed at `/close`. A spec without evidence cannot be closed — this is the core evidence gate principle.

## Revision Log

- 2026-02-10: Initial draft. Trigger: operator reported missing --version flag.
- 2026-02-11: Status changed to in-progress. Implementation started via /implement.
- 2026-02-13: Status changed to implemented. All tests passing, evidence captured.
- 2026-02-14: Status changed to closed via /close. All gates passed.

> **Why this matters:** The revision log is the spec's audit trail. Every status transition gets an entry with a date and a reason. This matters for traceability — if someone asks "when did this ship?" or "why was this reopened?", the revision log answers immediately. Include the trigger for the initial draft and the gate outcome for each transition.

---

Last verified against Spec 263 on 2026-04-15.
