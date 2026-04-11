#!/usr/bin/env bash
# FORGE forge-sync-commands — generate agent-specific command wrappers from canonical source
# Usage: forge-sync-commands.sh [--agents claude-code,cursor,copilot] [--scope user|project|both] [--dry-run]
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

source "${FORGE_DIR}/lib/logging.sh"
forge_log_init "forge-sync-commands"

# --- Defaults ---
DRY_RUN=false
CHECK_MODE=false
AGENTS_OVERRIDE=""
SCOPE="project"
CANONICAL_DIR="${FORGE_DIR}/commands"
TRIGGER_MAP="${FORGE_DIR}/templates/codex-trigger-map.yaml"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents)
      AGENTS_OVERRIDE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --check)
      CHECK_MODE=true
      shift
      ;;
    --scope)
      SCOPE="$2"
      if [[ "$SCOPE" != "user" && "$SCOPE" != "project" && "$SCOPE" != "both" ]]; then
        echo "Error: --scope must be 'user', 'project', or 'both'" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      echo "Usage: forge-sync-commands.sh [--agents claude-code,cursor,copilot,cline] [--scope user|project|both] [--dry-run]"
      echo ""
      echo "Generate agent-specific command wrappers from .forge/commands/ (canonical source)."
      echo ""
      echo "Options:"
      echo "  --check         Check if .claude/commands/ is in sync (exits non-zero if drifted)"
      echo "  --agents LIST   Comma-separated agent list (default: read from onboarding.yaml)"
      echo "  --scope SCOPE   Installation scope: project (default), user, or both"
      echo "                  project: sync to project agent directories (existing behavior)"
      echo "                  user: install Codex skills to ~/.codex/skills/ and commands to ~/.claude/commands/"
      echo "                  both: do both project and user installation"
      echo "  --dry-run       Report what would be generated without writing files"
      echo "  -h, --help      Show this help"
      echo ""
      echo "Supported agents: claude-code, cursor, copilot, cline"
      echo ""
      echo "If no --agents flag and no onboarding.yaml, defaults to claude-code only."
      exit 0
      ;;
    *)
      forge_log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# --- Determine which agents to generate for ---
resolve_agents() {
  if [[ -n "$AGENTS_OVERRIDE" ]]; then
    echo "$AGENTS_OVERRIDE" | tr ',' '\n'
    return
  fi

  local onboarding_file="${FORGE_DIR}/onboarding.yaml"
  if [[ -f "$onboarding_file" ]]; then
    # Parse agents section from onboarding.yaml
    local in_agents=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^agents: ]]; then
        in_agents=true
        continue
      fi
      if $in_agents; then
        # Stop at next top-level key (no leading whitespace)
        if [[ "$line" =~ ^[a-z_] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
          break
        fi
        # Parse "  key: true" lines
        if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(true|false) ]]; then
          local agent_key="${BASH_REMATCH[1]}"
          local agent_val="${BASH_REMATCH[2]}"
          if [[ "$agent_val" == "true" ]]; then
            # Convert yaml key to agent name (underscore to hyphen)
            echo "${agent_key//_/-}"
          fi
        fi
      fi
    done < "$onboarding_file"
    return
  fi

  # Default: claude-code only
  echo "claude-code"
}

mapfile -t AGENTS < <(resolve_agents)

