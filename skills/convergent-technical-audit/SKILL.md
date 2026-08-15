---
name: convergent-technical-audit
description: "Run a bounded, evidence-backed audit of a technical plan, design, specification, procedure, migration, report, or other technical artifact. Freeze inputs, cover applicable review lenses sequentially, independently verify candidates with an acceptance-biased gate, and stop after two clean generalist rounds or an explicit round cap. Produces an audit report and JSONL ledger only; never rewrites the artifact. Do not use for PR review, implementation, or a quick one-pass opinion."
compatibility: "Requires an Agent Skills-compatible harness with fresh native subagent sessions and completion delivery, plus Git for repository-backed evidence, Bash, Python 3, and a durable writable user-state directory."
metadata:
  version: "0.1.1"
  scope: local
---

# Convergent technical audit

Audit a frozen technical artifact until planned lens coverage is complete and two
independent generalist rounds add no accepted material finding, or the configured
round cap is reached. The deliverable is an audit, not a rewritten artifact.

`CONVERGED` means the stopping rule was met for the recorded snapshot and evidence
envelope. It never means “perfect.”

## Non-negotiable rules

- Keep the source artifact read-only. Audit state and frozen copies are the only writes.
- Store canonical state under the durable user-state root, never under `/tmp` or in the
  audited repository.
- Freeze Git evidence to an exact SHA plus approved non-secret tracked and untracked state.
- Run discovery sequentially. Integrate each verified pass before starting the next.
- Use a fresh verifier session; a discoverer never verifies its own candidates.
- Bias verification toward acceptance. Rejection requires affirmative disproof from a
  dedicated candidate-level deep dive at least as thorough as discovery.
- A candidate may be deferred once, for one evidence-resolution round only.
- Only accepted material findings reset the clean streak.
- Discovery and verification agents must not spawn subagents.
- Use harness-native subagent completion delivery. Never poll, scrape panes, or create watcher loops.
- Canonical outputs are `report.md` and append-only `findings.jsonl`.
- End only as `CONVERGED`, `CAPPED_NOT_CONVERGED`, or `BLOCKED`.

## Before running

When executing an audit, read
[State and schemas](references/STATE_AND_SCHEMAS.md) completely before Phase 1. It
defines the freeze protocol, durable layout, pass contracts, ledger events, and report
shape. Resolve relative paths from this skill directory.

Ask for missing decisions in one grouped question: artifact, evidence roots, scope,
exclusions, and any override to the default 12 discovery rounds. Do not ask when the
request and local context already answer them.

Before Phase 1, preflight the native subagent facility. It must launch fresh distinguishable
sessions, deliver completion without polling, and support a least-privilege child profile
that excludes delegation and source-writing tools. Use only read/search/browser tools plus
restricted shell inspection when needed. If that facility is unavailable, follow the bounded
preflight-failure procedure in the state reference; never improvise repeated role/model/fork
retries. If recovery does not restore it, write a minimal `BLOCKED` report under a validated
durable state root and stop.

## Finding taxonomy

Each candidate has one severity and one materiality value:

- `high`: can invalidate a major conclusion, enable substantial harm/failure, or block use.
- `medium`: a meaningful gap or risk requiring adjustment.
- `low`: a real, bounded issue with limited impact.
- `material: yes`: changes a conclusion, required scope/sequence, feasibility,
  correctness, safety, release decision, or measurable requirement.
- `material: no`: wording, presentation, or corroboration that does not change a conclusion.

Do not add confidence tiers or finer severity levels.

# Five phases

## Phase 1 — Freeze

1. Resolve a private durable run root using the reference rules. Reject any resolved path
   under `/tmp` or an audited repository before creating it.
2. Copy the artifact and non-repository evidence into `freeze/`, recording origin,
   retrieval time, and SHA-256.
3. For each Git source, record the base SHA, then enumerate tracked changes and untracked
   paths by name before reading content. Exclude likely credentials by default; capture only
   explicitly approved in-scope dirty content and record exclusions as unavailable.
4. Create a detached worktree with `--no-checkout`, materialize only approved tracked paths,
   apply approved dirty state, and copy the result without Git metadata into the final frozen
   snapshot. Hash it and make it read-only; never perform a full checkout first.
5. Record unavailable evidence. If the artifact or minimum evidence needed for a
   meaningful audit cannot be frozen, publish a `BLOCKED` report and stop.

Never rebind a run to a moving branch. Later source changes make the report stale; they
do not create an `INVALIDATED` state.

## Phase 2 — Plan lenses

Choose applicable lenses from:

- factual and internal correctness;
- implementation feasibility and dependencies;
- completeness and edge cases;
- failure handling and data integrity;
- security, privacy, and compliance;
- operations, observability, and recovery;
- testing and validation;
- rollout and rollback;
- performance, scalability, and cost;
- user and product impact.

