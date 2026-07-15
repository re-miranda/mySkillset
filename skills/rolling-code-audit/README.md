# rolling-code-audit

A standing, never-finished code review: the codebase is partitioned into areas in a
standing GitHub issue, and each run reviews exactly one area — the stalest — then
rotates it back into the queue. Designed for manual, spare-capacity triggering: there
is no calendar, only a staleness score.

## The pattern

- **State** lives in a standing issue titled "Rolling code audit — standing review
  index" holding an area table: paths, drift budget (commits), age floor (days), and
  last-reviewed SHA/date. The issue is never closed; areas are never done.
- **Scoring:** `score = max(commits-since-review ÷ budget, days-since-review ÷ floor)`;
  a score ≥ 1 means overdue. Never-reviewed areas rank first, so the seed phase
  performs the complete initial review one rotation at a time.
- **Two commands, by design** (the replan command's own rules forbid growing this):
  - `/rolling-code-audit` — one rotation: score every area, review the stalest at
    `origin/main`, file findings as issues, update the table and run log. It observes
    and files only; it never fixes.
  - `/rolling-code-audit-replan` — run when a newer, more capable model is available
    than the issue's "Plan shaped by" stamp: it re-derives the partition, budgets, and
    checklist from scratch, then diffs the result against the current plan.
- Every rotation carries an **open mandate** to hunt for problem classes the checklist
  does not name; recurring new classes get promoted into the checklist by a replan.

## Install

```bash
bash install.sh            # installs both skills into ~/.claude/skills
bash install.sh --dry-run  # preview
```

## Bootstrap in a repository

Create the standing issue first — the audit command stops if it is missing. Adapt the
placeholder area table in
[`references/standing-issue.example.md`](references/standing-issue.example.md)
to the target repository.

## Validation

```bash
bash test.sh
```
