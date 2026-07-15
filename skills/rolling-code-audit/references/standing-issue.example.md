# Standing issue template

Maintainer reference: bootstrap material for adopting this skill pair in a new
repository — the audit command intentionally refuses to create the standing issue
itself. Copy the body below into a new issue titled
"Rolling code audit — standing review index", replace the placeholder area table with
a partition of the target repository (every tracked source path in exactly one area;
lockfiles excluded so dependency-only commits do not inflate drift), fill in the
provenance stamp, and keep every row at never-reviewed so the seed phase performs the
complete initial review.

---

Standing index for the rolling code audit. This issue is never closed — areas are never "done", they rotate. Each run of `/rolling-code-audit` picks the stalest area, reviews it at `origin/main`, files findings as separate issues, and updates the table below plus a run-log comment. Runs only observe and file; they never fix.

## Cadence model

There is no calendar. Per area: **score = max(commits-since-last-review ÷ budget, days-since-last-review ÷ floor)**. Score ≥ 1 means overdue. Never-reviewed areas rank first (lowest budget first), so the seed phase performs the complete initial review one rotation at a time. Trigger a rotation whenever spare capacity exists; the score answers both "what's next" and "was it urgent". Budgets and floors are seeded guesses — tune them by editing the table; cadence is data here, not code.

## Plan provenance

Plan shaped by `<model-id>` on `<YYYY-MM-DD>`. The review method is bounded by the capability of the model that designed it — when a newer, more capable model is available, run `/rolling-code-audit-replan` so it can re-derive the partition, budgets, and checklist from scratch and diff the result against this plan. Keep exactly two commands: audit and replan.

## Areas

| Area | Paths | Budget (commits) | Floor (days) | Last reviewed SHA | Last reviewed date | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Payments & auth | `<payments module>`, `<auth module>`, `<billing UI>` | 15 | 90 | — | never | tightest budget: money and identity |
| Core domain | `<primary domain modules>` | 25 | 180 | — | never | split when it exceeds ~120 files |
| Jobs & integrations | `<cron/queue workers>`, `<third-party integration wrappers>` | 25 | 180 | — | never | |
| Product UI | `<feature UI directories>` | 30 | 180 | — | never | |
| Shared libraries & app shell | `<shared utils/components>`, `<app entry>` | 40 | 180 | — | never | |
| Platform & tooling | `<build and CI configs>`, `<scripts>`, `<agent instructions>` | 50 | 365 | — | never | lockfiles excluded by design |

## Out of scope

- Prose documentation — run a separate one-shot docs audit if needed.
- Fixing findings — runs file issues; fixes happen through the normal issue workflow.

## Run log

Each rotation appends a comment: date, model id, area, review SHA, drift covered, coverage (full/partial), findings filed, new checklist classes.
