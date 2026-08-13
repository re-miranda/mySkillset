---
name: failure-we-fear-most
description: "Identify the single catastrophic failure a project should fear most, then define prevention, rapid detection, reliable recovery, and a pre-ship recovery test. Use when the user invokes /failure-we-fear-most or asks for a focused worst-case resilience review. Do not use for broad multi-finding audits or ordinary bug triage."
compatibility: "Works with Pi and Claude Code; repository inspection tools are recommended for evidence-backed use."
metadata:
  version: "0.1.0"
  scope: global
---

# Failure we fear most

Choose one credible, highest-consequence failure and make the system's resilience against it concrete.

## Procedure

1. Inspect the available architecture, persistence, destructive operations, deployment controls, recovery documentation, and relevant tests.
2. State the single failure in one precise sentence.
3. Explain why it outranks plausible alternatives, citing repository evidence when available.
4. Outline controls that prevent or sharply limit catastrophic damage.
5. Define signals and thresholds that detect the failure quickly.
6. Give a reliable, ordered recovery procedure with explicit recovery objectives where evidence supports them.
7. Design a pre-ship drill that destroys representative test data, restores it through the real recovery path, and verifies integrity and access.

## Output contract

Use these sections:

1. **Single failure we fear most**
2. **Why this outranks alternatives**
3. **Prevent catastrophic damage**
4. **Detect quickly**
5. **Recover reliably**
6. **Test recovery before shipping**
7. **Unverified assumptions and release gates**

## Rules

- Select exactly one top-level failure; supporting failure modes may only explain that choice.
- Distinguish repository evidence from provider-console or operational assumptions.
- Prefer measurable detection, RPO, RTO, integrity, and authorization checks over vague assurances.
- Treat backups as unverified until a real restore succeeds.
- Remain read-only unless the user separately asks for implementation.
