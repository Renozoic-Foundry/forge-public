# Spec 001 - Hello World CLI

- Status: closed
- Change-Lane: `small-change`
- Priority-Score: BV=5 E=1 R=1 SR=5 -> score=50
- Owner: operator
- Last updated: 2026-01-15

## Objective

Create a Python CLI that prints "Hello, FORGE!" when run. This is the project's first deliverable — validates the toolchain and FORGE workflow end-to-end.

## Scope

In scope:
- `hello.py` script that prints "Hello, FORGE!"
- One pytest test verifying output
- README with run instructions

Out of scope:
- CLI argument parsing
- Package distribution (PyPI)

## Requirements

1. Running `python hello.py` prints "Hello, FORGE!" to stdout
2. `pytest tests/` passes with at least one test

## Acceptance Criteria

1. `python hello.py` outputs exactly "Hello, FORGE!"
2. `pytest tests/` exits with code 0
3. README.md documents how to run the program

## Test Plan

```bash
# Verify output
python hello.py | grep -q "Hello, FORGE!" && echo "PASS" || echo "FAIL"

# Verify tests pass
python -m pytest tests/ -v
```

## Implementation Summary

- Changed files:
  - `hello.py` (new — main script)
  - `tests/test_hello.py` (new — output test)
  - `README.md` (updated — run instructions)

## Evidence

- Tests/lint/output summary:
  - `python hello.py` -> "Hello, FORGE!" (PASS)
  - `pytest tests/ -v` -> 1 passed (PASS)
  - `ruff check .` -> All checks passed (PASS)

GATE implementation: PASS
GATE close: PASS

## Revision Log

- 2026-01-15: Created. Status -> draft.
- 2026-01-15: Approved by operator. Status -> in-progress.
- 2026-01-15: Implementation complete. Status -> implemented.
- 2026-01-15: All gates passed. Status -> closed.
