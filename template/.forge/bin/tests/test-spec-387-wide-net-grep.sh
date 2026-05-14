#!/usr/bin/env bash
# test-spec-387-wide-net-grep — AC12.
# Wide-net grep detects safety-named tokens in non-registered files and flags any match
# without a corresponding ## Safety Enforcement section reference.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

# Build a synthetic repo with: registry, two files (one registered, one not), a "safety_X" token in each.
mkdir -p .forge docs/specs scripts
cat > .forge/safety-config-paths.yaml << 'EOF'
patterns:
  - AGENTS.md
  - .forge/onboarding.yaml
EOF

# Registered file with token (should NOT be flagged — registered files use the prompt path, not wide-net).
# Use a token matching the wide-net regex: (safe|safety|enforce|require|validate|guard|prevent|reject)_[a-zA-Z_]+
cat > AGENTS.md << 'EOF'
multi_agent:
  require_confirmation_at: critical
EOF

# Non-registered file with token (SHOULD be flagged — no Safety Enforcement section references it).
cat > scripts/lonely.sh << 'EOF'
#!/usr/bin/env bash
require_human_approval=true
echo done
EOF

# Run wide-net grep, replicating the evolve.md Step S logic.
mapfile -t hits < <(grep -rnE '(safe|safety|enforce|require|validate|guard|prevent|reject)_[a-zA-Z_]+' \
    --include='*.sh' --include='*.md' --include='*.yaml' \
    --exclude-dir=.git . 2>/dev/null || true)

unflagged_in_registered=0
flagged_in_unregistered=0
for h in "${hits[@]}"; do
  f="${h%%:*}"
  f="${f#./}"
  # Determine if registered.
  is_registered=0
  while IFS= read -r pat; do
    bp="${pat//\*\*/\*}"
    # shellcheck disable=SC2053
    if [[ "$f" == $bp ]]; then is_registered=1; break; fi
  done < <(safety_config_load .forge/safety-config-paths.yaml)
  if (( is_registered )); then
    unflagged_in_registered=$((unflagged_in_registered+1))
  else
    # Check if any spec references this file in Enforcement code path.
    if ! grep -lE 'Enforcement code path: '"$f"'::' docs/specs/*.md >/dev/null 2>&1; then
      flagged_in_unregistered=$((flagged_in_unregistered+1))
    fi
  fi
done

# We expect: AT LEAST one hit in registered file (atomic_checkout in AGENTS.md) and
# AT LEAST one flagged hit in non-registered file (require_human_approval in scripts/lonely.sh).
if (( unflagged_in_registered < 1 )); then
  echo "FAIL: registered file's token should be detected but not flagged" >&2
  exit 1
fi
if (( flagged_in_unregistered < 1 )); then
  echo "FAIL: non-registered file's token should be flagged" >&2
  exit 1
fi
echo "PASS: wide-net flagged ${flagged_in_unregistered} hit(s) in non-registered file(s); ignored ${unflagged_in_registered} hit(s) in registered file(s)"
exit 0
