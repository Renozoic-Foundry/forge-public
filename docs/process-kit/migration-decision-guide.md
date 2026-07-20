# Migration Decision Guide — which /forge path does this project need?

Last verified: 2026-07-19 (Spec 579)

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
| 3 | **Stale plugin cache** (commands/help missing newer subcommands) | Payload version ≠ runtime version | `claude plugin marketplace update && claude plugin update forge` — ALWAYS first, before any other fix; stale caches mask capability |
| 4 | **Classic layout, wants segregation** | D-PATHS pre-migration WARN (config points at contained, files still classic) or operator intent | `/configure` → Layout (config-only), then `/forge retrofit` phase 3 (physical move, git-mv, history preserved) |
| 5 | **Split-brain** (files in BOTH layouts for one key) | D-PATHS SPLIT-BRAIN HIGH | `/forge retrofit` phase 3 — one location must end up owning the data |
| 6 | **Pre-v3 vendored tree** (framework files mixed into the repo) | Vendored `.forge/bin`, `.forge/lib`, command mirrors present with plugin installed | `/forge retrofit` (full four phases: inventory → de-vendor → reorganize → reconcile); dry-run first, always; mixed teams need the Spec 576 runtime installed before de-vendor |
| 7 | **Copier-scaffold consumer behind upstream** | `.copier-answers.yml` present, upstream tag newer | `/forge stoke` (Copier update path — legacy but supported until the Spec 558 cutover) |
| 8 | **Stale user-level `/forge-bootstrap`** | `~/.claude/commands/forge-bootstrap.md` present + plugin installed | Delete the user-level file — the plugin supersedes it (`install.sh --legacy-bootstrap` re-plants it if a pre-v3 Copier workflow genuinely needs it) |

States compose: a pre-v3 tree on a stale cache shows #3 first (update the plugin), then #6.

## What doctor will never do

Doctor is read-only end to end. It emits at most ONE recommendation choice block per run
(the single mapped fix + `details` + `not now`), never auto-runs a fix, and never chains
without your explicit choice. Destructive fixes (retrofit de-vendor) carry their own
confirmation gates inside their own commands.

## Non-Claude / no-AI teammates

The same repo states apply; the entry point is `bin/forge doctor` (CLI) instead of the slash
form, and fixes route through `bin/forge <sub>` or the documented runtime setup
(README § cross-IDE consumption; Spec 576 checkout-as-runtime).
