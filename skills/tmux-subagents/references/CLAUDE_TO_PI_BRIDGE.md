# Claude-to-Pi Bridge

Load this runtime reference only when Claude Code is the parent and Pi is the child. Pi parents and Claude Code children use their native lifecycle instead.

## Launch

1. Run `$HOME/.claude/bin/spawn-pi-agent <name> "<task>"` with a unique live name.
2. Confirm the output contains `LAUNCH=ok`; stop and report if launch verification fails.
3. Start the exact printed `WATCH=` command with Claude Code's managed background Bash execution.
4. Confirm the Bash tool returned a background task handle before saying the watcher is active.
5. Wait for `SIGNAL=result`, `SIGNAL=question`, `SIGNAL=pane-died`, or `SIGNAL=timeout`.
6. Use `$HOME/.claude/bin/poll-pi-agent <name>` only for an explicit manual status check.

For a long task, use the spawner's `--task-file` option instead of typing into Pi's TUI.

## File-only Pi signaling

Pi writes one assigned path:

- `result.md` when finished.
- `question.md` when blocked.

Pi must not target Claude's pane or invent another signaling mechanism. On watcher wake:

- `result`: read `RESULT_PATH`, validate the work, synthesize, and report.
- `question`: read `QUESTION_PATH`, decide, reply through the verified procedure below, then start a new managed watcher.
- `pane-died`: inspect the run files and report the crash.
- `timeout`: report that no file signal arrived.

## Stable Claude-to-Pi replies

Reply only for a real question or explicit follow-up. Resolve the pane from the unique agent name; never infer it from layout, focus, coordinates, or title.

```bash
name='<agent-name>'
pane=$(tr -d '[:space:]' < "/tmp/claude-agents/$name.pane")
case "$pane" in %*) ;; *) echo "invalid pane mapping: $pane" >&2; exit 1 ;; esac
resolved=$(tmux display-message -t "$pane" -p '#{pane_id}')
[ "$resolved" = "$pane" ] || { echo "stale pane mapping: $pane" >&2; exit 1; }
tmux capture-pane -t "$pane" -p -S -12
```

After that preflight, send one short plain-ASCII reply:

```bash
tmux send-keys -t "$pane" -X cancel 2>/dev/null || true
tmux send-keys -t "$pane" -l '<reply>'
sleep 1
tmux send-keys -t "$pane" Enter
sleep 1
tmux capture-pane -t "$pane" -p -S -12
```

Use the unmodified `Enter` key. End the reply in plain words so path or command completion is closed when Enter arrives.

Confirm delivery from Pi's session journal:

```bash
$HOME/.claude/bin/verify-pi-delivery "$name" --marker '<distinctive reply substring>' --timeout 20
```

Do not claim delivery without `DELIVERY=ok`. If it reports `DELIVERY=failed`, send only the unmodified `Enter` key once more and repeat the journal check. Stop and report the failure with its `JOURNAL=` path if the second check misses. Never resend the literal reply or try another pane.

For a long reply, write a file and send only `Read <absolute-path> and act on it.` through the same procedure.

## Multiple bridge children

Use a unique name, pane mapping, run directory, and watcher command for every live Pi child. Never reuse one child's mapping or watcher for another.
