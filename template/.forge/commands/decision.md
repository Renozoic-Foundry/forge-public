---
name: decision
description: "Create a new Architecture Decision Record (ADR)"
workflow_stage: planning
---
# Framework: FORGE
Create a new Architecture Decision Record (ADR) from the template.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /decision — Create a new Architecture Decision Record (ADR).
  Usage: /decision <short title or description of the decision>
  Arguments: title (required) — a short description of the architectural decision.
  Examples:
    /decision Use Copier instead of Cookiecutter for template rendering
    /decision Switch from REST to gRPC for inter-service communication
  Output: docs/decisions/ADR-NNN-short-title.md
  See: docs/decisions/_template.md, docs/decisions/README.md
  ```
  Stop — do not execute any further steps.

---

Usage: /decision <short title or description>

1. Read `docs/decisions/_template.md` to load the ADR template.
2. Scan `docs/decisions/` for existing ADR files. Determine the next ADR number:
   - Look for files matching the pattern `ADR-NNN-*.md` (e.g., `ADR-028-spec-status-source-of-truth.md`).
   - Extract the numeric portion from each filename and find the maximum.
   - The next ADR number is `max + 1`, zero-padded to three digits.
   - If no ADR files exist, start at `ADR-001`.
3. Generate a kebab-case slug from the title (e.g., "Use Copier for templates" becomes `use-copier-for-templates`).
4. Create the new ADR file at `docs/decisions/ADR-NNN-slug.md` with:
   - Title: `# ADR-NNN: <title>`
   - Date: today's date (YYYY-MM-DD)
   - Status: `proposed`
   - Spec: fill in if the user mentions a spec number, otherwise leave as `(none)`
   - Context section: pre-filled with a summary based on the user's description
   - Decision, Consequences, and References sections: left as template placeholders for the user to complete
5. Confirm the file was created and display the full path.
6. Present a context-aware next action: "Review the draft ADR and fill in the Decision and Consequences sections. Update status to `accepted` when the team agrees."
