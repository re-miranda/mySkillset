<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->
# Tmux subagent routing

- Use `/tmux-subagents <pi|claude> <unique-name> <task>` for explicit delegation from Claude Code.
- Claude children use Claude Code's native Agent lifecycle. Pi children use the Claude-to-Pi bridge documented by the `tmux-subagents` skill.
- Run a Pi child's exact printed `WATCH=` command only as a managed background Bash task, and require a returned task handle before calling it active.
- Pi signals its Claude parent only through its assigned `result.md` or `question.md`. Never tell it to target Claude's pane.
- For a bridge reply, load `references/CLAUDE_TO_PI_BRIDGE.md` from the skill and use only its verified stable-pane procedure.
- Never choose a pane by layout, focus, coordinates, or title. Use the recorded `%<id>` and verify it before capture, send, or cleanup.
- Treat the active harness as the orchestrator; a child runtime is not determined by its model provider.
<!-- END TMUX-SUBAGENTS-WORKFLOW -->
