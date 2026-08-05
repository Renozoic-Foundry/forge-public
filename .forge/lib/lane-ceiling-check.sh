#!/usr/bin/env bash
# FORGE Lane-Ceiling Check — Spec 611 Requirement 5
#
# Compares a spec's DECLARED `Change-Lane:` against OBJECTIVE diff signals (files touched,
# LOC delta, dependency-manifest changes) and FLAGS a mismatch for operator/DA attention.
#
# WHY THIS EXISTS: a spec's Change-Lane sets its token/cost/time budget ceiling (AGENTS.md
# "Budget ceilings per lane"), but the lane is SELF-CLASSIFIED by the authoring agent and,
# before this check, was never compared against what the implementation actually did. Spec
# 528's consensus round raised this as a CISO blocking finding: an unsupervised loop could
# declare `hotfix` and stay under a lighter budget/review bar than its diff warrants.
#
# FLAG-ONLY — LOAD-BEARING CONSTRAINT (Spec 611 Constraints; consensus round 2 CTO/CISO):
# this script MUST NOT reclassify the lane, and MUST NOT write to the spec file at all.
# Auto-correcting the lane would create exactly the self-authorization surface the check
# exists to close — an agent that can rewrite its own budget ceiling is not constrained by
# it. The script only ever READS the spec. Spec 611 AC7 asserts this mechanically by
# comparing the spec's frontmatter bytes before and after a run.
#
# POSTURE: advisory by default (flag, exit 0) — mirrors the Spec 327 authorization-rule lint
# convention. `--strict` makes a mismatch exit 1 for CI use.
#
# Usage:
#   lane-ceiling-check.sh <spec-file> [--base <git-ref>] [--strict]
#                         [--changed-files-from <path>] [--repo <dir>]
#
#   --base <ref>                compare against this ref (default: HEAD)
#   --strict                    exit 1 on mismatch instead of 0
#   --changed-files-from <path> read the changed-file list from a file (one path per line)
#                               instead of asking git — used by fixtures
#   --repo <dir>                run git queries in this directory (default: cwd)
#
# Exit codes: 0 = no mismatch, or mismatch in advisory mode.  1 = mismatch in --strict mode.
#             2 = usage/input error (spec file missing/unreadable, no Change-Lane).

set -euo pipefail

SPEC_FILE=""
BASE_REF="HEAD"
STRICT=0
CHANGED_FROM=""
REPO_DIR="."

while [ $# -gt 0 ]; do
  case "$1" in
    --base)                BASE_REF="${2:-}"; shift 2 ;;
    --strict)              STRICT=1; shift ;;
    --changed-files-from)  CHANGED_FROM="${2:-}"; shift 2 ;;
    --repo)                REPO_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: lane-ceiling-check.sh <spec-file> [--base <ref>] [--strict] [--changed-files-from <path>] [--repo <dir>]"
      exit 0 ;;
    *)
      if [ -z "$SPEC_FILE" ]; then SPEC_FILE="$1"; else echo "Unexpected argument: $1" >&2; exit 2; fi
      shift ;;
  esac
done

if [ -z "$SPEC_FILE" ] || [ ! -r "$SPEC_FILE" ]; then
  echo "lane-ceiling-check: spec file missing or unreadable: '${SPEC_FILE}'" >&2
  exit 2
fi

# ---- Read the declared lane (READ-ONLY; this script never writes the spec) ----------------
DECLARED_LANE=$(grep -m1 -E '^- Change-Lane:' "$SPEC_FILE" 2>/dev/null \
  | sed -E 's/^- Change-Lane:[[:space:]]*//; s/`//g; s/[[:space:]]*$//' || true)

if [ -z "$DECLARED_LANE" ]; then
  echo "lane-ceiling-check: no 'Change-Lane:' found in ${SPEC_FILE}" >&2
  exit 2
fi

# ---- Collect objective diff signals -------------------------------------------------------
CHANGED_FILES=""
if [ -n "$CHANGED_FROM" ]; then
  if [ ! -r "$CHANGED_FROM" ]; then
    echo "lane-ceiling-check: --changed-files-from path unreadable: '${CHANGED_FROM}'" >&2
    exit 2
  fi
  CHANGED_FILES=$(grep -v '^[[:space:]]*$' "$CHANGED_FROM" || true)
else
  CHANGED_FILES=$( { git -C "$REPO_DIR" diff --name-only "$BASE_REF" 2>/dev/null || true; \
                     git -C "$REPO_DIR" ls-files --others --exclude-standard 2>/dev/null || true; } \
                   | grep -v '^[[:space:]]*$' | sort -u || true)
fi

FILE_COUNT=0
if [ -n "$CHANGED_FILES" ]; then
  FILE_COUNT=$(printf '%s\n' "$CHANGED_FILES" | wc -l | tr -d '[:space:]')
fi

