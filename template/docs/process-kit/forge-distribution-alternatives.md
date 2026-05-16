# FORGE Distribution Alternatives Survey

**Status**: preparatory institutional-memory artifact. **No architectural recommendation.** Produced by Spec 420 v0.2.

This document surveys the option space for how FORGE could be distributed to and updated in consumer projects. It is the companion to `copier-friction-inventory.md`, which captures empirical defect classes that motivated questioning the current approach. Both documents are read together to inform any future architectural-decision spec.

**No option is presented as "primary direction."** All entries follow a symmetric structure (Description / Tradeoffs / Risks / Examples) so readers can weigh them without authorial framing bias. Per Spec 420 v0.2 Constraints + DA W2/W3 dispositions: implementer wrote each entry to comparable depth and detail.

---

## Alternatives

### F-1: Stay on Copier — accept the patches

**Description**: Continue using Copier as FORGE's distribution + update tool. When new defect classes surface (per the friction inventory), add new FORGE-internal compensating infrastructure (per the workaround spec catalogue). The Copier-on-FORGE complexity continues to accrete; the cost is paid one spec at a time.

**Tradeoffs**: Lowest immediate cost (no migration). Preserves consumer compatibility (every existing FORGE-on-Copier consumer continues to work unchanged). Inherits Copier's upstream fixes when they ship. Each new defect class costs ~one FORGE spec to work around. The cost is spread thin enough that no single decision point forces a re-architecture conversation.

**Risks**: Compounding workaround complexity. Each defect rediscovery costs operator attention even if the workaround pattern is now documented (the friction inventory mitigates this somewhat). The accumulated workaround-spec catalogue (10+ specs and counting) becomes its own maintenance burden. Over time, the FORGE-on-Copier ratio may make Copier feel more like a shared dependency than the tool actually doing the work.

**Examples**: status-quo as of 2026-05-12. Spec 090's path-of-least-resistance under F-1 would be SR-2 (drop AC 1, ship 8 of 10 ACs, accept the v3.X friction documented in the inventory).

---

### F-2: Hybrid — Copier bootstrap, FORGE-native `forge stoke v2` for updates

**Description**: Keep `copier copy` for greenfield project bootstrap (it works fine for that). Replace `copier update` with FORGE-native `forge stoke v2`: reads `.forge/version.json` for current FORGE version; reads consumer's `.forge/sync-manifest.yaml` for per-file policy; diffs upstream FORGE files against last-applied version; surfaces 3-way merge UI; operator approves per-file; writes new `.forge/version.json` on success. Provenance becomes trivial — JSON sidecar, no Copier answer-file fight.

**Tradeoffs**: Keeps the parts of Copier that work. Replaces the parts that hit defect classes #1-#4 from the inventory. FORGE gets full control over update semantics. Spec 090-class friction becomes trivial under this model (provenance via `.forge/version.json`, no `_baseline_*` underscore-stripping or `when:` filtering battles). Reverse cost: writing `forge stoke v2` is a real implementation effort (probably 5-10 follow-up specs). Consumers need a one-time migration from `copier update` to `forge stoke v2`. Ongoing dual-tool maintenance.

**Risks**: New code carries new attack surface — FORGE-internal review only, vs Copier's broader upstream review. The `--trust` security gate (defect class #5) becomes FORGE's responsibility to preserve in equivalent form. `.forge/version.json` is a new attack surface (tamper detection? signing?). 3-way merge logic is notoriously hard to get right; bugs can silently merge attacker-controlled content. Day-2 maintenance ownership is unclear if FORGE community grows.

**Examples**: pattern resembles tools like `dotbot` (config-driven file management with manifests) but customized for FORGE's framework-vs-project-file distinction. No exact industry analog.

---

### F-3: Full Copier replacement — drop Copier entirely

**Description**: Custom `forge init` (Jinja2 directly on ~10 template files needing project-name substitution) + custom `forge stoke` (manifest-driven sync) + `.forge/version.json` for provenance. Bootstrap and update both become FORGE-native. No Copier dependency.

**Tradeoffs**: Simplest mental model (one tool, one set of behaviors). No fighting Copier internals. "Minimal by default" honored at the architectural level. Carries the largest implementation cost (everything Copier did, FORGE now does). Consumers need significant changes for migration. Reinvents `copier copy` greenfield-render which is genuinely good at what it does.

**Risks**: Reinventing well-trod ground in Copier's bootstrap path. Loss of Copier upstream fixes/improvements. Largest engineering investment of any option. Without strong reason to leave Copier's bootstrap behavior, F-3 swaps known cost (Copier friction) for unknown cost (FORGE-native bootstrap maintenance).

