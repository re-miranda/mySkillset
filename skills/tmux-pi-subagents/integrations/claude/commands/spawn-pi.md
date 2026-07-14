Spawn a Pi companion in a tmux split pane and start its file watcher.

**Arguments:** `$ARGUMENTS` — `<unique-name> <task description...>`

## Procedure

1. Parse the first word as `<name>` and the rest as `<task>`.
2. Require a unique name for every live Pi agent.
3. Choose thinking level:

| Task | Thinking |
|---|---|
| Architecture/design | `xhigh` |
| Implementation/tests | `high` |
| Research/investigation | `medium` |
| Quick lookup | `low` |

4. Spawn through the helper only:

```bash
$HOME/.claude/bin/spawn-pi-agent --thinking <level> <name> "<task>"
```

For a long task, use `--task-file` rather than typing into the Pi TUI.

5. Read the helper output. It includes stable `PANE=%<id>`, `RESULT=`, `QUESTION=`, and `WATCH=` values.
6. Run the exact `WATCH=` command with Claude Code's managed Bash background execution. Do not use a foreground wait or an unmanaged shell `&`.
7. Verify the Bash tool returned a background task handle. If it did not, report that the watcher was not started.
8. Tell the user the Pi name/pane and that `/poll <name>` is available for manual status.

## Watcher wake

- `SIGNAL=result`: read `RESULT_PATH`, synthesize, report.
- `SIGNAL=question`: read `QUESTION_PATH`; load the `tmux-pi-subagents` skill before replying so the recorded pane ID is validated and delivery is checked. Then start a new managed watcher.
- `SIGNAL=pane-died`: inspect and report the failed run.
- `SIGNAL=timeout`: report the timeout.

## Hard boundaries

- Start `pi`, not `claude`.
- Do not manually split panes.
- Do not type the initial task into Pi.
- Do not tell Pi to signal through tmux, `send-keys`, `/poll`, or Claude's pane.
- Do not infer pane targets from the current layout.
- Do not claim the watcher or a reply is working without tool evidence.
