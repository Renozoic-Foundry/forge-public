# Framework: FORGE
# Model-Tier: haiku
Add a scratchpad note to be reviewed at the next appropriate process checkpoint.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /note — Add a scratchpad note for review at the next process checkpoint.
  Usage: /note <text>
  Arguments: text (required) — the note to save. Optionally prefix with a tag.
  Tags: [validate], [session], [evolve], [bug], [signal] — controls when/how the note is reviewed.
  Examples:
    /note check if the extractor handles empty inputs
    /note [evolve] review scoring weights after 5 completed specs
    /note [bug] login page returns 500 on empty password
    /note [signal] repeated friction with test harness teardown
  See: docs/sessions/scratchpad.md
  ```
  Stop — do not execute any further steps.

---

Usage: /note <your note text>

1. Read docs/sessions/scratchpad.md (create it if it does not exist).
2. Append the note as a new entry with today's date and a `[ ]` checkbox:
   ```
   - [ ] 2026-MM-DD: <note text>
   ```
3. Confirm the note was saved and state when it will be reviewed:
   - Notes tagged `[close]` → reviewed during the next `/close` run
   - Notes tagged `[session]` → reviewed during the next `/session` run
   - Notes tagged `[evolve]` (or legacy `[outer-loop]`) → reviewed during the next `/evolve` run
   - Notes tagged `[bug]` → handled as a structured bug report (see Step 3b below)
   - Notes tagged `[signal]` → handled as a signal capture (see Step 3c below)
   - Untagged notes → reviewed at next `/close` OR `/session`, whichever comes first
4. If no tag is provided and the note sounds like a process concern, suggest adding `[evolve]`.

### [mechanical] Step 3b — [bug] tag handling (Spec 131)

If the note is tagged `[bug]` (replaces the deprecated `/bug` command):

1. **Prompt for severity**: Ask the user to classify severity:
   - **critical**: data loss, crash, security vulnerability
   - **high**: feature broken, incorrect output, blocks workflow
   - **medium**: degraded behavior, workaround exists
   - **low**: cosmetic, minor inconvenience

2. **Build structured bug entry**: Format as:
   ```
   - [ ] 2026-MM-DD: [bug] <description> | Severity: <level>
   ```

3. **Route**: Search `docs/specs/` for an existing spec that covers this area.
   - If found: add `| Route: Spec NNN` to the entry
   - If not found: add `| Route: needs-spec`

4. **Persist**: Append to `docs/sessions/scratchpad.md` AND to `docs/sessions/signals.md` as type `bug`.

5. **Next action**:
   - If severity is `critical` or `high`: "Next: run `/spec <bug summary>` to create a hotfix spec immediately."
   - Otherwise: "Bug noted. It will surface at the next `/close` or `/session`."

### [mechanical] Step 3c — [signal] tag handling (Spec 131)

If the note is tagged `[signal]` (replaces the deprecated `/harvest` command):

1. **Prompt for category**: Ask the user to classify the signal:
   - **content**: what worked/didn't in a deliverable
   - **process**: what worked/didn't in the workflow
   - **architecture**: design insight for future work

2. **Build structured signal entry**: Format as:
   ```
   - [ ] 2026-MM-DD: [signal] <description> | Category: <category>
   ```

3. **Persist**: Append to `docs/sessions/scratchpad.md` AND to `docs/sessions/signals.md` as the appropriate signal type (`retro-content`, `retro-process`, or `retro-architecture`).

4. **Next action**: "Signal captured. It will inform the next `/close` retro chain and `/matrix` re-scoring."

**Automatic review:** The following commands check docs/sessions/scratchpad.md for open items:
- `/close` — prints open `[close]` and untagged notes before Quick Check items
- `/session` — prints all open notes and asks which to resolve or carry forward
- `/evolve` — prints open `[evolve]` notes as part of the process health check

5. Present a context-aware next action: "Note saved. Continue current work — it will surface at the next `/<review-command>`."
