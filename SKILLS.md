# Skill catalog

This is the authoritative root-level guide to the skills in this repository.

## How to choose a skill

1. Match the task to the **When to use** description.
2. Read that skill's `SKILL.md` before acting.
3. Load references only when `SKILL.md` directs you to them.
4. Do not combine two skills with conflicting routing or safety rules without asking the user.

## Available skills

### `ai-memory-vps-bootstrap`

- **Path:** [`skills/ai-memory-vps-bootstrap`](skills/ai-memory-vps-bootstrap/)
- **Purpose:** Converge an installed native ai-memory binary and existing authoritative data into a minimal loopback-only Pi-on-VPS user service, then verify the security and persistence invariants.
- **When to use:** Bootstrapping or accepting a single-user Linux VPS where ai-memory state already exists and the initial topology must remain `127.0.0.1:49374` with fresh local bearer authentication.
- **When not to use:** State migration, spool draining, credential rotation, remote exposure, provider setup, Claude wiring, live restore, or destructive cleanup.
- **Installs:** One operational skill, two guarded scripts, and a hardened service template for Pi and Claude Code; the installer never executes the VPS bootstrap.
- **Validation:** `bash skills/ai-memory-vps-bootstrap/test.sh`
- **Safety:** Preview by default; apply requires an explicit flag; existing incompatible files fail closed; config generation uses isolated temporary state; tokens are never printed or placed in curl arguments; network bind is fixed to loopback.

### `convergent-technical-audit`

- **Path:** [`skills/convergent-technical-audit`](skills/convergent-technical-audit/)
- **Purpose:** Audit a frozen technical artifact through sequential lens passes, conservative independent verification, and two clean generalist rounds, producing a Markdown report plus append-only JSONL ledger.
- **When to use:** Evidence-backed audits of technical plans, designs, specifications, procedures, migrations, reports, or comparable artifacts where one-pass review is insufficient.
- **When not to use:** PR or working-diff review, implementation, rewriting the source artifact, or a quick one-pass opinion.
- **Installs:** One portable skill plus its schema reference for both Pi and Claude Code.
- **Validation:** `bash skills/convergent-technical-audit/test.sh`
- **Safety:** Source artifact stays read-only; likely secret paths are excluded before dirty content capture; state is durable and private outside `/tmp` and the audited repository; discovery is sequential through preflighted least-privilege subagents with no recursive delegation; rejection requires affirmative disproof from a dedicated deep dive at least as thorough as discovery.

### `failure-we-fear-most`

- **Path:** [`skills/failure-we-fear-most`](skills/failure-we-fear-most/)
- **Purpose:** Select one credible catastrophic failure and turn it into concrete prevention, rapid detection, reliable recovery, and pre-ship recovery testing.
- **When to use:** `/failure-we-fear-most`, focused worst-case resilience reviews, or requests to identify the one failure a project should fear most.
- **When not to use:** Broad multi-finding audits, ordinary bug triage, or implementation work.
- **Installs:** One shared skill for Pi and Claude Code, Pi's `/failure-we-fear-most` prompt template, and Claude Code's `/failure-we-fear-most` command.
- **Validation:** `bash skills/failure-we-fear-most/test.sh`
- **Safety:** Read-only unless implementation is requested separately; exactly one top-level failure; operational assumptions stay explicitly unverified until tested.

### `tmux-subagents`

- **Path:** [`skills/tmux-subagents`](skills/tmux-subagents/)
- **Purpose:** Let Pi or Claude Code orchestrate Pi- or Claude-backed children through harness-native lifecycle adapters.
- **When to use:** Subagent, companion-agent, parallel delegation, reviewer, scout, worker, or split-pane requests where either harness may own the parent role.
- **When not to use:** Environments without the selected harness integration, or attempts to mix two lifecycle mechanisms for one child.
- **Installs:** The shared skill for both Pi and Claude, Pi's `claude-code` child definition only while the extension passes the `manual-permissions-v1` probe, Claude's canonical `/tmux-subagents` and bridge-only `/poll` commands, Claude-to-Pi helper scripts, a marked Claude routing block, and optional tmux key settings.
- **Communication:** Pi parents use the interactive-subagents extension; Claude parents use native Agents for Claude children and the file/watcher bridge only for Pi children.
- **Validation:** `bash skills/tmux-subagents/test.sh`
- **Maintainer warning:** Read `references/KNOWN_FAILURES.md` before changing routing or signaling. Its rejected examples must never enter generated child prompts.

### `rolling-code-audit`

- **Path:** [`skills/rolling-code-audit`](skills/rolling-code-audit/)
- **Purpose:** Maintain a standing, never-finished codebase review: score areas by staleness from a standing GitHub issue, review only the stalest area per run, file findings as issues, and rotate.
- **When to use:** Spare-capacity moments to run one audit rotation (`/rolling-code-audit`), or when a newer model than the plan's "Plan shaped by" stamp should re-derive the plan itself (`/rolling-code-audit-replan`).
- **When not to use:** Reviewing a PR or working diff, fixing findings, or repositories without the standing "Rolling code audit — standing review index" issue — bootstrap it from `references/standing-issue.example.md` first.
- **Installs:** Two Claude skills: `~/.claude/skills/rolling-code-audit` and `~/.claude/skills/rolling-code-audit-replan`.
- **Validation:** `bash skills/rolling-code-audit/test.sh`
- **Safety:** All GitHub writes are previewed and user-confirmed; runs never fix code and never close or create the standing issue; the replan command must keep the system at exactly two commands.

## Catalog entry requirements

Every new skill must add an entry containing:

- **Name and path**
- **Purpose**
- **When to use**
- **When not to use**
- **What it installs or changes**
- **Validation command**
- **Important safety constraints**
