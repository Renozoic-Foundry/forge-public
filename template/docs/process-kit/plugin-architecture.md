# FORGE Plugin Architecture (Spec 463 — slice 1)

> **Scope honesty.** This is **slice 1** of FORGE's Claude Code plugin evolution
> (ADR-449 NC-1b). It ships an **operator-only** plugin installable from a local
> checkout (`claude plugin install ./`) alongside the unchanged Copier distribution.
> It does **NOT** ship marketplace publication, signing infrastructure, provenance
> attestation, or any runtime telemetry. Those are deferred to follow-up specs.

Last verified: 2026-06-19

---

## Manifest schema

The plugin manifest lives at `.claude-plugin/plugin.json` (the path Claude Code
requires). Slice 1 declares **only** these fields — declarative metadata and payload
component paths, nothing more:

| Field | Required | Slice-1 value | Notes |
|-------|----------|---------------|-------|
| `name` | yes | `forge` | kebab-case identifier; drives the `/forge:<name>` command namespace |
| `version` | yes | `0.1.0` | semantic version |
| `description` | yes | (50–200 chars) | brief explanation |
| `author` | yes | `{ "name": "Renozoic Foundry" }` | object with `name` (email/url optional) |
| `homepage` | optional | repo URL | documentation pointer |
| `license` | optional | `MIT` | SPDX identifier |
| `keywords` | optional | discovery tags | array |
| `commands` | optional | `["./.claude/commands"]` | path(s) to command definitions (directory accepted) |
| `agents` | optional | `["./.claude/agents/<name>.md", …]` | **enumerated file** paths — the schema rejects a bare directory for `agents` (Spec 490 / SIG-487-03) |
| `skills` | optional | `["./.claude/skills"]` | path(s) to skill directories (`<name>/SKILL.md`); shipped + signed (Spec 490) |
| `hooks` | optional | `"./.claude-plugin/hooks/hooks.json"` | path to hook config JSON |

**Explicitly absent in slice 1** (negative scope — see AC10): NO `marketplace`
metadata, NO signing fields (`signature`, `sigstore`, `cosign`), NO `provenance`
attestation, NO runtime telemetry/beacon configuration. These are reserved for the
signing + publication follow-up spec.

Validate the manifest with `jq -e . .claude-plugin/plugin.json`.

---

## Payload mapping

The plugin payload reuses the **existing `.claude/` tree** rather than introducing a
third copy of the behavioral content. The manifest's component paths point at
`.claude/`; the `.claude-plugin/` directory holds only the manifest and the new hook.

### Payload-mapping table

| Component | Plugin manifest path | On-disk source | Copier mirror (parity target) |
|-----------|----------------------|----------------|-------------------------------|
| Commands | `./.claude/commands` | `.claude/commands/*.md` | `template/.claude/commands/` |
| Agents | enumerated `./.claude/agents/<name>.md` | `.claude/agents/*.md` | `template/.claude/agents/` |
| Skills | `./.claude/skills` (explicit `skills` field, Spec 490) | `.claude/skills/<name>/SKILL.md` | `template/.claude/skills/` |
| Hooks | `./.claude-plugin/hooks/hooks.json` | `.claude-plugin/hooks/` | (plugin-only; no Copier mirror) |
| Manifest | `.claude-plugin/plugin.json` | `.claude-plugin/plugin.json` | (plugin-only; no Copier mirror) |

### Documented divergences and their parity rule

- **Commands/agents/skills** are shared between the two distribution surfaces and
  **MUST be byte-identical** across `template/.claude/` (Copier source) and `.claude/`
  (plugin payload source). This is the **common subset** the parity gate enforces.
- **The manifest and the hook** are plugin-only — they have no Copier mirror and are
  therefore **out of the parity common subset** by design (a consumer rendered via
  Copier does not receive the plugin manifest; it gets the unnamespaced commands).
- **Skills** are declared via the manifest `skills` field (`["./.claude/skills"]`,
  Spec 490) — FORGE skills live under `.claude/skills/` (`<name>/SKILL.md`), are covered
  by the parity gate, and are now included in the **signed** payload manifest
  (`FORGE_PAYLOAD_DIRS` in `.forge/lib/payload-manifest.{sh,ps1}`). Before Spec 490 the
  manifest had no `skills` field, so skills shipped via Copier but NOT via the plugin
  (SIG-487-04).

---

## CI parity gate

Slice 1 uses **P1=C: explicit two-source + CI parity check**. The two sources are
`template/.claude/` (Copier) and `.claude/` (plugin payload). The gate fails on
byte-level drift across the common subset (`commands/`, `agents/`, `skills/`).

