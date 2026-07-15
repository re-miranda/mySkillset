---
name: rolling-code-audit-replan
description: "Re-derive the Rolling code audit plan itself — partition, budgets, scoring, checklist — typically when a newer, more capable model than the one stamped in the standing issue is available. Use when the user invokes /rolling-code-audit-replan or asks to review or upgrade the audit plan. Do not use to run an audit rotation."
compatibility: "Requires GitHub CLI (gh), authenticated GitHub access, and a fetchable origin remote."
metadata:
  version: "0.1.0"
  scope: local
---

# Rolling code audit — replan

The audit plan is bounded by the capability of the model that shaped it. This command
exists so a newer model can improve the plan itself, not just execute it. State lives in
the standing issue titled "Rolling code audit — standing review index".

## Procedure

1. **Check provenance**: read the "Plan shaped by" stamp in the standing issue. If the
   current model is the same or older than the stamp, say so — a replan is unlikely to
   add value — and continue only on explicit confirmation.
2. **Derive independently first**: before re-reading the existing plan in detail, survey
   the repo fresh — `git ls-files` distributions, 90-day churn
   (`git log --since=90.days --name-only --pretty=format:`), open issues, CLAUDE.md —
   and sketch the partition, budgets, scoring, and review checklist you would design
   from scratch. Anchoring on the old plan defeats the purpose of this command.
3. **Then diff against the current plan**: the standing issue body, its run-log comments,
   and both SKILL.md files. Pay special attention to "new checklist class" flags in run
   logs — promote recurring ones into the checklist.
4. **Propose changes** with rationale: area splits/merges, budget/floor retuning, scoring
   formula, checklist additions and removals, issue format, and edits to either skill.
   Unchanged areas keep their Last-reviewed SHA; split areas inherit the parent's SHA so
   review history is never reset.
5. **Apply, with user confirmation**: update the issue body (new "Plan shaped by" model id
   and date), edit both commands' SKILL.md files in the location this project loads
   them from (the project's skills directory, or `~/.claude/skills` for a global
   install), and leave a replan comment on the issue summarizing what changed and why.

## Rules

- Keep exactly two commands: audit and replan. Reject changes that add process without
  adding findings — over-engineering is the failure mode this rule guards against.
- Never close the standing issue or discard run-log history; provenance and run logs are
  the audit's memory.
- Every GitHub write and file edit is previewed and confirmed.
