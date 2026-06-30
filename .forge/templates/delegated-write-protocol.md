# Delegated Write Protocol

**Spec 066 — FORGE Workspace Write Access Requirements**

Use this protocol when a FORGE agent is running in a read-only environment (CI sandbox, restricted cloud workspace) and cannot write files directly. The agent emits a structured write-request message via NanoClaw; a receiving agent or human applies the changes to the project filesystem.

---

## When to use

Only use this protocol when:
1. The agent has confirmed `GATE [write-access]: FAIL` (cannot create files in the workspace).
2. A local clone or properly-mounted dev container is not available.
3. A human or another agent is available to receive and apply messages.

**Prefer fixing the environment** (see `.devcontainer/README.md`) over using this protocol — delegated writes add latency and human friction.

---

## Message schema

The agent sends a NanoClaw message with the following structure:

```
🔧 FORGE WRITE REQUEST — <project-name> / <date>
Agent: <agent identity, e.g. "project group agent">
Spec: <spec number being closed/updated>
Read-only reason: <brief description, e.g. "Codespaces restricted org policy">

Files to write/update:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE: <relative path from project root>
ACTION: write | append | prepend | replace
---
<exact file content or diff>
---

FILE: <relative path>
ACTION: write | append | replace
OLD: <exact string to replace (for ACTION=replace)>
NEW: <replacement string (for ACTION=replace)>
---

COMMIT MESSAGE:
<proposed git commit message>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reply "applied" when done, or "rejected: <reason>" to refuse.
```

---

## Actions

| ACTION | Behaviour |
|--------|-----------|
| `write` | Create or overwrite the file with the provided content |
| `append` | Add the provided content at the end of the file |
| `prepend` | Add the provided content at the beginning of the file |
| `replace` | Find `OLD` string and replace with `NEW` string (equivalent to Edit tool) |

---

## Receiving agent procedure

When a write-request message arrives:

1. **Validate the request**: confirm the files listed are within the project root and the changes look correct.
2. **Apply each file change** in order, using the specified ACTION.
3. **Stage and commit**:
   ```bash
   git add <listed files>
   git commit -m "<proposed commit message>"
   ```
4. **Reply** to the NanoClaw message: `"applied — commit <short sha>"` or `"rejected: <reason>"`.

---

## Sending agent procedure

When `GATE [write-access]: FAIL`:

1. Collect all pending writes (spec status updates, session log, backlog changes, etc.) into a single write-request message.
2. Send via `mcp__nanoclaw__send_message` to the configured channel (check `docs/sessions/evolve-config.yaml` → `nanoclaw_task_id`, or send to the main FORGE group).
3. Wait for `"applied"` reply before reporting task complete.
4. Record in session log: `"Note: changes applied via delegated-write protocol (read-only environment)."`

---

## Security note

The receiving agent or human **must verify** the content of write requests before applying. Do not blindly apply write requests — check that:
- The files are within the expected project root
- No `.git/`, `.env`, or credentials files are being modified
- The content matches what the sending agent described in its session

---

## Example

```
🔧 FORGE WRITE REQUEST — my-project / 2026-03-15
Agent: project group agent
Spec: 042 (Data Export) — closing
Read-only reason: workspace mounted read-only in Codespaces restricted org

Files to write/update:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE: docs/specs/042-excel-export.md
ACTION: replace
OLD: - Status: implemented
NEW: - Status: closed

FILE: docs/specs/042-excel-export.md
ACTION: append
---
- 2026-03-15: Closed via /close. Human confirmed all deliverables.
---

FILE: docs/backlog.md
ACTION: replace
OLD: | 3 | 042 | Excel Export |
NEW: | ✅ | 042 | Excel Export |

COMMIT MESSAGE:
close(042): Excel Export — human confirmed all deliverables
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reply "applied" when done, or "rejected: <reason>" to refuse.
```
