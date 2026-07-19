#!/usr/bin/env bash
# freshness.sh — Spec 278 `Last verified:` marker helper (Spec 509 stamp-stale entry point).
#
# Spec 278 established the doc-freshness convention: a `Last verified:` marker surfaced
# by /now when stale. Spec 509 adds the /close stamp path: when a closing spec changes a
# documented public surface, the mapped public doc's marker is stamped STALE so the /now
# freshness surfacer flags it immediately and /evolve tracks chronic deferral.
# Signal only — this helper NEVER blocks anything and ALWAYS exits 0 in stamp/check modes.
#
# SINGLE-SOURCE MAPPING NOTE (Spec 509 AC4): the surface→doc mapping in resolve_docs()
# below is the ONE machine-readable copy of the Spec 511 canonical mapping. The
# validator-side assertions on the same doc set live in scripts/validate-public-docs.sh
# Sections 6–7 (count consistency / config-key validity). Command bodies (close.md,
# now.md) MUST invoke this helper rather than re-inline the mapping:
#   slash-command surface   -> docs/command-reference.md
#   AGENTS.md config block  -> docs/agents-config-reference.md
#   install/distribution    -> README.md, docs/getting-started.md, docs/VERSIONING.md
#
# Generated-doc interaction: docs/command-reference.md is gen-command-reference.sh
# output; a stamp there is erased by the next generator run — that IS the refresh
# semantics (regeneration = re-verification). Hand-maintained docs clear the stamp by
# re-verifying and updating the marker per docs/process-kit/runbook.md § Freshness.
# forge:path-literal-ok (comment)
#
# Consumer projects: the mapped docs are FORGE-repo public docs and do not exist in
# rendered consumer projects — missing docs are skipped silently (no false noise).
#
# Usage:
#   freshness.sh stamp --spec NNN [--baseline REF] [--date YYYY-MM-DD] [--] [FILE...]
#       Classify changed FILEs (a `git diff --name-only` list; read from stdin when no
#       FILE args are given), resolve touched documented surfaces via the mapping, and
#       stamp each resolved doc's `Last verified:` marker STALE. Prints one
#       `STAMPED <doc> — <reason>` line per doc written; silent when no documented
#       surface changed. Idempotent: an already-STALE marker is left untouched.
#       With --baseline, precision refinement runs (Spec 509 R3):
#         - modified-only command files stamp only when a `description:` or
#           `model_tier:` frontmatter line changed (the fields the command reference
#           renders); added/deleted/renamed command files always stamp (count changes).
#         - AGENTS.md stamps only when a YAML-key-shaped line was added/removed/edited.
#       Without --baseline, any path hit stamps (recall fallback).
#   freshness.sh check
#       Print one `<doc>:<line> — <stale annotation>` line per mapped doc whose marker
#       carries a STALE stamp (consumed by /now Step 8c). Silent when none.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Spec 511 canonical surface→doc mapping (single machine-readable copy; see header) ---
DOCS_COMMAND="docs/command-reference.md"
DOCS_CONFIG="docs/agents-config-reference.md"
DOCS_INSTALL="README.md docs/getting-started.md docs/VERSIONING.md"
ALL_MAPPED_DOCS="$DOCS_COMMAND $DOCS_CONFIG $DOCS_INSTALL"

usage() {
  sed -n '2,50p' "${BASH_SOURCE[0]}" | grep -E '^# ?' | sed -E 's/^# ?//'
}

