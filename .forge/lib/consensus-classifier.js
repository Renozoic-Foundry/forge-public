// FORGE consensus divergence classifier (Spec 524, Req 8 — canonical single source).
//
// Ports the Spec 301 tally signals + Spec 391 round-2 trigger as PURE LOGIC.
// The Spec 468 terminal classifier (APPROVED/REVISE/STALEMATE/HUMAN-JUDGMENT +
// the 5-trigger taxonomy) is deliberately NOT here — it is judgment-layer and
// stays model-side in the main loop over this module's structured output
// (explore F1). This module only returns data; it never auto-revises anything.
//
// The block between the CLASSIFIER-CORE sentinels below is byte-verified against
// the embedded copy in .forge/workflows/consensus.workflow.js by
// .forge/bin/check-consensus-classifier-parity.sh (wired into forge-parity.sh).
// Workflow scripts cannot import modules at runtime (no filesystem/Node API), so
// the copy is duplicated-and-verified rather than imported. Edit BOTH copies
// together — the drift gate FAILs otherwise.

// >>> forge:consensus-classifier-core (Spec 524 — byte-identical in the workflow embed)
function tally(verdicts) {
  const t = { approve: 0, concern: 0, reject: 0, error: 0 };
  for (const v of verdicts) {
    const vote = v && v.vote;
    if (vote === 'approve' || vote === 'concern' || vote === 'reject') t[vote] += 1;
    else t.error += 1;
  }
  return t;
}

function divergenceSignal(t) {
  const decided = t.approve + t.concern + t.reject;
  if (decided === 0) return 'no-verdicts';
  if (t.approve === decided) return 'aligned-approve';
  if (t.concern === decided) return 'aligned-concern';
  if (t.reject === decided) return 'aligned-reject';
  if (t.reject >= 1 && t.approve >= 2) return 'strong-divergence';
  if (t.reject > decided / 2) return 'blocked';
  if (t.reject === 0) return 'mild-divergence';
  // reject present but neither strong (needs 2+ approve) nor majority
  return 'strong-divergence';
}

function recommendedAction(signal, t) {
  switch (signal) {
    case 'aligned-approve': return 'Proceed';
    case 'aligned-concern': return 'Revise — defer or rework before proceeding';
    case 'aligned-reject': return 'Do not proceed — significant opposition';
    case 'mild-divergence': return 'Proceed with noted concerns';
    case 'strong-divergence': return 'Discuss — roles fundamentally disagree';
    case 'blocked': return 'Do not proceed — significant opposition';
    default: return 'No verdicts — re-dispatch';
  }
  void t;
}

// Spec 391 round-2 trigger: >=2 DISTINCT named candidates AND not already
// aligned-approve >=4/5. Candidates come from the additive `candidate` field
// (string|null) — never prose-parsed (Spec 524 Req 3). A `reframe:true` verdict
// counts its candidate too. Returns {trigger:boolean, candidates:string[]}.
function roundTwoTrigger(verdicts, t) {
  const decided = t.approve + t.concern + t.reject;
  const alignedApprove4of5 = decided >= 5 && t.approve >= 4 && t.reject === 0 && t.concern <= 1
    ? t.approve / decided >= 0.8 : (decided > 0 && t.approve / decided >= 0.8 && t.approve >= 4);
  const names = new Set();
  for (const v of verdicts) {
    if (v && typeof v.candidate === 'string' && v.candidate.trim() !== '') names.add(v.candidate.trim());
  }
  return { trigger: names.size >= 2 && !alignedApprove4of5, candidates: Array.from(names).sort() };
}

function classify(verdicts) {
  const t = tally(verdicts);
  const signal = divergenceSignal(t);
  const action = recommendedAction(signal, t);
  const round2 = roundTwoTrigger(verdicts, t);
  return { tally: t, divergence: signal, recommended_action: action, round_two: round2 };
}
// <<< forge:consensus-classifier-core

module.exports = { classify, tally, divergenceSignal, recommendedAction, roundTwoTrigger };
