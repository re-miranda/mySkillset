Delegate from Claude Code to a Pi or Claude Code child through the canonical `tmux-subagents` workflow.

**Arguments:** `$ARGUMENTS` — `<pi|claude> <unique-name> <task description...>`

1. Require an explicit child runtime (`pi` or `claude`), a short name, and a non-empty task.
2. Load the `tmux-subagents` skill.
3. For `claude`, use Claude Code's native Agent tool and managed completion flow. Do not start a Pi helper or watcher.
4. For `pi`, follow the skill's Claude-to-Pi bridge reference exactly, including launch verification and the managed watcher.
5. Report which runtime and lifecycle owner were selected. Never substitute one runtime merely because the requested route is unavailable.
