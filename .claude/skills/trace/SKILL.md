---
name: trace
description: "Generate bidirectional traceability matrix from spec annotations"
disable-model-invocation: false
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
# Framework: FORGE
# Model-Tier: sonnet
Generate a bidirectional traceability matrix from spec traceability link annotations.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /trace — Generate bidirectional traceability matrix (FORGE Spec 036). Lane B.
  Usage: /trace [--forward] [--backward] [--gaps] [--format md|csv|json|html] [--spec NNN]
                [--artifacts [ID]] [--rebuild]

  Arguments:
    (none)          Full report: forward trace + backward trace + gap analysis (markdown)
    --forward       Forward trace only: requirement → spec → code → test → evidence
    --backward      Backward trace only: code → requirement → test coverage
    --gaps          Gap analysis only: missing links across all specs
    --format <fmt>  Output format: md (default), csv, json, html
    --spec NNN      Limit analysis to a single spec number

  Cross-Artifact Relationship Index (Spec 108):
    --artifacts [ID]  Query cross-artifact relationships. ID is optional:
                        /trace --artifacts          Show full relationship index summary
                        /trace --artifacts 099      Show all artifacts linked to Spec 099
                        /trace --artifacts SIG-045  Show all artifacts linked to signal SIG-045
                        /trace --artifacts 2026-03-25-001  Show artifacts linked to session
    --rebuild         Rebuild the full artifact-links index from scratch (use with --artifacts)

  Data source:
    Each spec file's ## Traceability Links section (YAML-structured annotations).
    Only specs with Status: implemented or closed are included by default.

  Output: Rendered inline as markdown, or saved to docs/compliance/traceability-YYYY-MM-DD.md

  Annotation format (add to spec files):
    ## Traceability Links
    requirements:
      - REQ-001: <requirement text or external reference>
    code:
      - src/path/to/file.py::function_name
    tests:
      - tests/test_file.py::test_function_name
    evidence:
      - tmp/evidence/SPEC-NNN-YYYYMMDD/test-run.txt

  See: docs/specs/036-bidirectional-traceability.md, docs/process-kit/mcp-setup.md
  ```
  Stop — do not execute any further steps.

---

Parse $ARGUMENTS:
- Set MODE = `full` (default), or `forward`, `backward`, `gaps`, `artifacts` from flags.
- Set FORMAT = `md` (default), or `csv`, `json`, `html` from `--format`.
- Set SPEC_FILTER = spec number from `--spec NNN`, else empty (all specs).
- If `--artifacts` is present: set MODE = `artifacts`. Set ARTIFACT_QUERY = the next argument if present (spec number, signal ID, or session ID), else empty.
- If `--rebuild` is present: set REBUILD = true.

If MODE is `artifacts`: jump to **Step A1** (Cross-Artifact Relationship Index).

---

## [mechanical] Step 1 — Collect specs

Read `docs/specs/README.md`.
Build a list of specs to analyze:
- If SPEC_FILTER is set: only that spec.
- Otherwise: all specs with status `implemented` or `closed`.

For each spec in the list, read the spec file (`docs/specs/NNN-*.md`).

---

## [mechanical] Step 2 — Extract traceability links

For each spec file, find the `## Traceability Links` section.
Parse the YAML-structured content:
- `requirements:` — list of REQ-NNN: <text> entries
- `code:` — list of file::symbol paths
- `tests:` — list of test file::function paths
- `evidence:` — list of artifact paths

If a spec has no `## Traceability Links` section: record it as **unlinked** (relevant for gap analysis).

Build an in-memory index:
```
SPECS[NNN] = {
  title, status, lane,
  requirements: [...],
  code: [...],
  tests: [...],
  evidence: [...]
}
```

---

## [mechanical] Step 3 — Build forward trace

For each spec with requirements:
  For each requirement:
    Forward chain: requirement → spec (NNN) → code files → tests → evidence

Structure:
```
REQ-NNN (<spec NNN — title>)
  → Code:  src/path/to/file.py::function
  → Tests: tests/test_file.py::test_function
  → Evidence: tmp/evidence/SPEC-NNN-YYYYMMDD/test-run.txt
```

---

## [mechanical] Step 4 — Build backward trace

For each code file::symbol referenced across all specs:
  Backward chain: code → which spec claimed it → which requirement drove it → which test covers it

Structure:
```
src/path/to/file.py::function
  ← Spec NNN — <title>
  ← REQ-NNN: <requirement text>
  ← Tests: tests/test_file.py::test_function
```

---

## [mechanical] Step 5 — Gap analysis

Identify and flag:

1. **Requirements without code**: specs with requirements entries but empty code list.
2. **Code without tests**: specs with code entries but empty tests list.
3. **Tests without evidence**: specs with tests entries but empty evidence list.
4. **Unlinked specs**: implemented/closed specs with no `## Traceability Links` section at all.
5. **Orphaned code claims**: code paths in traceability links that do not exist in the repo (use file existence check).

