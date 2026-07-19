# Guard-Family Protected-File Apply Note (Spec 503)

<!-- forge:maintainer-detail:start -->
The FORGE authority/edit/commit/push guard scripts and the autonomy-config files protect
themselves: they sit in the authority-guard deny set (`.forge/bin/check-authority-guard.sh`),
so an agent cannot edit them in-session. Both channels deny the write — the Edit/Write
channel (a write whose target is a protected path) and the Bash verb-class channel (a write
verb naming a protected path; conservatively, it over-blocks any command that merely *names*
a protected path next to a write verb). That is the safe default for the ADR-046 trust root.
It means **any spec that modifies a guard-family file must hand the live-root edit to the
operator** — `deny` is a hard block with no in-session permission dialog.

## The apply pattern (proven — use this for every guard-family spec)

1. **Edit the `template/` mirror, not the root.** `template/.forge/bin/<guard>.sh` is NOT in
   the deny set, so the agent edits it directly. Make the change there.
2. **Stage the root copy.** Root and template guards are kept byte-identical (parity
   Surface 3), so the staged content *is* the edited template mirror.
3. **Operator applies the root copy in the terminal** (the agent cannot). From the repo root:
   ```
   cp template/.forge/bin/<guard>.sh .forge/bin/<guard>.sh
   ```
   (For `.claude/settings.json` / `.forge/config/authority.yaml`, copy from the staged
   template/`.forge`-config source the same way.)
4. **Re-verify parity (Surface 3):** `.forge/bin/forge-parity.sh --check` must pass — root
   and template guard byte-identical.

## Why no helper

A `forge apply-guards` helper was considered and dropped (Spec 503): the one-paragraph
convention above is the whole deliverable. The operator `cp` is a single, auditable,
human-authored action — exactly the operator-provenance property the guard exists to protect.
Automating it would re-introduce an agent-driven path to the trust root.

## Known accepted false-positives (deferred)

The Bash verb-class channel over-blocks a protected-path substring that appears (a) inside a
heredoc body, or (b) as a copy/move/link SOURCE operand — even though neither writes the
protected file. These are **accepted/deferred** (Spec 503): the over-block fails toward the
safe direction, and the same operator-mediated `cp` is the workaround. Revisit only if a
false-positive recurs in NON-meta guard work (a spec that does not itself edit the guard
family), or when the managed-settings trust root (ADR-453 §6.1) changes the picture.
<!-- forge:maintainer-detail:end -->
