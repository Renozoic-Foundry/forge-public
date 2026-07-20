#!/usr/bin/env bash
# FORGE forge-sync-skills — generate .claude/skills/<name>/SKILL.md from canonical
# .forge/commands/<name>.md + .forge/commands/invocation-policy.yaml (Spec 491).
#
# Root-cause fix for command/skill divergence: the skill surface is GENERATED from the
# canonical command source (not hand-maintained), so it can no longer drift. The
# disable-model-invocation flag is stamped per the level-invariant policy manifest.
#
# Usage:
#   forge-sync-skills.sh                 Generate every policy skill into .claude/skills/.
#   forge-sync-skills.sh --check         Regenerate to a temp tree, diff vs on-disk;
#                                        exit non-zero + list drift. Exit 0 = in sync.
#   forge-sync-skills.sh --verify-policy AC9 classification gate: assert no command-form
#                                        name has a skill dir, every explicit skill is
#                                        disable-model-invocation: true, every
#                                        model-invokable skill is false. Exit non-zero on
#                                        any violation.
#   forge-sync-skills.sh --template-side Operate on template/ (canonical + target both
#                                        under template/) instead of repo root.
#   forge-sync-skills.sh -h|--help       Show this help.
#
# Exit codes: 0 = success / in-sync / policy-clean; 1 = drift (--check) / policy
#             violation (--verify-policy) / argument error.
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"
# Spec 329 frontmatter-aware helpers: strip_frontmatter, extract_frontmatter, bodies_equal.
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

MODE="generate"
TEMPLATE_SIDE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)         MODE="check"; shift ;;
    --verify-policy) MODE="verify-policy"; shift ;;
    --template-side) TEMPLATE_SIDE=true; shift ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      echo "Run 'forge-sync-skills.sh --help' for usage." >&2
      exit 1
      ;;
  esac
done

# --- Resolve canonical source + skills target (root, or template/ in --template-side) ---
if $TEMPLATE_SIDE; then
  CANONICAL_DIR="${PROJECT_DIR}/template/.forge/commands"
  SKILLS_DIR="${PROJECT_DIR}/template/.claude/skills"
  POLICY_FILE="${PROJECT_DIR}/template/.forge/commands/invocation-policy.yaml"
else
  CANONICAL_DIR="${FORGE_DIR}/commands"
  SKILLS_DIR="${PROJECT_DIR}/.claude/skills"
  POLICY_FILE="${FORGE_DIR}/commands/invocation-policy.yaml"
fi

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "ERROR: invocation policy not found: $POLICY_FILE" >&2
  exit 1
fi
if [[ ! -d "$CANONICAL_DIR" ]]; then
  echo "ERROR: canonical command dir not found: $CANONICAL_DIR" >&2
  exit 1
fi

# --- Read a bracketed list key from invocation-policy.yaml (space-separated names) ---
# Usage: policy_list commands   ->   prints one name per line.
policy_list() {
  local key="$1" line names
  line="$(grep -E "^${key}:" "$POLICY_FILE" | head -1)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  # Strip "key: [" prefix and trailing "]", then split on commas.
  names="${line#*[}"
  names="${names%]*}"
  echo "$names" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true
}