Severity:
- `systemic` — 3+ gaps of the same type
- `recurring` — 2 gaps of the same type
- `isolated` — 1 gap

---

## [mechanical] Step 6 — Render report

Render based on MODE and FORMAT.

### Markdown output (FORMAT=md)

```markdown
# FORGE Traceability Matrix
Generated: YYYY-MM-DD
Specs analyzed: N | Requirements: N | Code links: N | Tests: N | Evidence: N

---

## Forward Trace
(omit if MODE=backward or MODE=gaps)

### Spec NNN — <Title>
| Requirement | Code | Test | Evidence |
|------------|------|------|----------|
| REQ-001: <text> | `src/file.py::fn` | `tests/test.py::test_fn` | `tmp/evidence/…` |
| REQ-002: <text> | *(gap — no code)* | *(gap)* | *(gap)* |

---

## Backward Trace
(omit if MODE=forward or MODE=gaps)

### src/path/to/file.py
| Symbol | Spec | Requirement | Test |
|--------|------|-------------|------|
| `function_name` | Spec NNN — <Title> | REQ-001: <text> | `tests/test.py::test_fn` |

---

## Gap Analysis
(always included unless MODE=forward or MODE=backward)

### ⚠ Requirements without code coverage (N)
- Spec NNN REQ-001: <text> — no code link recorded

### ⚠ Code without test coverage (N)
- Spec NNN `src/file.py::fn` — no test link recorded

### ⚠ Tests without evidence (N)
- Spec NNN `tests/test.py::test_fn` — no evidence artifact linked

### ⚠ Unlinked specs (N)
- Spec NNN — <Title>: no ## Traceability Links section

### ⚠ Orphaned code paths (N)
- Spec NNN `src/missing_file.py::fn` — file not found in repo

---

## Summary
Total gaps: N | Systemic: N | Recurring: N | Isolated: N
Coverage: N% of implemented specs fully linked
```

### CSV output (FORMAT=csv)

Emit a flat table:
```
spec_id,spec_title,requirement_id,requirement_text,code_path,test_path,evidence_path,gaps
```

### JSON output (FORMAT=json)

Emit structured JSON:
```json
{
  "generated": "YYYY-MM-DD",
  "specs": [
    {
      "id": "NNN",
      "title": "...",
      "requirements": [...],
      "code": [...],
      "tests": [...],
      "evidence": [...],
      "gaps": [...]
    }
  ],
  "summary": { "total_specs": N, "total_gaps": N, "coverage_pct": N }
}
```

### HTML output (FORMAT=html)

Emit an HTML table with alternating row colors, sortable columns, and gap rows highlighted in amber.

---

## [mechanical] Step 7 — Save artifact

Save the rendered output to:
`docs/compliance/traceability-YYYY-MM-DD.md` (or `.csv` / `.json` / `.html` by format).

Create `docs/compliance/` if it does not exist.
Add `docs/compliance/traceability-*.html` and `docs/compliance/traceability-*.csv` to `.gitignore` (generated artifacts — markdown is kept for audit trail).

Report: "Traceability matrix saved to docs/compliance/traceability-YYYY-MM-DD.<ext>"

---

## [mechanical] Next action

- If gaps found: "Next: annotate the flagged specs with `## Traceability Links` sections, then re-run `/trace`."
- If coverage is 100%: "Next: run `/close` or attach `docs/compliance/traceability-YYYY-MM-DD.md` to your compliance gate message."
- If no specs have traceability links yet: "Next: add `## Traceability Links` sections to your implemented specs. See the annotation format in `/trace ?`."

---

# Cross-Artifact Relationship Index (Spec 108)

The following steps execute when MODE = `artifacts`.

---

## [mechanical] Step A1 — Determine index action

- If REBUILD is true: proceed to Step A2 (full rebuild).
- If `.forge/state/artifact-links.json` does not exist: proceed to Step A2 (initial build).
- If `.forge/state/artifact-links.json` exists and ARTIFACT_QUERY is set: proceed to Step A4 (query).
- If `.forge/state/artifact-links.json` exists and ARTIFACT_QUERY is empty: proceed to Step A4 (summary).

---

## [mechanical] Step A2 — Scan artifacts for cross-references

Parse the following artifact sources for cross-references:

1. **Spec files** (`docs/specs/*.md`): Read each file. Extract references to other artifacts.
2. **Session logs** (`docs/sessions/*.md`, excluding `_template.md`, `README.md`, `signals.md`, `context-snapshot.md`, `registry.md`): Read each file. Extract references.
3. **Signals file** (`docs/sessions/signals.md`): Read the file. Extract references in each signal entry.
4. **ADR files** (`docs/decisions/*.md`, if the directory exists): Read each file. Extract references.
5. **Scratchpad** (`docs/scratchpad.md`, if it exists): Read the file. Extract references.

### Reference patterns to detect

