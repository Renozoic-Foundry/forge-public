# Copier-on-FORGE Friction Inventory

**Status**: preparatory institutional-memory artifact. **No architectural recommendation.** Produced by Spec 420 v0.2.

This document captures empirical Copier integration defect classes observed in FORGE history, plus a catalogue of FORGE infrastructure specs built primarily to compensate for Copier limitations. The inventory's value is institutional memory: it prevents future specs from rediscovering the same Copier behaviors, regardless of whether FORGE eventually decides to stay on Copier (Option F-1/F-4), build a hybrid (F-2), replace Copier (F-3), or follow a less-explored path (F-5+).

The companion document `forge-distribution-alternatives.md` surveys the option space at a level appropriate for future architectural conversations, also without recommendation.

---

## Empirical defect classes (Copier 9.14.0)

### 1. Underscore-prefix answer-key stripping

**Observed behavior**: Copier filters all answer keys whose names start with `_` (underscore) from the persisted `.copier-answers.yml`, even when those keys were supplied via `--data-file`. The keys are read into the in-memory render context (templates can reference them) but vanish from the answers file after render.

**Mechanism** (verified in `copier._main.Worker` source by Spec 090 round-2 validator subagent): Copier applies `if not k.startswith("_")` when building the persisted answers mapping. Underscore-prefixed keys are treated as "internal/metadata" and excluded by design.

**Reproducible evidence**:
```bash
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/template"
cat > "$TMPDIR_TEST/copier.yml" <<'EOF'
_subdirectory: "template"
_min_copier_version: "9.3.0"
_baseline_name: { type: str, default: "" }
EOF
echo "x" > "$TMPDIR_TEST/template/file.txt"
echo "_baseline_name: my-name" > "$TMPDIR_TEST/data.yml"
copier copy "$TMPDIR_TEST" "$TMPDIR_TEST/out" --data-file "$TMPDIR_TEST/data.yml" --defaults
grep "_baseline_name" "$TMPDIR_TEST/out/.copier-answers.yml"  # → no match (filtered)
```

**Affected FORGE specs**: Spec 090 v3 (provenance design used `_baseline_*` names; AC 1 FAILed at /close validator); Spec 090 v3.2 reframe renamed to `forge_baseline_*` to escape the filter.

**Workaround pattern**: name persistence-required answer keys WITHOUT leading underscore (FORGE's `forge_baseline_*` naming convention).

---

### 2. `when: false` answer-key filtering

**Observed behavior**: same filtering effect as #1 (key absent from `.copier-answers.yml` even when `--data-file` supplies it), but triggered by `when: false` on the question definition rather than by underscore-prefix on the key name. Affects literal `when: false` AND any Jinja expression that evaluates falsy at template-load time.

**Mechanism**: Copier treats `when: false` questions as "not applicable to this render" — sets the value in-memory to its default but excludes from persisted answers, regardless of whether `--data-file` provided a non-default value.

**Reproducible evidence**:
```bash
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/template"
cat > "$TMPDIR_TEST/copier.yml" <<'EOF'
_subdirectory: "template"
_min_copier_version: "9.3.0"
forge_baseline_name:
  type: str
  default: ""
  when: false
EOF
echo "x" > "$TMPDIR_TEST/template/file.txt"
echo "forge_baseline_name: persistent-name" > "$TMPDIR_TEST/data.yml"
copier copy "$TMPDIR_TEST" "$TMPDIR_TEST/out" --data-file "$TMPDIR_TEST/data.yml" --defaults
grep "forge_baseline_name" "$TMPDIR_TEST/out/.copier-answers.yml"  # → no match (when:false filtered)
```

**Affected FORGE specs**: Spec 090 v3.2 (used `when: false` to suppress prompts; provenance keys silently dropped from `.copier-answers.yml`; AC 1 FAILed at /implement Step 2b DA gate on round 4 retest).

**Workaround pattern (P2f)**: replace `when: false` with self-referential `when:` that evaluates against the supplied answer (e.g., `when: "{{ forge_baseline_name|default('') != '' }}"`). Validator + value persist when supplied; both absent when not. Empirically verified in Spec 090 v3.3.

---

### 3. `_migrations:` phase-ordering vs in-memory validator state

**Observed behavior**: `_migrations:` blocks run at the `before` stage (before validator phase) but do NOT refresh Copier's in-memory answer state with the migration's disk mutations. A migration that appends `accept_security_overrides: true` to `.copier-answers.yml` is invisible to the validator that runs immediately afterward — the validator reads the in-memory state (which still has the pre-migration values) and aborts the entire `copier update` with exit 1.

**Mechanism**: Copier's phase ordering loads answer-file → runs `_migrations:` → runs validator (against in-memory state). The migration's effect on disk is real but ignored by the in-flight render.

**Reproducible evidence**: Spec 090 v3.1 implementation; validator FAIL on AC 9 with empirical reproduction documented in DA Findings table.

**Affected FORGE specs**: Spec 090 v3.1 (auto-migration to inject `accept_security_overrides: true` for pre-existing consumers; AC 9 FAILed at /close validator); Spec 090 v3.2 reframe dropped the auto-migration approach entirely (Option A vote at `/consensus 090` round 4).

**Workaround pattern**: do NOT use `_migrations:` to mutate values that subsequent validators will read. Manual migration documented as a one-line operator fix is a more honest pattern.

---

### 4. `_tasks:` failure cascading into full-output rollback

**Observed behavior**: when ANY `_tasks:` entry exits non-zero, Copier deletes the entire output directory (rolls back the render). Even files successfully created earlier in the render (including `.copier-answers.yml`) are removed.

**Reproducible evidence** (empirically reproduced 2026-05-11 against production FORGE template):
```bash
TMPDIR_TEST=$(mktemp -d)
copier copy . "$TMPDIR_TEST/render" \
  --data-file docs/process-kit/baselines/python-fastapi.yaml --defaults --trust 2>&1 | tail -5
# Task 1 (scrub_answers.py): runs OK
# Task 2 (migrate-to-derived-view.py): raises ModuleNotFoundError: split_file_writer
# Result: Copier deletes $TMPDIR_TEST/render entirely
ls "$TMPDIR_TEST/render" 2>&1  # → "No such file or directory"
```

**Affected FORGE specs**: triggered for Spec 090 v3.3 by Spec 400's split-file migration (`split_file_writer` missing from environment); rendered Spec 090's Test 13 unrunnable. The defect is not Spec 090's; it surfaces because Spec 090's Test 13 invokes the production template.

**Workaround pattern**: ensure `_tasks:` scripts have hard-pinned dependencies and are robust against environment differences; OR accept that any `_tasks:` failure blocks every consumer's `copier update` until the task is fixed (Spec 400's pattern).

