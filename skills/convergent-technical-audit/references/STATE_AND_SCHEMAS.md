# State and schemas

Read this reference before executing a convergent technical audit. It defines the
portable run state and contracts; do not improvise incompatible formats mid-run.

## Durable run root

Start with:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/agent-audits/convergent-technical-audit/<audit-id>/
```

Resolve the candidate path before creating it. If `XDG_STATE_HOME` resolves under `/tmp`,
ignore it and retry with `$HOME/.local/state`. Reject the final path when it resolves under
`/tmp` or inside any audited repository; if no safe durable path exists, terminate `BLOCKED`.
Do boundary-aware path comparison, not string-prefix comparison.

Create the accepted root with mode `0700`. Choose an audit ID from a UTC timestamp plus a
short artifact slug. Never store credentials, auth exports, session transcripts, or
unrestricted secret files. Hash and mark secret-bearing evidence unavailable unless the user
explicitly approves its protected inclusion.

```text
<audit-id>/
├── config.json
├── status.json
├── freeze/
│   ├── source-manifest.json
│   ├── supplemental-evidence.jsonl
│   ├── artifact/
│   ├── evidence/
│   ├── supplements/
│   └── worktrees/
├── coverage.json
├── findings.jsonl
├── accepted-findings.md
├── passes/
│   └── <sequence>-<kind>/
│       ├── brief.md
│       ├── result.md
│       └── investigation.json
└── report.md
```

Write mutable JSON/Markdown to a temporary sibling in the same directory, validate it,
then rename it over the destination. `findings.jsonl` is append-only.

## Configuration schema

`config.json`:

```json
{
  "schemaVersion": 1,
  "auditId": "20260115T120000Z-example-design",
  "artifactLabel": "Example design",
  "scope": ["artifact.md", "implementation repository"],
  "exclusions": ["commercial wording"],
  "maxDiscoveryRounds": 12,
  "requiredCleanGeneralistRounds": 2,
  "execution": "sequential",
  "verifierBias": "accept_unless_affirmatively_disproved"
}
```

Record a later configuration change as a `config.changed` ledger event and in report
provenance. Never silently replace the original settings.

`status.json`:

```json
{
  "schemaVersion": 1,
  "phase": "verified_lens_passes",
  "nextPassSequence": 4,
  "discoveryRoundsUsed": 3,
  "cleanStreak": 0,
  "coverageComplete": false,
  "pendingCandidateIds": [],
  "terminalStatus": null,
  "resumeInstruction": "Run lens pass LP-04"
}
```

## Freeze protocol

### Repository-backed evidence

For every repository:

1. Record repository label, resolved root, branch label, submodule/LFS state, and immutable
   `BASE_SHA=$(git rev-parse HEAD)`. Use that exact value throughout this freeze.
2. Enumerate tracked paths plus tracked changes by name (`git ls-files` and
   `git diff --name-only "$BASE_SHA"`) before reading dirty content. Classify likely
   secret-bearing names such as `.env*`, key/certificate stores, credential/auth exports,
   and provider dumps.
3. Enumerate untracked path names with `git ls-files --others --exclude-standard`. Ask once
   which in-scope tracked and untracked secret candidates may receive protected inclusion.
4. Capture binary patches one approved changed path at a time with
   `git diff --binary "$BASE_SHA" -- "$approved_path"`. Never run an unrestricted diff or
   place excluded content in a patch. Verify `git rev-parse HEAD` still equals `BASE_SHA`
   before and after capture; if it moved, discard this incomplete capture and restart Phase 1.
5. Create a temporary detached worktree with
   `git worktree add --detach --no-checkout <staging> "$BASE_SHA"`. Materialize only the
   NUL-delimited approved tracked list with `git checkout "$BASE_SHA"
   --pathspec-from-file=<approved-list> --pathspec-file-nul`; never use moving `HEAD` or
   perform a full checkout. Apply only filtered patches and copy approved untracked files.
6. Copy the materialized tree without its `.git` pointer into the final
   `freeze/worktrees/<label>/` snapshot, then unregister/remove the temporary worktree. This
   prevents excluded Git objects from being reachable through the reviewer-facing snapshot.
7. Record each excluded path as `availability: "unavailable"` without content or content hash.
   Hash every remaining frozen in-scope file into `source-manifest.json`, then remove write
   permission from the final snapshot.
8. Give reviewers only frozen paths. Never let a pass switch branches or refresh from origin.

Do not include `.env`, key stores, credential directories, provider exports, or auth state by
default, even when Git already tracks them at the base SHA. Protected inclusion requires the
user's explicit approval and the private `0700` state root. A worktree registration changes
Git metadata but must not change source files or commits.

### Non-repository and live evidence

Copy local artifacts into `freeze/artifact/`. Save fetched primary documentation or console
exports under `freeze/evidence/`. Each manifest entry records:

```json
{
  "logicalName": "provider restore documentation",
  "frozenPath": "freeze/evidence/provider-restore.html",
  "origin": "https://docs.example.invalid/restore",
  "retrievedAt": "2026-01-15T12:01:00Z",
  "sha256": "<64 lowercase hex characters>",
  "availability": "frozen"
}
```

Use `availability: "unavailable"` with a reason when evidence cannot be captured. The
consumer decides whether a later source revision warrants a new audit.

### Supplemental evidence for deferrals

The baseline freeze is immutable. Evidence acquired during a deferral goes into a new
`freeze/supplements/<resolution-pass-id>/` directory. Record origin, retrieval time, SHA-256,
relationship to the frozen claim, and acquiring actor in append-only
`freeze/supplemental-evidence.jsonl`; then remove write permission from that supplement.
Append a matching `evidence.supplemented` event to `findings.jsonl` and include the supplement
in report provenance. Never overwrite `source-manifest.json` or a prior supplement.

A supplemental source may clarify the frozen artifact but cannot silently replace it. If the
only available source describes a newer implementation or specification, record that version
difference and treat it as supplemental rather than evidence of the frozen snapshot.

## Coverage schema

`coverage.json`:

```json
{
  "schemaVersion": 1,
  "passes": [
    {
      "id": "LP-01",
      "kind": "lens",
      "lenses": ["correctness", "internal consistency"],
      "question": "Do the artifact's claims agree with each other and primary evidence?",
      "evidenceScope": ["freeze/artifact", "freeze/worktrees/app"],
      "status": "complete"
    }
  ],
  "omittedLenses": ["compliance"],
  "reservedGeneralistRounds": 2
}
```

Keep omitted lenses to one list. The pass question and evidence scope are required.

## Ledger events

One compact JSON object per line. Required common fields:

- `schemaVersion`: `1`;
- `eventId`: unique append-order ID;
- `eventType`;
- `recordedAt`: UTC ISO-8601;
- `passId` and actor/session identity when applicable.

### Discovery

```json
{"schemaVersion":1,"eventId":"E-0001","eventType":"candidate.discovered","recordedAt":"2026-01-15T12:15:00Z","passId":"LP-01","candidateId":"CTA-0001","fingerprint":"correctness|artifact-section-4|retry-is-not-durable","claim":"The stated retry is not durable across process restart.","artifactLocations":["artifact.md:88"],"evidence":[{"kind":"code","location":"freeze/worktrees/app/src/retry.ts:42-61","summary":"Retry state exists only in process memory."}],"impact":"The recovery claim fails after restart.","proposedAdjustment":"Require a durable queue or narrow the claim.","severity":"high","material":true,"investigation":{"sourcesRead":["artifact.md","src/retry.ts"],"commandsOrTests":["targeted restart test"],"reproductions":["restart loses pending item"]}}
```

### Decision

```json
{"schemaVersion":1,"eventId":"E-0002","eventType":"candidate.decided","recordedAt":"2026-01-15T12:30:00Z","passId":"VP-01","candidateId":"CTA-0001","decision":"accepted","findingId":"F-0001","materialDelta":true,"reason":"The frozen implementation confirms process-local state and no durable resumer.","evidence":["freeze/worktrees/app/src/retry.ts:42-61"]}
```

Allowed decisions are `accepted`, `merged`, `deferred`, `rejected`, and `unverified`.
A deferred event also requires `missingEvidence`, `acquisitionAction`, `owner`, and
`expiresAfterResolutionPass`. A merged event requires `findingId` and whether it adds a
`materialDelta`.

A rejected event additionally requires:

- `disproof`: concrete counterevidence;
- `discoveryEffort`: copied discovery investigation record;
- `verificationEffort`: sources, commands/tests, and reproductions from the deep dive;
- `effortComparison`: why verification was at least as thorough;
- dedicated verifier pass/session identity.

The batch verifier emits `rejection_deep_dive_required`, not `rejected`. Only the resulting
dedicated pass may append a rejected decision.

### Configuration and run events

Use `config.changed`, `evidence.supplemented`, `pass.completed`, and `audit.terminated`
events. A supplemental-evidence event records its immutable directory, manifest-line ID,
origin, retrieval time, hash, and candidate ID. The terminal event records status, clean
streak, discovery rounds used, accepted material count, unverified count, and resume
instruction when applicable.

Validate every line before continuing:

```bash
python3 - "$RUN_ROOT/findings.jsonl" <<'PY'
import json
import pathlib
import sys

