#!/usr/bin/env bash
# FORGE close adoption-gate helpers — Spec 402 library.
# Sourceable: pure functions, no main execution.
#
# Closes the build-without-adopt failure mode: a spec ships new machinery
# (frontmatter field, generated-artifact path, config block, annotation format)
# without any consumer using/exercising it. The originating spec body counts as
# a consumer. An explicit `Follow-up adoption spec: NNN` field defers adoption.
#
# Public functions:
#   adoption_detect_frontmatter_fields <spec-file>
#       — emit new frontmatter-field tokens declared in the spec body (one per line).
#         A declaration is a line of the form `New-Field-name:` in the Requirements/Scope
#         narrative or a `_template.md` diff. Excludes known template fields.
#   adoption_detect_artifact_paths <spec-file>
#       — emit generated-artifact-path declarations (glob/output paths) one per line.
#   adoption_detect_config_blocks <spec-file>
#       — emit new config-block keys (e.g. forge.dispatch_rules) one per line.
#   adoption_has_followup <spec-file>
#       — exit 0 if a `Follow-up adoption spec: NNN` field is present AND the
#         referenced spec exists; exit 1 otherwise (writes reason to stderr on the
#         present-but-missing case).
#   adoption_count_consumers <declaration> <repo-root> <spec-file>
#       — print the number of files (other than the spec's own Evidence/Revision
#         narrative) that reference the declaration. The originating spec body
#         counts as 1 when the declaration is exercised there.
#   adoption_gate_check <spec-file> <repo-root>
#       — top-level driver. Exit 0 PASS, exit 2 FAIL. Writes a one-line
#         GATE [close-adoption] result to stdout and FAIL detail to stderr.

# Frontmatter fields that already exist in the FORGE convention — never flagged.
# (Mirror of _template.md frontmatter + lifecycle fields written by commands.)
ADOPTION_KNOWN_FIELDS=(
  Status Change-Lane Priority-Score Approved-SHA Trigger Dependencies
  Consensus-Review Consensus-Close-SHA Consensus-Exempt Consensus-Status
  Provisional-Until Owner Author Reviewer Approver "Implementation owner"
  "Last updated" valid-until Supersedes Lane-B-Sealed DA-Reviewed DA-Decision
  DA-Encoded-Via DA-Verification Safety-Override Spec-vs-HEAD-Exempt
  Enforcement-Layers Gate-Mediation-Exempt "Follow-up adoption spec"
  Consensus-Exempt-Reason
)

# Return 0 if $1 is a known/allowed frontmatter field name.
_adoption_is_known_field() {
  local candidate="$1" known
  for known in "${ADOPTION_KNOWN_FIELDS[@]}"; do
    if [[ "$candidate" == "$known" ]]; then
      return 0
    fi
  done
  return 1
}

# Extract the spec body section between two `##` headings (heading text in $2),
# exclusive of the headings themselves. Prints to stdout.
_adoption_section() {
  local spec_file="$1" heading="$2"
  awk -v h="## ${heading}" '
    $0 == h { p=1; next }
    /^## / { p=0 }
    p { print }
  ' "$spec_file"
}

