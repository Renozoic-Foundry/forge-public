# Bootstrap Conflict Resolution — Root-File Handling

**Spec 307 — `/forge-bootstrap` root-file conflict handler**

Last updated: 2026-04-23

When `/forge-bootstrap` scaffolds FORGE into an existing ("brownfield") project, several template-written files at the repository root may collide with files the project already maintains. This document defines the **deterministic** rules the command uses to detect those collisions, produce a recommendation, and apply the user's choice.

The rules are reproducible: given the same original file and the same FORGE template file, the command MUST produce the same recommendation, the same diff truncation point, and the same merged output structure. No LLM judgment is allowed in the recommendation path — only the rules below.

---

## 1. Canonical conflict set

The command enumerates **only** these root paths for conflict detection (Spec 307 scope). Subdirectory files are out of scope.

| Path | Template writes it? | Primary FORGE content |
|---|---|---|
| `README.md` | Yes — project intro + FORGE-process section | Headline + install/bootstrap crib |
| `CLAUDE.md` | Yes — agent instructions + spec-gate rules | Two hard rules + repo structure + change lanes |
| `AGENTS.md` | Yes — agent registry + tier mapping | Mirror of CLAUDE.md for AGENTS.md-aware tools |
| `MEMORY.md` | Only if present in template output | Human-maintained memory index |
| any other root-level `*MEMORY*.md` (e.g. `PROJECT_MEMORY.md`) | If present | Same as above |
| `.copier-answers.yml` | Yes — Copier state file | Template version pin + answers |

Files NOT in this list are written with Copier's default behavior (skip-if-exists, `_skip_if_exists` in `copier.yml`). This document does not govern them.

### `.copier-answers.yml` special case

`.copier-answers.yml` is **never** subject to the three-option prompt. If it already exists, `/forge-bootstrap` stops at Step 2 with the existing "already linked" message. Users redirect to `/forge stoke`. This preserves the pre-Spec-307 behavior as a regression guard.

---

## 2. Detection

Before invoking Copier, `/forge-bootstrap`:

1. Renders the template to a scratch directory (`$TMPDIR/forge-bootstrap-preview-<pid>/`).
2. For each path in the canonical conflict set, checks whether both `$SCRATCH/<path>` and `./<path>` exist.
3. Builds a conflict list of tuples: `(path, original_bytes, template_bytes, unified_diff, recommendation, rationale)`.

If the list is empty → zero-impact path: proceed directly to Step 4 of the existing bootstrap flow. **No prompt is shown.** (AC 4 — greenfield-safe.)

If the list is non-empty → emit one **batched** prompt covering all conflicts (AC 5 — no N separate blocking prompts).

---

## 3. Diff presentation

For each conflict, the prompt contains:

1. The path (bold).
2. The unified diff of original vs. template (`diff -u original template`).
3. Truncation rule: if the diff exceeds **120 lines**, display the first 60 and last 30 with a `... (N lines truncated — reply 'show full <path>' to expand) ...` marker between them. The 120/60/30 thresholds are fixed — do not tune per file.
4. The FORGE recommendation (one of `merge` / `keep-append` / `overwrite`) and a one-sentence rationale keyed to the rule that produced it.

---

## 4. Recommendation rules

Rules are evaluated **in order**. First rule that matches wins. The rule's name is included in the rationale so the user can understand why.

### Rule R1 — `identical`

If `sha256(original) == sha256(template)`, drop the conflict from the list entirely. No action required, no prompt. (This can happen when `/forge-bootstrap` is re-run after a partial bootstrap.)

### Rule R2 — `tiny-original`

If the original file is **≤ 400 bytes** OR consists of fewer than 3 non-blank lines → recommend **overwrite**.

Rationale template: `"Original is a stub (<N> bytes, <L> non-blank lines); overwriting preserves the stub as <name>.original.<ext>."`

This matches the common case of a fresh `git init` with a one-line `README.md` or a placeholder `CLAUDE.md`.

### Rule R3 — `boilerplate-readme`

Applies only to `README.md`. If the original matches the GitHub auto-generated template (first line is `# <repo-name>`, no body content other than optional blank lines and a single optional description line) → recommend **overwrite**.

Detection heuristic (deterministic):
- Line 1 starts with `# ` followed by any text.
- Total non-blank lines ≤ 3.
- No fenced code blocks, no tables, no `##` headings.

Rationale template: `"Original README is a GitHub-style boilerplate stub; overwriting (with .original.md preserved) installs the FORGE README."`

### Rule R4 — `structural-overlap`

If the original contains **any** of the FORGE template's top-level headings (`## FORGE Process`, `## Two hard rules`, `## Repo structure`, `## Change lanes`, `## Spec lifecycle`) **anywhere** → recommend **merge**.

Rationale template: `"Original already contains FORGE section '<heading>'; merging reconciles both versions without duplicating that section."`

### Rule R5 — `substantial-original`

If the original is **> 400 bytes** AND has **≥ 3 non-blank lines** AND no structural overlap with FORGE headings → recommend **keep-append**.

Rationale template: `"Original has project-specific content (<N> bytes, <L> lines) and no FORGE sections yet; appending FORGE content under '## FORGE Process' preserves the original verbatim."`

### Rule R6 — `fallback`