# --- Read the YAML `description:` from a canonical command file (frontmatter only) ---
read_description() {
  local file="$1" in_fm=false line
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "---" ]] && ! $in_fm; then
      in_fm=true
      continue
    elif [[ "$line" == "---" ]] && $in_fm; then
      break
    elif $in_fm; then
      if [[ "$line" =~ ^description:[[:space:]]*\"?(.*)$ ]]; then
        local val="${BASH_REMATCH[1]}"
        val="${val%\"}"   # strip closing quote if present
        echo "$val"
        return 0
      fi
    fi
  done < "$file"
}

# --- Read disable-model-invocation from an existing SKILL.md (preserve fallback) ---
read_existing_dmi() {
  local file="$1" in_fm=false line
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "---" ]] && ! $in_fm; then
      in_fm=true
      continue
    elif [[ "$line" == "---" ]] && $in_fm; then
      break
    elif $in_fm; then
      if [[ "$line" =~ ^disable-model-invocation:[[:space:]]*(true|false) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
      fi
    fi
  done < "$file"
}

# --- Write one SKILL.md (canonical frontmatter -> 3-line skill frontmatter + body) ---
# Args: <name> <disable-model-invocation flag> <output-skills-root>
write_skill() {
  local name="$1" dmi="$2" out_root="$3"
  local src="${CANONICAL_DIR}/${name}.md"
  local out_dir="${out_root}/${name}"
  local out="${out_dir}/SKILL.md"

  # Spec 491: --template-side canonical may carry a .md.jinja Copier-time variation
  # instead of a plain .md (e.g. template/.forge/commands/explore.md.jinja). Fall back
  # to it so the template skill surface generates from the same canonical body.
  if [[ ! -f "$src" ]] && [[ -f "${CANONICAL_DIR}/${name}.md.jinja" ]]; then
    src="${CANONICAL_DIR}/${name}.md.jinja"
  fi

  if [[ ! -f "$src" ]]; then
    echo "ERROR: canonical source missing for skill '${name}': ${CANONICAL_DIR}/${name}.md" >&2
    return 1
  fi

  local description
  description="$(read_description "$src")"
  if [[ -z "$description" ]]; then
    # Spec 491 T3: preserve the existing skill's description if canonical lacks one.
    description="$(read_description "${SKILLS_DIR}/${name}/SKILL.md")"
  fi

  mkdir -p "$out_dir"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "%s"\n' "$description"
    printf 'disable-model-invocation: %s\n' "$dmi"
    printf -- '---\n'
    # Spec 584 (SIG-574-03): the skill lives one directory DEEPER than its canonical command
    # (<root>/.claude/skills/<name>/SKILL.md vs <root>/.forge/commands/<name>.md), so
    # parent-relative markdown doc links need one more level: ](../../ -> ](../../../
    # Scoped to markdown link syntax only (idempotent: the ../../../ result no longer
    # matches the ](../../<non-dot> pattern); root-relative and external links untouched.
    strip_frontmatter < "$src" | sed -E 's/\]\(\.\.\/\.\.\/([^.])/](..\/..\/..\/\1/g'
  } > "$out"
}

# --- Generate every policy skill into a target root ---
generate_all() {
  local out_root="$1" name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    write_skill "$name" "false" "$out_root"
  done < <(policy_list skills_model_invokable)
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    write_skill "$name" "true" "$out_root"
  done < <(policy_list skills_explicit)
}

# ====================================================================
# Mode: verify-policy (AC9 — classification safety gate)
# ====================================================================
if [[ "$MODE" == "verify-policy" ]]; then
  VIOL=0

  # 1. No command-form name may have a .claude/skills/<name>/ directory.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ -d "${SKILLS_DIR}/${name}" ]]; then
      echo "VIOLATION: command-form '${name}' has a skill dir ${SKILLS_DIR#"${PROJECT_DIR}"/}/${name}/ (must be command-only)" >&2
      VIOL=$((VIOL + 1))
    fi
  done < <(policy_list commands)

  # 2. Every explicit skill must be disable-model-invocation: true.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    sf="${SKILLS_DIR}/${name}/SKILL.md"
    if [[ ! -f "$sf" ]]; then
      echo "VIOLATION: explicit skill '${name}' missing SKILL.md at ${sf#"${PROJECT_DIR}"/}" >&2
      VIOL=$((VIOL + 1))
      continue
    fi
    dmi="$(read_existing_dmi "$sf")"
    if [[ "$dmi" != "true" ]]; then
      echo "VIOLATION: explicit (gated) skill '${name}' must be disable-model-invocation: true (got '${dmi:-<none>}')" >&2
      VIOL=$((VIOL + 1))
    fi
  done < <(policy_list skills_explicit)

  # 3. Every model-invokable skill must be disable-model-invocation: false.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    sf="${SKILLS_DIR}/${name}/SKILL.md"
    if [[ ! -f "$sf" ]]; then
      echo "VIOLATION: model-invokable skill '${name}' missing SKILL.md at ${sf#"${PROJECT_DIR}"/}" >&2
      VIOL=$((VIOL + 1))
      continue
    fi
    dmi="$(read_existing_dmi "$sf")"
    if [[ "$dmi" != "false" ]]; then
      echo "VIOLATION: model-invokable skill '${name}' must be disable-model-invocation: false (got '${dmi:-<none>}')" >&2
      VIOL=$((VIOL + 1))
    fi
  done < <(policy_list skills_model_invokable)

  # 4. Spec 580: every invocable must carry exactly one grammar class (work-loop | lifecycle).
  #    Skip silently when the class_ keys are absent (pre-580 consumer policies).
  if grep -qE '^class_(work_loop|lifecycle):' "$POLICY_FILE"; then
    all_names="$(policy_list commands; policy_list skills_model_invokable; policy_list skills_explicit)"
    classed="$( { grep -E '^class_work_loop:' "$POLICY_FILE"; grep -E '^class_lifecycle:' "$POLICY_FILE"; } | sed -E 's/^[a-z_]+: *\[//; s/\]//' | tr ',' '\n' | tr -d ' ' )"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      if ! grep -qxF "$name" <<< "$classed"; then
        echo "VIOLATION: '${name}' has no grammar class (Spec 580 — add it to class_work_loop or class_lifecycle)" >&2
        VIOL=$((VIOL + 1))
      fi
    done <<< "$all_names"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      if ! grep -qxF "$name" <<< "$all_names"; then
        echo "VIOLATION: class entry '${name}' names an unknown invocable (Spec 580 — not in any policy set)" >&2
        VIOL=$((VIOL + 1))
      fi
    done <<< "$classed"
  fi

  if [[ "$VIOL" -eq 0 ]]; then
    echo "OK: invocation-policy verified — all command-form names skill-free; explicit skills true; model-invokable skills false; grammar classes complete."
    exit 0
  else
    echo "" >&2
    echo "FAILED: ${VIOL} policy violation(s) — invocation surface does not match invocation-policy.yaml." >&2
    exit 1
  fi
