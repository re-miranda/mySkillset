# convergent-technical-audit

A bounded, evidence-backed audit workflow for technical plans, designs, specifications,
procedures, migrations, reports, and comparable artifacts.

The skill freezes its inputs, runs applicable review lenses sequentially, independently
verifies every candidate through a conservative acceptance-biased gate, and then runs two
clean generalist rounds. It produces a Markdown report and append-only JSONL finding ledger;
it never rewrites the audited artifact.

## Distinctive guarantees

- Exact Git SHA plus approved non-secret dirty state in a dedicated read-only worktree.
- Name-first secret screening before tracked or untracked dirty content is captured.
- Durable resumable state outside `/tmp` and outside the audited repository.
- Sequential discovery for reliable novelty checks.
- Cheap batched acceptance/merge, but candidate-level deep disproof before rejection.
- One-round-only deferral that becomes resolved or visibly unverified.
- Material findings alone reset the two-clean-round streak.
- Honest `CONVERGED`, `CAPPED_NOT_CONVERGED`, and `BLOCKED` outcomes.
- Preflighted native harness subagents with least-privilege tools, no recursive delegation,
  and no watcher polling.

## Install

```bash
bash install.sh            # install for Pi and Claude Code
bash install.sh --dry-run  # preview both targets
bash install.sh --target pi
bash install.sh --target claude
```

Environment overrides:

- `PI_HOME` (default `~/.pi/agent`)
- `CLAUDE_HOME` (default `~/.claude`)

## Validate

```bash
bash test.sh
```

## Runtime outputs

Canonical audit state defaults to:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/agent-audits/convergent-technical-audit/<audit-id>/
```

The two canonical deliverables are `report.md` and `findings.jsonl`. Optional HTML is a
disposable rendering of those files.
