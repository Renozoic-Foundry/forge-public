#!/usr/bin/env bash
# sync-to-public.sh — Sync the public subset of d:\forge to d:\forge-public
#
# Architecture:
#   d:\forge       — full development history (specs, sessions, backlog) — PRIVATE
#   d:\forge-public — curated public face (template/, root docs) — PUBLIC
#
# This script copies only the public-safe files. Private content
# (docs/specs/, docs/sessions/, docs/backlog.md, docs/decisions/,
# docs/digests/, docs/pilot/) is NEVER synced.
#
# Usage:
#   bash scripts/sync-to-public.sh              # dry-run (shows what would change)
#   bash scripts/sync-to-public.sh --execute    # apply changes
#
# Spec: 165

set -euo pipefail

FORGE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORGE_PUBLIC="${FORGE_PUBLIC:-$(cd "${FORGE_SRC}/../forge-public" 2>/dev/null && pwd || echo "")}"
DRY_RUN=true

if [[ "${1:-}" == "--execute" ]]; then
  DRY_RUN=false
fi

if [[ -z "$FORGE_PUBLIC" ]] || [[ ! -d "$FORGE_PUBLIC" ]]; then
  echo "ERROR: forge-public directory not found."
  echo "  Expected: ${FORGE_SRC}/../forge-public"
  echo "  Set FORGE_PUBLIC=/path/to/forge-public to override."
  exit 1
fi

echo "FORGE sync: ${FORGE_SRC} → ${FORGE_PUBLIC}"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY RUN — pass --execute to apply changes"
  echo ""
fi

# --- Pre-flight: validate public docs (Spec 219) ---
VALIDATE_SCRIPT="${FORGE_SRC}/scripts/validate-public-docs.sh"
if [[ -f "$VALIDATE_SCRIPT" ]]; then
  echo "==> Pre-flight: validating public docs"
  if ! bash "$VALIDATE_SCRIPT"; then
    echo ""
    echo "ERROR: Public docs validation failed. Fix errors before syncing."
    exit 1
  fi
  echo ""
else
  echo "NOTE: validate-public-docs.sh not found — skipping docs validation"
  echo ""
fi

# Sync a directory with delete semantics
# Uses rsync if available (Linux/Mac), otherwise Python shutil (cross-platform)
sync_dir() {
  local src="$1" dst="$2"
  if command -v rsync &>/dev/null; then
    local flags="-av --delete"
    [[ "$DRY_RUN" == "true" ]] && flags="${flags} --dry-run"
    rsync ${flags} "${src}/" "${dst}/"
  else
    # Fallback: Python mirror (works on Windows Git Bash without rsync)
    python3 - "${src}" "${dst}" "${DRY_RUN}" << 'PYEOF'
import sys, os, shutil, filecmp

src, dst, dry_run = sys.argv[1], sys.argv[2], sys.argv[3] == "true"

# Paths (relative to src root) that are runtime artifacts — never sync to public
EXCLUDE_DIRS = {".forge/logs", ".forge/metrics"}

def rel(path, base):
    return os.path.relpath(path, base).replace("\\", "/")

def mirror(src, dst, dry_run, root=None):
    if root is None:
        root = src
    os.makedirs(dst, exist_ok=True)
    src_names = set(os.listdir(src))
    dst_names = set(os.listdir(dst)) if os.path.exists(dst) else set()

    # Copy new/changed files
    for name in sorted(src_names):
        s = os.path.join(src, name)
        d = os.path.join(dst, name)
        rel_path = rel(s, root)
        # Skip excluded runtime directories
        if any(rel_path == ex or rel_path.startswith(ex + "/") for ex in EXCLUDE_DIRS):
            continue
        if os.path.isdir(s):
            mirror(s, d, dry_run, root)
        else:
            if not os.path.exists(d) or not filecmp.cmp(s, d, shallow=False):
                print(f"{'(dry-run) ' if dry_run else ''}copy: {d}")
                if not dry_run:
                    shutil.copy2(s, d)

    # Delete files in dst not in src (or excluded from src)
    for name in sorted(dst_names - src_names):
        d = os.path.join(dst, name)
        print(f"{'(dry-run) ' if dry_run else ''}delete: {d}")
        if not dry_run:
            if os.path.isdir(d):
                shutil.rmtree(d)
            else:
                os.remove(d)

mirror(src, dst, dry_run)
PYEOF
  fi
}

# --- Sync template/ (the core deliverable) ---
# Runtime artifacts excluded: .forge/logs/, .forge/metrics/ (populated at runtime, not part of the template)
echo "==> template/"
sync_dir "${FORGE_SRC}/template" "${FORGE_PUBLIC}/template"

