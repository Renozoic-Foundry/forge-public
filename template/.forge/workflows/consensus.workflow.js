export const meta = {
  name: 'consensus-fanout',
  description: 'Consensus role fan-out (rounds 1-2): schema-enforced verdicts, in-script tally + divergence + Spec 391 round-2 re-vote. Rounds 3+, cap/extension prompts, Spec 468 terminal classification, and the Consensus-Close-SHA write stay in the /consensus command body (main loop). Returns structured data only — no repo side effects, no auto-revise.',
  phases: [
    { title: 'Round 1' },
    { title: 'Round 2' },
  ],
}

// Spec 524 — Consensus-as-Workflow. Replaces MECHANICS only (fan-out, verdict
// capture, tally). Governance surfaces (roster, escalation, gates, evidence
// writes, operator prompts) stay FORGE-owned in the main loop (explore F5/F7).
//
// args (passed by /consensus command body):
//   { specId, reviewMaterial, roster: [{role, agentType, effort?, model?}],
//     stageFraming, roundCap }  // roundCap is 1 or 2 (F2: this workflow covers
//                               // at most rounds 1-2; 3+ re-invokes)

// Role-identity-pinned per-role effort/model overrides (Spec 524 Req 5).
// PINNED BY ROLE IDENTITY ONLY — never derived from args.reviewMaterial or any
// $ARGUMENTS content (consensus R1 CISO: a crafted review target must not steer
// a security-relevant role onto a cheaper tier). Advisory C-suite roles run
// low-effort; DA/MT/CISO stay at session default (null = inherit).
const OVERRIDE_BY_ROLE = {
  'forge:cto': { effort: 'low' },
  'forge:coo': { effort: 'low' },
  'forge:cfo': { effort: 'low' },
  'forge:cmo': { effort: 'low' },
  'forge:cro': { effort: 'low' },
  'forge:creso': { effort: 'low' },
  'forge:cxo': { effort: 'low' },
  'forge:cco': { effort: 'low' },
  'forge:cqo': { effort: 'low' },
  'forge:cefo': { effort: 'low' },
  'forge:devils-advocate': {},        // session default
  'forge:maverick-thinker': {},       // session default
  'forge:ciso': {},                   // session default — security role, never downgraded
}

function resolveOverride(role) {
  // Look up by role identity ONLY. Unknown roles → session default.
  return Object.prototype.hasOwnProperty.call(OVERRIDE_BY_ROLE, role)
    ? OVERRIDE_BY_ROLE[role] : {}
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['role', 'vote', 'rationale', 'key_risk'],
  properties: {
    role: { type: 'string' },
    vote: { type: 'string', enum: ['approve', 'concern', 'reject'] },
    rationale: { type: 'string' },
    key_risk: { type: 'string' },
    candidate: { type: ['string', 'null'] },   // Spec 391 named-candidate (additive)
    reframe: { type: 'boolean' },               // MT self-declared reframe (additive)
  },
}

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

function dispatchPrompt(role, spec, material, framing) {
  return `${framing || ''}\n\nConsensus review of ${spec}. Material:\n${material}\n\n` +
    `Review from your role's perspective. Produce a JSON verdict:\n` +
    `{"role":"${role}","vote":"approve|concern|reject","rationale":"1-3 sentences",` +
    `"key_risk":"single most important risk or 'none'","candidate":"<named alternative path or null>",` +
    `"reframe":<true if you are proposing a mechanism reframe, else false>}`
}

async function runRound(roster, spec, material, framing, phase) {
  const verdicts = await parallel(roster.map((r) => () => {
    const ov = resolveOverride(r.role)   // identity-pinned; args cannot influence
    const opts = { agentType: r.agentType || r.role, schema: VERDICT_SCHEMA, phase, label: `${phase}:${r.role}` }
    if (ov.effort) opts.effort = ov.effort
    if (ov.model) opts.model = ov.model
    return agent(dispatchPrompt(r.role, spec, material, framing), opts)
      .then((v) => (v ? { ...v, role: r.role } : { role: r.role, vote: 'error', rationale: 'dispatch-failed', key_risk: 'unknown', candidate: null, reframe: false }))
  }))
  const c = classify(verdicts)
  return { verdicts, tally: c.tally, divergence: c.divergence, recommended_action: c.recommended_action, round_two: c.round_two }
}

// args normally arrives as a JSON value; some invocation paths hand it through
// as a JSON string — tolerate both so the roster is never silently empty.
const A = (typeof args === 'string') ? JSON.parse(args) : args
const spec = A.specId
const material = A.reviewMaterial
const roster = A.roster || []
const framing = A.stageFraming || ''
const roundCap = Math.min(Math.max(A.roundCap || 1, 1), 2)

const rounds = []
phase('Round 1')
const r1 = await runRound(roster, spec, material, framing, 'Round 1')
rounds.push(r1)
log(`Round 1: ${JSON.stringify(r1.tally)} → ${r1.divergence}`)

// Spec 391 round-2 re-vote: auto-triggered (no operator gate), only if roundCap allows.
if (roundCap >= 2 && r1.round_two.trigger) {
  phase('Round 2')
  const candMaterial = `${material}\n\nRound 2 — candidate paths surfaced in round 1: ` +
    `${r1.round_two.candidates.join('; ')}. Re-vote considering these and the other roles' concerns.`
  const r2 = await runRound(roster, spec, candMaterial, framing, 'Round 2')
  rounds.push(r2)
  log(`Round 2: ${JSON.stringify(r2.tally)} → ${r2.divergence}`)
}

const last = rounds[rounds.length - 1]
const role_yield = rounds.flatMap((rd, i) =>
  rd.verdicts.map((v) => ({ round: i + 1, role: v.role, vote: v.vote, reframe: !!v.reframe, candidate: v.candidate || null })))

// Return schema is a SUPERSET of sidecar needs (explore F5 design rule). All repo
// side effects (sidecar write, Spec 305 record-dispatch, Spec 389 SHA) run in the
// main loop after this returns — the workflow performs none.
return {
  rounds,
  final_divergence: last.divergence,
  recommended_action: last.recommended_action,
  role_yield,
}