# classify <path> -> echoes surface name(s): command | config | install (or nothing)
classify() {
  local p="$1"
  case "$p" in
    .forge/commands/*.md|.claude/commands/*.md|template/.forge/commands/*.md|template/.claude/commands/*.md)
      echo "command" ;;
    AGENTS.md|template/AGENTS.md.jinja)
      echo "config" ;;
    .claude-plugin/*|template/.claude-plugin/*|copier.yml|.forge/bin/forge-install.sh|.forge/bin/forge-install.ps1|template/.forge/bin/forge-install.sh|template/.forge/bin/forge-install.ps1)
      echo "install" ;;
  esac
}

# stamp_doc <relpath> <reason> — annotate the doc's `Last verified:` marker as STALE.
# Marker resolution order:
#   1. existing `Last verified` line anywhere in the doc (HTML-comment marker or the
#      footer style used by the public docs) -> append the STALE annotation in place
#      (inside the comment when the line closes with `-->`);
#   2. no marker -> insert a Spec 278-format HTML-comment marker after the first H1
#      (or at the top), carrying the STALE annotation.
# Missing file or already-STALE marker: silent no-op.
stamp_doc() {
  local rel="$1" reason="$2"
  local f="$ROOT/$rel"
  if [[ ! -f "$f" ]]; then
    return 0
  fi
  if grep -q 'Last verified.*STALE' "$f"; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v reason="$reason" '
    BEGIN { done = 0; seen_h1 = 0; has_marker = 0 }
    NR == FNR {
      if (!has_marker && $0 ~ /Last verified/) has_marker = 1
      next
    }
    {
      line = $0
      if (!done && has_marker && line ~ /Last verified/) {
        sub(/\r$/, "", line)
        if (line ~ /-->[[:space:]]*$/) {
          sub(/[[:space:]]*-->[[:space:]]*$/, " | STALE: " reason " -->", line)
        } else {
          line = line " | STALE: " reason
        }
        done = 1
      }
      print line
      if (!done && !has_marker && !seen_h1 && line ~ /^# /) {
        seen_h1 = 1
        print "<!-- Last verified: (unset) | STALE: " reason " -->"
        done = 1
      }
    }
    END {
      if (!done) print "<!-- Last verified: (unset) | STALE: " reason " -->"
    }
  ' "$f" "$f" > "$tmp"
  mv "$tmp" "$f"
  echo "STAMPED $rel — $reason"
}

cmd_stamp() {
  local spec="" baseline="" date_str=""
  local files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --spec)     spec="${2:-}"; shift 2 ;;
      --baseline) baseline="${2:-}"; shift 2 ;;
      --date)     date_str="${2:-}"; shift 2 ;;
      --)         shift; while [[ $# -gt 0 ]]; do files+=("$1"); shift; done ;;
      -h|--help)  usage; exit 0 ;;
      *)          files+=("$1"); shift ;;
    esac
  done
  if [[ -z "$spec" ]]; then
    echo "freshness.sh stamp: --spec NNN is required" >&2
    exit 2
  fi
  if [[ -z "$date_str" ]]; then
    date_str="$(date +%Y-%m-%d)"
  fi
  if [[ ${#files[@]} -eq 0 ]]; then
    # No FILE args: read the changed-files list from stdin (one path per line).
    if [[ ! -t 0 ]]; then
      while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ -n "$line" ]]; then
          files+=("$line")
        fi
      done
    fi
  fi
  if [[ ${#files[@]} -eq 0 ]]; then
    exit 0
  fi

  local hit_command=0 hit_config=0 hit_install=0
  local cmd_hits=()
  local p surface
  for p in "${files[@]}"; do
    surface="$(classify "$p")"
    case "$surface" in
      command) hit_command=1; cmd_hits+=("$p") ;;
      config)  hit_config=1 ;;
      install) hit_install=1 ;;
    esac
  done

  # --- Precision refinement (Spec 509 R3) — only possible with a baseline ref ---
  if [[ -n "$baseline" ]] && git -C "$ROOT" rev-parse --verify --quiet "$baseline" > /dev/null 2>&1; then
    if [[ $hit_command -eq 1 ]]; then
      # Added/deleted/renamed command files always stamp (row/count changes). For a
      # modified-only set, stamp only when a rendered frontmatter field changed.
      local status_out
      status_out="$(git -C "$ROOT" diff --name-status "$baseline"..HEAD -- "${cmd_hits[@]}" 2>/dev/null || true)"
      if [[ -n "$status_out" ]] && ! grep -qE '^[ADRC]' <<< "$status_out"; then
        if ! git -C "$ROOT" diff "$baseline"..HEAD -- "${cmd_hits[@]}" 2>/dev/null \
             | grep -qE '^[+-](description|model_tier):'; then
          hit_command=0
        fi
      fi
    fi
    if [[ $hit_config -eq 1 ]]; then
      # Stamp only when a YAML-key-shaped line was added/removed/edited (a config
      # block change), not on prose-only AGENTS.md edits. Heuristic: ± lines whose
      # first token is a lowercase/level-key identifier followed by ':'.
      if ! git -C "$ROOT" diff "$baseline"..HEAD -- AGENTS.md template/AGENTS.md.jinja 2>/dev/null \
           | grep -qE '^[+-][[:space:]]*(L[0-4]|-[[:space:]]+[a-z][A-Za-z0-9_.-]*|[a-z][A-Za-z0-9_.-]*)[[:space:]]*:'; then
        hit_config=0
      fi
    fi
  fi

  local d
  if [[ $hit_command -eq 1 ]]; then
    stamp_doc "$DOCS_COMMAND" "re-verify — Spec $spec changed a slash-command surface (/close $date_str, Spec 509)"
  fi
  if [[ $hit_config -eq 1 ]]; then
    stamp_doc "$DOCS_CONFIG" "re-verify — Spec $spec changed AGENTS.md config (/close $date_str, Spec 509)"
  fi
  if [[ $hit_install -eq 1 ]]; then
    for d in $DOCS_INSTALL; do
      stamp_doc "$d" "re-verify — Spec $spec changed an install/distribution surface (/close $date_str, Spec 509)"
    done
  fi
  exit 0
}

cmd_check() {
  local rel f hit
  for rel in $ALL_MAPPED_DOCS; do
    f="$ROOT/$rel"
    if [[ ! -f "$f" ]]; then
      continue
    fi
    hit="$(grep -n 'Last verified' "$f" | grep 'STALE' | head -n 1 || true)"
    if [[ -n "$hit" ]]; then
      local lineno="${hit%%:*}"
      local text="${hit#*STALE: }"
      text="${text% -->*}"
      text="${text%$'\r'}"
      echo "$rel:$lineno — STALE: $text"
    fi
  done
  exit 0
}

case "${1:-}" in
  stamp) shift; cmd_stamp "$@" ;;
  check) shift; cmd_check "$@" ;;
  -h|--help|"") usage; exit 0 ;;
  *) echo "freshness.sh: unknown mode '${1}' (expected: stamp | check)" >&2; exit 2 ;;
esac
