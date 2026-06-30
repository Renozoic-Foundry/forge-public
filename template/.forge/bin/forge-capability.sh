#!/usr/bin/env bash
# forge-capability.sh — FORGE capability discovery + one-touch activation (Spec 471).
#
# Subcommands:
#   list                 one line per registry entry: "<id> | <active|inactive> | <title>"
#   pending              bare integer: # entries inactive AND not in capabilities_dismissed:
#   activate <id>        merge the entry's declared event blocks INTO .claude/settings.json
#   deactivate <id>      surgically remove the entry's declared event entries (delpaths-style)
#   dismiss <id>         append <id> to capabilities_dismissed: in .forge/onboarding.yaml
#
# Design (Spec 471):
#   - Capabilities ship INACTIVE; activation is an explicit operator action only.
#   - jq dependency is asymmetric: read subcommands (list/pending) degrade to
#     "unknown (jq required)" and exit 0 without jq; write subcommands
#     (activate/deactivate) hard-require jq and exit 1 with an actionable message,
#     writing nothing.
#   - The helper is the SOLE state-write path. It writes only:
#     .claude/settings.json, its timestamped backup, and .forge/onboarding.yaml
#     (capabilities_dismissed: key).
set -euo pipefail

# Resolve repo root from this script's location (works from temp dirs / CI).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${FORGE_CAP_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

REGISTRY="$REPO_ROOT/.forge/capabilities.yaml"
SETTINGS="$REPO_ROOT/.claude/settings.json"
ONBOARDING="$REPO_ROOT/.forge/onboarding.yaml"

die() { echo "$1" >&2; exit 1; }

usage() {
    cat >&2 <<'EOF'
usage: forge-capability.sh <list|pending|activate <id>|deactivate <id>|dismiss <id>>
EOF
    exit 1
}

# have_jq: true when jq is callable. FORGE_CAP_NO_JQ=1 forces the jq-absent path
# (test-only hook; the production check is the command -v probe).
have_jq() {
    [ "${FORGE_CAP_NO_JQ:-0}" = "1" ] && return 1
    command -v jq >/dev/null 2>&1
}

# --- minimal YAML registry parsing (no yq dependency) -----------------------
# Emits one line per entry: "<id>\t<title>\t<source>\t<detect>\t<recommended>\t<events-csv>"
parse_registry() {
    [ -f "$REGISTRY" ] || die "registry not found: $REGISTRY"
    awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function strip_quotes(s) {
            s = trim(s)
            if (s ~ /^".*"$/) { s = substr(s, 2, length(s) - 2) }
            else if (s ~ /^'\''.*'\''$/) { s = substr(s, 2, length(s) - 2) }
            return s
        }
        BEGIN { in_entry = 0; in_members = 0; id=""; title=""; source=""; detect=""; rec="false"; events="" }
        function flush() {
            if (id != "") {
                printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, title, source, detect, rec, events
            }
            id=""; title=""; source=""; detect=""; rec="false"; events=""
        }
        # top-level entry marker: "  - id: <value>"
        /^[ ]+-[ ]+id:[ ]*/ {
            line = $0
            indent = match(line, /[^ ]/) - 1
            sub(/^[ ]+-[ ]+id:[ ]*/, "", line)
            val = strip_quotes(line)
            # member id lines are more deeply indented and inside a members: block
            if (in_members && indent >= member_indent) {
                next
            }
            flush()
            in_entry = 1; in_members = 0
            id = val
            entry_indent = indent
            next
        }
        in_entry && /^[ ]+title:[ ]*/ && !in_members {
            line = $0; sub(/^[ ]+title:[ ]*/, "", line); title = strip_quotes(line); next
        }
        in_entry && /^[ ]+source:[ ]*/ && !in_members {
            line = $0; sub(/^[ ]+source:[ ]*/, "", line); source = strip_quotes(line); next
        }
        in_entry && /^[ ]+detect:[ ]*/ && !in_members {
            line = $0; sub(/^[ ]+detect:[ ]*/, "", line); detect = strip_quotes(line); next
        }
        in_entry && /^[ ]+recommended:[ ]*/ && !in_members {
            line = $0; sub(/^[ ]+recommended:[ ]*/, "", line); rec = strip_quotes(line); next
        }
        in_entry && /^[ ]+members:[ ]*$/ {
            in_members = 1; member_indent = match($0, /[^ ]/) - 1 + 2; next
        }
        in_members && /^[ ]+event:[ ]*/ {
            line = $0; sub(/^[ ]+event:[ ]*/, "", line); ev = strip_quotes(line)
            events = (events == "" ? ev : events "," ev)
            next
        }
        END { flush() }
    ' "$REGISTRY"
}

