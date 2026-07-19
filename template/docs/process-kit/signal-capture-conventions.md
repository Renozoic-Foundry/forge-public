# Signal Capture Conventions — Session-Log ↔ Persistent-Log Propagation

Spec 452 closed a meta-process defect: EA/CI entries captured in session logs
but never propagated to the persistent logs made `/evolve` pattern analysis
structurally blind to the strongest signal cluster of any review window
(13 entries from session 2026-05-16-001 were invisible at loop 20). This doc
records the conventions that keep the signal surfaces in lock-step.

## The propagation invariant

**Every EA-NNN / CI-NNN entry in a session log MUST also exist in the matching
persistent log within the same close transaction.**

- `### EA-NNN` blocks (session log `## Error autopsies`) → `docs/sessions/error-log.md`
- `### CI-NNN` blocks (session log `## Chat insights`) → `docs/sessions/insights-log.md`
- Each propagated entry also gets a stub in `docs/sessions/signals.md`
  (`### SIG-NNN-EA-<ID> — <title> (propagated from session YYYY-MM-DD-NNN; detail: error-log.md)`)
  so `/evolve` pattern analysis — which reads signals.md as the canonical
  aggregation source — sees the entry even though the detail lives in the
  persistent log. Per Spec 472 the stub also **carries the source block's
  structured classification fields** (see [Enriched stub format](#enriched-stub-format-spec-472)).

The session log is the **source of truth**; propagation never rewrites it.
The persistent logs are **append-only targets**. Entry IDs are preserved
verbatim — never renumbered — including spec-scoped sub-ID forms
(`CI-429-A`, `EA-423-01`).

## Auto-propagation at /close (Step 5d)

`/close` Step 5d runs the propagation before the status transition:

```bash
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py scripts/migrate-spec-452-backfill-orphaned-signals.py \
  --apply --session-only=YYYY-MM-DD-NNN --spec=NNN
```

- Exit 0 → `GATE [signal-propagation]: PASS` — proceed.
- Exit 2 (malformed EA/CI block) or 1 (write error) → `GATE [signal-propagation]: FAIL`
  with the named stderr diagnostic, and /close **HALTs before the status
  transition** (Spec 452 Req 1f). A propagation failure must never be silent.
- Idempotent: dedup is by entry ID, so /close re-entry (e.g., /revise +
  re-close) appends nothing. Missing persistent logs are created with a header.
- Fresh-project tolerance: no session log, or no EA/CI sections → skip
  silently; nothing to propagate is not a failure.

## In-session capture at /session (Step 4)

`/session` Step 4 drafts EA/CI candidates and, on a **single operator
confirmation**, performs the tri-target append in the same cycle: session log
section + persistent log (with `- Session:` line) + signals.md stub. One
confirmation, three writes — no second prompt, no deferred propagation.
/close Step 5d then acts as the backstop for entries that reached the session
log through any other path.

## One-shot remediation: the migration script

`scripts/migrate-spec-452-backfill-orphaned-signals.py` (stdlib-only, Spec 401)
is both the propagation engine used by /close Step 5d and the one-shot
backfill tool for historical drift:

- `--dry-run` (default) — report `MIGRATE | SKIP-DUPLICATE | ERROR` per entry,
  mutate nothing.
- `--apply` — append missing entries.
- `--session-only=YYYY-MM-DD-NNN` — restrict to one session log.
- `--spec=NNN` — spec number keyed into the SIG stub IDs (default 452).
- `--sessions-dir=<dir>` — override for test fixtures.

Parser tolerances: pre-Spec-267 entries without classification fields are
copied verbatim (no field validation beyond "at least one `- field` line");
code fences and HTML comments are never parsed as entries; foreign `###`
headings inside EA/CI sections (e.g. an appended `### Spec NNN — closed`
record) are skipped. Malformed means an `### EA-`/`### CI-`-prefixed heading
that fails the `### EA-NNN: <title>` contract, or an entry block with no
field lines — those exit 2 with a `MALFORMED-BLOCK | <file> | <detail>`
diagnostic.

## Enriched stub format (Spec 472)

Spec 452 made EA/CI entries *visible* to `/evolve` by emitting signals.md
stubs, but the original stubs carried only a title and a breadcrumb pointer.
`/evolve` Step 8 clusters on structured fields the one-line stub lacked, so
propagated entries passed through pattern analysis as low-information noise.
Spec 472 closes that gap: the stub copies the source block's **Spec 267
classification fields** verbatim, so `/evolve` clusters on the stub directly
without re-reading the persistent log.

The fields copied onto the stub, in emission order, are:

- `Type` (the Spec 267 signal axis: `content | process | architecture | trust`)
- `Root-cause category`
- `Wrong assumption`
- `Evidence-gate coverage`

An enriched stub looks like:

```
### SIG-472-EA-901 — classified autopsy (propagated from session 2026-06-01-001; detail: error-log.md)
- Type: process
- Root-cause category: implementation-error
- Wrong assumption: the parser handled CRLF
- Evidence-gate coverage: missed-by-existing-gate — pre-commit lint
```

**Verbatim, no invention.** Each field is copied byte-for-byte from the source
EA/CI block (only the leading bullet is normalized). Non-classification body
fields (`Error`, `Insight`, `Root cause`, `Prevention`, …) stay in the
persistent log — the two-tier split is intentional (Spec 452 CTO assessment):
the stub carries just enough to cluster, the detail lives in `error-log.md` /
`insights-log.md`.

**Graceful degradation.** A pre-Spec-267 block that carries none of these
fields emits the historical one-line stub — byte-identical to the Spec 452
output. The propagation never fabricates a classification value for a block
that lacks one.

### Re-enrichment: `--enrich-stubs`

The 30 stubs backfilled at the Spec 452 close are the one-line form. The
migration script upgrades them in place:

```bash
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py scripts/migrate-spec-452-backfill-orphaned-signals.py --enrich-stubs --dry-run
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py scripts/migrate-spec-452-backfill-orphaned-signals.py --enrich-stubs --apply
```

- Re-reads every session log to recover each entry's structured fields, then
  rewrites signals.md so any one-line stub whose source block carries fields
  gains those field lines beneath its heading.
- `--dry-run` (default) reports `ENRICH | SKIP-ENRICHED | SKIP-NO-FIELDS` per
  stub and mutates nothing; `--apply` writes the upgrade.
- **Idempotent.** A stub that already carries the structured fields
  (`SKIP-ENRICHED`) or whose source block has none (`SKIP-NO-FIELDS`) is left
  byte-for-byte unchanged, so a second `--apply` run reports `0 stubs enriched`.
- **Read-only on the sources.** The session logs and the persistent logs are
  never modified by enrichment — only signals.md is rewritten.

## Drift detection (advisory)

`/now` Step 11c runs the script in `--dry-run` and surfaces a one-line
advisory when any orphaned entries exist. `/evolve` can use the same scan
during pattern analysis. Detection is advisory only — it never blocks and
never auto-applies; remediation is the operator running `--apply` or the next
/close Step 5d picking up today's entries.

### Recency cap (Spec 473)

`/now` is the highest-frequency command and the session-log count grows
monotonically, so its advisory Step 11c scan is bounded by a **30-day recency
window**: `/now` invokes the script with `--since=<today−30d>`, which skips any
session log whose filename date is strictly before the cutoff (filename-derived
date only — no file reads). This keeps the per-`/now` cost O(recent) instead of
O(project age).

The cap scopes **only** the `/now` advisory invocation. The escape hatch for a
full audit is the unscoped run, which remains the default everywhere else:

- Bare `--dry-run` / `--apply` (manual runs) scan **all** session logs.
- The one-shot Spec 452 backfill scans all logs.
- `/close` Step 5d uses `--session-only` (a single session) and is unaffected.

`--since` is composable with `--session-only`: `--session-only` is the narrowest
scope and wins; when both are passed, `--since` is ignored with a `NOTE |` line.
`--since` never changes dedup behavior — an `--apply --since=...` run still
dedups against the **full** persistent logs (only the session-log scan set is
filtered), so a capped run can never append a duplicate of an older entry.