ledger_path = pathlib.Path(sys.argv[1])
for line_number, line in enumerate(ledger_path.read_text().splitlines(), start=1):
    try:
        json.loads(line)
    except json.JSONDecodeError as error:
        raise SystemExit(f"invalid JSONL at line {line_number}: {error}") from error
PY
```

## Subagent preflight and pass contracts

Before freezing inputs, verify the harness can launch fresh distinguishable subagent sessions
and automatically deliver completion. Configure children with a least-privilege profile that
excludes subagent/delegation, resume, write, and edit tools. Permit read/search/browser tools
and restricted shell inspection only as needed. Every child brief repeats the no-delegation
rule. If the harness cannot enforce separate sessions and exclude orchestration tools,
terminate `BLOCKED` rather than substituting tmux, polling, or watcher scripts.

### Preflight completion failure

Treat an acknowledged launch followed immediately by `Aborted while waiting for subagent to
finish`, with no child activity or new child turns, as a probable harness lifecycle failure—not
an artifact finding. Do not cycle through agents, models, working directories, or fork modes;
they share the same completion layer and repeated retries do not establish independence.

Use one bounded recovery path:

1. Preserve the exact wrapper error and whether any child activity/session turns exist. Do
   not inspect panes or add polling/watchers.
2. Ask the operator to run the harness's extension reload command (for Pi, `/reload`) or
   restart the parent process. An already-loaded faulty extension cannot repair itself from a
   file update until it reloads.
3. Run one fresh least-privilege preflight after reload/restart. If it fails again, terminate
   `BLOCKED` and record the execution-layer limitation without claiming a deeper cause the
   wrapper did not expose.

If failure happened before Phase 1, create a new audit ID after recovery and freeze fresh
inputs; never resume the pre-freeze `BLOCKED` run as though it had an evidence envelope. If a
later phase is interrupted, resume only from previously validated canonical state and record
the runtime interruption in provenance.

### Discovery brief

Include:

- frozen artifact and evidence paths;
- assigned lenses/question or `generalist residual review`;
- accepted-finding digest for novelty;
- remaining discovery-round budget;
- output fields from the discovery event;
- read-only and no-recursive-delegation rules;
- instruction to summarize checked scope when no candidate survives self-review.

Discovery returns candidates, not decisions. Persist the exact response, append one validated
`candidate.discovered` event per candidate to the canonical ledger, and only then launch
verification.

### Batch verifier brief

Use a fresh session. Include candidates, their full investigation records, frozen paths, and
accepted digest. Require candidate-by-candidate `ACCEPT`, `MERGE`, `DEFER`, or
`REJECTION_DEEP_DIVE_REQUIRED`. The verifier cannot reject in this batch.

### Rejection deep-dive brief

Use a fresh session for one candidate only. Include all discovery effort. Require direct
disproof, every cited source inspected, every reproduction repeated or invalidated, and equal
or broader evidence scope. If that bar is not met, return `ACCEPT` or `DEFER`.

### Deferral resolution brief

Use one pass only. Include the precise missing evidence and acquisition action. Finish as
accepted, merged, qualifying rejected, or unverified. Never return deferred.

## Novelty and streak rules

- Assign candidate IDs monotonically; never recycle IDs.
- Fingerprints assist matching but do not replace semantic comparison.
- Pure duplicate/corroboration merges into the existing finding without material delta.
- Broader scope or changed impact is a material delta only when it changes the required action
  or conclusion.
- Only a new accepted material finding or material merge delta resets `cleanStreak` to zero.
- Non-material acceptance and pure duplicate merge do not reset it.
- A deferred generalist round earns no clean credit and pauses the current streak. Its one
  resolution pass also earns no credit; it resets the streak only when it accepts a material
  finding or material merge delta.
- Convergence requires two clean-round credits from distinct generalist sessions with no
  accepted material finding between them. The credited rounds need not be adjacent to a
  deferral-resolution pass.

## Report template

```markdown
# <Artifact> — Convergent Technical Audit

## Executive verdict
- Status: CONVERGED | CAPPED_NOT_CONVERGED | BLOCKED
- Frozen snapshot: <manifest/SHA summary>
- Discovery rounds: <used>/<cap>
- Accepted material findings: <count>
- Unverified items: <count>

## Frozen scope
<artifact, revisions, baseline and supplemental evidence envelopes, exclusions, generated-at date>

## Coverage
<pass table>
Omitted lenses: <one line>

## Accepted findings
### [High|Medium|Low] <claim>
- Material: yes|no
- Artifact: <location>
- Evidence: <frozen citation>
- Impact: <why it matters>
- Adjustment: <change the artifact should make>

## Unverified items and limitations
<expired deferrals, missing evidence, and scope caveats>

## Provenance and stop reason
<pass sequence, distinct verifier sessions, rounds, exact rule>

## Appendix: rejected candidates
<candidate, affirmative disproof, discovery effort, verifier effort, comparison>
```

Generate this file from the complete canonical state: `config.json`,
`freeze/source-manifest.json`, `freeze/supplemental-evidence.jsonl`, `coverage.json`,
`status.json`, and `findings.jsonl`. Never silently omit accepted, unverified, or rejected
records.
