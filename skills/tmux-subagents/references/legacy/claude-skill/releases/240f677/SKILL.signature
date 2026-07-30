---
name: tmux-pi-subagents
description: Delegate work from Claude Code to Pi in tmux split panes. Use for Pi companions, Pi subagents, or tmux split-agent requests. Spawns Pi with /spawn-pi, starts the printed watcher as a managed background Bash task, and uses stable recorded pane IDs for the rare Claude-to-Pi reply.
license: 0BSD
compatibility: Requires Claude Code, Pi, tmux, and Bash. The optional tmux key configuration needs tmux 3.5 or newer for CSI-u format.
metadata:
  version: "1.2.1"
---

# Tmux Pi Subagents

## One workflow only

1. Run `$HOME/.claude/bin/spawn-pi-agent <name> "<task>"`.
2. Confirm the spawn output contains `LAUNCH=ok`; stop and report if launch verification fails.
3. Start the exact printed `WATCH=` command with Claude Code's managed Bash background execution.
4. Confirm the Bash tool returned a background task handle before saying the watcher is active.
5. Wait for `SIGNAL=result`, `SIGNAL=question`, `SIGNAL=pane-died`, or `SIGNAL=timeout`.
6. Use `$HOME/.claude/bin/poll-pi-agent <name>` only for a manual status check.

Do not use `/spawn`; it starts Claude rather than Pi. Do not manually create panes for this workflow.

## Pi signaling is file-only

Pi writes one of these paths:

- `/tmp/claude-agents/<name>.result.md` — finished.
- `/tmp/claude-agents/<name>.question.md` — blocked.

Pi must never target Claude's pane, run `tmux send-keys`, or type `/poll`. The generated Pi `system.md` and `brief.md` contain this rule. Do not send Pi any contradictory signaling instructions in the task.

On watcher wake:

- `result`: read `RESULT_PATH`, synthesize, report.
- `question`: read `QUESTION_PATH`, decide, reply to that Pi, then start a new managed watcher.
- `pane-died`: inspect the run files and report the crash.
- `timeout`: report that no file signal arrived.

## Stable pane routing for Claude → Pi replies

Only reply to Pi when handling a real question or explicit follow-up. Never infer a target from pane order, active pane, window layout, title, or `tmux display-message` without `-t`.

Resolve and verify the pane by agent name:

```bash
name='<agent-name>'
pane=$(tr -d '[:space:]' < "/tmp/claude-agents/$name.pane")
case "$pane" in %*) ;; *) echo "invalid pane mapping: $pane" >&2; exit 1 ;; esac
resolved=$(tmux display-message -t "$pane" -p '#{pane_id}')
[ "$resolved" = "$pane" ] || { echo "stale pane mapping: $pane" >&2; exit 1; }
tmux capture-pane -t "$pane" -p -S -12
```

Only after that preflight, send one short plain-ASCII reply:

```bash
tmux send-keys -t "$pane" -X cancel 2>/dev/null || true
tmux send-keys -t "$pane" -l '<reply>'
sleep 1
tmux send-keys -t "$pane" Enter
sleep 1
tmux capture-pane -t "$pane" -p -S -12
```

Use the unmodified `Enter` key only; Ctrl-modified or alternate Enter variants are not submission keys in Pi's enhanced-keyboard TUI. Keep the delay between literal text and Enter so the composer can settle. End every reply in plain words, such as `Read <path> and act on it.`, so no path or command autocomplete is open when Enter arrives.

Confirm delivery from Pi's session journal; the pane capture is secondary forensic evidence only:

```bash
$HOME/.claude/bin/verify-pi-delivery "$name" --marker '<distinctive reply substring>' --timeout 20
```

Do not claim delivery without `DELIVERY=ok`. On `DELIVERY=failed`, send the unmodified `Enter` key once more, run the same journal check again, and then stop and report the failed delivery with its `JOURNAL=` path if it still misses. Never retry the literal reply or target another pane.

For long replies, write a file and send only `Read <absolute-path> and act on it.` through the same verified procedure.

## Multiple agents

Use a unique name for every live agent. Repeat spawn plus managed watcher once per name. Never reuse one agent's pane mapping or watcher command for another.

## Maintenance only

When asked to modify this workflow, first read [Known failures and rejected patterns](references/KNOWN_FAILURES.md). Do not load that reference during normal delegation; its bad snippets are regression evidence, not instructions.
