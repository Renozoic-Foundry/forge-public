<!-- Last updated: 2026-03-27 -->
# Human Validation Runbook

Last updated: 2026-03-13

## Validation philosophy

**Test new and changed functionality. Spot-check adjacent areas that could plausibly have been affected. Do not run sections unrelated to the change.**

This is not a regression suite. A full regression exists in the automated test suite. This runbook ensures the human can see that what the AI built actually works for the changed surface, and that nothing obviously adjacent broke.

---

## When to run this

**Every session ends with section G (Session Capture). No exceptions.**

| What changed | Run |
|---|---|
| Source code | A |
| Spec declares shadow validation | E |
| Primary output or schema | B |
| Validation artifacts | C |
| Spec created or updated | D |
| Spec just moved to `implemented` | F (evolve loop trigger) |
| Monthly | F (full KPI review) |

<!-- customize: add project-specific trigger rows above (e.g., "Vision tags → E") -->

---

## A. After a code change

> **Adjacent areas to spot-check:** if the change is in an extractor, spot-check one output row (B1). If in a shared module, spot-check dependent modules.

### Quick Check (always run)
- [ ] Source Control diff — no unintended files, no debug code (A1 step 3)
- [ ] Problems panel — zero Errors (A2 step 2)
- [ ] Test Explorer — all tests green for the changed module (A3 step 2–3)

### A1. Review the diff in Source Control

1. Click the **Source Control** icon in the VS Code Activity Bar (`Ctrl+Shift+G`).
2. Click each changed file to open the diff view.
3. Confirm:
   - [ ] No unintended files (`.env`, `tmp/`, `__pycache__/`)
   - [ ] No commented-out debug code or `print()` left in
   - [ ] Changed files match what the spec scope described

### A2. Check for lint and type problems

1. Open **Problems** panel (`Ctrl+Shift+M`).
2. Filter to **Errors** — should be zero.
3. Investigate any new Warnings in changed files.

### A3. Run tests via the Test Explorer

1. Click the **Testing** icon (flask) in the Activity Bar.
2. Click **Run All Tests**.
3. Confirm:
   - [ ] All tests pass (green)
   - [ ] No unexpected skips

---

## B. After primary output changes

<!-- customize: replace "output CSV" with your project's primary output format -->

> **Adjacent areas to spot-check:** verify output schema matches expectations.

### Quick Check (always run)
- [ ] Output file header/schema matches expected structure (B1)
- [ ] Row/record count matches expectation (B2)

### B1. Inspect the output

1. Open the output file in VS Code Explorer.
2. Confirm:
   - [ ] Schema/header matches expected field order
   - [ ] No blank or corrupted records
   - [ ] Key fields have expected values

### B2. Verify record count

1. Check the output contains the expected number of records.
2. Confirm no unexpected duplicates or missing entries.

---

## C. After a validation artifact run

<!-- customize: replace with your project's validation/harness artifact format -->

### Quick Check (always run)
- [ ] Validation artifact exists in `tmp/` directory (C1)
- [ ] All checks pass (C1 step 3)

### C1. Review the validation report

1. Open the validation artifact in VS Code Explorer.
2. Confirm:
   - [ ] All pass/fail checks are in expected state
   - [ ] No unexpected failures
3. Spot-check key metrics against previous run if available.

---

## D. After a spec change

> **Adjacent areas to spot-check:** verify the spec index (D2) and changelog (D3). If the spec references CLAUDE.md or checklists, confirm those files weren't left in an inconsistent state.

### Quick Check (always run)
- [ ] Spec opens in Markdown preview with no `<placeholder>` text and `Change-Lane:` filled in (D1)
- [ ] Spec appears in the index with correct status (D2)

### D1. Preview the spec

1. Open the spec (`docs/specs/NNN-*.md`), press `Ctrl+Shift+V` for preview.
2. Confirm:
   - [ ] All template sections present
   - [ ] `Change-Lane:` and `Priority-Score:` filled in
   - [ ] `Status:` reflects actual state
   - [ ] No `<placeholder>` text

### D2. Check the spec index

