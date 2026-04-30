# Onboarding Recovery Procedures

Operator-facing recovery procedures for the FORGE `/onboarding` lifecycle. Cross-references Spec 315 (mature-repo detector + staged writes).

This page is referenced by `.forge/commands/onboarding.md` and is required reading when any of the following occurs:
- The mature-repo detector auto-completed onboarding incorrectly
- Atomic application halted partway through with a partial-state report
- A pre-existing staging directory was found at session start
- The integrity manifest reported a hash mismatch
- `/implement` was interrupted while testing the onboarding detector

---

## Quick reference

| Situation | Action |
|-----------|--------|
| Detector fired but repo isn't actually mature | Edit `.forge/onboarding.yaml`: set `status: pending`. Remove the `# Auto-set by mature-repo detection` comment. Or run `/forge init` to restart. |
| `/onboarding` halts mid-application with a partial-state report | Re-run `/onboarding` to trigger the inspect-resume / discard-restart prompt. |
| Pre-existing staging dir surprised you | Run `/onboarding`; choose **inspect-resume** (review the diff before applying) or **discard-restart** (wipe and start fresh). |
| Manifest mismatch warning | Treat as suspicious. Choose **discard-restart** unless you are certain the staging content is benign — there is no silent-trust path. |
| `/implement` aborted while testing Spec 315 | Restore `.forge/onboarding.yaml` from the git baseline: `git restore .forge/onboarding.yaml`. |

---

## Erroneous mature-repo auto-completion (Req 9)

The mature-repo detector at `/onboarding` Step 0 uses three heuristics combined "any 2-of-3":

1. ≥ 20 closed/implemented specs in `docs/specs/`
2. `.copier-answers.yml` has a resolvable `_commit:` SHA (with structural fallback for offline)
3. `CLAUDE.md` has customization beyond template defaults (e.g., a `# Model override` section, or byte-size > 2× template baseline)

If two of these fire on a project that is NOT actually past onboarding (e.g., an imported corpus of historical specs, a placeholder customized CLAUDE.md), the detector will short-circuit `/onboarding` with `status: complete`. Recovery procedure:

**To revert: edit .forge/onboarding.yaml — set `status: pending` and remove the `# Auto-set by mature-repo detection` comment. Re-run `/onboarding`.**

Alternatively, run `/forge init` to restart the lifecycle from scratch — this also rewrites `.forge/onboarding.yaml`.

If the heuristic fired because of a single tampered signal (e.g., someone fabricated `_commit` in `.copier-answers.yml`), the recovery is the same: revert the YAML and re-run. The "any 2-of-3" combining rule means a single tampered signal cannot trigger the detector on its own — another signal had to legitimately match.

---

## Partial-failure resumption (Req 10)

If the atomic-application phase halts on a per-file write failure (disk full, permission denied, lock contention), the staging directory is **preserved** (not removed). The operator sees a partial-state report listing files-applied and files-pending.

**To continue: re-run `/onboarding`.** The pre-existing-staging detection (Step 0.5) fires on session start, and the inspect-resume / discard-restart prompt appears:

- **inspect-resume** — review the staged files' diffs against the current working-tree (which now has the partially-applied state from the previous attempt). Decide whether to re-apply the remaining staged content or discard.
- **discard-restart** — wipe staging and restart `/onboarding` from the beginning. The partially-applied files in the working tree remain — clean them up manually with `git restore <files>` or `git checkout HEAD -- <files>` as appropriate.

The integrity manifest is re-verified at every `inspect-resume`. If a staged file's hash no longer matches the manifest (e.g., something else modified it between staging and resume), a manifest-mismatch warning fires and you are forced into an explicit discard-or-proceed-despite-tampering choice.

---

## Audit-before-accept (Req 13 + CISO round-2 residual)

When you choose **inspect-resume**, the command shows you a diff between each staged file and the current working-tree counterpart. Read the diff carefully before answering "yes" to apply.

**Audit the diff shown in inspect-resume against your expectations before choosing accept; staged content older than 24h or with a manifest-mismatch warning should be treated as suspicious.**