- Script: `.forge/bin/plugin-parity-check.sh` (+ `.ps1` mirror). Exit 0 = parity;
  exit 1 = drift, naming each drifted file.
- CI: `.github/workflows/plugin-parity.yml` runs `jq` manifest validity, the parity
  check, and the behavioral fixture on every push/PR to `main`.
- `/close` gate: the close workflow runs the parity check as a mechanical gate before
  a spec can be closed (see `/close` Step 2b6).

**Forward compatibility.** When the single-source generator (NC-1a / Spec 480) lands,
this gate becomes the generator's drift detector — the two-source check is the
contract the generator must satisfy. No rework of the gate is required.

**Constraint (AC3 / Constraints):** any change to a manifest file, plugin payload, or
this process-kit doc updates BOTH the root and the `template/` mirror in the same
change.

---

## Skills are generated, not hand-maintained (Spec 491)

Before Spec 491, `.claude/skills/<name>/SKILL.md` files were **hand-maintained** copies
of the corresponding command — so they silently diverged from the canonical
`.forge/commands/` source (consensus, evolve, and interview had each drifted by 50–75
body lines). Spec 491 makes the skill surface a **generated artifact**, closing the
divergence class permanently:

- **Generator:** `.forge/bin/forge-sync-skills.sh` writes every `.claude/skills/<name>/SKILL.md`
  from the canonical `.forge/commands/<name>.md` body plus a derived three-line frontmatter
  (`name`, `description` read from the canonical YAML, `disable-model-invocation` stamped per
  policy). `--template-side` regenerates `template/.claude/skills/` from `template/.forge/commands/`.
- **Single source of truth for the surface split:** `.forge/commands/invocation-policy.yaml`
  lists three disjoint sets — `commands` (16, command-form only), `skills_model_invokable` (9,
  `disable-model-invocation: false`), and `skills_explicit` (7, `disable-model-invocation: true`).
  No name appears twice (commands and skills never overlap).
- **Parity / policy gates:** `forge-parity.sh --check` adds **Surface 5**, which runs
  `forge-sync-skills.sh --check` (regenerate-to-temp drift gate, fails on any hand-edit) **and**
  `forge-sync-skills.sh --verify-policy` (the AC9 classification gate). `forge-sync-commands.sh`
  skips the skill-form names for the Claude-Code surface so no stale `.claude/commands/<skill>.md`
  mirror is emitted. `.github/workflows/plugin-parity.yml` runs the same `--check`, `--verify-policy`,
  and the `test-spec-491-policy.sh` fixture on every push/PR.
- **Intentional FORGE-self-vs-consumer divergence carries through to skills.** A canonical
  command listed in `.forge/state/expected-cross-level-drift.txt` (e.g. `interview`, `now`)
  generates an intentionally divergent root vs. template `SKILL.md`; `plugin-parity-check.sh`
  excludes those skill paths from the byte-identity common subset via the same escape-hatch it
  uses for commands.

### Level-invariant model-invocation policy (Spec 491 R6)

`disable-model-invocation` controls whether Claude may **opportunistically auto-fire** an
invocable. Its value is decided **once, by the invocable's safety profile, and does NOT change
across autonomy levels (L0–L4)**:

- **`false` (model-invokable), 9 skills** — `now`, `note`, `brainstorm`, `dependency-audit`,
  `explore`, `insights`, `trace`, `test`, `signal-to-strategy`. Read-only / additive / reversible:
  safe to auto-trigger at any level.
- **`true` (explicit), 7 skills** — `consensus`, `decision`, `evolve`, `interview`, `matrix`,
  `revise`, `synthesize`. Un-namespaced ergonomics but never opportunistically auto-fired.
- **command-form, 16** — `close`, `implement`, `spec`, `forge`, `forge-init`, `forge-stoke`,
  `parallel`, `reconcile`, `config-change`, `configure`, `configure-nanoclaw`, `nanoclaw`,
  `onboarding`, `scheduler`, `tab`, `session`. Authorization-gated / lifecycle-mutating /
  cost-spawning — never model-invokable.

