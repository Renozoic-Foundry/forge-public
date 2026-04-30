---
name: tab
description: "Initialize or close a multi-tab session for parallel development"
workflow_stage: implementation
---
# Framework: FORGE
Initialize or close a multi-tab session for coordinated parallel development.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /tab — Initialize or close a multi-tab coordination session.
  Usage:
    /tab <label> <lane> [spec-number]  — start a tab session
    /tab close                          — close the current tab session
  Arguments:
    label (required) — short name for this tab (e.g., "main", "ui-work", "hotfix-42")
    lane (required) — one of: process-only, feature, hotfix
    spec-number (optional) — claim a specific spec for this tab
  Behavior:
    - Reads the session registry and checks for conflicts
    - Registers this tab with its lane and optional spec claim
    - Reports any other active tabs and their claims
    - /tab close releases all claims and marks the tab as closed
  See: docs/sessions/registry.md
  ```
  Stop — do not execute any further steps.

---

## /tab close

If $ARGUMENTS starts with `close`:

1. Read `docs/sessions/registry.md`.
2. Find the row for the current session (match by today's date and context — ask if ambiguous; if `.forge/state/active-tab-*.json` marker exists, use the `registry_row_pointer` from the most recent marker for an exact match).
3. Update that row's Status to `closed` and add a `Closed` timestamp.
3b. **Delete the active-tab marker (Spec 353)**: remove any `.forge/state/active-tab-*.json` files matching this session. Use:
   ```bash
   rm -f .forge/state/active-tab-*.json
   ```
   Skip silently if no marker exists (fallback path: operator opened a tab without /tab register, or marker was manually cleaned up).
4. List all files modified during this session (from git status or session context).
5. Report: "Tab '<label>' closed. Claims released. Marker deleted. Modified files: <list>."
6. Stop.

---

## /tab <label> <lane> [spec-number]

1. Parse $ARGUMENTS to extract `label`, `lane`, and optional `spec-number`.
   - Valid lanes: `process-only`, `feature`, `hotfix`
   - If lane is invalid, report: "Invalid lane '<lane>'. Use: process-only, feature, or hotfix."

2. **Read registry**: Read `docs/sessions/registry.md`. If the file does not exist, create it with the header:
   ```markdown
   # Session Registry — Multi-Tab Coordination

   Active sessions for parallel Claude Code instances. Ephemeral — do not commit to git.

   | Session | Tab | Spec(s) | Lane | Status | Started | Last active |
   |---------|-----|---------|------|--------|---------|-------------|
   ```

3. **Check for conflicts**:
   a. Scan for rows with Status = `active`.
   b. **Spec conflict**: If `spec-number` is provided and another active tab has claimed the same spec, report:
      "CONFLICT: Tab '<other-tab>' is active on Spec <N>. Choose a different spec or wait for that tab to close."
      Stop — do not register.
   c. **Lane overlap**: If another active tab has the same lane AND same spec, report the conflict.
      (Same lane with different specs is allowed — e.g., two `feature` tabs on different specs.)

4. **Stale claim cleanup**: For any row with Status = `active` where `Last active` is more than 30 minutes ago (if detectable from timestamps), mark it as `stale` and report:
   "Stale session detected: Tab '<label>' (started <time>, last active <time>). Marking as stale."

5. **Register this tab**: Append a new row to the registry:
   ```
   | <session-id> | <label> | <spec-number or —> | <lane> | active | <now> | <now> |
   ```

5b. **Write active-tab marker (Spec 353)**: After the registry row is appended, write a session-local identity marker at `.forge/state/active-tab-<id>.json` so other lifecycle commands (`/implement`, `/close`, `/session`, `/parallel`, `/spec`, `/scheduler`, `/forge stoke`) can identify which registry row belongs to this chat.

   - Generate a stable random `<id>` for this session. Use either:
     ```bash
     # Bash:
     id=$(head -c 6 /dev/urandom | base64 | tr -d '/+=' | head -c 8)
     ```
     ```powershell
     # PowerShell:
     $id = -join ((48..57) + (97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})
     ```
   - Marker schema (all fields required except `spec_id` which is empty string when no spec is claimed):
     ```json
     {
       "session_id": "<id>",
       "label": "<label>",
       "lane": "<lane>",
       "spec_id": "<spec-number or empty string>",
       "tab_started": "<ISO 8601 now>",
       "last_command_at": "<ISO 8601 now>",
       "registry_row_pointer": "<session-id used in registry row column 1>"
     }
     ```
   - Write atomically:
     ```bash
     mkdir -p .forge/state
     cat > ".forge/state/active-tab-${id}.json" <<EOF
     {"session_id":"${id}","label":"<label>","lane":"<lane>","spec_id":"<spec-number or empty string>","tab_started":"<ISO 8601 now>","last_command_at":"<ISO 8601 now>","registry_row_pointer":"<session-id used in registry row column 1>"}
     EOF
     ```
   - The marker is **ephemeral and not authoritative** — it is a hint that lets lifecycle commands find their registry row without operator prompting. The registry row in `docs/sessions/registry.md` remains the persisted truth for claim history. See `docs/process-kit/multi-tab-quickstart.md` § Registry artifacts for the naming distinction.

6. **Report active tabs**: List all rows with Status = `active` (including the one just added):
   ```
   ## Active Tabs
   - <label> (lane: <lane>, spec: <N>, started: <time>)
   - <this-tab> (lane: <lane>, spec: <N>, started: now) ← you are here
   ```

7. **Lane guidance**: Based on the assigned lane, remind what this tab may touch:
   - `process-only`: `docs/`, `.claude/`, `CLAUDE.md`, `AGENTS.md` only
   - `feature`: `src/`, `tests/`, `ui/` — one spec at a time
   - `hotfix`: one specific file, one bug, no spec number advancement

8. Report: "Tab '<label>' initialized. Lane: <lane>. Spec: <N or none>. Safe to begin."
