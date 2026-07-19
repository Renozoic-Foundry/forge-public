# Scripted-edit conventions — verify after every scripted edit

**Spec:** 483 — Verify-after-scripted-edit convention (catch silent no-op edits)
**Last verified:** 2026-06-15
**Applies to:** FORGE command bodies (`.forge/commands/`) and scripts (`scripts/`, `.forge/lib/`, `.forge/bin/`).

<!-- forge:maintainer-detail:start -->
> Audience: framework maintainers.

## The defect class

The **Edit/Write tools error on no-match** — if the `old_string` is not found, the
edit fails loudly. **Scripted edits do not.** A bash `sed -i`, a `python -c
"...open(path,'w')..."` rewrite, or a heredoc-driven substitution that matches
*nothing* still exits `0` and reports success. The author believes the edit
applied; it didn't; the defect surfaces downstream — or ships.

This is not hypothetical. It recurred **4 times** (SIG-451-EA-425) and was caught
only by ad-hoc reviewer grep (SIG-451-B) or by checking the verbatim string against
the actual file after the fact (SIG-460-B). A scripted edit with no post-condition
is a defect class, not a one-off.

## The rule

> **Every executed scripted edit pairs with a post-condition that verifies the
> edit actually changed the target.** A bare `sed -i` / file-rewrite with no
> `assert_*` / grep check after it is a defect.

Two ways the edit can silently fail, and the check for each:

| Failure | What happened | Check |
|---------|---------------|-------|
| **Silent no-op** | The pattern matched nothing; file unchanged. | `assert_changed` — file content differs from a pre-captured baseline. |
| **Wrong result** | The edit ran but the intended string isn't present. | `assert_contains` — the expected verbatim string is in the file post-edit. |

## The helper

`.forge/lib/assert-edit.sh` (bash) and `.forge/lib/assert-edit.ps1` (PowerShell
parity). Source the helper, then use the capture-before / assert-after pattern.
Each `assert_*` emits `ASSERT-EDIT FAIL: <file> — <expectation>` to stderr and
returns non-zero on failure; it succeeds silently. It is **advisory** by default —
the caller decides whether a FAIL halts the flow (`|| exit 1` to make it fatal;
under `set -e` a non-zero return is already fatal).

### Bash — worked example

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert-edit.sh"

file="docs/specs/README.md"

# 1. Capture a baseline BEFORE the edit.
before="$(assert_edit_sha "$file")"

# 2. The scripted edit.
sed -i "s/${old_count} specs/${new_count} specs/" "$file"

# 3. Assert it actually changed (catches the silent no-op / EA-425 class).
assert_changed "$file" "$before" || exit 1

# 4. Assert the intended result is present (catches the wrong-result / 460-B class).
assert_contains "$file" "${new_count} specs" || exit 1
```

If the `sed` pattern matched nothing, step 3 prints
`ASSERT-EDIT FAIL: docs/specs/README.md — unchanged (...)` and returns non-zero —
the no-op is caught at the point of edit, not downstream.

### PowerShell — worked example

```powershell
. "$PSScriptRoot/../lib/assert-edit.ps1"

$file = "docs/specs/README.md"

$before = Get-AssertEditSha $file
(Get-Content -Raw $file) -replace "$oldCount specs", "$newCount specs" | Set-Content $file

if ((Assert-Changed  -File $file -BeforeSha $before) -ne 0) { exit 1 }
if ((Assert-Contains -File $file -Expected "$newCount specs") -ne 0) { exit 1 }
```

## The advisory lint

`scripts/validate-scripted-edits.sh` flags executed in-place rewrites
(`sed -i`, python open-for-write) in `scripts/**/*.sh` and `.forge/commands/*.md`
that have no paired verification (an `assert_*` / `Assert-*` call or a grep
post-condition) within a small proximity window.

- **Advisory at first ship** — WARN to stderr, **always exits 0**.
- Run `scripts/validate-scripted-edits.sh --strict` to fail on findings (the
  intended end state once existing rewrites are retrofitted).
- It scans *script files and command bodies only* (R4): it does not flag command
  *prose* that merely describes an edit, only the executable forms — keeping the
  finding set bounded and triageable.

Retrofit of existing rewrites is **opportunistic**, not required by this spec: when
you touch a script with a flagged rewrite, add the `assert_*` / grep post-condition.

## When this does NOT apply

- **Edit/Write tool calls** — they already error on no-match; no helper needed.
- **Append-only writes** (`>>`, `cat <<EOF > new_file`) where there is no pattern
  to fail to match — though `assert_contains` after a create is still cheap insurance.
- **Idempotent rewrites you intend to no-op** — in that case the no-op is correct;
  prefer `assert_contains` (assert the desired end-state) over `assert_changed`.
<!-- forge:maintainer-detail:end -->