The operator is the last line of defense against adversary-controlled staged content. Reqs 12–14 raise the cost of forging undetected — integrity manifest catches post-staging tampering, the diff makes adversarial replacements visible, the 24h-stale warning encourages discard-restart for abandoned dirs — but an operator who chooses "proceed-despite-tampering" without auditing the diff defeats the gate. This is unavoidable without removing operator agency entirely; it is documented as an accepted residual.

If you see anything in a diff you did not expect, choose **discard-restart**. Re-running `/onboarding` is cheap; auditing an attacker-controlled CLAUDE.md applied to your repo is not.

---

## Recognized template sources (Req 1)

The mature-repo detector's Heuristic 2 (Copier provenance) requires `.copier-answers.yml` to have a `_commit:` value that resolves against a recognized FORGE template source. The current canonical allowlist:

| Source | URL / pattern | Notes |
|--------|---------------|-------|
| FORGE public release | `gh:Renozoic-Foundry/forge-public` | Canonical public template; recommended for consumer projects |
| FORGE internal | `gh:Renozoic-Foundry/forge` | FORGE framework's own development repo |
| Local FORGE clone | filesystem path containing `forge` segment (e.g., `c:/Code/local/forge`, `/home/user/code/forge`) | Used by FORGE developers for testing the template; falls through to structural fallback (40-hex SHA + non-empty `_src_path`); the 2-of-3 rule still requires another signal |

**Allowlist edits require a follow-up spec.** The list is intentionally narrow — silent expansion would let any attacker-controlled URL count as a "recognized template source" and weaken Heuristic 2. Adding a new entry (e.g., a fork URL, a different organization) goes through `/spec` → consensus → `/implement`.

**Disconnected-setup degradation (DA round-2 residual)**: in air-gapped or offline environments where neither the template's commit graph nor a network-reachable URL allowlist can be consulted, validation degrades to structural-only (40-hex SHA + non-empty `_src_path`). Forgery cost in offline scenarios reduces to single-signal — operators in such environments should treat the mature-repo skip as advisory and verify their onboarding state manually before assuming the detector's output is trustworthy.

---

## Coordinated-tampering residual (Req 12 cross-reference)

The integrity manifest at `.forge/state/onboarding-staging/.manifest.sha256` is **not self-hashed**. An adversary with write access to the staging directory can replace BOTH a staged file AND its entry in the manifest, defeating the per-file integrity check entirely.

In that case, the only remaining defense is the diff-on-resume operator-vigilance gate (Req 13): when **inspect-resume** is chosen, the operator sees a diff between the staged content and the current working-tree counterpart. An adversarial replacement that altered staged content meaningfully will show up in that diff — but only if the operator actually reads it.

**This is an accepted residual.** Self-hashing the manifest would require an external tamper-evident anchor (signed commit, external KMS, etc.) which is out of scope for `/onboarding`'s lightweight staging model. The threat is bounded: it requires write access to `.forge/state/onboarding-staging/` between staging and resume, which is the same access required to modify any project file at any time. The defense-in-depth posture is: integrity manifest catches casual / non-adversarial corruption; diff-on-resume catches adversarial replacement only via operator vigilance.

---

## Implementation-time abort during Spec 315 testing (DA disposition #5)

If `/implement` is interrupted during AC 1 testing — which requires temporarily flipping `.forge/onboarding.yaml` from `complete` to `pending` to exercise the mature-repo detector, then restoring it — the repo could be left in `pending` state without breadcrumbs.

Recovery: `git restore .forge/onboarding.yaml` to bring the file back to its committed baseline. The committed baseline is `status: complete` for this FORGE repo (per Spec 315 Req 7 / AC 5). For consumer projects, the baseline depends on where in the lifecycle the project was when it was committed — `git log .forge/onboarding.yaml` will show the history.

---

## See also

- `.forge/commands/onboarding.md` — the canonical `/onboarding` command body
- `docs/specs/315-onboarding-staged-writes-and-mature-repo-detection.md` — the spec authorizing this recovery procedure
- `docs/process-kit/runbook.md` — broader operator runbook