1. Open `docs/specs/README.md` in preview.
2. Confirm:
   - [ ] New/updated spec in the index with correct status
   - [ ] No orphan specs (files that exist but aren't indexed)

### D3. Check the changelog

1. Open `docs/specs/CHANGELOG.md`.
2. Confirm an entry exists for today's date referencing the spec number.

---

## E. After shadow validation (Spec 115)

> **Trigger:** Spec declares a shadow validation strategy in its `## Shadow Validation` section.

### Quick Check
- [ ] Shadow validation evidence exists in the spec's Evidence section (E1)
- [ ] Outputs match or divergences are documented and justified (E1 step 3)

### E1. Review shadow validation evidence

1. Open the spec file. Find the `## Shadow Validation` section.
2. Confirm:
   - [ ] A strategy is declared (reference-comparison, dual-run, or test-oracle-replay)
   - [ ] Evidence field is filled (not "pending")
3. Review the evidence:
   - [ ] Outputs match the reference, or divergences are expected and documented
   - [ ] No unexplained differences
4. If evidence is missing: this is a non-blocking warning. The spec can still close, but the shadow validation is incomplete.

See [shadow-validation-guide.md](shadow-validation-guide.md) for strategy details.

---

## F. Evolve loop — process health

**Triggers:**
- **Per-spec fast path (F1+F4):** runs inline as part of `/close` after every spec reaches `implemented`
- **Full review (F1–F4):** every 5 closed specs or every 7 days, whichever comes first — run via `/evolve`

> When triggered by a spec completion (inline in `/close`), focus on F1 (drift check for the spec just completed) and F4 (backlog update). Skip F2 and F3 unless it's a full periodic review.

### Quick Check (always run on spec completion)
- [ ] Spec just completed: acceptance criteria still match implemented behavior (F1)
- [ ] Backlog row updated to `implemented` (F4)

### F1. Spec vs implementation drift

1. Open `docs/specs/README.md` in preview.
2. For the spec just completed (or all `implemented` specs on monthly review), open it and spot-check one acceptance criterion against code or a test.
   - [ ] No implemented spec has acceptance criteria the code clearly doesn't satisfy
   - [ ] No `draft` spec has code committed without approval

### F2. README accuracy (monthly only)

<!-- customize: replace with your project's CLI help command -->
1. Open `README.md` in preview.
2. Confirm CLI commands listed match actual CLI help output.
   - [ ] No missing or removed commands

### F3. Process KPI review (monthly only)

- [ ] Lead time from spec `draft` → `implemented` (check Revision Log dates)
- [ ] Number of hotfixes since last review
- [ ] Regressions caught vs missed
- [ ] Documentation drift events
- [ ] Score calibration: compare 2–3 completed specs' predicted vs actual BV — update rubric anchors if bias found

### F4. Backlog health

1. Open `docs/backlog.md` in preview.
2. Confirm:
   - [ ] Completed spec row updated to `implemented`
   - [ ] Any new specs from recent sessions appear in the table
   - [ ] Top spec with highest score has a draft spec file started

---

## G. Every session — session capture (required, no exceptions)

### Quick Check (always run)
- [ ] Session log file exists at `docs/sessions/YYYY-MM-DD-NNN.md` (G1)
- [ ] If spec is partially implemented: completed/remaining ACs documented in session log (G1)
- [ ] Process improvement items have backlog entries (G2)

### Partial failure recovery rule

**If a spec is partially implemented** (some ACs committed, others remaining) and the session must end:

- **Spec status stays `in-progress`** — do not revert to `draft`. Rationale: reverting to `draft` loses the signal that real progress was made and risks re-work of already-completed acceptance criteria.
- Document the partial state in the session log (see G1 checklist below).
- Use [Spec 119 (JSON session handoff)](../specs/119-json-session-handoff.md) to capture structured state for the next session, and [Spec 123 (checkpoint resume)](../specs/123-checkpoint-resume-on-context-overflow.md) for mid-command recovery on context overflow.

### G1. Review the session log

1. In VS Code Explorer, open `docs/sessions/` — find today's log file.
   - If missing: this is a process defect. Create it from `_template.md` now.
2. Open and confirm:
   - [ ] **Summary** filled in (2–3 sentences)
   - [ ] **Decisions made** lists every concrete choice this session
   - [ ] **Process pain points** lists anything that caused friction
   - [ ] **Spec triggers** lists new specs needed
   - [ ] **Process improvement items** lists workflow changes needed
   - [ ] **If spec is partially implemented** (some ACs committed, others remaining): document completed ACs, remaining ACs, and suggested resume point in the session log

### G2. Act on process improvement items

1. Open `docs/backlog.md`.
2. For each item in the session log:
   - [ ] Add as a proposed spec entry with score, or confirm existing entry exists
3. If `small-change` lane and urgent, create the spec file now.

### G3. Check the backlog is current

1. Open `docs/backlog.md`.
2. Confirm:
   - [ ] Specs proposed this session appear in the table
   - [ ] No spec moved to `implemented` without its row updated