# Is the capability active? Runs the entry detect expression against settings.json.
# Echoes "active", "inactive", or "unknown" (jq missing).
cap_status() {
    local detect="$1"
    if ! have_jq; then echo "unknown"; return; fi
    if [ ! -f "$SETTINGS" ]; then echo "inactive"; return; fi
    local out
    out="$(jq -r "$detect" "$SETTINGS" 2>/dev/null || true)"
    if [ -n "$out" ] && [ "$out" != "null" ] && [ "$out" != "[]" ]; then
        echo "active"
    else
        echo "inactive"
    fi
}

# Read dismissed ids (one per line) from .forge/onboarding.yaml capabilities_dismissed:.
dismissed_ids() {
    [ -f "$ONBOARDING" ] || return 0
    awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        /^capabilities_dismissed:[ \t]*$/ { in_list = 1; next }
        /^capabilities_dismissed:[ \t]*\[/ {
            # inline list form: capabilities_dismissed: [a, b]
            line = $0
            sub(/^capabilities_dismissed:[ \t]*\[/, "", line)
            sub(/\].*$/, "", line)
            n = split(line, arr, ",")
            for (i = 1; i <= n; i++) {
                v = trim(arr[i]); gsub(/^["'\'']|["'\'']$/, "", v)
                if (v != "") print v
            }
            next
        }
        in_list {
            if ($0 ~ /^[ ]+-[ ]+/) {
                v = $0; sub(/^[ ]+-[ ]+/, "", v); v = trim(v)
                gsub(/^["'\'']|["'\'']$/, "", v)
                print v
            } else if ($0 ~ /^[^ ]/) {
                in_list = 0
            }
        }
    ' "$ONBOARDING"
}

is_dismissed() {
    local id="$1" d
    while IFS= read -r d; do
        [ "$d" = "$id" ] && return 0
    done < <(dismissed_ids)
    return 1
}

# --- subcommands ------------------------------------------------------------

cmd_list() {
    local id title source detect rec events status
    while IFS=$'\t' read -r id title source detect rec events; do
        [ -n "$id" ] || continue
        status="$(cap_status "$detect")"
        if [ "$status" = "unknown" ]; then
            echo "$id | unknown (jq required) | $title"
        else
            echo "$id | $status | $title"
        fi
    done < <(parse_registry)
}

cmd_pending() {
    local id title source detect rec events status count=0
    while IFS=$'\t' read -r id title source detect rec events; do
        [ -n "$id" ] || continue
        status="$(cap_status "$detect")"
        # unknown (jq missing) is treated as not-counted: read path degrades gracefully.
        if [ "$status" = "inactive" ] && ! is_dismissed "$id"; then
            count=$((count + 1))
        fi
    done < <(parse_registry)
    echo "$count"
}

# Look up a single entry's fields by id. Sets globals E_TITLE E_SOURCE E_DETECT E_EVENTS.
lookup_entry() {
    local want="$1" id title source detect rec events
    E_FOUND=0; E_TITLE=""; E_SOURCE=""; E_DETECT=""; E_EVENTS=""
    while IFS=$'\t' read -r id title source detect rec events; do
        if [ "$id" = "$want" ]; then
            E_FOUND=1; E_TITLE="$title"; E_SOURCE="$source"; E_DETECT="$detect"; E_EVENTS="$events"
            return 0
        fi
    done < <(parse_registry)
    return 0
}

require_jq_for_write() {
    if ! have_jq; then
        cat >&2 <<'EOF'
ERROR: jq is required to activate/deactivate capabilities, and it is not installed.
  Install: apt-get install jq  |  brew install jq  |  https://jqlang.github.io/jq/
  Manual fallback: copy the event blocks from .claude/settings.json.template into
  .claude/settings.json by hand. No file was written.
EOF
        exit 1
    fi
}

backup_settings() {
    if [ -f "$SETTINGS" ]; then
        local stamp; stamp="$(date -u +%Y%m%dT%H%M%SZ)"
        cp "$SETTINGS" "$SETTINGS.bak-$stamp"
    fi
}

cmd_activate() {
    local id="$1"
    require_jq_for_write
    lookup_entry "$id"
    [ "$E_FOUND" = "1" ] || die "unknown capability id: $id"
    local src="$REPO_ROOT/$E_SOURCE"
    [ -f "$src" ] || die "activate: source file not found: $src"

    # Already active?
    if [ "$(cap_status "$E_DETECT")" = "active" ]; then
        echo "$id already active — no change."
        return 0
    fi

    backup_settings

    local tmp; tmp="$(mktemp)"
    local ev_args="" ev
    IFS=',' read -ra EVENTS_ARR <<< "$E_EVENTS"

    # Base document: existing settings, or an empty object when none exists yet.
    local jq_prog='.hooks //= {}'
    for ev in "${EVENTS_ARR[@]}"; do
        [ -n "$ev" ] || continue
        jq_prog="$jq_prog | .hooks.\"$ev\" = \$srcwrap[0].hooks.\"$ev\""
        ev_args="$ev_args $ev"
    done

    local srcwrap; srcwrap="$(mktemp)"
    jq '{hooks: .hooks}' "$src" > "$srcwrap"
    if [ -f "$SETTINGS" ]; then
        jq --slurpfile srcwrap "$srcwrap" "$jq_prog" "$SETTINGS" > "$tmp"
    else
        echo '{}' | jq --slurpfile srcwrap "$srcwrap" "$jq_prog" > "$tmp"
    fi
    rm -f "$srcwrap"

    mv "$tmp" "$SETTINGS"
    echo "$id activated (events:$ev_args)."
}

cmd_deactivate() {
    local id="$1"
    require_jq_for_write
    lookup_entry "$id"
    [ "$E_FOUND" = "1" ] || die "unknown capability id: $id"
    local src="$REPO_ROOT/$E_SOURCE"

    if [ ! -f "$SETTINGS" ] || [ "$(cap_status "$E_DETECT")" = "inactive" ]; then
        echo "$id already inactive — no change."
        return 0
    fi
    [ -f "$src" ] || die "deactivate: source file not found: $src"

    backup_settings

    # Surgical removal: for each declared event, remove from the target array only
    # those hook-group entries whose declared command strings match the source's
    # entries for that event. Drop the event key only when its array becomes empty.
    # A naive top-level key-delete is non-compliant (would strip sibling hooks).
    local tmp; tmp="$(mktemp)"
    local ev
    IFS=',' read -ra EVENTS_ARR <<< "$E_EVENTS"
    # Build the jq program. We collect the set of command strings the source declares
    # for each event, then filter the target array to drop hook-groups that contain
    # any of those commands.
    # shellcheck disable=SC2016  # jq program: $-vars are jq bindings, must stay literal
    local jq_filter='.'
    for ev in "${EVENTS_ARR[@]}"; do
        [ -n "$ev" ] || continue
        jq_filter="$jq_filter
| (\$srcwrap[0].hooks.\"$ev\" // []) as \$srcgroups
| [ \$srcgroups[].hooks[].command ] as \$srccmds
| (if (.hooks.\"$ev\" // null) != null then
     (.hooks.\"$ev\" | map(select( ([.hooks[].command] | any(. as \$c | \$srccmds | index(\$c))) | not )) ) as \$kept
     | if (\$kept | length) == 0 then (del(.hooks.\"$ev\")) else (.hooks.\"$ev\" = \$kept) end
   else . end)"
    done

    local srcwrap; srcwrap="$(mktemp)"
    jq '{hooks: .hooks}' "$src" > "$srcwrap"
    jq --slurpfile srcwrap "$srcwrap" "$jq_filter" "$SETTINGS" > "$tmp"
    rm -f "$srcwrap"
    mv "$tmp" "$SETTINGS"
    echo "$id deactivated."
}

cmd_dismiss() {
    local id="$1"
    lookup_entry "$id"
    [ "$E_FOUND" = "1" ] || die "unknown capability id: $id"

    if is_dismissed "$id"; then
        echo "$id already dismissed — no change."
        return 0
    fi

    local key='capabilities_dismissed:'
    if [ ! -f "$ONBOARDING" ]; then
        { printf '%s\n' "$key"; printf '  - %s\n' "$id"; } > "$ONBOARDING"
        echo "$id dismissed."
        return 0
    fi

    if grep -qE '^capabilities_dismissed:[ \t]*$' "$ONBOARDING"; then
        # Block-list form present: insert a new list item right after the key.
        local tmp; tmp="$(mktemp)"
        awk -v newid="$id" '
            BEGIN { inserted = 0 }
            { print }
            /^capabilities_dismissed:[ \t]*$/ && !inserted {
                print "  - " newid
                inserted = 1
            }
        ' "$ONBOARDING" > "$tmp"
        mv "$tmp" "$ONBOARDING"
    else
        # No block-list key (absent or inline form): append a fresh block.
        { printf '\n%s\n' "$key"; printf '  - %s\n' "$id"; } >> "$ONBOARDING"
    fi
    echo "$id dismissed."
}

# --- dispatch ---------------------------------------------------------------
[ "$#" -ge 1 ] || usage
SUB="$1"; shift || true
case "$SUB" in
    list)       cmd_list ;;
    pending)    cmd_pending ;;
    activate)   [ "$#" -ge 1 ] || usage; cmd_activate "$1" ;;
    deactivate) [ "$#" -ge 1 ] || usage; cmd_deactivate "$1" ;;
    dismiss)    [ "$#" -ge 1 ] || usage; cmd_dismiss "$1" ;;
    *)          usage ;;
esac
