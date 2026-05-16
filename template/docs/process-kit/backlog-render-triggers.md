# Backlog Render-Trigger Inventory

**Spec 440 AC 5 deliverable.** Enumerates every operator path that produces, refreshes, or reads `docs/backlog.md`. Feeds the Req 1a readership measurement that informs the ADR storage-model decision.

This inventory is a **snapshot of the FORGE-internal repo at the time Spec 440 was implemented (2026-05-15)**. Consumer projects diverge in three ways: (1) older FORGE versions may pre-date Spec 439's helper-routing rewire; (2) consumers may have local commands that read `docs/backlog.md` directly; (3) consumers customize `/forge-init`-derived files freely. Re-run this inventory in a consumer project before assuming the human-read column matches.

## Producers — write or refresh `docs/backlog.md`

| Path | Trigger | Write mode | Notes |
|------|---------|-----------|-------|
| `/matrix` | Operator invocation | Renderer write — `assemble_view.py docs/backlog.md` (split-file) OR `render_backlog.py --output docs/backlog.md` (mode=generated) | Canonical refresh point. Skipped when `--skip-canonical-write` helper returns `skip` and the project is on split-file mode. |
| `/forge-init` | First-time bootstrap | Direct write — creates the file with empty ranked tables and scoring formula | One-shot. Consumer projects only. |
| `/close` Step "Backlog sync" (Spec 086) | After spec close | Direct row edit — finds the spec's row and updates status column + Rank=✅ | **Bypasses the renderer.** Known leak point flagged in Spec 439's rewire scope. |
| `/close` Step "Deferred Scope" disposition | When operator chooses `backlog` for deferred items | Direct write — appends to "Deferred Scope" section | Bypasses renderer. |
| `/close` Step "Deferred Scope" disposition (promote) | When operator chooses `promote` for deferred items | Direct write — adds the new spec row | Bypasses renderer. |
| `/revise` status-reset path | When a status reset to `approved` fires | Direct row edit — updates the spec's row to `approved` | Bypasses renderer. |
| `/evolve` Step 7 | At score-calibration completion | Direct write — updates `Last score calibration:` field | Bypasses renderer. |
| `scripts/migrate-to-derived-view.py` | One-shot migration | Direct rewrite — inserts sentinel markers, regenerates body | Spec 254 / Spec 398 migration. |

## Consumers — read `docs/backlog.md`

| Path | Read type | Routed through `derived_state.py`? | Human-facing or programmatic? |
|------|-----------|------------------------------------|-------------------------------|
| `/matrix` | Structured table | YES (Spec 439 rewire) | Programmatic; operator sees rendered output, not raw read |
| `/brainstorm` | Structured table | YES (Spec 439 rewire) | Programmatic |
| `/scheduler` | Structured table (status filter) | NO — still reads file directly | Programmatic; **not yet rewired** |
| `/forge status` | Top-3 ranked specs | NO — still reads file directly | Programmatic; **not yet rewired** |
| `/insights` | Velocity / aging stats | NO — still reads file directly | Programmatic; **not yet rewired** |
| `/interview` | Context-gathering read list | NO — listed alongside README, signals, scratchpad | Programmatic; **not yet rewired** |
| `/explore` | Text search for existing topics | NO — substring grep | Programmatic; **not yet rewired** |
| `/spec` (Spec 399 explicit) | Consensus-Review field check | N/A — explicitly says "Do NOT read backlog.md for this; read per-spec frontmatter" | Programmatic; correctly routed |
| `/now` See: line | None (advisory reference only) | N/A — file mentioned in See: line only | Documentation pointer, not a read |
| `/parallel` consistency check | Lightweight verify after merge | NO — mentioned for "verify consistency" | Programmatic |
| Operator opening file in IDE / VS Code | Visual read | N/A — direct disk read by IDE | **Human-facing** |
| Operator viewing file on GitHub web UI | Visual read | N/A — direct file render by GitHub | **Human-facing** |
| Reviewer scanning rendered backlog in PR diff | Visual read | N/A | **Human-facing** |

## Readership measurement (Req 1a)

| Class | Count (at 2026-05-15) | Notes |
|-------|----------------------|-------|
| Programmatic reads routed through `derived_state.py` | 2 | `/matrix`, `/brainstorm` |
| Programmatic reads NOT yet routed (file still read directly) | 5 | `/scheduler`, `/forge status`, `/insights`, `/interview`, `/explore` |
| Human-facing reads (IDE / GitHub UI / PR review) | non-zero | Operator workflow documentation explicitly refers to `docs/backlog.md` as the "operator-visible artifact" |

**Decision input**: readership is non-zero on both axes. **Deletion is NOT viable** as the fourth ADR option (Req 1a's deletion-evaluation branch). The 5 not-yet-rewired programmatic readers are out of scope for Spec 440 — captured as a follow-up signal for a future rewire pass once Spec 439's helper-routing pattern matures.

## Bypass-commit-path inventory

Paths that produce commits without running an operator pre-commit hook (relevant to the ADR's bypass-commit-path decision criterion):

| Path | Where it commits from | Hook fires? |
|------|----------------------|-------------|
| `git commit` from operator workstation | Local | YES (if installed) |
| `git commit --no-verify` | Local | NO (explicit bypass) |
| GitHub web-UI edit (e.g., a typo fix via the GitHub editor) | Remote — server-side | NO |
| GitHub PR merge (squash/rebase/merge commit) | Remote — server-side | NO |
| CI bot commit (e.g., a dependabot PR auto-merge) | Remote — CI runner | NO |
| Operator on a second machine without hooks installed | Local — different env | NO (until they install) |
| Operator running `git rebase` with `--no-verify` | Local | NO (explicit bypass) |
| Initial clone of an existing repo | N/A — no commit | N/A (but: the rendered view IS or ISN'T present on clone depending on storage model) |

The bypass-commit-path criterion is what discriminates between **gitignore + pre-commit hook** (silent desync on any of the above) and **tracked + render-on-commit** (file is present and current as of the last operator commit that ran the hook; bypassed commits just don't update the view, and the next operator-side commit re-renders it).

## Sibling artifact note

`docs/spec-index-table.md` (and the broader split-file rendering surface from Spec 398) has the same structural property — it is a rendered view stored alongside its source of truth. Out of scope for Spec 440 by design, but the storage-model decision made here is the **pattern template** for future rendered-view storage decisions. Re-use this inventory format for sibling artifacts.

## Maintenance

This document is **not generated**. When a command's read-side or write-side changes (e.g., when one of the 5 not-yet-rewired commands gets routed through `derived_state.py`), update the relevant table row by hand and add a note to the Revision Log section of Spec 440 if the change is structural.

## Revision Log

- 2026-05-15: Initial inventory written at Spec 440 /implement Step 0. Readership measurement confirms deletion is not viable.
