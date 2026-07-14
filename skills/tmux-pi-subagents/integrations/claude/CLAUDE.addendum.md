<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->
# Claude ↔ Pi tmux workflow

- Use `/spawn-pi <unique-name> <task>` for Pi work. Do not use `/spawn` or manually create the pane.
- After spawning, run the exact printed `WATCH=` command as a managed background Bash task. Verify the tool returned a background task handle before calling the watcher active.
- Pi signals Claude only through `result.md` or `question.md`. Never tell Pi to use tmux, `send-keys`, `/poll`, or Claude's pane.
- For a Pi reply, load the `tmux-pi-subagents` skill and follow its single verified Claude → Pi delivery procedure.
- Never choose a pane by layout, active pane, index, or title. Use the `%<id>` stored in `/tmp/claude-agents/<name>.pane`, validate it, capture before sending, and capture after submission.
- Do not claim a reply was delivered until the post-send capture shows submission or Pi activity.
- Claude owns consequential decisions; Pi supplies execution and recommendations.
<!-- END CLAUDE-PI-TMUX-WORKFLOW -->