LOC_DELTA=0
if [ -z "$CHANGED_FROM" ]; then
  LOC_DELTA=$(git -C "$REPO_DIR" diff --numstat "$BASE_REF" 2>/dev/null \
    | awk '{ a=($1=="-"?0:$1); d=($2=="-"?0:$2); s+=a+d } END { print (s==""?0:s) }' || echo 0)
fi

# Dependency-manifest touch (AGENTS.md lists dependency additions as requires-confirmation).
DEP_TOUCHED=0
DEP_HITS=""
if [ -n "$CHANGED_FILES" ]; then
  DEP_HITS=$(printf '%s\n' "$CHANGED_FILES" \
    | grep -E '(^|/)(package\.json|requirements([-.].*)?\.txt|pyproject\.toml|Cargo\.toml|go\.mod|Gemfile|pom\.xml|build\.gradle(\.kts)?)$' || true)
  if [ -n "$DEP_HITS" ]; then DEP_TOUCHED=1; fi
fi

# Non-docs touch — the objective discriminator for the `process-only` lane, whose AGENTS.md
# definition is "Changes to FORGE's own docs/tracking only".
NONDOCS_HITS=""
if [ -n "$CHANGED_FILES" ]; then
  NONDOCS_HITS=$(printf '%s\n' "$CHANGED_FILES" \
    | grep -E '\.(sh|ps1|py|js|ts|jinja)$' || true)
fi

# ---- Lane ceilings ------------------------------------------------------------------------
# Bands derive from the scoring-rubric E anchors (E=1: 1 file; E=2: 2-5; E=3: 5-15) and the
# AGENTS.md lane definitions. They are advisory thresholds for FLAGGING, not lane law.
MISMATCHES=""
add_mismatch() { MISMATCHES="${MISMATCHES}  - $1"$'\n'; }

case "$DECLARED_LANE" in
  hotfix)
    if [ "$FILE_COUNT" -gt 3 ]; then
      add_mismatch "declared \`hotfix\` but the diff touches ${FILE_COUNT} files (ceiling 3). AGENTS.md: a hotfix edits only files within an already-open spec's scope."
    fi
    if [ "$LOC_DELTA" -gt 100 ]; then
      add_mismatch "declared \`hotfix\` but the diff changes ${LOC_DELTA} lines (ceiling 100)."
    fi
    if [ "$DEP_TOUCHED" -eq 1 ]; then
      add_mismatch "declared \`hotfix\` but a dependency manifest changed: $(printf '%s' "$DEP_HITS" | tr '\n' ' ')"
    fi
    ;;
  small-change)
    if [ "$FILE_COUNT" -gt 5 ]; then
      add_mismatch "declared \`small-change\` but the diff touches ${FILE_COUNT} files (ceiling 5)."
    fi
    if [ "$LOC_DELTA" -gt 300 ]; then
      add_mismatch "declared \`small-change\` but the diff changes ${LOC_DELTA} lines (ceiling 300)."
    fi
    if [ "$DEP_TOUCHED" -eq 1 ]; then
      add_mismatch "declared \`small-change\` but a dependency manifest changed: $(printf '%s' "$DEP_HITS" | tr '\n' ' ')"
    fi
    ;;
  process-only)
    if [ -n "$NONDOCS_HITS" ]; then
      add_mismatch "declared \`process-only\` (docs/tracking only) but the diff touches executable/template files: $(printf '%s' "$NONDOCS_HITS" | tr '\n' ' ')"
    fi
    if [ "$DEP_TOUCHED" -eq 1 ]; then
      add_mismatch "declared \`process-only\` but a dependency manifest changed: $(printf '%s' "$DEP_HITS" | tr '\n' ' ')"
    fi
    ;;
  standard-feature)
    : # widest lane — no upper ceiling to flag against
    ;;
  *)
    add_mismatch "unrecognized Change-Lane '\`${DECLARED_LANE}\`' (expected hotfix | small-change | standard-feature | process-only)."
    ;;
esac

# ---- Report -------------------------------------------------------------------------------
if [ -z "$MISMATCHES" ]; then
  echo "GATE [lane-ceiling]: PASS — declared \`${DECLARED_LANE}\` is consistent with the diff (${FILE_COUNT} file(s), ${LOC_DELTA} line(s) changed)."
  exit 0
fi

echo "GATE [lane-ceiling]: FLAG — declared lane \`${DECLARED_LANE}\` does not match the diff signals."
printf '%s' "$MISMATCHES"
echo "  Signals: files=${FILE_COUNT} lines=${LOC_DELTA} dependency-manifest-touched=${DEP_TOUCHED}"
echo "  This is ADVISORY and FLAG-ONLY — the lane was NOT changed and this spec file was NOT written to."
echo "  Remediation: either widen Change-Lane via /revise (operator decision), or record why the"
echo "  declared lane is still correct. Auto-reclassification is deliberately not implemented"
echo "  (Spec 611: it would recreate the self-authorization surface this check exists to close)."

if [ "$STRICT" -eq 1 ]; then exit 1; fi
exit 0
