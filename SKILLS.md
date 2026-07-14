# Skill catalog

This is the authoritative root-level guide to the skills in this repository.

## How to choose a skill

1. Match the task to the **When to use** description.
2. Read that skill's `SKILL.md` before acting.
3. Load references only when `SKILL.md` directs you to them.
4. Do not combine two skills with conflicting routing or safety rules without asking the user.

## Available skills

### `tmux-pi-subagents`

- **Path:** [`skills/tmux-pi-subagents`](skills/tmux-pi-subagents/)
- **Purpose:** Let Claude Code orchestrate one or more Pi companions in tmux split panes while Claude retains consequential decisions.
- **When to use:** Requests to delegate through Pi, spawn Pi companions, or run split-pane Pi agents with automatic completion/blocker notification.
- **When not to use:** Pi's own internal subagent extension, Claude-only `/spawn` windows, or environments without tmux.
- **Installs:** Claude skill, `/spawn-pi` and `/poll` commands, spawn/watch/poll/cleanup scripts, a marked global Claude protocol block, and optional tmux key settings.
- **Communication:** Pi writes `result.md` or `question.md`; only Claude may send a necessary tmux reply after validating the recorded stable `%<pane-id>`.
- **Validation:** `bash skills/tmux-pi-subagents/test.sh`
- **Maintainer warning:** Read `references/KNOWN_FAILURES.md` before changing routing or signaling. Its rejected examples must never enter generated Pi prompts.

## Catalog entry requirements

Every new skill must add an entry containing:

- **Name and path**
- **Purpose**
- **When to use**
- **When not to use**
- **What it installs or changes**
- **Validation command**
- **Important safety constraints**
