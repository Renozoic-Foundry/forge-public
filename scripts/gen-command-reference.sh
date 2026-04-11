#!/usr/bin/env bash
set -euo pipefail

# gen-command-reference.sh — Generate docs/command-reference.md from command source files.
# Reads template/.claude/commands/*.md and outputs a grouped markdown reference.
# Spec 214.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CMD_DIR="$REPO_ROOT/template/.claude/commands"

# --- Stage groupings (from docs/QUICK-REFERENCE.md) ---

declare -A STAGE_MAP
# Session and orientation
for cmd in now session note insights tab; do
  STAGE_MAP[$cmd]="Session and orientation"
done
# Planning and discovery
for cmd in explore brainstorm interview spec matrix consensus decision revise; do
  STAGE_MAP[$cmd]="Planning and discovery"
done
# Implementation
for cmd in implement close test trace parallel scheduler; do
  STAGE_MAP[$cmd]="Implementation"
done
# Lifecycle and maintenance
for cmd in forge forge-init forge-stoke onboarding config-change; do
  STAGE_MAP[$cmd]="Lifecycle and maintenance"
done
# Process and review
for cmd in evolve synthesize dependency-audit nanoclaw configure-nanoclaw; do
  STAGE_MAP[$cmd]="Process and review"
done

# Ordered stage list for output
STAGES=(
  "Session and orientation"
  "Planning and discovery"
  "Implementation"
  "Lifecycle and maintenance"
  "Process and review"
)

# --- Extract metadata from a command file ---

extract_description() {
  local file="$1"
  local in_frontmatter=0
  local frontmatter_found=0
  local desc=""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    # Detect YAML frontmatter
    if [[ "$line" == "---" ]]; then
      if [[ $in_frontmatter -eq 1 ]]; then
        in_frontmatter=0
        if [[ -n "$desc" ]]; then
          echo "$desc"
          return
        fi
        continue
      else
        in_frontmatter=1
        frontmatter_found=1
        continue
      fi
    fi

    # Inside frontmatter — look for description field
    if [[ $in_frontmatter -eq 1 ]]; then
      if [[ "$line" =~ ^description:\ *\"(.+)\"$ ]]; then
        desc="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^description:\ *(.+)$ ]]; then
        desc="${BASH_REMATCH[1]}"
      fi
      continue
    fi

    # Outside frontmatter — find the first substantive line
    if [[ $frontmatter_found -eq 0 ]]; then
      # Skip empty lines, comment headers, markdown headers, blockquotes, deprecated notices
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^# ]] && continue
      # Use blockquote as description (strip "> " prefix), but skip Note/meta blockquotes
      if [[ "$line" =~ ^\>\ \*\*Note ]]; then
        continue
      fi
      if [[ "$line" =~ ^\>\ *$ ]]; then
        continue
      fi
      if [[ "$line" =~ ^\>\ (.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
      fi
      # Found a substantive line
      echo "$line"
      return
    fi
  done < "$file"

  # Fallback
  echo "(no description)"
}

extract_model_tier() {
  local file="$1"
  local in_frontmatter=0
  local tier=""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "---" ]]; then
      if [[ $in_frontmatter -eq 1 ]]; then
        break
      else
        in_frontmatter=1
        continue
      fi
    fi

    if [[ $in_frontmatter -eq 1 ]]; then
      if [[ "$line" =~ ^model_tier:\ *(.+)$ ]]; then
        tier="${BASH_REMATCH[1]}"
      fi
      continue
    fi

    # No frontmatter — check for legacy comment format
    if [[ "$line" =~ ^#\ Model-Tier:\ *(.+)$ ]]; then
      tier="${BASH_REMATCH[1]}"
      break
    fi
    # Stop scanning after first non-comment, non-empty line
    [[ -n "$line" && ! "$line" =~ ^# ]] && break
  done < "$file"

  echo "${tier:-sonnet}"
}

# --- Build command data ---

declare -A CMD_DESC
declare -A CMD_TIER

total=0
# Process .md files
for filepath in "$CMD_DIR"/*.md; do
  [[ -f "$filepath" ]] || continue
  filename="$(basename "$filepath" .md)"
  CMD_DESC[$filename]="$(extract_description "$filepath")"
  CMD_TIER[$filename]="$(extract_model_tier "$filepath")"
  total=$((total + 1))
done
# Process .md.jinja files (e.g., explore.md.jinja)
for filepath in "$CMD_DIR"/*.md.jinja; do
  [[ -f "$filepath" ]] || continue
  filename="$(basename "$filepath" .md.jinja)"
  # Skip if already processed as .md
  [[ -n "${CMD_DESC[$filename]+x}" ]] && continue
  CMD_DESC[$filename]="$(extract_description "$filepath")"
  CMD_TIER[$filename]="$(extract_model_tier "$filepath")"
  total=$((total + 1))
done

# --- Output ---

cat <<HEADER
# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in \`template/.claude/commands/\`.

**Total commands: $total**
HEADER

for stage in "${STAGES[@]}"; do
  # Collect commands for this stage
  stage_cmds=()
  for cmd in "${!CMD_DESC[@]}"; do
    if [[ "${STAGE_MAP[$cmd]:-}" == "$stage" ]]; then
      stage_cmds+=("$cmd")
    fi
  done

  # Skip empty stages
  [[ ${#stage_cmds[@]} -eq 0 ]] && continue

  # Sort commands alphabetically
  mapfile -t sorted < <(printf '%s\n' "${stage_cmds[@]}" | sort)

  echo ""
  echo "## $stage"
  echo ""
  echo "| Command | Model tier | Description |"
  echo "|---------|-----------|-------------|"
  for cmd in "${sorted[@]}"; do
    echo "| \`/$cmd\` | ${CMD_TIER[$cmd]} | ${CMD_DESC[$cmd]} |"
  done
done

cat <<'FOOTER'

## Next Steps

See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for detailed usage patterns and workflow sequences.

---

*Last verified against Spec 214.*
FOOTER