**Examples**: tools like `dotnet new` and `rails generators` are bootstrap+update fully-custom in their respective ecosystems. They work because the parent platform funds the maintenance. FORGE doesn't have that scale.

---

### F-4: Stay on Copier; add FORGE Copier Discipline guide

**Description**: Same surface as F-1 (no architectural change), but invest in documentation + spec-template constraints to prevent future specs from rediscovering known-bad patterns. The friction inventory becomes prescriptive: "don't use `_*` answer keys for persistence-required values; don't use `when: false` for metadata; don't put validators on questions whose values you need persisted; don't rely on `_migrations:` to mutate validator state." Could be enforced via `/spec` template lint or `/implement` Step 4-class active detection.

**Tradeoffs**: Zero migration cost. Zero new tools. Encodes institutional learning into mechanical guardrails so it doesn't depend on operator memory. Doesn't address the accumulated complexity (workaround specs persist). Doesn't help with Copier defects we haven't hit yet.

**Risks**: Discipline guides drift unless mechanically enforced. Without lint enforcement, the guide is only as effective as operator memory — same failure mode that produced the friction in the first place. New FORGE contributors need to read the inventory + guide; onboarding cost.

**Examples**: similar to project-internal Python style guides ("don't use mutable default arguments") that ship as both prose AND lint rules (via tools like ruff or pylint). Effective only when lint enforcement matches the prose.

---

### F-5: Copier-discipline guide + upstream PRs (Maverick proposal)

**Description**: F-4 plus active engagement with Copier upstream. Treat the 7 defect classes as a usage-pattern audit: for the 2-3 that are genuine Copier bugs (rather than FORGE misuse), file upstream PRs/issues with reproductions. For the rest, document FORGE patterns to avoid them. Defer architectural replacement until a defect class emerges that documentation + upstream fixes provably cannot address.

**Tradeoffs**: Combines F-4's mechanical guardrails with potential upstream improvement. Some friction may be addressable at the source. Lowest-risk incremental path. Defers the harder architectural question. Depends on Copier upstream's willingness to accept PRs / fix the issues.

**Risks**: Upstream PRs take time and may be rejected. No immediate relief for current friction. If upstream is unresponsive, F-5 collapses back to F-4 with extra effort spent. Doesn't address the meta-question of whether FORGE has outgrown Copier conceptually.

**Examples**: most mature open-source projects mature by upstreaming improvements rather than forking. Examples include teams that contribute back to dependencies they heavily use (e.g., feature contributions to popular libraries). Whether Copier's maintainership accepts the kind of changes FORGE would propose is unknown without trying.

---

### F-6: Buy/reuse — adopt an existing file-sync tool

**Description**: Rather than building `forge stoke v2` (F-2/F-3), adopt an existing tool that handles incremental file-sync better than Copier's update path. Candidates: `chezmoi` (dotfile manager with templating + diff/apply), `dotbot` (manifest-driven config management), `stow` (symlink-based), `dvc` (data version control with sync semantics).

**Tradeoffs**: Leverages mature outside-of-FORGE engineering. Avoids reinventing. Bootstrap could still use Copier or move to the chosen tool. Each tool has its own learning curve, idioms, and limitations FORGE would discover. Migration cost depends on chosen tool. May expose FORGE consumers to multiple-tool fatigue.

**Risks**: Risk of trading known Copier friction for unknown new-tool friction. Each candidate tool has its own framing assumptions (chezmoi assumes per-user dotfiles; dotbot assumes static config; stow assumes symlinks acceptable; dvc assumes data-pipeline workflows). None is a perfect match for "framework distributed to many consumer projects." Adoption requires evaluation/spike work to assess fit.

**Examples**: `chezmoi` is widely used for dotfile management; some teams use it for project-template-like workflows. `dotbot` is common in dotfile communities. `stow` is the GNU-blessed symlink farm manager. `dvc` is data-science-focused. None has a 1:1 match to FORGE's job-to-be-done; all could be adapted.

---

### F-7: PR-based update model (Independent advisor proposal)