| Pattern | Example | Artifact type |
|---------|---------|---------------|
| `Spec NNN` or `spec NNN` or `Spec-NNN` | Spec 099 | spec |
| `SIG-NNN-XX` | SIG-045-01 | signal |
| `CI-NNN` | CI-036 | content-insight |
| `EA-NNN` | EA-020 | evolution-anchor |
| `ADR-NNN` | ADR-005 | adr |
| `session YYYY-MM-DD-NNN` or `YYYY-MM-DD-NNN` (in session context) | session 2026-03-25-001 | session |

Use case-insensitive matching for the keyword prefix (e.g., `spec`, `Spec`, `SPEC` all match).

### Relationship type classification

Determine the relationship type from the surrounding context:

| Context pattern | Relationship type |
|-----------------|-------------------|
| `Trigger:` or `Triggered by` or `triggered by` | `triggered-by` |
| `Depends on` or `Dependencies:` or `blocked by` | `depends-on` |
| `Closed in` or `closed via` or `closed in session` | `closed-in` |
| `Signal` in source + spec in target (or vice versa) | `signal-from` |
| All other references | `references` |

### Error handling

- If a file cannot be read: skip it, log a warning, continue to the next file.
- If a reference pattern is malformed (e.g., `Spec abc`): skip it silently.
- Never crash on parse errors — always continue scanning remaining files.

---

## [mechanical] Step A3 — Build and write index

Build the relationship index as a JSON array. Each entry:
```json
{
  "source": "<artifact-id of the file containing the reference>",
  "target": "<artifact-id of the referenced artifact>",
  "type": "<relationship type>",
  "context": "<the sentence or line containing the reference>"
}
```

Artifact ID format:
- Specs: `spec-NNN` (e.g., `spec-099`)
- Signals: `SIG-NNN-XX` (e.g., `SIG-045-01`)
- Content insights: `CI-NNN` (e.g., `CI-036`)
- Evolution anchors: `EA-NNN` (e.g., `EA-020`)
- ADRs: `ADR-NNN` (e.g., `ADR-005`)
- Sessions: `session-YYYY-MM-DD-NNN` (e.g., `session-2026-03-25-001`)

Deduplicate: if the same source-target-type triple already exists, keep the first occurrence only.

Write the index to `.forge/state/artifact-links.json`:
```json
{
  "generated": "YYYY-MM-DDTHH:MM:SS",
  "version": "1.0",
  "total_links": <count>,
  "links": [ <array of link objects> ]
}
```

Create `.forge/state/` directory if it does not exist.

Report: "Artifact relationship index built: <count> links from <file count> artifacts. Saved to .forge/state/artifact-links.json"

Proceed to Step A4 if ARTIFACT_QUERY is set, otherwise stop.

---

## [mechanical] Step A4 — Query and display

Read `.forge/state/artifact-links.json`.

### If ARTIFACT_QUERY is empty — display summary

Show an overview:
```markdown
# Artifact Relationship Index
Generated: <timestamp>
Total links: <count>

## Link type distribution
| Type | Count |
|------|-------|
| references | N |
| triggered-by | N |
| depends-on | N |
| closed-in | N |
| signal-from | N |

## Most-connected artifacts (top 10)
| Artifact | Inbound | Outbound | Total |
|----------|---------|----------|-------|
| spec-099 | 5 | 3 | 8 |
| ... | | | |
```

### If ARTIFACT_QUERY is set — display relationships for a specific artifact

Normalize the query:
- If numeric (e.g., `099` or `99`): search for `spec-099` (zero-padded to 3 digits).
- If matches `SIG-NNN-XX`: search as-is.
- If matches `CI-NNN`, `EA-NNN`, `ADR-NNN`: search as-is.
- If matches `YYYY-MM-DD-NNN`: search for `session-YYYY-MM-DD-NNN`.

Find all links where the queried artifact is either `source` or `target`.

Display:
```markdown
# Artifact Relationships: <artifact-id>

## Outbound (this artifact references)
| Target | Type | Context |
|--------|------|---------|
| spec-036 | depends-on | "Dependencies: 036 (closed) — Bidirectional Traceability" |

## Inbound (referenced by)
| Source | Type | Context |
|--------|------|---------|
| session-2026-03-25-001 | closed-in | "Closed Spec 099 in this session" |
| SIG-045-01 | triggered-by | "Trigger: SIG-045-01 — performance regression" |

## Summary
Outbound: N | Inbound: N | Total: N
```

If no links found for the queried artifact: "No relationships found for <artifact-id>. Run `/trace --artifacts --rebuild` to regenerate the index."

---

## [mechanical] Step A5 — Next action (artifacts mode)

- If index was just built: "Artifact index ready. Query with `/trace --artifacts <ID>` to explore relationships."
- If query returned results: "Explore further with `/trace --artifacts <related-id>` or rebuild with `/trace --artifacts --rebuild`."
- If no results: "Run `/trace --artifacts --rebuild` to regenerate, or check that the artifact ID is correct."
