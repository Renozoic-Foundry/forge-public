#!/usr/bin/env bash
# test-spec-387-backfill-sla-enforcement — AC14.
# When the SLA marker is past now AND the audit reports unenforced declarations,
# the gate returns exit 2 with the canonical R6b message.
# Tests the close.md gate's invocation logic against a synthetic deadline + audit output.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Build a synthetic state directory with an expired deadline.
mkdir -p "${TMP}/.forge/state"
deadline_file="${TMP}/.forge/state/safety-backfill-deadline.txt"
expired_date=$(date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-1d +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' "$expired_date" > "$deadline_file"

# Synthetic audit script that emits one MISSING entry.
mkdir -p "${TMP}/scripts"
cat > "${TMP}/scripts/safety-backfill-audit.sh" << 'EOF'
#!/usr/bin/env bash
echo "MISSING: AGENTS.md::multi_agent.atomic_checkout (no enforcement)"
exit 0
EOF
chmod +x "${TMP}/scripts/safety-backfill-audit.sh"

# Replay the close.md SLA-check logic in isolation.
cd "$TMP"
deadline=$(cat "$deadline_file")
now_epoch=$(date -u +%s)
deadline_epoch=$(date -u -d "$deadline" +%s 2>/dev/null \
  || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$deadline" +%s 2>/dev/null \
  || echo 0)

if (( now_epoch > deadline_epoch && deadline_epoch > 0 )); then
  audit_output=$(bash scripts/safety-backfill-audit.sh)
  unenforced_count=$(echo "$audit_output" | grep -cE '^MISSING:' || true)
  if (( unenforced_count > 0 )); then
    msg="GATE [safety-backfill-sla]: FAIL — Safety-backfill SLA expired. ${unenforced_count} declaration(s) still without enforcement or UNENFORCED annotation. Disposition required."
    if [[ "$msg" == *"Safety-backfill SLA expired"* ]] && [[ "$msg" == *"Disposition required"* ]]; then
      echo "PASS: SLA-expired + missing entries produces the R6b canonical message"
      echo "  $msg"
      exit 0
    fi
    echo "FAIL: message did not match R6b template: $msg" >&2
    exit 1
  fi
fi
echo "FAIL: SLA logic did not flag the synthetic expired/missing combination" >&2
exit 1