if [[ ${#AGENTS[@]} -eq 0 ]]; then
  AGENTS=("claude-code")
fi

forge_log_info "Target agents: ${AGENTS[*]}"

# --- Validate canonical source exists ---
if [[ ! -d "$CANONICAL_DIR" ]]; then
  forge_log_error "Canonical command directory not found: $CANONICAL_DIR"
  exit 1
fi

# --- Strip YAML frontmatter from a file ---
# Reads stdin, outputs content without leading ---...--- block
strip_frontmatter() {
  local in_frontmatter=false
  local frontmatter_done=false
  while IFS= read -r line; do
    if ! $frontmatter_done; then
      if [[ "$line" == "---" ]] && ! $in_frontmatter; then
        in_frontmatter=true
        continue
      elif [[ "$line" == "---" ]] && $in_frontmatter; then
        frontmatter_done=true
        continue
      elif $in_frontmatter; then
        continue
      fi
    fi
    printf '%s\n' "$line"
  done
}

# --- Get agent's native command directory ---
agent_command_dir() {
  local agent="$1"
  case "$agent" in
    claude-code) echo "${PROJECT_DIR}/.claude/commands" ;;
    cursor)      echo "${PROJECT_DIR}/.cursor/commands" ;;
    copilot)     echo "${PROJECT_DIR}/.github/prompts" ;;
    cline)       echo "${PROJECT_DIR}/.cline/commands" ;;
    *)
      forge_log_warn "Unknown agent: $agent — skipping"
      echo ""
      ;;
  esac
}

# --- Check if file is a FORGE-managed command ---
is_forge_command() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  # Check first 5 lines for the FORGE header or subcommand header
  head -5 "$file" | grep -qE "(# Framework: FORGE|## Subcommand:)" 2>/dev/null
}

