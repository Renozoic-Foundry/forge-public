#!/usr/bin/env bash
# FORGE metrics rotation — manual trigger for metrics file rotation
#
# Usage:
#   bash .forge/bin/forge-metrics-rotate.sh [retention_days]
#
# Arguments:
#   retention_days — number of days to retain (default: reads from AGENTS.md, fallback 30)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export FORGE_DIR

# shellcheck source=../lib/metrics.sh
source "${FORGE_DIR}/.forge/lib/metrics.sh"

# Read retention config from AGENTS.md if no argument provided
retention_days="${1:-}"
if [[ -z "${retention_days}" ]]; then
    if [[ -f "${FORGE_DIR}/AGENTS.md" ]]; then
        retention_days="$(grep -oP 'metrics_retention_days:\s*\K[0-9]+' "${FORGE_DIR}/AGENTS.md" 2>/dev/null || echo "30")"
    else
        retention_days="30"
    fi
fi

echo "FORGE Metrics Rotation"
echo "  Directory: ${FORGE_DIR}/.forge/metrics/"
echo "  Retention: ${retention_days} days"
echo ""

forge_metrics_rotate "${retention_days}"
