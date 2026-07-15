---
name: rolling-code-audit
description: "Run one rotation of the standing Rolling code audit: score every area by staleness, review the stalest at origin/main, file findings as issues, and update the standing issue's table. Use when the user invokes /rolling-code-audit or asks to run the rolling audit. Do not use for reviewing a PR or the working diff."
compatibility: "Requires GitHub CLI (gh), authenticated GitHub access, and a fetchable origin remote."
metadata:
  version: "0.1.0"
  scope: local
---

# Rolling code audit — one rotation

State lives in the standing issue titled "Rolling code audit — standing review index"
(find it with `gh issue list --search '"Rolling code audit" in:title' --state open`).
That issue is never closed; areas are never done, they rotate.

## Procedure

1. **Sync**: `git fetch origin`. All scoring and review happens against `origin/main`;
   record `git rev-parse origin/main` as the review SHA.
2. **Load state**: `gh issue view <n> --json body` and parse the Areas table
   (paths are the backticked entries in each row).
3. **Score every area**:
   - never reviewed → score is infinite; among never-reviewed, lowest budget (highest risk) first
   - else `drift = git rev-list --count <lastSHA>..origin/main -- <paths>` and
     `age = days since last review`; **score = max(drift ÷ budget, age ÷ floor)**
   - ties go to the area with the lower budget
4. **Report the ranking** (top 3 with scores) and the pick before reviewing. If the top
   score is well below 1, say so — the user may prefer to spend tokens elsewhere — and
   continue only on confirmation. If the user named an area when invoking, review that one.
5. **Review the picked area** at the review SHA, scaled to drift:
   - previously reviewed → first read every file in `git diff --name-only <lastSHA>..origin/main -- <paths>`,
     then skim the rest of the area for cross-cutting issues
   - never reviewed → read the whole area
   - checklist (a floor, not a ceiling): correctness bugs; security (authz gaps, injection,
     secret handling, unsafe parsing, Firestore/storage rule mismatches); violations of
     CLAUDE.md principles; dead code; missing or assertion-free tests; dependency risks
   - **open mandate**: spend part of every review hunting for problem classes the checklist
     does not name — findings only a newer model would surface are the point of this audit.
     Flag any new class in the run log so a future `/rolling-code-audit-replan` can promote
     it into the checklist.
6. **Sizing guard**: if drift > 3× budget, or a never-reviewed area exceeds ~120 files,
   review the riskiest slice, record coverage as partial in Notes, and propose a split
   in the run log.
7. **Report findings** severity-ordered with `file:line` references, and say which
   deserve issues.
8. **Persist, with user confirmation** (preview every write):
   - one issue per confirmed finding, referencing the standing issue
   - a run-log comment on the standing issue: date, model id, area, review SHA, drift
     covered, coverage (full/partial), findings filed, new checklist classes
   - table row update via `gh issue edit <n> --body-file`: new Last-reviewed SHA + date, Notes
9. Never fix findings during a run; the audit only observes and files.

## Rules

- Read-only until step 8; every GitHub write is previewed and confirmed.
- If the standing issue is missing, stop and tell the user instead of creating one.