---

### 5. `--trust` flag friction for templates with `_tasks:`

**Observed behavior**: Copier 9.14.0 refuses to run `_tasks:` blocks unless the operator passes `--trust` (or the `--UNSAFE` alias). Without `--trust`, Copier prints a warning ("Template uses potentially unsafe feature: tasks") and skips the tasks — producing a subtly-different render than with `--trust`. This is by design (Copier's security feature forcing operator opt-in to template-controlled code execution).

**Reproducible evidence**: documented inline in Copier's CLI and `copier.yml` comments at lines 23-24 (FORGE's reference to Git for Windows Option 3 / Git Bash terminal requirement).

**Affected FORGE specs**: implicit dependency on every spec that exercises the FORGE template via `copier copy .` or `copier update` — Spec 090 Test 13 documented the requirement (DA C2 finding at v3.3 retest); existing `CLAUDE.md` § "Testing changes" sequence omits `--trust`, which works for the scrub_answers task but bypasses the split-file-migration task silently.

**Workaround pattern**: every documented `copier copy/update` invocation in FORGE must include `--trust` for behavioral parity with production renders. Operator habit / muscle-memory dependency.

---

### 6. `_validators:` plural-block does not exist as a Copier feature

**Observed behavior**: only per-question `validator:` (singular) exists. There is no top-level `_validators:` (plural) block in Copier's YAML schema.

**Mechanism**: Copier's question-level `validator:` field takes a Jinja expression returning empty string (valid) or non-empty error message (invalid). No project-level validators block.

**Affected FORGE specs**: Spec 090 v3.1 spec text used `_validators:` (incorrect terminology); Spec 090 v3.3 W7 disposition fixed plural→singular wording. Pure spec-text consistency issue, not a runtime defect.

**Workaround pattern**: spec-text discipline — use singular `validator:` to match Copier's actual schema. Could be enforced by a FORGE-internal lint scanning spec text for `_validators:` mentions.

---

### 7. Validator Jinja context lacks operation-type / source-provenance

**Observed behavior**: `_copier_conf.operation` is undefined in validator Jinja context. Validators cannot distinguish `copier copy` (greenfield render with `--data-file` baseline) from `copier update` (re-render against existing `.copier-answers.yml`). Validators also cannot distinguish whether an answer value came from `--data-file`, `--data` inline, interactive prompt, or persisted prior answer.

**Mechanism**: Copier's validator API exposes `_copier_python` (interpreter path), `_copier_conf.dst_path` / `src_path` / `answers_file` (path strings), `_folder_name` (target name) — but no operation type and no per-answer source/history.

**Reproducible evidence** (Spec 090 round-4 consensus AC9-design subagent probe):
```yaml
_message_after_copy: |
  {%- if _copier_conf.operation is defined %}op={{ _copier_conf.operation }}{%- else %}NOT DEFINED{%- endif %}
```
Both `copier copy` and `copier update` print "NOT DEFINED".

**Affected FORGE specs**: Spec 090 round-4 Maverick proposed Option D (scope-aware validator that fires on greenfield only, not on update) — empirically infeasible because the operation type is not exposed. Tracked on `docs/sessions/watchlist.md` for future Copier release.

