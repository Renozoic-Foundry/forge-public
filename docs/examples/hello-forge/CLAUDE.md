# CLAUDE.md — hello-forge

A minimal CLI app that prints "Hello, FORGE!" — used to demonstrate the FORGE workflow.

## Two hard rules — no exceptions

1. **Every change has a matching spec.** No implementation without one.
2. **Every session ends with a session log.** No exceptions.

## Project details

- **Stack**: Python 3.12
- **Test command**: `python -m pytest tests/`
- **Lint command**: `ruff check .`

## Spec lifecycle

`draft -> in-progress -> implemented -> closed`
