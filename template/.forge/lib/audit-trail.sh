#!/usr/bin/env bash
# FORGE audit-trail.sh — Git-signed audit trail (Spec 103)
# Sourced by other FORGE scripts. Do not execute directly.
#
# Provides:
#   forge_audit_trail_gpg_available  — check if GPG signing is configured
#   forge_audit_trail_signed_commit  — create a GPG-signed commit
#   forge_audit_trail_signed_tag     — create a GPG-signed tag
#   forge_audit_trail_generate_manifest — generate audit manifest with hashes
#   forge_audit_trail_is_lane_b      — check if project is Lane B

# --- Lane B detection ---

forge_audit_trail_is_lane_b() {
  local project_dir="${1:-$PROJECT_DIR}"
  [[ -f "${project_dir}/docs/compliance/profile.yaml" ]]
}

# --- GPG detection ---

forge_audit_trail_gpg_available() {
  # Check if GPG signing is configured for git commits.
  # Returns 0 if available, 1 if not.
  local signing_key
  signing_key="$(git config --get user.signingkey 2>/dev/null || true)"
  if [[ -z "$signing_key" ]]; then
    return 1
  fi
  # Verify GPG itself is available
  if ! command -v gpg &>/dev/null; then
    return 1
  fi
  return 0
}

# --- Signed commit ---

forge_audit_trail_signed_commit() {
  # Create a GPG-signed commit with the given message.
  # Falls back to unsigned commit with warning if GPG is not configured.
  local message="$1"

  if forge_audit_trail_gpg_available; then
    git commit -S -m "$message"
    echo "Signed commit created." >&2
  else
    echo "WARNING: GPG signing not available — audit trail is unsigned. Configure GPG for full Lane B compliance." >&2
    git commit -m "$message"
  fi
}

# --- Signed tag ---

forge_audit_trail_signed_tag() {
  # Create a GPG-signed tag.
  # Falls back to annotated (unsigned) tag with warning if GPG is not configured.
  local tag_name="$1"
  local message="$2"

  if forge_audit_trail_gpg_available; then
    git tag -s "$tag_name" -m "$message"
    echo "Signed tag created: ${tag_name}" >&2
  else
    echo "WARNING: GPG signing not available — tag is unsigned. Configure GPG for full Lane B compliance." >&2
    git tag -a "$tag_name" -m "$message"
  fi
}

# --- Hash computation ---

_forge_hash_file() {
  # Compute SHA-256 hash of a file. Returns empty string if file doesn't exist.
  local filepath="$1"
  if [[ ! -f "$filepath" ]]; then
    echo ""
    return
  fi
  sha256sum "$filepath" 2>/dev/null | cut -d' ' -f1
}

# --- Manifest generation ---

forge_audit_trail_generate_manifest() {
  # Generate audit manifest for a closed spec.
  # Writes to docs/compliance/audit-manifest.json (appends entry).
  local spec_id="$1"
  local project_dir="${2:-$PROJECT_DIR}"
  local manifest_file="${project_dir}/docs/compliance/audit-manifest.json"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Find spec file
  local spec_file=""
  local f
  for f in "${project_dir}"/docs/specs/${spec_id}-*.md; do
    if [[ -f "$f" ]]; then
      spec_file="$f"
      break
    fi
  done

  if [[ -z "$spec_file" ]]; then
    echo "ERROR: No spec file found for spec ${spec_id}" >&2
    return 1
  fi

  # Compute spec hash
  local spec_hash
  spec_hash="$(_forge_hash_file "$spec_file")"

  # Compute gate state hashes
  local gate_hashes="[]"
  local gate_dir="${project_dir}/.forge/state"
  if [[ -d "$gate_dir" ]]; then
    gate_hashes="["
    local first=true
    local gate_file
    for gate_file in "${gate_dir}"/*"${spec_id}"*.json; do
      [[ -f "$gate_file" ]] || continue
      local gh
      gh="$(_forge_hash_file "$gate_file")"
      local gname
      gname="$(basename "$gate_file")"
      if $first; then
        first=false
      else
        gate_hashes+=","
      fi
      gate_hashes+="{\"file\":\"${gname}\",\"sha256\":\"${gh}\"}"
    done
    gate_hashes+="]"
  fi

  # Compute evidence artifact hashes
  local evidence_hashes="[]"
  local evidence_base="${project_dir}/tmp/evidence"
  local edir
  for edir in "${evidence_base}"/SPEC-"${spec_id}"-*/; do
    if [[ -d "$edir" ]]; then
      evidence_hashes="["
      local efirst=true
      local efile
      for efile in "${edir}"/*; do
        [[ -f "$efile" ]] || continue
        local eh
        eh="$(_forge_hash_file "$efile")"
        local ename
        ename="$(basename "$efile")"
        if $efirst; then
          efirst=false
        else
          evidence_hashes+=","
        fi
        evidence_hashes+="{\"file\":\"${ename}\",\"sha256\":\"${eh}\"}"
      done
      evidence_hashes+="]"
      break
    fi
  done

  # Get current commit hash
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"

  # Build the manifest entry
  local entry="{"
  entry+="\"spec_id\":\"${spec_id}\","
  entry+="\"timestamp\":\"${timestamp}\","
  entry+="\"commit_hash\":\"${commit_hash}\","
  entry+="\"spec_hash\":{\"file\":\"$(basename "$spec_file")\",\"sha256\":\"${spec_hash}\"},"
  entry+="\"gate_hashes\":${gate_hashes},"
  entry+="\"evidence_hashes\":${evidence_hashes}"
  entry+="}"

  # Ensure compliance directory exists
  mkdir -p "$(dirname "$manifest_file")"

  # Append to manifest (create if needed)
  if [[ -f "$manifest_file" ]]; then
    # Read existing, strip trailing ] and append
    local existing
    existing="$(cat "$manifest_file")"
    # Remove trailing ] and whitespace
    existing="${existing%]}"
    existing="${existing%,}"
    echo "${existing},${entry}]" > "$manifest_file"
  else
    echo "[${entry}]" > "$manifest_file"
  fi

  echo "Audit manifest updated: ${manifest_file}" >&2
}
