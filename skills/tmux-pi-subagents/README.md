# tmux-pi-subagents

A Claude Code orchestration skill for delegating autonomous work to Pi in tmux split panes.

## When to use

Use when Claude should remain the decision-owning orchestrator while one or more Pi companions execute work independently.

Do not use for ordinary Pi-internal subagents, Claude-only `/spawn` windows, or environments without tmux.

## Communication contract

- Pi → Claude: file-only through per-run `result.md` and `question.md` paths.
- Claude → Pi: tmux only when a real reply is needed, using the recorded stable `%<pane-id>`, session-journal delivery verification, and pane captures as secondary evidence.
- Completion monitoring: the exact printed watcher command must run through Claude Code's managed background Bash execution.

Maintainer-only rejected examples live in [`references/KNOWN_FAILURES.md`](references/KNOWN_FAILURES.md). They must never enter generated Pi prompts.

## Install

From the repository root:

```bash
bash install.sh --skill tmux-pi-subagents
```

Optional tmux key configuration:

```bash
bash install.sh --skill tmux-pi-subagents --with-tmux
```

The installer copies the Claude skill, slash commands, and helper scripts into `~/.claude`, backing up conflicting files. Override the target for testing with `CLAUDE_HOME=/tmp/test-claude`.

## Validate

```bash
bash skills/tmux-pi-subagents/test.sh
```

The test can create an isolated temporary tmux session when run outside tmux. It covers installer upgrades, generated-prompt isolation, stable pane IDs, launch recovery, journal delivery verification, watcher signals, name reuse, and rejection of ambiguous targets.

## Files

- `SKILL.md` — runtime operating procedure.
- `scripts/` — spawn, watch, poll, and cleanup helpers.
- `integrations/claude/` — slash commands and global Claude addendum.
- `integrations/tmux/` — optional key-forwarding configuration.
- `references/KNOWN_FAILURES.md` — maintainer-only failure history.
- `install.sh` — idempotent skill installer.
- `test.sh` — standalone regression suite.
