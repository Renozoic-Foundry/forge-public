---
name: tab
description: "Initialize or close a multi-tab session for parallel development"
model_tier: sonnet
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
2. Find the row for the current session (match by today's date and context — ask if ambiguous).
3. Update that row's Status to `closed` and add a `Closed` timestamp.
4. List all files modified during this session (from git status or session context).
5. Report: "Tab '<label>' closed. Claims released. Modified files: <list>."
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
