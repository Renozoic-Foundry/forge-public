#!/usr/bin/env bash
# FORGE plugin-parity-check (Spec 463, P1=C two-source parity gate).
#
# Slice 1 ships TWO sources of the FORGE behavioral payload:
#   1. template/.claude/  — the Copier source (rendered into consumer projects).
#   2. .claude/           — the plugin payload source. The plugin manifest
#                           (.claude-plugin/plugin.json) points its component
#                           paths at this tree (./.claude/commands, ./.claude/agents,
#                           and convention-discovered ./.claude/skills).
#
# This gate FAILs on byte-level drift between the two sources across the common
# subset (commands/, agents/, skills/). Forward-compatible with the future
# single-source generator (NC-1a / Spec 480): when that lands, this gate becomes
# the generator's drift detector.
#
# Usage:
#   plugin-parity-check.sh            Check parity; non-zero exit on drift.
#   plugin-parity-check.sh -h|--help  Show this help.
#
# Exit codes:
#   0 = no drift across the common subset
#   1 = drift detected, or argument error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .forge/bin/ -> repo root is two levels up.
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'HELP'
Usage: plugin-parity-check.sh

Spec 463 (P1=C) plugin parity gate. Verifies byte-level parity between the two
payload sources over the common subset:
  - template/.claude/  (Copier source)
  - .claude/           (plugin payload source, referenced by .claude-plugin/plugin.json)

Common subset checked: commands/, agents/, skills/.
Exit 0 on parity; exit 1 on any byte-level drift (named per file).
HELP
  exit 0
fi

PLUGIN_SRC="${REPO_ROOT}/.claude"
COPIER_SRC="${REPO_ROOT}/template/.claude"
SUBDIRS=("commands" "agents" "skills")

