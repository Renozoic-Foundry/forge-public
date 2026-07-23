# Migration Decision Guide — which /forge path does this project need?

Last verified: 2026-07-20 (Spec 587)

One page, one decision tree. `/forge doctor` emits the short form of this map and links here;
`/forge help` links here. Nothing else restates the tree (single source). Every node ends in an
**operator decision** — FORGE diagnoses and offers; it never migrates, updates, or deletes
without an explicit choice.

## The grammar (read this once)

- **Work-loop verbs are top-level**: `/spec`, `/implement`, `/close`, `/now`, `/note`, … —
  the daily delivery loop.
- **Project-lifecycle operations go through `/forge <sub>`**: `init`, `stoke`, `doctor`,
  `retrofit`, `status`, `baselines` — anything about the project's relationship to FORGE itself.
- **`/forge:<name>` colon forms** are the harness's plugin-qualified spellings of the same
  invocables. They are valid, never advertised, and only needed when a name collides with
  another plugin or a project-local command.

## The decision tree

Start with **`/forge doctor`** — it detects which state you're in and offers the mapped fix.

| # | Your project's state | How doctor detects it | The fix (your decision) |
|---|---------------------|----------------------|------------------------|
| 1 | **No FORGE at all** (greenfield or brownfield) | No AGENTS.md runtime block, no `.forge/` | `/forge init` — scaffolds process data (contained layout by default; `--layout classic` opt-out); brownfield ends with the bounded `/reconcile` offer |
| 2 | **Plugin-current, healthy** | All checks green | Nothing — doctor reports findings only, no choice block |
| 3 | **Stale plugin cache** (commands/help missing newer subcommands) | Payload version ≠ runtime version | `/forge update` (Spec 587) — single verb wrapping the five-step journey below; or run it by hand: `claude plugin marketplace update && claude plugin update forge` — ALWAYS first, before any other fix; stale caches mask capability |
| 4 | **Classic layout, wants segregation** | D-PATHS pre-migration WARN (config points at contained, files still classic) or operator intent | `/configure` → Layout (config-only), then `/forge retrofit` phase 3 (physical move, git-mv, history preserved) |
| 5 | **Split-brain** (files in BOTH layouts for one key) | D-PATHS SPLIT-BRAIN HIGH | `/forge retrofit` phase 3 — one location must end up owning the data |
| 6 | **Pre-v3 vendored tree** (framework files mixed into the repo) | Vendored `.forge/bin`, `.forge/lib`, command mirrors present with plugin installed | `/forge retrofit` (full four phases: inventory → de-vendor → reorganize → reconcile); dry-run first, always; mixed teams need the Spec 576 runtime installed before de-vendor |
| 7 | **Copier-scaffold consumer behind upstream** | `.copier-answers.yml` present, upstream tag newer | `/forge stoke` — content-merge is now the DEFAULT apply path (Spec 591); `--classic` reaches the deprecated `copier update` path (removal targeted **v4.0.0** — see below) until the Spec 558 cutover deletes it |
| 8 | **Stale user-level `/forge-bootstrap`** | `~/.claude/commands/forge-bootstrap.md` present + plugin installed | Delete the user-level file — the plugin supersedes it (`install.sh --legacy-bootstrap` re-plants it if a pre-v3 Copier workflow genuinely needs it) |

States compose: a pre-v3 tree on a stale cache shows #3 first (update the plugin), then #6.

## The `/forge update` verb (Spec 587)

`/forge update` is the single source for the plugin-update journey (field report rec #2 — the
five-step chain was previously the most error-prone consumer path). It reports the skew probe
first, then this five-step chain (never mutates without an explicit yes/no):

1. `claude plugin marketplace update` — refresh the marketplace index
2. `claude plugin update forge` — pull the newer cached version
3. `/reload-plugins` — the harness must reload the plugin payload into the running session
   (cache-copy model: editing `template/` in place does nothing until re-cached)
4. Re-run `/forge doctor` — confirm the version-skew finding cleared
5. If skew persists: `claude plugin uninstall forge` then `claude plugin install
   forge@<marketplace>` — a full reinstall, since stale caches occasionally survive an
   `update` alone

## `/forge stoke` deprecation window: `--classic` → removal in v4.0.0 (Spec 591)

As of Spec 591, `/forge stoke`'s default apply backend is content-merge (Spec 559's
3-way `upgrade_merge.py` engine) instead of shelling out to `copier update`. The
classic Copier-update path remains reachable via `--classic` during the soak
window — it is **deprecated and scheduled for removal in v4.0.0** (Spec 558 deletes
`copier.yml` / `scripts/copier-hooks/**` / the Copier apply machinery once this
release has soaked for at least one release cycle).

- **Default (`/forge stoke`, no flag)**: content-merge. No warning printed.
- **`/forge stoke --classic`**: reaches the unchanged `copier update` pipeline.
  Prints exactly one line to **stderr** per run:
  > `DEPRECATION: --classic (the `copier update` stoke apply path) is scheduled for removal in v4.0.0. The default content-merge path is now the supported mechanism -- see docs/process-kit/migration-decision-guide.md.`
- **`/forge stoke --merge-native`**: accepted no-op alias — content-merge is already
  the default; the flag exists for consumers' explicit scripts/muscle memory.
- **Six consent-gated keys** (`test_command`, `lint_command`, `harness_command`,
  `include_nanoclaw`, `include_advanced_autonomy`, `include_two_stage_review`) now
  resolve through a live consent gate on every `/forge stoke apply` invocation
  (both backends), in addition to the render-time `secret: true` /
  `forge_consent_gate.py` backstop, which remains active until Spec 558.

**Action for consumers still on `--classic`**: no forced migration — the flag and
the render-time backstop both remain functional through the soak window. Migrate at
your own pace before the v4.0.0 cut; `/forge doctor` will flag `--classic` usage
once evidence supports it.

## Vendored-shadow self-rescue (Spec 587, field report rec #1)

If `/forge help` is missing `doctor`/`retrofit`, or `/forge doctor` behaves like an old
version, a project-local `.claude/commands/forge.md` from an old vendored tree is likely
shadowing the plugin's dispatcher. Two escape hatches, both plugin-qualified so the shadow
can't mask them: **`/forge:doctor`** (Spec 587 thin alias, dispatches straight to the plugin's
doctor flow) or **`/forge:forge doctor`** (full plugin-qualified form). Bare `/forge doctor` in
a shadowed project still hits the stale file — that's the shadow, not a bug in the alias.

## What doctor will never do

Doctor is read-only end to end. It emits at most ONE recommendation choice block per run
(the single mapped fix + `details` + `not now`), never auto-runs a fix, and never chains
without your explicit choice. Destructive fixes (retrofit de-vendor) carry their own
confirmation gates inside their own commands.

## Non-Claude / no-AI teammates

The same repo states apply; the entry point is `bin/forge doctor` (CLI) instead of the slash
form, and fixes route through `bin/forge <sub>` or the documented runtime setup
(README § cross-IDE consumption; Spec 576 checkout-as-runtime).