Add artifact-specific lenses. Group related lenses into passes with a concrete question
and evidence scope. List omitted baseline lenses on one line; do not write per-lens N/A
rationales.

Reserve two discovery-round slots for final generalist rounds. If the lens plan cannot
fit under the cap, combine related lenses or ask the user to raise the cap before starting.

## Phase 3 — Run verified lens passes

For each pass, sequentially:

1. Spawn one fresh discovery subagent with the frozen paths, assigned lenses, accepted-
   finding digest, output contract, and explicit no-delegation/read-only rules.
2. Persist its returned result and investigation scope under `passes/`. Append and validate
   one `candidate.discovered` event per candidate in `findings.jsonl` before verification.
3. Spawn a different verifier session. It may batch `ACCEPT`, `MERGE`, and `DEFER`
   decisions for that discovery pass.
4. If the verifier proposes rejection, spawn a fresh dedicated deep-dive verifier for
   that candidate alone. A batch verifier cannot issue `REJECT`.
5. Append decision events to `findings.jsonl`, validate every JSON line, regenerate the
   accepted digest, and atomically update status before the next discovery pass.

### Conservative verifier gate

- `ACCEPT`: retain the candidate when evidence survives review and no concrete disproof exists.
- `MERGE`: attach a duplicate to the same underlying finding. Duplicate is not rejection.
- `DEFER`: name genuinely missing evidence, acquisition action, owner, and one-round expiry.
- `REJECT`: only a dedicated deep dive may affirmatively disprove the claim with code,
  reproduction, test, or authoritative specification evidence.

A rejection deep dive must inspect every cited source, repeat or directly invalidate every
recorded reproduction, cover equal or greater relevant evidence breadth, and record its
investigation. If it cannot do all four, it must accept or defer. Plausibility, intuition,
style, “seems unlikely,” and lack of quick confirmation never justify rejection.

A deferral makes the current pass non-clean. Acquire any new evidence into a new immutable
supplement directory, hash it, append its provenance event, and leave the baseline freeze
unchanged. Run one evidence-resolution pass; then append `ACCEPT`, `MERGE`, qualifying
`REJECT`, or `UNVERIFIED`. Never defer it again. An unverified candidate remains visible but
no longer blocks convergence.

Coverage is complete when all assigned lens passes and one-time deferral resolutions end.
Do not maintain dirty-lens bookkeeping; mention recent finding areas in the next brief instead.

## Phase 4 — Run two clean generalist rounds

Set the clean streak to zero after lens coverage. Run fresh generalist discovery sessions
sequentially; each receives frozen inputs and the accepted digest, not another reviewer's
private reasoning. Verify every candidate through Phase 3's gate.

A round is clean when it leaves no newly accepted material finding, no material expansion
to an existing finding, and no unresolved deferral.

- Accepted material finding or material merge expansion: reset streak to zero.
- Accepted non-material finding: record it; it does not reset the streak.
- Pure duplicate/corroborating merge: record provenance; it does not reset the streak.
- Deferral: the round earns no clean credit and pauses the existing streak. Its resolution
  resets the streak only if it accepts a material finding or material merge expansion.
- Two clean-round credits from distinct sessions with no accepted material finding between
  them: `CONVERGED`. Resolution passes never earn clean credit.

Default `max_discovery_rounds` is 12 and counts lens-discovery plus generalist-discovery
rounds. Do not add a wall-clock cap. Candidate-bound rejection deep dives and one-time
deferral resolution cannot launch new discovery. If the cap arrives first, end
`CAPPED_NOT_CONVERGED`; durable state must make a later raised-cap resume possible.

## Phase 5 — Report

Generate `report.md` from complete canonical state—`config.json`, baseline and supplemental
evidence manifests, `coverage.json`, `status.json`, and `findings.jsonl`. Never hand-patch an
older render. Use this concise order:

1. executive verdict and exact status;
2. frozen scope, revisions, exclusions, and evidence envelope;
3. assigned lens coverage plus one-line omitted lenses;
4. accepted findings by high/medium/low, each marked material yes/no;
5. unverified items and limitations;
6. run provenance, round usage, and stop reason;
7. rejected-candidate appendix with affirmative disproof and deep-dive effort.

Fold corrections to artifact claims into their findings. Optional HTML is disposable and
must be generated from the canonical Markdown/JSONL pair.

## Termination

- `CONVERGED`: lens coverage completed and two clean-round credits finished with no accepted material finding between them.
- `CAPPED_NOT_CONVERGED`: the discovery cap arrived before convergence; report the exact resume point.
- `BLOCKED`: minimum frozen artifact/evidence or an independent verifier was unavailable.

Individual missing evidence follows the one-round deferral path; it is not a global blocker.
Report the final paths, status, accepted-material count, unverified count, rounds used, and
anything required to resume. Do not edit or implement the audited artifact afterward unless
the user starts a separate task.
