#!/usr/bin/env bash
# Spec 439 test harness — verify command-body rewire to derived_state.py.
#
# Verifies:
#   AC 1: /now command-body programmatic reads cite derived_state.py (not docs/backlog.md)
#   AC 2: /brainstorm command-body programmatic reads cite derived_state.py
#   AC 3: /forge stoke has no docs/backlog.md references (programmatic or otherwise)
#   AC 4: derived_state.py --get-backlog --format=table delegates to render_backlog.py
#         and produces output byte-identical (after CRLF normalization) to the
#         table-rows portion of docs/.generated/backlog-table.md
#
# Exit 0 on all-pass; nonzero on any failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

say() { printf '%s\n' "$*"; }
fail() { say "FAIL: $*"; FAIL=$((FAIL + 1)); }
pass() { say "PASS: $*"; }

# ---------- AC 1 — /now programmatic reads ----------
# Allow operator-visible references on `See:` lines; fail on programmatic ones.
for f in \
    .forge/commands/now.md \
    .claude/commands/now.md; do
    [ -f "$f" ] || continue
    if grep -nE 'docs/backlog\.md' "$f" | grep -v 'See:' | grep -v 'operator-visible' >/dev/null; then
        fail "AC 1 — $f has non-See: reference to docs/backlog.md"
    else
        pass "AC 1 — $f"
    fi
done

# ---------- AC 2 — /brainstorm programmatic reads ----------
for f in \
    .forge/commands/brainstorm.md \
    .claude/commands/brainstorm.md; do
    [ -f "$f" ] || continue
    # programmatic reads would be on bullets like "- docs/backlog.md" without a "Do NOT" or "operator-visible" qualifier
    if grep -nE '^\s*-\s+`?docs/backlog\.md`?\s*$' "$f" >/dev/null; then
        fail "AC 2 — $f has bare bullet-list reference to docs/backlog.md (programmatic read)"
    else
        pass "AC 2 — $f"
    fi
done

# ---------- AC 3 — /forge stoke has no backlog refs ----------
for f in \
    .forge/commands/forge-stoke.md \
    .claude/commands/forge-stoke.md; do
    [ -f "$f" ] || continue
    if grep -nE 'docs/backlog\.md' "$f" >/dev/null; then
        # Allowed: See: lines only
        if grep -nE 'docs/backlog\.md' "$f" | grep -v 'See:' >/dev/null; then
            fail "AC 3 — $f has non-See: reference to docs/backlog.md"
        else
            pass "AC 3 — $f (only See: references)"
        fi
    else
        pass "AC 3 — $f (no references)"
    fi
done

# ---------- AC 4 — helper delegates + byte-identical to rendered rows ----------
# (a) grep audit: helper imports render_backlog
if grep -nE 'from render_backlog import render' .forge/lib/derived_state.py >/dev/null; then
    pass "AC 4a — derived_state.py imports render_backlog.render (delegation, no parallel formatter)"
else
    fail "AC 4a — derived_state.py does NOT import render_backlog (delegation contract broken)"
fi

# (b) byte-identity (after CRLF normalization)
HELPER_OUT="$(mktemp)"
RENDERED_OUT="$(mktemp)"
trap 'rm -f "$HELPER_OUT" "$RENDERED_OUT" "$HELPER_OUT.lf" "$RENDERED_OUT.lf"' EXIT

# Re-render to a fresh tmp file so we compare like-for-like (the on-disk .generated/
# file may be stale w.r.t. a frontmatter edit in this session).
RENDERED_TMP="$(mktemp --suffix=.md)"
.forge/bin/forge-py .forge/lib/render_backlog.py --output "$RENDERED_TMP" 2>/dev/null

.forge/bin/forge-py .forge/lib/derived_state.py --get-backlog --format=table > "$HELPER_OUT"
awk '/^## Ranked backlog$/{flag=1; next} flag && /^\|/' "$RENDERED_TMP" > "$RENDERED_OUT"
rm -f "$RENDERED_TMP"

tr -d '\r' < "$HELPER_OUT" > "$HELPER_OUT.lf"
tr -d '\r' < "$RENDERED_OUT" > "$RENDERED_OUT.lf"

if diff -q "$HELPER_OUT.lf" "$RENDERED_OUT.lf" >/dev/null; then
    pass "AC 4b — helper --format=table output byte-identical to rendered table rows"
else
    fail "AC 4b — helper output differs from rendered table rows; see diff:"
    diff "$HELPER_OUT.lf" "$RENDERED_OUT.lf" | head -20
fi

# ---------- Result ----------
if [ "$FAIL" -eq 0 ]; then
    say ""
    say "All Spec 439 ACs PASS."
    exit 0
else
    say ""
    say "$FAIL failure(s)."
    exit 1
fi
