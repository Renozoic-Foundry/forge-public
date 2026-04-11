#!/usr/bin/env bash
# FORGE metrics.sh — metrics rotation and retention for FORGE runtime data
# Source this file; do not execute directly.
#
# Usage:
#   source "${FORGE_DIR}/lib/metrics.sh"
#   forge_metrics_rotate [retention_days]
#
# Environment:
#   FORGE_DIR — project root (auto-detected if unset)

set -euo pipefail

# Rotate metrics files older than the retention period.
# Moves files to .forge/metrics/archive/ and compresses them.
#
# Arguments:
#   $1 — retention period in days (default: 30)
#
# Globals read:
#   FORGE_DIR — project root
forge_metrics_rotate() {
    local retention_days="${1:-30}"
    local metrics_dir="${FORGE_DIR:-.}/.forge/metrics"
    local archive_dir="${metrics_dir}/archive"

    # Nothing to rotate if metrics dir doesn't exist or is empty
    if [[ ! -d "${metrics_dir}" ]]; then
        echo "metrics: no metrics directory found — skipping rotation"
        return 0
    fi

    # Create archive directory if needed
    mkdir -p "${archive_dir}"

    local rotated=0
    local skipped=0

    # Find YAML/JSON metrics files older than retention period
    # Skip the archive directory and .gitkeep files
    # Skip files modified today (protect in-flight data)
    while IFS= read -r -d '' file; do
        local basename
        basename="$(basename "${file}")"

        # Skip .gitkeep and non-data files
        if [[ "${basename}" == ".gitkeep" ]]; then
            continue
        fi

        # Skip files in the archive subdirectory
        if [[ "${file}" == "${archive_dir}"* ]]; then
            continue
        fi

        # Check file age against retention period
        local file_age_days
        if [[ "$(uname -s)" == "Darwin" ]]; then
            # macOS: use stat -f
            local mod_time
            mod_time="$(stat -f '%m' "${file}")"
            local now
            now="$(date +%s)"
            file_age_days="$(( (now - mod_time) / 86400 ))"
        else
            # Linux/Git Bash: use stat -c or find -mtime
            local mod_time
            mod_time="$(stat -c '%Y' "${file}" 2>/dev/null || stat -f '%m' "${file}")"
            local now
            now="$(date +%s)"
            file_age_days="$(( (now - mod_time) / 86400 ))"
        fi

        if [[ "${file_age_days}" -ge "${retention_days}" ]]; then
            # Archive: move and compress
            mv "${file}" "${archive_dir}/"
            gzip -f "${archive_dir}/${basename}"
            rotated=$((rotated + 1))
        else
            skipped=$((skipped + 1))
        fi
    done < <(find "${metrics_dir}" -maxdepth 1 -type f -print0 2>/dev/null)

    echo "metrics: rotation complete — ${rotated} archived, ${skipped} retained (threshold: ${retention_days} days)"
}