# --- Read frontmatter field from a canonical command file ---
read_frontmatter_field() {
  local file="$1"
  local field="$2"
  local in_frontmatter=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]] && ! $in_frontmatter; then
      in_frontmatter=true
      continue
    elif [[ "$line" == "---" ]] && $in_frontmatter; then
      break
    elif $in_frontmatter; then
      if [[ "$line" =~ ^${field}:[[:space:]]*\"?([^\"]*)\"? ]]; then
        echo "${BASH_REMATCH[1]}"
        return
      fi
    fi
  done < "$file"
}

# --- Generate Copilot frontmatter wrapper ---
generate_copilot_header() {
  local desc="$1"
  echo "---"
  echo "mode: agent"
  echo "description: \"$desc\""
  echo "---"
}

# --- Read a field from the trigger map for a given command ---
# Usage: read_trigger_field "implement" "action"
read_trigger_field() {
  local cmd_name="$1"
  local field="$2"
  local in_command=false
  local found_commands=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^commands: ]]; then
      found_commands=true
      continue
    fi
    if ! $found_commands; then
      continue
    fi
    # Match command key (2-space indent)
    if [[ "$line" =~ ^[[:space:]][[:space:]]([a-z_-]+): ]] && [[ ! "$line" =~ ^[[:space:]][[:space:]][[:space:]][[:space:]] ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$cmd_name" ]]; then
        in_command=true
        continue
      else
        if $in_command; then
          break
        fi
      fi
    fi
    if $in_command; then
      if [[ "$line" =~ ^[[:space:]]+${field}:[[:space:]]*\"?(.*)\"?$ ]]; then
        local val="${BASH_REMATCH[1]}"
        # Strip trailing quote if present
        val="${val%\"}"
        echo "$val"
        return
      fi
    fi
  done < "$TRIGGER_MAP"
}

# --- Generate Codex skill files for a single command ---
generate_codex_skill() {
  local src_file="$1"
  local cmd_name="$2"
  local skill_dir="$3"

  # Read trigger map fields
  local action description triggers
  action="$(read_trigger_field "$cmd_name" "action")"
  triggers="$(read_trigger_field "$cmd_name" "triggers")"

  # Read description from canonical frontmatter
  description="$(read_frontmatter_field "$src_file" "description")"

  # Fallback if trigger map has no entry
  if [[ -z "$action" ]]; then
    action="run the FORGE /$cmd_name command"
  fi
  if [[ -z "$triggers" ]]; then
    triggers="'/$cmd_name'"
  fi

  # Strip frontmatter to get body
  local body
  body="$(strip_frontmatter < "$src_file")"

  # Convert command name to display name (hyphen to space, title case first word)
  local display_name
  display_name="$(echo "$cmd_name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')"

  if $DRY_RUN; then
    echo "  Would generate Codex skill: $skill_dir/SKILL.md"
    echo "  Would generate Codex agent: $skill_dir/agents/openai.yaml"
    return
  fi

  mkdir -p "$skill_dir/agents"

  # Generate SKILL.md from template
  local skill_desc="${description}. Use when the user wants to ${action}. Triggers on: ${triggers}."

  cat > "$skill_dir/SKILL.md" <<SKILL_EOF
---
name: forge-${cmd_name}
description: "${skill_desc}"
---

# FORGE: ${display_name}

${body}

## Project Context

When inside a FORGE-managed project (has AGENTS.md or .forge/ directory), this command reads project-level configuration:
- AGENTS.md for autonomy levels and enforcement rules
- docs/specs/ for spec files
- docs/sessions/ for session logs and signals
- docs/backlog.md for prioritized work

When NOT inside a FORGE project, this command will note that no project context is available and suggest running \`forge install\` followed by \`/forge init\` to set up a project.
SKILL_EOF

  # Generate agents/openai.yaml
  cat > "$skill_dir/agents/openai.yaml" <<AGENT_EOF
# Codex agent configuration for forge-${cmd_name}
model: o4-mini
instructions_file: ../SKILL.md
AGENT_EOF
}

# --- Generate all Codex skills ---
generate_codex_skills() {
  local codex_skills_dir="${HOME}/.codex/skills"
  forge_log_step "Generating Codex skills in $codex_skills_dir"

  if [[ ! -f "$TRIGGER_MAP" ]]; then
    forge_log_warn "Trigger map not found: $TRIGGER_MAP — skipping Codex skill generation"
    return
  fi

  local codex_count=0
  for src_file in "$CANONICAL_DIR"/*.md "$CANONICAL_DIR"/*.md.jinja; do
    [[ -f "$src_file" ]] || continue

    local src_base cmd_name skill_dir
    src_base="$(basename "$src_file")"
    # Strip .md or .md.jinja suffix to get command name
    cmd_name="${src_base%.md.jinja}"
    cmd_name="${cmd_name%.md}"
    skill_dir="${codex_skills_dir}/forge-${cmd_name}"

    generate_codex_skill "$src_file" "$cmd_name" "$skill_dir"
    codex_count=$((codex_count + 1))
  done

  forge_log_info "  Generated: $codex_count Codex skills in $codex_skills_dir"
}

# --- Install commands to user-level Claude Code directory ---
install_claude_code_user() {
  local user_cmd_dir="${HOME}/.claude/commands"
  forge_log_step "Installing FORGE commands to $user_cmd_dir"

  if $DRY_RUN; then
    local count=0
    for src_file in "$CANONICAL_DIR"/*.md "$CANONICAL_DIR"/*.md.jinja; do
      [[ -f "$src_file" ]] || continue
      local src_base
      src_base="$(basename "$src_file")"
      echo "  Would install: ${user_cmd_dir}/${src_base}"
      count=$((count + 1))
    done
    forge_log_info "  Would install: $count commands to $user_cmd_dir"
    return
  fi

  mkdir -p "$user_cmd_dir"

  local user_count=0
  for src_file in "$CANONICAL_DIR"/*.md "$CANONICAL_DIR"/*.md.jinja; do
    [[ -f "$src_file" ]] || continue

    local src_base dst_file
    src_base="$(basename "$src_file")"
    dst_file="${user_cmd_dir}/${src_base}"

    # Check for conflicts: existing non-FORGE file
    if [[ -f "$dst_file" ]] && ! is_forge_command "$dst_file"; then
      forge_log_warn "CONFLICT: $dst_file exists and is not a FORGE command — skipping"
      continue
    fi

    strip_frontmatter < "$src_file" > "$dst_file"
    user_count=$((user_count + 1))
  done

  forge_log_info "  Installed: $user_count commands to $user_cmd_dir"
}

# --- Check mode: verify .claude/commands/ matches what sync would generate ---
if $CHECK_MODE; then
  DRIFT_COUNT=0
  for src_file in "$CANONICAL_DIR"/*.md "$CANONICAL_DIR"/*.md.jinja; do
    [[ -f "$src_file" ]] || continue
    src_base="$(basename "$src_file")"
    dst_file="${PROJECT_DIR}/.claude/commands/${src_base}"

    if [[ ! -f "$dst_file" ]]; then
      echo "DRIFT: $src_base — missing from .claude/commands/"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
      continue
    fi

    expected="$(strip_frontmatter < "$src_file")"
    actual="$(cat "$dst_file")"
    if [[ "$expected" != "$actual" ]]; then
      echo "DRIFT: $src_base — content differs"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    fi
  done

  # Check for files in .claude/commands/ not in canonical source
  for dst_file in "${PROJECT_DIR}/.claude/commands/"*.md "${PROJECT_DIR}/.claude/commands/"*.md.jinja; do
    [[ -f "$dst_file" ]] || continue
    dst_base="$(basename "$dst_file")"
    if [[ ! -f "${CANONICAL_DIR}/${dst_base}" ]]; then
      if is_forge_command "$dst_file"; then
        echo "DRIFT: $dst_base — exists in .claude/commands/ but not in .forge/commands/"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
      fi
    fi
  done

  if [[ $DRIFT_COUNT -eq 0 ]]; then
    echo "OK: .claude/commands/ is in sync with .forge/commands/"
    exit 0
  else
    echo ""
    echo "FAILED: $DRIFT_COUNT files out of sync. Run forge-sync-commands.sh to fix."
    exit 1
  fi
fi

# --- Counters ---
GENERATED=0
# shellcheck disable=SC2034
SKIPPED=0
CONFLICTS=0

# --- User-level installation ---
if [[ "$SCOPE" == "user" || "$SCOPE" == "both" ]]; then
  generate_codex_skills
  install_claude_code_user
fi

# --- Project-level installation ---
if [[ "$SCOPE" != "user" ]]; then
# Process each agent
for agent in "${AGENTS[@]}"; do
  target_dir="$(agent_command_dir "$agent")"
  if [[ -z "$target_dir" ]]; then
    continue
  fi

  forge_log_step "Generating commands for: $agent"

  if ! $DRY_RUN; then
    mkdir -p "$target_dir"
  fi

  # Process each canonical command
  for src_file in "$CANONICAL_DIR"/*.md "$CANONICAL_DIR"/*.md.jinja; do
    [[ -f "$src_file" ]] || continue

    src_base="$(basename "$src_file")"
    dst_file="${target_dir}/${src_base}"

    # Check for conflicts: existing non-FORGE file with same name
    if [[ -f "$dst_file" ]] && ! is_forge_command "$dst_file"; then
      forge_log_warn "CONFLICT: $dst_file exists and is not a FORGE command — skipping"
      CONFLICTS=$((CONFLICTS + 1))
      continue
    fi

    # Read description for Copilot wrapper
    local_desc="$(read_frontmatter_field "$src_file" "description")"

    if $DRY_RUN; then
      echo "  Would generate: $dst_file"
      GENERATED=$((GENERATED + 1))
      continue
    fi

    # Generate the file based on agent type
    case "$agent" in
      claude-code|cursor|cline)
        # Strip frontmatter, copy command body as-is
        strip_frontmatter < "$src_file" > "$dst_file"
        ;;
      copilot)
        # Add Copilot-specific frontmatter, strip FORGE frontmatter from body
        {
          generate_copilot_header "$local_desc"
          strip_frontmatter < "$src_file"
        } > "$dst_file"
        ;;
    esac

    GENERATED=$((GENERATED + 1))
  done

  forge_log_info "  Generated: $GENERATED files in $target_dir"
done
fi  # end project-level installation

# --- Summary ---
echo ""
echo "## forge-sync-commands — Complete"
echo "Agents: ${AGENTS[*]}"
echo "Commands generated: $GENERATED"
echo "Conflicts (skipped): $CONFLICTS"
if $DRY_RUN; then
  echo "Mode: dry-run (no files written)"
fi