If none of R1–R5 match (should not occur with the canonical set; included as a safety net) → recommend **keep-append**.

Rationale template: `"Fallback rule — preserving original and appending FORGE content is the least destructive choice."`

### Rule application notes

- Rules R2, R3, R5 are mutually exclusive by construction (size thresholds partition the space).
- R4 can override R2/R5 (structural overlap beats size-based rules) — R4 is placed before R5 in the evaluation order to ensure this.
- The evaluation order is: R1 → R2 → R3 → R4 → R5 → R6.

### Determinism contract

For the same `(original_bytes, template_bytes)` pair the command MUST produce the same recommendation across runs, platforms, and FORGE versions within a single major version. This contract is what makes the rules document usable as a test oracle.

---

## 5. User choice

For each conflict the user may choose:

| Choice | Behavior |
|---|---|
| `merge` | Write a merged file (Section 6). Do not keep an `.original.*` copy — the merged file contains both sets of content. |
| `keep-append` | Write the original verbatim followed by a `## FORGE Process` block containing the FORGE template content. Do not keep an `.original.*` copy. |
| `overwrite` | Write the FORGE template version. Preserve the original as `<stem>.original.<ext>` (e.g. `README.original.md`). **Regression guard: this matches pre-Spec-307 behavior.** |
| `accept-all` | Apply FORGE's recommendation for every conflict in the batch. |
| `cancel` | Abort bootstrap; touch nothing. |

The prompt's **default action on blank submission** is `accept-all`. This is the only place the recommendation is applied without per-file confirmation. (AC 4 / Constraint: "No silent merge default without asking" — the batched prompt is shown; `accept-all` requires an explicit empty-Enter that the user sees in the prompt text.)

---

## 6. Merge output format

When the user picks `merge`, the output file is produced by the following deterministic algorithm:

1. Copy the original file verbatim up to but not including any heading that matches one of the FORGE template's top-level headings (from R4 list).
2. For each FORGE-template heading not already present in the original, insert it in the order it appears in the template, prefixed by a source marker comment:
   ```
   <!-- BEGIN FORGE-inserted (spec-307) -->
   ## <heading>
   <template content for this section>
   <!-- END FORGE-inserted (spec-307) -->
   ```
3. If the original has trailing content after its final heading, append it last.

**Source markers are required** on every FORGE-inserted block (AC 2). This lets future re-runs detect previously inserted FORGE content deterministically (rule R4 checks the heading, not the marker; future specs may extend to marker-based detection).

---

## 7. Keep-original-and-append output format

When the user picks `keep-append`, the output file is:

```
<original content verbatim, no modifications>

<!-- BEGIN FORGE-inserted (spec-307) -->
## FORGE Process

<entire FORGE template content, headings downshifted by one level so they nest under "## FORGE Process">
<!-- END FORGE-inserted (spec-307) -->
```

Heading downshift rule: `^# ` → `^## `, `^## ` → `^### `, etc. Stop at h6. If downshift would produce h7+, leave the heading unchanged and prefix its text with `▸ ` as a visual indicator (edge case, should not occur with current templates).

The **final newline** of the original is preserved; exactly one blank line separates the original from the `<!-- BEGIN FORGE-inserted ... -->` marker.

---

## 8. Overwrite output format

When the user picks `overwrite`:

1. Rename the original from `<stem>.<ext>` to `<stem>.original.<ext>`. If `<stem>.original.<ext>` already exists (from a prior bootstrap), append `.N` to the stem where N is the smallest positive integer producing a non-colliding path (`README.original.1.md`, `README.original.2.md`, ...).
2. Let Copier write the template version.

The original is never deleted under any code path (Constraint).

---

## 9. Interaction with `.copier-answers.yml`

See Section 1 — this file bypasses the handler entirely. If the user reaches this document looking for answer-file merge support, that is out of scope for Spec 307. File a follow-up spec if needed.

---

## 10. Test oracle

The following fixture-style table is the contract the rules doc promises. Any future change to rules must update this table and re-run the fixtures.

| Fixture | `README.md` content (abridged) | Expected recommendation | Expected rule |
|---|---|---|---|
| `empty-repo` | (no file) | n/a — no conflict | — |
| `github-stub` | `# my-project\n` | `overwrite` | R3 |
| `tiny-stub` | `# my-project\n\nTodo.\n` | `overwrite` | R2 |
| `project-description` | `# Acme API\n\nInternal REST service for …\n\n## Install\n\n…\n\n## License\n\nMIT\n` | `keep-append` | R5 |
| `already-forge-ified` | `# Acme\n\n…\n\n## FORGE Process\n\n(old content)\n` | `merge` | R4 |
| `bit-for-bit-match` | identical to template | (dropped) | R1 |

Fixtures live under `docs/process-kit/fixtures/bootstrap-conflict/` if formal tests are added. Spec 307 ships the rules doc only; fixture automation is a follow-up if regressions surface.

---

## 11. Out of scope (Spec 307)

- Subdirectory conflicts (template writes under its own subtrees — low collision surface).
- Full 3-way merge tooling.
- Silent/non-interactive CI mode — the handler is interactive by design.
- Backporting the handler to direct `copier copy` invocations outside `/forge-bootstrap`.

---

## Revision Log

- 2026-04-23: Initial version — created under Spec 307.