# Return 0 if the spec is the adoption-gate's own defining spec (Spec 402).
# That spec names field/path/config tokens definitionally (in its ACs as examples
# of what the gate detects), not as machinery it ships — so it is self-excluded,
# exactly as the gate library/tests/guide are excluded from the consumer count.
# Its real machinery (the lib + close.md Step 2g+) is genuinely adopted.
_adoption_is_defining_spec() {
  case "$1" in
    */402-*.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Detect newly-declared frontmatter fields in the spec body.
# A declaration is `Field-Name:` appearing in the body, where Field-Name is
# Capitalized-Hyphenated and not a known field.
adoption_detect_frontmatter_fields() {
  local spec_file="$1"
  [[ -f "$spec_file" ]] || return 0
  _adoption_is_defining_spec "$spec_file" && return 0
  local body
  body="$(_adoption_section "$spec_file" Scope)
$(_adoption_section "$spec_file" Requirements)
$(_adoption_section "$spec_file" 'Acceptance Criteria')"
  # Match `Word-Word:` field-name declarations (single-line, value optional).
  printf '%s\n' "$body" \
    | grep -oE '\b[A-Z][A-Za-z]+(-[A-Za-z]+)+:' \
    | sed -E 's/:$//' \
    | sort -u \
    | while IFS= read -r field; do
        [[ -z "$field" ]] && continue
        _adoption_is_known_field "$field" && continue
        printf '%s\n' "$field"
      done
}

# Detect generated-artifact-path declarations (output/generated file paths).
# Matches backticked paths with a single-`*` glob segment that look like generated
# outputs (e.g. docs/compliance/traceability-*.md). Double-glob `**` patterns are
# pattern-CLASS descriptions (detection rules), not concrete outputs — skipped.
adoption_detect_artifact_paths() {
  local spec_file="$1"
  [[ -f "$spec_file" ]] || return 0
  _adoption_is_defining_spec "$spec_file" && return 0
  local body
  body="$(_adoption_section "$spec_file" Scope)
$(_adoption_section "$spec_file" Requirements)
$(_adoption_section "$spec_file" 'Acceptance Criteria')"
  printf '%s\n' "$body" \
    | grep -oE '`[A-Za-z0-9_./-]+\*[A-Za-z0-9_./*-]*\.(md|json|jsonl|yaml|yml|txt|csv)`' \
    | tr -d '`' \
    | grep -v '\*\*' \
    | sort -u
}

# Detect new config-block keys (dotted keys like forge.dispatch_rules).
adoption_detect_config_blocks() {
  local spec_file="$1"
  [[ -f "$spec_file" ]] || return 0
  _adoption_is_defining_spec "$spec_file" && return 0
  local body
  body="$(_adoption_section "$spec_file" Scope)
$(_adoption_section "$spec_file" Requirements)
$(_adoption_section "$spec_file" 'Acceptance Criteria')"
  printf '%s\n' "$body" \
    | grep -oE '\b(forge|multi_agent)\.[a-z_]+(\.[a-z_]+)*' \
    | sort -u
}

# Return 0 if a valid `Follow-up adoption spec: NNN` field is present.
# Present-but-missing-target returns 1 with a stderr message.
adoption_has_followup() {
  local spec_file="$1" repo_root="${2:-.}"
  [[ -f "$spec_file" ]] || return 1
  local line ref
  line="$(grep -iE '^- ?Follow-up adoption spec:' "$spec_file" | head -1 || true)"
  [[ -z "$line" ]] && return 1
  ref="$(printf '%s' "$line" | grep -oE '[0-9]{3}' | head -1)"
  if [[ -z "$ref" ]]; then
    printf 'Follow-up adoption spec field present but no NNN reference parsed.\n' >&2
    return 1
  fi
  if ! ls "${repo_root}"/docs/specs/"${ref}"-*.md >/dev/null 2>&1; then
    printf 'Follow-up adoption spec %s referenced but no such spec exists.\n' "$ref" >&2
    return 1
  fi
  return 0
}

# Count consumers of a declaration across the repo. The originating spec body
# counts when the token appears outside the Scope/Requirements/AC declaration
# context (i.e. populated in frontmatter, or referenced in another file).
adoption_count_consumers() {
  local declaration="$1" repo_root="${2:-.}" spec_file="$3"
  local count=0
  # Repo-wide grep, excluding the spec's own narrative-declaration sections and
  # this gate's own library/tests (which name the tokens by construction).
  local f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # Skip the gate library/tests/guide — they mention tokens definitionally.
    case "$f" in
      */close-adoption-gate.*|*/test-spec-402-*|*close-adoption-gate-guide.md) continue ;;
    esac
    count=$((count + 1))
  done < <(grep -rlF "$declaration" "$repo_root" \
              --include='*.md' --include='*.json' --include='*.jsonl' \
              --include='*.yaml' --include='*.yml' --include='*.jinja' \
              --include='*.sh' --include='*.ps1' --include='*.py' 2>/dev/null \
            | grep -vF "$spec_file" || true)
  # Originating-spec-as-consumer: a frontmatter field is "adopted" when the spec
  # itself populates it in its own frontmatter block.
  if [[ -f "$spec_file" ]]; then
    local fm
    fm="$(awk '/^## /{exit} {print}' "$spec_file")"
    if printf '%s\n' "$fm" | grep -qE "^- ?${declaration}:"; then
      count=$((count + 1))
    fi
  fi
  printf '%s\n' "$count"
}

# Top-level gate driver.
adoption_gate_check() {
  local spec_file="$1" repo_root="${2:-.}"
  if [[ ! -f "$spec_file" ]]; then
    printf 'GATE [close-adoption]: FAIL — spec file not found: %s\n' "$spec_file"
    return 2
  fi
  # Escape hatch: explicit follow-up adoption spec defers the gate entirely.
  if adoption_has_followup "$spec_file" "$repo_root"; then
    printf 'GATE [close-adoption]: PASS — adoption deferred via Follow-up adoption spec.\n'
    return 0
  fi
  local -a declarations=()
  local d
  while IFS= read -r d; do [[ -n "$d" ]] && declarations+=("$d"); done < <(adoption_detect_frontmatter_fields "$spec_file")
  while IFS= read -r d; do [[ -n "$d" ]] && declarations+=("$d"); done < <(adoption_detect_artifact_paths "$spec_file")
  while IFS= read -r d; do [[ -n "$d" ]] && declarations+=("$d"); done < <(adoption_detect_config_blocks "$spec_file")

  if [[ ${#declarations[@]} -eq 0 ]]; then
    printf 'GATE [close-adoption]: PASS — no new artifact/field/config declarations detected.\n'
    return 0
  fi

  local -a unadopted=()
  for d in "${declarations[@]}"; do
    local n
    n="$(adoption_count_consumers "$d" "$repo_root" "$spec_file")"
    if [[ "$n" -lt 1 ]]; then
      unadopted+=("$d")
    fi
  done

  if [[ ${#unadopted[@]} -eq 0 ]]; then
    printf 'GATE [close-adoption]: PASS — all %d declaration(s) have ≥1 consumer.\n' "${#declarations[@]}"
    return 0
  fi

  printf 'GATE [close-adoption]: FAIL — %d declaration(s) shipped without a consumer: %s\n' \
    "${#unadopted[@]}" "$(printf '%s, ' "${unadopted[@]}" | sed 's/, $//')"
  printf 'Remediation: (a) exercise the declaration (the originating spec body counts — populate the field/path/config in this spec or a consuming file), or (b) add `Follow-up adoption spec: NNN` to the spec frontmatter naming the successor that owns adoption.\n' >&2
  return 2
}
