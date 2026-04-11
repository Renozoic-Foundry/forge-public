---
name: config-change
description: "Propose and apply changes to agent configuration files"
model_tier: sonnet
workflow_stage: configuration
---
# Framework: FORGE
Propose and apply changes to agent configuration files (AGENTS.md, CLAUDE.md) with human approval, rollback, and audit logging.

⚠ **Highest-risk command in FORGE.** All proposals require explicit human approval. Agents cannot approve their own config changes.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /config-change — Propose changes to AGENTS.md or CLAUDE.md with human approval gate.
  Usage: /config-change [--propose <section> "<change description>"] [--rollback] [--log]
  Arguments:
    --propose <section> "<description>"  — propose a change to a specific config section
    --rollback                           — revert the most recent applied config change
    --log                                — show the config change audit log
  Behavior:
    - Agent proposes a structured diff of the config change
    - Human receives diff via NanoClaw (or inline) for approve/reject/modify
    - Approved changes are applied with automatic rollback point saved
    - All proposals, decisions, and outcomes are recorded in the audit log
    - Scope limits and cool-down period are enforced
  Config: docs/sessions/config-change-config.yaml
  Audit log: docs/sessions/config-change-audit.md
  See: docs/specs/046-autonomy-config-protocol.md, docs/decisions/ADR-046-autonomy-self-modification.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Load config and check mode

Read `docs/sessions/config-change-config.yaml` (skip if absent — use defaults).
Defaults:
- `allowed_sections: [autonomy-levels, model-tiering, test-commands, permission-mode]` — sections of AGENTS.md/CLAUDE.md that agents may propose changes to
- `blocked_sections: [two-hard-rules, spec-gate, change-lanes]` — sections that are always out of scope
- `cool_down_days: 7` — minimum days between applied config changes
- `notify_via: inline` — `inline` (present in conversation) or `nanoclaw`
- `audit_log: docs/sessions/config-change-audit.md`

If `--log` in $ARGUMENTS: read and display `docs/sessions/config-change-audit.md`. Stop.

If `--rollback` in $ARGUMENTS: proceed to **Rollback procedure** (step 6). Skip all other steps.

## [mechanical] Step 2 — Cool-down check

Read `docs/sessions/config-change-audit.md`. Find the most recent entry with `outcome: applied`.
- If that entry's date is within `cool_down_days` of today: stop and report:
  ```
  ⛔ CONFIG CHANGE BLOCKED — cool-down period active.
  Last applied change: YYYY-MM-DD (<section>)
  Cool-down expires: YYYY-MM-DD (N days remaining)
  Reason: rapid successive config changes increase drift risk.
  ```

## [mechanical] Step 3 — Draft the proposal

Parse `--propose <section> "<description>"` from $ARGUMENTS.

a. **Scope check**: verify `<section>` is in `allowed_sections`:
   - If section is in `blocked_sections` or not in `allowed_sections`: stop and report:
     ```
     ⛔ CONFIG CHANGE BLOCKED — section "<section>" is out of scope.
     Allowed sections: <list from config>
     Blocked sections: <list from config>
     To change this section, update config-change-config.yaml (requires human edit).
     ```

b. Read the current content of the target file (AGENTS.md or CLAUDE.md) for the relevant section.

c. Draft the proposed change as a unified diff:
   ```
   Proposed Config Change
   ======================
   File: AGENTS.md | CLAUDE.md
   Section: <section name>
   Proposed by: <agent identity>
   Date: YYYY-MM-DD

   --- current
   +++ proposed
   @@ <section heading> @@
   -<current line(s)>
   +<proposed line(s)>

   Rationale: <1-2 sentences explaining why this change improves the workflow>
   Signal reference: SIG-NNN (if triggered by a signal)
   ```

## [mechanical] Step 3b — Review Router (Spec 159)

Before presenting the proposal for human approval, run the review router:

a. Select perspectives: **DA** (always — risk check on config changes). Add **CISO** if the change touches security-related config (auth, keys, permissions, secrets). Add **CTO** if the change is architectural (file structure, module config, integration settings).
b. Display selection rationale.
c. Run selected perspectives on the proposed change (the diff from Step 3).
d. Present the Review Brief as part of the proposal output in Step 4.
e. BLOCK is advisory — the operator decides whether to proceed.

## [decision] Step 4 — Human approval gate

Present the proposal to the human (including the Review Brief from Step 3b):
```
⚠️ CONFIG CHANGE PROPOSAL — requires explicit approval

<diff from step 3>

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `approve` | Apply the change; save rollback point; record in audit log |
> | **2** | `reject` | Discard the proposal; record reason in audit log |
> | **3** | `modify` | Edit the diff above, then re-present for approval |
> | **4** | `defer` | Save proposal to audit log as pending; apply later |
```

If `notify_via=nanoclaw`: send the proposal via `mcp__nanoclaw__send_message` with the diff. Wait for operator reply before proceeding.

**DO NOT apply the change without explicit human approval.** If the human does not respond, treat as `defer`.

## [mechanical] Step 5 — Apply approved change

On `approve`:

a. **Save rollback point**: write the current file content to `docs/sessions/config-change-rollback.md`:
   ```
   # Config Change Rollback Point — YYYY-MM-DD HH:MM
   File: AGENTS.md | CLAUDE.md
   Section: <section>

   ## Saved content (before change)
   <full current section content>
   ```

b. **Apply the diff**: edit the target file to apply the proposed change.

c. **Record in audit log** (`docs/sessions/config-change-audit.md`):
   ```
   ## Change YYYY-MM-DD — <section>
   - Proposed by: <agent>
   - Approved by: human (explicit)
   - Outcome: applied
   - File: AGENTS.md | CLAUDE.md
   - Section: <section>
   - Diff: <inline diff>
   - Rollback: docs/sessions/config-change-rollback.md
   ```

d. **Permission mode sync (Spec 117)**: If the change affects the `autonomy-levels` section and modifies `default_autonomy`:
   - Map the new autonomy level to Claude Code permission mode: L0–L1 → `default`, L2 → `auto`, L3–L4 → `bypassPermissions`
   - Read `.claude/settings.json` (create if absent). Update `defaultMode`.
   - Report: `Permission mode updated: <old mode> → <new mode> (written to .claude/settings.json)`

e. Report: "Config change applied. Rollback available: `/config-change --rollback`"

On `reject`:
- Record in audit log with `outcome: rejected` and the human's reason (ask if not provided).
- Report: "Proposal rejected and recorded. No change applied."

On `modify`:
- Accept operator's revised diff. Re-present as new proposal in step 4.

On `defer`:
- Record in audit log with `outcome: deferred`. Report proposal ID for future reference.

## [mechanical] Step 6 — Rollback procedure

On `--rollback`:

a. Read `docs/sessions/config-change-rollback.md`.
b. If absent or empty: report "No rollback point available."
c. Present the saved content and confirm:
   ```
   > **Rollback config change?**
   > This will revert: <file> / <section> to the saved state from YYYY-MM-DD.
   > Current content will be overwritten. Proceed? (yes/no)
   ```
d. On `yes`: overwrite the section with saved content. Append to audit log:
   ```
   ## Rollback YYYY-MM-DD — <section>
   - Rolled back by: human (explicit)
   - Restored to: state from YYYY-MM-DD
   ```
   Report: "Rollback complete."
e. On `no`: stop. No change made.