**Model-invocation vs. auto-progression — the distinction that matters at L4.** Autonomous
workflow advancement does NOT happen through opportunistic skill invocation; it happens through
FORGE's **`auto_progression` chains** (deterministic, evidence-gated, audited — see AGENTS.md).
L4 does not flip any `disable-model-invocation` flag — it raises the `auto_progression` ceiling so
chains run unattended. Conflating the two is exactly what produced the unauthorized `/close`
incidents (EA-025/026/027); the Priority-1 authorization gates (push, scope, close-invocation)
apply at **every** level, including L4. This is why no lifecycle-mutating, authorization-gated,
cost-spawning, or irreversible invocable is ever model-invokable.

---

## Operator decision matrix (Copier vs plugin vs both)

| Situation | Use | Command surface | Notes |
|-----------|-----|-----------------|-------|
| Air-gapped / offline / regulated | **Copier** | unnamespaced `/spec`, `/close`, … | Plugin install needs no network either, but Copier is the proven path |
| Bootstrapping a brand-new project | **Copier** (`copier copy`) | unnamespaced | Renders the full FORGE tree into the project |
| Existing FORGE consumer wanting plugin invocation | **Plugin** (`claude plugin install ./`) | namespaced `/forge:<name>` | Additive; does not touch the Copier-rendered tree |
| Both installed | **Both coexist** | bare name → Copier; `/forge:<name>` → plugin | See conflict resolution below |

### Conflict resolution — which command wins

When BOTH the Copier-rendered template AND the plugin are present and the operator
types the **bare** name (`/spec`), the **Copier-rendered command wins by default**.
The plugin-installed command is reached explicitly via the namespace: `/forge:spec`.
This is the P4=B dual-availability behavior. Some operator confusion is the accepted
cost of the transition window; the matrix above is documentation, not enforcement.

### Namespacing sunset anchor

The dual-availability window is **not indefinite** (P4=C permanent-dual was rejected):
**dual-availability holds through FORGE v2.0.0 OR 9 months from /close 463, whichever is later**.
The successor spec ID for retiring the unnamespaced surface is recorded in this spec's
Compatibility Notes at `/close 463`.

---

## Plugin-install-failure runbook

If `claude plugin install ./` fails, the **Copier fallback path remains operational by
construction** — no FORGE workflow depends on the plugin in slice 1.

| Failure | Symptom | Operator action |
|---------|---------|-----------------|
| Network unavailable | install hangs / DNS error | Plugin installs from local checkout and needs no network; if it still fails, use the Copier path (`copier copy` / `copier update`) — unchanged and fully functional |
| Schema mismatch | manifest rejected by installed Claude Code version | Confirm Claude Code `>= 2.1.133`; if older, upgrade Claude Code or stay on the Copier path; re-pin the spec via `/revise` if the manifest schema changed upstream |
| Payload corruption / tamper | SessionStart integrity hook FAILS CLOSED in installed mode | The signed manifest no longer matches the payload (Spec 488). Reinstall the plugin from a clean signed release; in source/dev mode (`CLAUDE_PLUGIN_ROOT` unset) verification is skipped so local edits never block you |
| Plugin not discovered | `/forge:<name>` commands absent | Verify `.claude-plugin/plugin.json` is valid (`jq -e .`); confirm the install completed; fall back to Copier-rendered unnamespaced commands |

