#!/usr/bin/env bash
set -euo pipefail

# gen-command-reference.sh — Generate docs/command-reference.md from command source files.
# Reads .forge/commands/*.md (the canonical command surface) and outputs a grouped markdown reference.
# Spec 214; source repointed to canonical .forge/commands/ + STAGE_MAP completeness guard (Spec 510);
# shared metadata lib + invocation-form column + provenance/revision-history footer (Spec 571).
#
# Usage: gen-command-reference.sh [--write]
#   (default)  print the generated reference to stdout
#   --write    write docs/command-reference.md in place

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/command-stages.sh
source "$SCRIPT_DIR/lib/command-stages.sh"

# --- Build command data ---

declare -A CMD_DESC
declare -A CMD_TIER

total=0
for filepath in "$CMD_DIR"/*.md; do
  [[ -f "$filepath" ]] || continue
  filename="$(basename "$filepath" .md)"
  CMD_DESC[$filename]="$(extract_description "$filepath")"
  CMD_TIER[$filename]="$(extract_model_tier "$filepath")"
  total=$((total + 1))
done

load_invocation_forms

# --- STAGE_MAP completeness guard (Spec 510) ---
unmapped=()
for cmd in "${!CMD_DESC[@]}"; do
  if [[ -z "${STAGE_MAP[$cmd]:-}" ]]; then
    unmapped+=("$cmd")
  fi
done
if [[ ${#unmapped[@]} -gt 0 ]]; then
  mapfile -t unmapped_sorted < <(printf '%s\n' "${unmapped[@]}" | sort)
  {
    echo "ERROR: gen-command-reference.sh — ${#unmapped_sorted[@]} canonical command(s) have no STAGE_MAP entry:"
    printf '  - %s\n' "${unmapped_sorted[@]}"
    echo "Add each to a STAGE_MAP bucket in scripts/lib/command-stages.sh — Spec 510 drift guard."
  } >&2
  exit 1
fi

# --- Invocation-form completeness guard (Spec 571) ---
# Every canonical command must be classified in invocation-policy.yaml.
unlisted=()
for cmd in "${!CMD_DESC[@]}"; do
  if [[ -z "${CMD_FORM[$cmd]:-}" ]]; then
    unlisted+=("$cmd")
  fi
done
if [[ ${#unlisted[@]} -gt 0 ]]; then
  mapfile -t unlisted_sorted < <(printf '%s\n' "${unlisted[@]}" | sort)
  {
    echo "ERROR: gen-command-reference.sh — ${#unlisted_sorted[@]} canonical command(s) missing from invocation-policy.yaml:"
    printf '  - %s\n' "${unlisted_sorted[@]}"
    echo "Add each to commands / skills_model_invokable / skills_explicit — Spec 491 policy manifest."
  } >&2
  exit 1
fi

# --- Output ---

HASH="$(source_content_hash)"
VERSION="$(plugin_version)"

render() {
  emit_generated_header "scripts/gen-command-reference.sh" "$HASH" "$VERSION"
  cat <<HEADER
# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in \`.forge/commands/\`.

**Total commands: $total**

**Invocation forms** (Spec 491 policy manifest): \`command\` — a \`.claude/commands\` slash command,
never model-invoked; \`skill (auto)\` — a skill Claude may invoke opportunistically (read-only /
additive / reversible); \`skill (explicit)\` — a skill invoked only when you name it. Every entry is
also invocable outside Claude Code as \`bin/forge <name>\` (Windows: \`bin\\forge.ps1 <name>\`).
Model tier is operator-advisory only (ADR-316) — Claude Code's model picker is the real selector.
HEADER

  for stage in "${STAGES[@]}"; do
    stage_cmds=()
    for cmd in "${!CMD_DESC[@]}"; do
      if [[ "${STAGE_MAP[$cmd]:-}" == "$stage" ]]; then
        stage_cmds+=("$cmd")
      fi
    done

    [[ ${#stage_cmds[@]} -eq 0 ]] && continue

    mapfile -t sorted < <(printf '%s\n' "${stage_cmds[@]}" | sort)

    echo ""
    echo "## $stage"
    echo ""
    echo "| Command | Form | Model tier (advisory) | Description |"
    echo "|---------|------|-----------------------|-------------|"
    for cmd in "${sorted[@]}"; do
      echo "| \`$(advertised_invocation "$cmd")\` | ${CMD_FORM[$cmd]} | ${CMD_TIER[$cmd]} | ${CMD_DESC[$cmd]} |"
    done
  done

  # /forge subcommands (parsed from forge.md's help block)
  echo ""
  echo "## /forge subcommands"
  echo ""
  echo "| Subcommand | Description |"
  echo "|------------|-------------|"
  extract_forge_subcommands | while IFS=$'\t' read -r name desc; do
    echo "| \`/forge $name\` | $desc |"
  done

  cat <<'FOOTER'

## Next Steps

See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for detailed usage patterns and workflow sequences.
FOOTER

  emit_provenance_footer "scripts/gen-command-reference.sh" "$HASH" "$VERSION"
}

if [[ "${1:-}" == "--write" ]]; then
  render > "$REPO_ROOT/docs/command-reference.md"
  echo "Wrote docs/command-reference.md (source hash $HASH)" >&2
else
  render
fi