fi

# ====================================================================
# Mode: check (idempotency / drift gate)
# ====================================================================
if [[ "$MODE" == "check" ]]; then
  TMP_ROOT="$(mktemp -d)"
  trap 'rm -rf "$TMP_ROOT"' EXIT
  generate_all "$TMP_ROOT"

  DRIFT=0
  # Compare each generated skill against on-disk (CR-normalized).
  for gen in "$TMP_ROOT"/*/SKILL.md; do
    [[ -f "$gen" ]] || continue
    name="$(basename "$(dirname "$gen")")"
    disk="${SKILLS_DIR}/${name}/SKILL.md"
    if [[ ! -f "$disk" ]]; then
      echo "DRIFT: ${name} — missing on disk (${SKILLS_DIR#"${PROJECT_DIR}"/}/${name}/SKILL.md)"
      DRIFT=$((DRIFT + 1))
      continue
    fi
    if ! diff <(tr -d '\r' < "$gen") <(tr -d '\r' < "$disk") >/dev/null 2>&1; then
      echo "DRIFT: ${name} — SKILL.md differs from canonical-generated output"
      DRIFT=$((DRIFT + 1))
    fi
  done

  # Detect on-disk skill dirs not produced by the generator (stray / orphan skills).
  for d in "$SKILLS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    if [[ ! -f "${TMP_ROOT}/${name}/SKILL.md" ]]; then
      echo "DRIFT: ${name} — present on disk but not generated from policy (orphan skill)"
      DRIFT=$((DRIFT + 1))
    fi
  done

  if [[ "$DRIFT" -eq 0 ]]; then
    echo "OK: .claude/skills/ is in sync with canonical .forge/commands/ + invocation-policy.yaml"
    exit 0
  else
    echo ""
    echo "FAILED: ${DRIFT} skill(s) out of sync. Run forge-sync-skills.sh to regenerate."
    exit 1
  fi
fi

# ====================================================================
# Mode: generate (default — write the skill files)
# ====================================================================
generate_all "$SKILLS_DIR"

MI_COUNT="$(policy_list skills_model_invokable | grep -c . || true)"
EX_COUNT="$(policy_list skills_explicit | grep -c . || true)"
echo "## forge-sync-skills — Complete"
echo "Skills generated: $((MI_COUNT + EX_COUNT)) (${MI_COUNT} model-invokable, ${EX_COUNT} explicit)"
echo "Target: ${SKILLS_DIR#"${PROJECT_DIR}"/}/"