# --- Sync root public-facing files ---
echo ""
echo "==> Root files"
for f in copier.yml README.md ACKNOWLEDGEMENTS.md CONTRIBUTING.md LICENSE SECURITY.md install.sh install.ps1 forge-bootstrap.md; do
  if [[ -f "${FORGE_SRC}/${f}" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "(dry-run) would copy: ${f}"
    else
      cp "${FORGE_SRC}/${f}" "${FORGE_PUBLIC}/${f}"
      echo "copied: ${f}"
    fi
  fi
done

# --- Sync .claude/commands/ (root-level commands for local clone usage) ---
echo ""
echo "==> .claude/commands/ (root-level)"
mkdir -p "${FORGE_PUBLIC}/.claude/commands"
for f in forge.md forge-init.md; do
  if [[ -f "${FORGE_SRC}/.claude/commands/${f}" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "(dry-run) would copy: .claude/commands/${f}"
    else
      cp "${FORGE_SRC}/.claude/commands/${f}" "${FORGE_PUBLIC}/.claude/commands/${f}"
      echo "copied: .claude/commands/${f}"
    fi
  fi
done

# --- Sync scripts/ (public scripts only) ---
echo ""
echo "==> scripts/ (public subset)"
PUBLIC_SCRIPTS=(
  "sync-to-public.sh"
  "validate-bash.sh"
  "validate-command-sync.sh"
  "smoke-test-runtime.sh"
  "validate-spec-index.sh"
  "validate-readme-stats.sh"
  "smoke-test-template.sh"
  "gen-command-reference.sh"
)
mkdir -p "${FORGE_PUBLIC}/scripts"
for script in "${PUBLIC_SCRIPTS[@]}"; do
  if [[ -f "${FORGE_SRC}/scripts/${script}" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "(dry-run) would copy: scripts/${script}"
    else
      cp "${FORGE_SRC}/scripts/${script}" "${FORGE_PUBLIC}/scripts/${script}"
      echo "copied: scripts/${script}"
    fi
  fi
done

# --- Sync docs/ (public subset only — NO specs/sessions/backlog/decisions/digests) ---
echo ""
echo "==> docs/ (public subset)"
PUBLIC_DOC_FILES=(
  "docs/roadmap.md"
  "docs/concept-overview.md"
  "docs/getting-started.md"
  "docs/command-reference.md"
  "docs/example-spec.md"
  "docs/faq.md"
  "docs/agents-config-reference.md"
  "docs/style-guide.md"
  "docs/QUICK-REFERENCE.md"
)
for f in "${PUBLIC_DOC_FILES[@]}"; do
  if [[ -f "${FORGE_SRC}/${f}" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "(dry-run) would copy: ${f}"
    else
      mkdir -p "$(dirname "${FORGE_PUBLIC}/${f}")"
      cp "${FORGE_SRC}/${f}" "${FORGE_PUBLIC}/${f}"
      echo "copied: ${f}"
    fi
  fi
done

# --- Post-sync PII verification (--execute mode only) ---
if [[ "$DRY_RUN" == "false" ]]; then
  echo ""
  echo "==> PII verification"

  # Configurable PII patterns — add/remove as needed
  PII_PATTERNS=(
    "bwcarty"
    "bcarty"
    "automationdirect"
    "7126376745"
    "adcpolaris01"
  )

  pii_found=0
  pii_report=""
  for pattern in "${PII_PATTERNS[@]}"; do
    # Search all text files, exclude .git directory
    matches=$(grep -rl --include='*.md' --include='*.yml' --include='*.yaml' \
      --include='*.json' --include='*.sh' --include='*.ps1' --include='*.py' \
      --include='*.jinja' --include='*.txt' --include='*.html' --include='*.css' \
      --include='*.js' --include='*.toml' \
      "${pattern}" "${FORGE_PUBLIC}/" 2>/dev/null | grep -v '\.git/' || true)
    if [[ -n "$matches" ]]; then
      count=$(echo "$matches" | wc -l)
      pii_found=$((pii_found + count))
      pii_report="${pii_report}  Pattern '${pattern}' found in ${count} file(s):\n"
      while IFS= read -r match_file; do
        pii_report="${pii_report}    - ${match_file}\n"
      done <<< "$matches"
    fi
  done

  if [[ "$pii_found" -gt 0 ]]; then
    echo "WARNING: PII patterns detected in forge-public!"
    echo ""
    echo -e "${pii_report}"
    echo ""
    read -rp "PII matches found. Proceed anyway? (y/N): " proceed
    if [[ "${proceed,,}" != "y" ]]; then
      echo "Aborted. Review and clean the flagged files before syncing."
      exit 1
    fi
    echo "Proceeding despite PII matches (operator override)."
  else
    echo "PII check: clean"
  fi
fi

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run complete. Run with --execute to apply."
else
  echo "Sync complete."
fi
