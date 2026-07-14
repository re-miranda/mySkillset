Poll a Pi or Claude sub-agent by name or exact tmux pane ID.

**Arguments:** `$ARGUMENTS` — agent name or `%<pane-id>`

Run:

```bash
$HOME/.claude/bin/poll-pi-agent <name-or-pane-id>
```

The helper checks `result.md`, `question.md`, then the recorded live pane.

- `RESULT_READY=1`: synthesize the result and ask before cleanup.
- `QUESTION_PENDING=1`: read the question and load the `tmux-pi-subagents` skill before replying. It contains the only approved pane-resolution and delivery procedure.
- No file signal: summarize the captured progress; do not dump raw pane output.
- Missing/stale pane: report it. Do not guess another pane from the layout.

After a completed run, cleanup only with user confirmation:

```bash
$HOME/.claude/bin/cleanup-pi-agent --kill-pane <name>
```

Do not purge the preserved run directory unless explicitly requested.