**Signing — LANDED (Spec 488):** key-based detached signing (minisign), a fail-closed
verifying integrity hook, key-rotation, and provenance attestation now ship — see
"SessionStart integrity verification" below and the key-management runbook
([plugin-key-management.md](plugin-key-management.md)). **Still deferred:** marketplace
publication (Spec 489 phase-D's out-of-scope item).

---

## SessionStart integrity verification — signed, fail-closed (Spec 488)

The `SessionStart` hook (`.claude-plugin/hooks/session-start-integrity.sh`) verifies a
**minisign detached signature** over a deterministic payload manifest. This is no longer
decorative: it withstands an attacker who controls the payload, because the trust root is
anchored **outside** the payload.

**How it works.** A release step (`.forge/bin/forge-sign-payload.{sh,ps1}`) builds a
deterministic manifest — `LC_ALL=C`-sorted `sha256␠␠relpath` over every payload file, each
file LF-normalized before hashing so a Windows CRLF checkout verifies identically — and
signs it with minisign, embedding a **signed trusted comment** `tier=<t> version=<v>`. The
manifest + `.minisig` ship inside the payload. At SessionStart the hook recomputes the
manifest from disk, verifies the shipped manifest's signature against the
**externally-anchored** public key, and diffs recomputed-vs-signed. Both halves are
load-bearing: the signature proves the manifest is authentic; the diff proves the files
match it. The manifest algorithm is a single shared library
(`.forge/lib/payload-manifest.{sh,ps1}`, byte-identical across bash and PowerShell) so the
sign and verify sides can never drift.

**Root of trust is external (the crux, R5).** The verification pubkey, version floor, and
expected tier are read from an external anchor — `managed-settings.json` (managed orgs,
ADR-453 trust root) or a pinned anchor (`FORGE_PLUGIN_ANCHOR`) — and **never from the
payload**. A swapped payload carrying a swapped embedded key still fails; an anchor that
resolves inside the payload is refused. Per-tier keys (forge-private dev / forge-public
Renozoic / a-consumer-project Customer InfoSec) are signed at each tier's release; signatures do not
propagate down the pipeline.

**Posture.**
- **Installed mode** (`CLAUDE_PLUGIN_ROOT` set): verify, **FAIL CLOSED** on
  tamper/mismatch/missing-signature.
- **Source/dev mode** (`CLAUDE_PLUGIN_ROOT` unset): **skip** verification (warn-only) so a
  developer editing the payload is never bricked (reuses Spec 487 `resolve-root`).
- **Offline / no-anchor**: anchor unreachable/absent → **fail closed, no grace window** (a
  grace is an attacker-exploitable race).
- **Verifier-missing vs failed**: a signature MISMATCH fails closed; a missing `minisign`
  BINARY degrades loud with a machine-parseable `SIGNAL=minisign-missing severity=degraded`
  line (not a brick) — permitted only because `install.sh` hard-enforces minisign at install.
- **Downgrade/tier protection**: the version floor and expected tier come from the external
  anchor (never the payload); an older `version=` or wrong `tier=` is rejected.

The InfoSec-ratified toolchain (minisign, ratified 2026-06-17) is recorded in Spec 488. The
weakest anchor tier — forge-public's TLS-TOFU pin, hardened by an out-of-band pubkey
checksum at install — remains a tracked watchlist item (TOFU → pinned-distribution upgrade).

---

## AP4 doctrinal tension note

Architectural Principle 4 currently reads 'Template is the product'; this slice ships plugin as additive infrastructure without claiming canonicality.

The doctrinal canonicality decision (whether the plugin or the Copier template becomes
the canonical distribution surface) is **deferred to a future doctrinal spec**. Slice 1
ships both surfaces as functionally equivalent rendered artifacts of the same payload.
CLAUDE.md / AGENTS.md AP#4 copy is intentionally **not** modified by this spec.

---

## Phase D — render-shrink + plugin-sole-enforcement (Spec 489)

Phase D completes the plugin-primary migration: once the payload is **signed + fail-closed
verified** (Spec 488), the Copier render stops shipping the framework and the **signed plugin
becomes the sole enforcement path**. This is a **BREAKING consumer-contract change**.

**What changes:**
- **Framework-free render.** `copier.yml` `_exclude` drops `.claude/commands`, `.claude/agents`,
  and `.forge/{bin,lib,templates,modules,adapters}` from the render. Consumers get the framework
  (commands, agents, runtime, hooks) from the **installed plugin**. (`_exclude` applies to BOTH
  `copier copy` AND `copier update` — see the deprecation note below.)
- **Doctrine is RETAINED.** `AGENTS.md`/`CLAUDE.md` keep their full operating doctrine — plugins
  **cannot** inject ambient `CLAUDE.md`/`AGENTS.md` context (verified against the Claude Code
  plugin reference; SIG-489-01). Only framework *files* leave the render, never the doctrine.
- **Rendered hooks removed.** The six functional gate-hooks are no longer in the rendered
  `settings.json`; the signed plugin `hooks.json` registers them. The ONE residual rendered hook
  is the **detective audit** (`.forge/check-neither-path.sh`).
- **Detective audit (the compensating control).** A SessionStart hook that **fails loud** when a
  consumer reaches a "neither path enforcing" state — neither rendered gate-hooks NOR a verified
  plugin. It lives at `.forge/` root (not under the excluded subdirs) so it survives the shrink.

**Consumer bootstrap (deprecation window):** `claude plugin install ./` from a forge-public
checkout + `copier copy` for project scaffolding. (Marketplace publication remains deferred.)

**⚠ `copier update` no longer delivers framework updates.** After the phase-D tag, `copier update`
will NOT deliver `.forge/{bin,lib}`, `.claude/commands`, or `.claude/agents` updates — **install the
signed plugin to receive framework updates.**

**Migration procedure (existing rendered consumers):** `claude plugin install ./` → confirm the
488 integrity hook returns PASS (verified plugin) → snapshot via `.forge/lib/migration-snapshot.sh
snapshot` → remove the rendered hooks. The verify-before-trust ordering is *enforced* by 488's
fail-closed gate; rollback (`migration-snapshot.sh restore`) restores the rendered hooks + full
doctrine verbatim from the snapshot (never re-renders).

**Deprecation window (concrete):** both paths coexist from the **phase-D release tag**; rendered-hook
removal is enforced **no earlier than tag + 90 days**. Exact calendar dates are pinned at the release
tag and surfaced to consumers in the release notes.

---

## Copier fallback (pre-phase-D: unchanged; phase-D: framework-free — see above)

**Through Spec 487 (pre-phase-D)**, the Copier distribution is functionally identical to pre-spec
behavior: both `copier copy` and `copier update` deliver framework + updates without a plugin install,
and air-gapped/offline environments use Copier exclusively. **Phase D (Spec 489) changes this** — the
render becomes framework-free and consumers install the plugin (see the Phase D section above). The
doctrine (`AGENTS.md`/`CLAUDE.md`) is rendered in both eras.

---

## Runtime-complete payload + dual-mode resolution (Spec 487)

Slice 1 (Spec 463) shipped only the command/agent **text** plus a decorative
SessionStart integrity hook. The **functional enforcement hooks** were registered only
in the Copier-rendered project `.claude/settings.json`, so a plugin-only install could
not enforce FORGE's gates. Spec 487 (phases B+C) makes the plugin **runtime-complete**.

### What changed

- **Hook registration (the enabler).** `.claude-plugin/hooks/hooks.json` now registers
  all six functional hooks via `${CLAUDE_PLUGIN_ROOT}/.forge/bin/check-*.sh`:
  `check-role-permissions`, `check-edit-gate`, `check-authority-guard` (PreToolUse
  Write/Edit), `check-commit-guard` + `check-authority-guard` (PreToolUse Bash),
  `check-session-start` (SessionStart, alongside the integrity check), `check-stop`
  (Stop). A plugin-only install now enforces the same gates a Copier render does.
- **Runtime presence.** The `.forge/` runtime (`bin`, `lib`, `templates`, …) is present
  in the plugin payload by virtue of the local-checkout install (`claude plugin install
  ./` — the checkout *is* the plugin root). No manifest "runtime dirs" key is required.

### Dual-mode resolution contract (`.forge/lib/resolve-root.{sh,ps1}`)

| Variable | Resolves to | Holds |
|----------|-------------|-------|
| `FORGE_PROJECT_ROOT` | Always the consumer working-tree (git repo root) | Project artifacts + `.forge/state/*` — read/written here in **both** modes |
| `FORGE_ASSET_ROOT` | Plugin root when `CLAUDE_PLUGIN_ROOT` points at a dir with `.claude-plugin/plugin.json`; else repo-root (rendered) | Framework assets |

The helper **fails closed** (non-zero + clear error) if neither root resolves, and
degrades to repo-root on a set-but-invalid `CLAUDE_PLUGIN_ROOT` — never a silent-allow
path. **No `.forge/state/*` access ever resolves under `FORGE_ASSET_ROOT`.**

### Why only two hooks were retrofitted

Four of the six hooks — `check-edit-gate`, `check-commit-guard`,
`check-role-permissions`, `check-authority-guard` — are the **authority-guard protected
set** (ADR-046/453 trust root). The agent is forbidden from editing them, and they
already resolve project state via `git`/CWD, so they are **mode-agnostic from the plugin
payload unchanged**. Only the two non-protected advisory hooks (`check-session-start`,
`check-stop`) were retrofitted to source the helper and use `FORGE_PROJECT_ROOT`
explicitly. Modifying the protected set is operator-mediated only.

### Dual-registration safety

On a project that is **both** plugin-installed and Copier-rendered, each gate may be
registered twice. This is safe: PreToolUse gates are pure read→decide and re-entrant
(the same input yields the same block/allow decision with no state mutation — the hooks
never *write* `.forge/state`), and the advisory hooks tolerate double-emission.

### Deferred

- **Phase D** (shrink the Copier render to project scaffolding only, removing the
  rendered hooks) is a separate spec and is **hard-gated on plugin payload signing**
  (Spec 463 deferred scope) — the rendered hooks remain the trusted enforcement path
  until then.
- Bringing all of `.forge/{bin,lib}` under `forge-parity.sh` (so template mirrors
  can't silently drift) is **Spec 480's single-source-generator domain**; Spec 487 uses
  a targeted byte-identity check for the resolution helper in the interim.