**Workaround pattern**: design FORGE patterns to NOT depend on operation-type detection in validators. If operation-aware logic is needed, do it OUTSIDE of validators (e.g., in `_tasks:` Python scripts which DO have access to wider context).

---

### 8. Cross-platform `sh` PATH dependency on Windows

**Observed behavior**: FORGE's `copier.yml` `_tasks:` blocks invoke `sh -c '...'` for portable shell scripting. On Windows, `sh` must be on PATH — which requires either Git for Windows installer Option 3 ("Use Git and optional Unix tools from the Command Prompt") OR launching FORGE commands from Git Bash terminal.

**Mechanism**: Windows lacks a built-in `sh`; Git for Windows ships one but doesn't expose it on PATH by default.

**Reproducible evidence**: documented inline in `copier.yml` lines 22-23 + `docs/process-kit/cross-platform-python-guide.md` § Windows prerequisite detail.

**Affected FORGE specs**: any spec touching `copier.yml` `_tasks:` indirectly inherits this dependency (Spec 294 scrub, Spec 400 migration). Surfaces operator-friction at /forge stoke time on Windows installs that didn't choose Option 3 at Git installation.

**Workaround pattern**: documentation + check-script in `forge-init` Step 0 prereq verification (per Spec 401). Friction shifts to install-time rather than render-time.

---

## Workaround spec catalogue

The following FORGE infrastructure specs exist primarily to compensate for one or more Copier limitations from the inventory above. One-line annotation per spec on which limitation each addresses:

| Spec | Title (short) | Compensates for |
|------|---------------|-----------------|
| 086 | Three-source verification (spec ↔ README ↔ backlog) | Copier doesn't track FORGE's spec-status invariant across multiple files; FORGE built three-source-sync because Copier persists answers but not derived state. |
| 145 | Edit-gate sentinel (`.forge/state/implementing.json`) | Copier has no transactional concept of "this spec is being implemented"; sentinel-based gating is FORGE-native. |
| 254 | Per-spec event stream (Approach D) | Copier persists scalar answers but not event history; event-stream is FORGE-native append-only audit log that Copier doesn't try to manage. |
| 294 | Copier-native placeholder scrub (`scrub_answers.py`) | Copier's answer persistence is too sticky — once a placeholder default lands in `.copier-answers.yml`, Copier replays it forever. Scrub script clears legacy placeholders defensively. |
| 327 | Authorization-rule lint gate | Copier doesn't validate command-body content; FORGE built lint to scan `.claude/commands/*.md` for unsafe patterns (relates to defect class #5 `--trust` semantics). |
| 330 | AGENTS.md prose↔YAML drift detector | Copier doesn't enforce consistency between human-readable prose and machine-readable YAML; FORGE built drift detector. |
| 398 | Split-file rendering (curated parents + generated children) | Copier renders templates atomically; FORGE wanted derived-view rendering (`docs/.generated/*.md`) which Copier doesn't natively support — split-file scheme + custom assembler. |
| 400 | Auto-migration on `copier update` for split-file rendering | Copier `_migrations:` runs upgrade scripts but doesn't handle FORGE's split-file mode transition; custom `migrate-to-derived-view.py` fills the gap. (Note: this script's `ModuleNotFoundError` is the production-tree blocker that surfaced defect class #4.) |
| 090 (v3.X) | Shared team baselines | Hits defect classes #1, #2, #3, #4, #5, #6 across 4 /implement attempts before being paused pending this spec. The most concentrated single example of FORGE-on-Copier friction. |
| 401 | Cross-platform Python invocation | Hits defect class #8 (Windows `sh` PATH dependency); ships `.forge/bin/forge-py` wrapper to reduce shell-out fragility. |

This list is not exhaustive — implementer was unable to grep every closed spec for Copier-related justifications in scope of Spec 420 v0.2. The 10 specs above are the load-bearing examples; future analysis may surface more (track via `/evolve` loop review).

---

## Read this inventory before

- Drafting any new FORGE spec that touches `copier.yml`, `_tasks:`, `_migrations:`, `_validators:`, or `.copier-answers.yml` persistence.
- Diagnosing a `copier update` failure on a consumer project.
- Discussing FORGE's distribution architecture (companion: `forge-distribution-alternatives.md`).
- Adding a new FORGE-internal infrastructure spec to compensate for a Copier behavior — first check whether the behavior is documented here as a known limitation, and whether the workaround pattern matches what you're proposing.

## See also

- `docs/process-kit/forge-distribution-alternatives.md` — survey of architectural options (F-1 through F-5 + buy/reuse + PR-model + drop-update-aspiration). Also preparatory; no recommendation.
- `docs/specs/090-shared-team-baselines.md` — paused pending operator review of this inventory + alternatives survey.
- `docs/specs/420-copier-on-forge-friction-and-stoke-v2-spike.md` — this spec.
- `docs/sessions/watchlist.md` — tracks deferred follow-ups including a future architectural-decision spec IF warranted.
