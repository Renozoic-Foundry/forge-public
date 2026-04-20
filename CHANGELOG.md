# FORGE Changelog

Releases of the FORGE (Framework for Organized Reliable Gated Engineering) template.

This changelog follows [Semantic Versioning](https://semver.org) bound to three explicit surfaces per the FORGE versioning contract:
- **Surface 1** — `copier.yml` variable names/types
- **Surface 2** — Slash-command public contract (`Usage:` line, argument parsing, choice-block options)
- **Surface 3** — `.forge/templates/project-schema.yaml` (reserved; introduced in future release)

---

## v2.0.0 — 2026-04-20

First post-v1.0.0 release. Four breaking changes across Surfaces 1 and 2 triggered a MAJOR bump per the FORGE versioning contract.

**Audit**: [ADR-295 v1.0.0→v2.0.0 audit](https://github.com/Renozoic-Foundry/forge/blob/main/docs/decisions/ADR-295-v1.0.0-to-v2.0.0-audit.md) (private-repo link; operators with forge/ access). Consensus: 3/3 approve (DA + CRO + CTO, all with surface-diff citations).

### Breaking changes (MAJOR drivers)

| Spec | Surface | Change | Migration |
|------|---------|--------|-----------|
| 205 | Surface 1 | `copier.yml` — `compliance_profile` variable removed | Lane B (safety-critical) compliance gates deferred from public release. All conditionals hardcode `"none"`. No consumer action required; existing `.copier-answers.yml` entries for `compliance_profile` are ignored. |
| 218 | Surface 2 | `/retro` command deleted | Use `/close` — signal capture is now embedded in the spec-close workflow (Step 6, "Signal Capture"). No standalone `/retro` invocation needed. |
| 263 | Surface 2 | `/bug` command deleted | Use `/note [bug] <description>` instead. The `[bug]` tag triggers severity classification + routing to an existing or new spec. |
| 266 | Surface 2 | `/onboarding` argument contract rewritten | Onboarding collapsed from 12 interactive stops to **2 interactions**. Defaults are accepted automatically; adjustments happen later via the new `/configure` command. Scripts relying on the old 12-step prompt sequence will break — adopt `/onboarding` followed by `/configure` as needed. |

### Additive changes (MINOR specs — non-breaking)

- **Spec 256** — `/close` Step 10: post-close context compaction hook (opt-in via `forge.context.optimization.level`)
- **Spec 258** — `/close` Review Brief: new `consensus` choice option (preserves existing `approve`/`reject`/`show`)
- **Spec 266** (companion) — new `/configure` command for post-onboarding stack selection
- **Spec 284** — `/configure` now displays pinned MCP package versions for visibility

### Notable PATCH changes (non-breaking)

- **Spec 290** — `copier.yml`: `author` and `harness_command` default values changed from placeholder strings (`"Your Name"`, `"# No harness configured..."`) to empty strings. Default-value change only; variable names and types unchanged.
- 20+ other PATCH-level specs (docs improvements, output polish, internal step additions). See [ADR-295](https://github.com/Renozoic-Foundry/forge/blob/main/docs/decisions/ADR-295-v1.0.0-to-v2.0.0-audit.md) for the full classification table.

### Updating from v1.0.0

**Option A — Fresh bootstrap** (recommended for new projects):
```bash
python -m copier copy gh:Renozoic-Foundry/forge-public . --vcs-ref v2.0.0 --defaults
```

**Option B — Update an existing v1.0.0 project** (once Spec 291's `/forge stoke` MAJOR-drift block ships):
```bash
# /forge stoke will block on a MAJOR drift by default; explicit --allow-major required
/forge stoke --allow-major
```

**Option C — Update before Spec 291 ships**:
```bash
# Manual Copier update; operator reviews the diff
python -m copier update
```

After updating, review the migration table above for any scripted workflows that depend on `/retro`, `/bug`, the 12-step `/onboarding`, or the `compliance_profile` Copier variable.

---

## v1.0.0 — 2026-04-11

Initial public release. See [commit `2e8de6a`](https://github.com/Renozoic-Foundry/forge-public/commit/2e8de6a).
