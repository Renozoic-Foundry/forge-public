#!/usr/bin/env bash
# Spec 381 — thin bash wrapper for .forge/lib/stoke.py.
# Forwards args to Python. Contains no business logic.
# Constraint (Spec 381 Constraints): all stoke transactional logic lives in
# stoke.py — this wrapper exists only as invocation glue.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/stoke.py" "$@"
