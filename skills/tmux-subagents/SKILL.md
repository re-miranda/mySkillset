---
name: tmux-subagents
description: Delegate work from either Pi or Claude Code to Pi- or Claude-backed subagents using the active harness's native lifecycle and managed terminal surfaces. Use for subagent, companion-agent, parallel delegation, reviewer, scout, worker, or split-pane requests.
license: 0BSD
compatibility: Requires Claude Code and/or Pi. Pi orchestration requires pi-interactive-subagents; Claude children require its auto-permissions-v1 capability and Claude Auto-mode support. The Claude-to-Pi bridge additionally requires Pi, tmux, and Bash.
metadata:
  version: "2.0.4"
---

# Tmux Subagents

## Route by orchestrator and child runtime

Treat the parent harness and child runtime as separate choices. An Anthropic model running inside Pi is still a Pi child; only an agent definition with `cli: claude` starts Claude Code.

| Orchestrator | Child | Lifecycle owner |
|---|---|---|
| Pi | Pi or Claude Code | Pi's `subagent` extension |
| Claude Code | Claude Code | Claude Code's native Agent tool |
| Claude Code | Pi | Claude-to-Pi bridge |

Honor an explicit runtime request. If the child runtime is ambiguous and changes routing, ask before spawning. Never mix lifecycle mechanisms for one child.

## Pi as orchestrator

1. Use `subagents_list` when the requested role or runtime is not already known.
2. Call `subagent` with a unique display name, a focused task, and the narrowest suitable agent definition.
3. A definition without `cli: claude` starts Pi. A Claude Code child requires an available definition that explicitly contains `cli: claude`; never infer the CLI from its model name.
4. Use parallel calls only for independent work.
5. After spawning, end the turn or continue unrelated work. The extension delivers completion automatically; never poll logs, session files, or panes.
6. Use `interactive: true` to suppress parent stall nudges for user-driven children; it does not disable auto-exit. To keep a Pi child open, select an agent with `auto-exit: false`. Claude Code children start in Auto mode with classifier-based permission checks; keep remaining approval prompts interactive and never bypass permissions.
7. Validate a child's result before reporting completion or applying consequential recommendations.

Do not call the Claude-to-Pi bridge from a Pi parent. The extension owns surface creation, delivery, resumption, and status.

## Claude Code as orchestrator

### Claude Code child

Use Claude Code's native Agent tool and its managed completion flow. Do not start the Pi bridge, watcher, or Pi polling helpers for a Claude child. Do not promise a tmux pane unless the native tool reports one.

### Pi child

Read [Claude-to-Pi bridge](references/CLAUDE_TO_PI_BRIDGE.md) before launching, polling, or replying. That reference is the only runtime recipe for the file/watcher bridge.

## When this session is itself a child

Injected child instructions take precedence over the parent routes above. In particular, a Pi launched by the Claude-to-Pi bridge must write only to its assigned result or question path and must not target its parent pane or start another bridge unless the parent explicitly delegates that authority.

## Maintenance

Before changing routing, pane addressing, or delivery behavior, read [Known failures and rejected patterns](references/KNOWN_FAILURES.md). Its negative examples are regression evidence and must never enter generated child prompts.