# Single source of truth for INTENTIONAL FORGE-self-vs-consumer divergence: the same
# escape-hatch the cross-level generator uses (Spec 270). A command listed there has a
# known, deliberate difference between the FORGE-self payload (.claude/) and the
# consumer-facing Copier render (template/.claude/) — it is OUT of the parity common
# subset by design. Reading this file (rather than hardcoding) keeps the gate
# forward-compatible with the NC-1a generator: same exclusion set, one source.
ESCAPE_HATCH="${REPO_ROOT}/.forge/state/expected-cross-level-drift.txt"
declare -A EXPECTED_DRIFT_BASENAME=()
# Spec 491: skills are GENERATED from the same canonical .forge/commands/ source the
# commands are. A canonical command that is intentionally FORGE-self-vs-consumer
# divergent (escape-hatch listed) therefore produces an intentionally divergent SKILL.md
# when it is a skill-form name (e.g. interview, now). Map the drift-listed canonical
# basename to its skill rel-path (<name>/SKILL.md) so the skills subset honors the same
# single source of intentional divergence the commands subset does.
declare -A EXPECTED_DRIFT_SKILL=()
if [[ -f "$ESCAPE_HATCH" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    path_part="${line%%|*}"
    path_part="${path_part#"${path_part%%[![:space:]]*}"}"
    path_part="${path_part%"${path_part##*[![:space:]]}"}"
    [[ -z "$path_part" ]] && continue
    # Map an escape-hatch canonical command path (.forge/commands/<name>.md) to its
    # rendered basename (<name>.md) so we can match against .claude/commands/<name>.md.
    case "$path_part" in
      .forge/commands/*.md)
        base="$(basename "$path_part")"
        EXPECTED_DRIFT_BASENAME["$base"]=1
        EXPECTED_DRIFT_SKILL["${base%.md}/SKILL.md"]=1
        ;;
    esac
  done < "$ESCAPE_HATCH"
fi

echo "## plugin-parity-check (Spec 463 / P1=C)"
echo ""
echo "Plugin payload source : ${PLUGIN_SRC}"
echo "Copier source         : ${COPIER_SRC}"
echo "Expected-drift exclusions (from ${ESCAPE_HATCH##*/}): ${#EXPECTED_DRIFT_BASENAME[@]} command(s)"
echo ""

if [[ ! -d "$PLUGIN_SRC" ]]; then
  echo "ERROR: plugin payload source not found: $PLUGIN_SRC" >&2
  exit 1
fi
if [[ ! -d "$COPIER_SRC" ]]; then
  echo "ERROR: Copier source not found: $COPIER_SRC" >&2
  exit 1
fi

DRIFT=()

for sub in "${SUBDIRS[@]}"; do
  plugin_dir="${PLUGIN_SRC}/${sub}"
  copier_dir="${COPIER_SRC}/${sub}"

  if [[ ! -d "$plugin_dir" && ! -d "$copier_dir" ]]; then
    continue
  fi
  if [[ ! -d "$plugin_dir" ]]; then
    DRIFT+=("${sub}/ — present in Copier source, MISSING from plugin source")
    continue
  fi
  if [[ ! -d "$copier_dir" ]]; then
    DRIFT+=("${sub}/ — present in plugin source, MISSING from Copier source")
    continue
  fi

  # Build the union of relative file paths in both trees.
  # Exclusions from the common subset (all intentional, by design):
  #   - Copier-time .jinja variations (Spec 281/390): template-only.
  #   - A plugin-side <name>.md whose Copier counterpart is <name>.md.jinja
  #     (the Copier render substitutes vars; no byte parity is possible/expected).
  #   - Commands on the expected-cross-level-drift escape-hatch (Spec 270):
  #     deliberate FORGE-self-vs-consumer content differences.
  declare -A seen=()
  while IFS= read -r -d '' f; do
    rel="${f#"${plugin_dir}/"}"
    [[ "$rel" == *.jinja ]] && continue
    # Skip a plugin-side .md whose Copier counterpart is a .jinja file.
    if [[ "$sub" == "commands" && -f "${copier_dir}/${rel}.jinja" ]]; then continue; fi
    if [[ "$sub" == "commands" && -n "${EXPECTED_DRIFT_BASENAME[$rel]+_}" ]]; then continue; fi
    # Spec 491: skill generated from an escape-hatch-divergent canonical command.
    if [[ "$sub" == "skills" && -n "${EXPECTED_DRIFT_SKILL[$rel]+_}" ]]; then continue; fi
    seen["$rel"]=1
  done < <(find "$plugin_dir" -type f -print0)
  while IFS= read -r -d '' f; do
    rel="${f#"${copier_dir}/"}"
    [[ "$rel" == *.jinja ]] && continue
    if [[ "$sub" == "commands" && -n "${EXPECTED_DRIFT_BASENAME[$rel]+_}" ]]; then continue; fi
    if [[ "$sub" == "skills" && -n "${EXPECTED_DRIFT_SKILL[$rel]+_}" ]]; then continue; fi
    seen["$rel"]=1
  done < <(find "$copier_dir" -type f -print0)

  for rel in "${!seen[@]}"; do
    pf="${plugin_dir}/${rel}"
    cf="${copier_dir}/${rel}"
    if [[ ! -f "$pf" ]]; then
      DRIFT+=("${sub}/${rel} — present in Copier source, MISSING from plugin source")
    elif [[ ! -f "$cf" ]]; then
      DRIFT+=("${sub}/${rel} — present in plugin source, MISSING from Copier source")
    elif ! cmp -s "$pf" "$cf"; then
      DRIFT+=("${sub}/${rel} — BYTE-LEVEL DRIFT between plugin and Copier source")
    fi
  done
  unset seen
done

echo "## Summary"
if [[ ${#DRIFT[@]} -eq 0 ]]; then
  echo "PASS: plugin payload source and Copier source are byte-identical across the common subset."
  exit 0
else
  echo "FAILED: ${#DRIFT[@]} parity violation(s):"
  for d in "${DRIFT[@]}"; do
    echo "  - $d"
  done
  echo ""
  echo "Remediation: re-sync the two sources (they MUST be byte-identical across commands/, agents/, skills/)."
  exit 1
fi
