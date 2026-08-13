# failure-we-fear-most

A focused resilience-review skill and matching slash command for Pi and Claude Code.

## When to use

Use it when a project needs one worst-case failure selected and analyzed through prevention, rapid detection, reliable recovery, and a real pre-ship recovery drill.

Do not use it for broad audits, ordinary bug triage, or requests that require a list of unrelated findings.

## Install

From the repository root:

```bash
bash install.sh --skill failure-we-fear-most
```

This installs:

- `~/.pi/agent/skills/failure-we-fear-most/SKILL.md`
- `~/.pi/agent/prompts/failure-we-fear-most.md`
- `~/.claude/skills/failure-we-fear-most/SKILL.md`
- `~/.claude/commands/failure-we-fear-most.md`

Override destinations during testing with `PI_AGENT_DIR` and `CLAUDE_HOME`.

## Use

In either Pi or Claude Code:

```text
/failure-we-fear-most
```

The shared command preserves the original prompt exactly:

> Identify the single failure we fear most. Then outline how to prevent catastrophic damage, detect it quickly, recover reliably, and test that recovery before shipping.

Start a fresh agent session after installation so skill discovery reloads.

## Validate

```bash
bash skills/failure-we-fear-most/test.sh
```

The test checks the exact prompt, metadata, shell syntax, isolated installation, idempotence, conflict backups, dry-run behavior, and atomic destination preflight.