**Description**: Inspired by Renovate / Dependabot / RenovateBot. FORGE doesn't directly mutate consumer projects — instead, when a FORGE update is available, it generates a pull request against the consumer's git repo with the proposed changes. Operator reviews diffs in their normal PR-review tooling and merges (or doesn't). No `copier update` invocation; no merge-conflict UI to write; no `--trust` semantics; no `_tasks` failure cascades.

**Tradeoffs**: Leverages every operator's existing PR-review tooling and habits. Updates are observable as standard git diffs. No FORGE-controlled code execution on consumer machines (security win). No 3-way merge logic to get right. Requires FORGE-internal automation infrastructure to generate and submit PRs. Requires consumers to be in a git repo with PR support (effectively GitHub/GitLab/Bitbucket).

**Risks**: PR generation infrastructure is non-trivial (needs to know which files to update, how to handle consumer customizations, when to skip). Doesn't help consumers in air-gapped or non-web-Git environments. PR-fatigue: consumers may accumulate stale FORGE-update PRs they never review. Cross-platform PR generation needs careful handling of credentials/tokens.

**Examples**: Renovate (npm/python/ruby ecosystem deps), Dependabot (GitHub-native dep updates), the broader category of "automated PR generators." None is a 1:1 match for framework-distribution but the pattern is well-established and operator-familiar.

---

### F-8: Drop the update aspiration (Independent advisor proposal)

**Description**: Cookiecutter, Yeoman, dotnet new, rails generators are bootstrap-only by design — they create a new project from a template and that's it. Updates happen via deliberate operator action (running specific migration scripts when needed), not via a generic update tool. Make FORGE follow the same pattern: `forge init` for bootstrap; for updates, ship per-spec migration scripts that operators run intentionally when they want to adopt a specific spec's changes. Replace `/forge stoke` with `/forge migrate <spec-NNN>` invocations.

**Tradeoffs**: Smallest implementation cost (just remove `/forge stoke` and the update infrastructure that compensates for Copier's update friction). Aligns with widely-adopted industry pattern (most template tools are bootstrap-only). Eliminates the entire class of update-mechanism defects. Per-spec migration scripts make changes deliberate and observable. Loses the convenience of "pull all framework improvements with one command." Operators carry the burden of knowing which specs they want to adopt; some specs they may never adopt.

**Risks**: FORGE adoption cost increases (operators must read each spec's migration script and decide). Discoverability problem (how do operators know what's available?). Could fragment the FORGE-using ecosystem (different consumers on different effective FORGE versions). May surface as feature-request to add an update tool back, partially undoing the simplification.

**Examples**: cookiecutter, Yeoman, dotnet new, rails generators (`rails new`), create-react-app, npx create-* (npm ecosystem), `cargo new`, `mix new` (Elixir). The vast majority of template/scaffolding tools are bootstrap-only. The "framework with continuous updates" model is the unusual one.

---

#### Security context for any future architectural-decision spec

Per `/consensus 420` round-1 CISO finding: any future architectural-decision spec following from this survey MUST address the following security requirements before authorizing implementation. Captured here so the requirement does not get lost:

- **Trust-on-execute gate equivalent to Copier `--trust`**: any FORGE-native update tool that runs scripts or `_tasks`-equivalent operations must require operator opt-in equivalent to Copier's `--trust` flag. The default must not silently execute template-controlled code.

- **Integrity / authenticity of per-consumer state file**: if `.forge/version.json` (or equivalent provenance file) drives update decisions, it must be tamper-resistant. An attacker who can write to the file should not be able to downgrade FORGE to a vulnerable version OR cause the update tool to skip security-relevant updates. Mitigation options: signing, content-addressed storage, append-only audit log.

- **Trust model + signing for any one-time migration tool**: if FORGE ships a migration script to transition consumers from `copier update` to `forge stoke v2` (or any other replacement), that script runs FORGE-controlled code on consumer machines. The trust model for the migration script must be explicit — what does it do; what are the constraints; how can the operator verify it before running.

- **Formal security review binding on follow-up implementation spec**: any custom-update-tool implementation must include a CISO + DA + independent reviewer pass on the actual code, including audited 3-way merge logic. 3-way merge bugs can silently promote attacker-controlled content into trusted files. The implementation spec must require the audit, not just recommend it.

These requirements apply regardless of which option (F-2, F-3, F-6, F-7) is chosen IF it involves new FORGE-controlled code paths on consumer machines. Options F-1, F-4, F-5, F-8 inherit Copier's existing security posture and don't introduce these requirements (though F-8 still needs to ensure per-spec migration scripts follow the same trust-on-execute model).

---

## Read this survey before

- Drafting any future architectural-decision spec following from the friction inventory.
- Discussing FORGE's distribution architecture in any forum (issue, PR review, design doc, /consensus round).
- Choosing how to address a new Copier-related defect: the options here may be more cost-effective than another workaround spec.
- Onboarding new FORGE contributors who ask "why is FORGE built this way / why this distribution mechanism?"

## See also

- `docs/process-kit/copier-friction-inventory.md` — empirical defect classes + workaround spec catalogue. Read this first.
- `docs/specs/090-shared-team-baselines.md` — paused pending operator review of these two artifacts.
- `docs/specs/420-copier-on-forge-friction-and-stoke-v2-spike.md` — this spec.
- `docs/sessions/watchlist.md` — tracks deferred follow-ups including a future architectural-decision spec IF warranted (per Spec 420 Compatibility note).
