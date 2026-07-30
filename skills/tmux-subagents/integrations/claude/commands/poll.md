Poll a Pi child launched through the Claude-to-Pi bridge.

**Arguments:** `$ARGUMENTS` — bridge-agent name or exact `%<pane-id>`

Run:

```bash
$HOME/.claude/bin/poll-pi-agent <name-or-pane-id>
```

The helper checks `result.md`, `question.md`, then the recorded live pane.

- `RESULT_READY=1`: validate and synthesize the result, then ask before cleanup.
- `QUESTION_PENDING=1`: read the question and load the `tmux-subagents` skill's Claude-to-Pi bridge reference before replying.
- No file signal: summarize captured progress without dumping raw pane output.
- Missing or stale pane: report it; never guess another target from the layout.

After a completed bridge run, clean up only with user confirmation:

```bash
$HOME/.claude/bin/cleanup-pi-agent --kill-pane <name>
```

Do not use `/poll` for native Claude agents or Pi-extension children; their parent harness owns status and completion. Do not purge a preserved run directory unless explicitly requested.
