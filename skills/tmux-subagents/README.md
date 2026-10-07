# tmux-subagents

A harness-neutral delegation skill for Pi and Claude Code. Either harness can be the orchestrator, and each route uses the lifecycle mechanism native to that parent.

## Routing model

| Orchestrator | Child | Route |
|---|---|---|
| Pi | Pi or Claude Code | `pi-interactive-subagents` |
| Claude Code | Claude Code | Native Agent tool |
| Claude Code | Pi | File/watcher bridge |

The watcher is not the generic protocol. It is a private adapter for the one route where Claude Code launches a Pi process.

A Pi agent using an Anthropic model remains a Pi process. Pi starts Claude Code only when the selected agent definition explicitly declares `cli: claude`.

## Install

The Pi extension companion is tracked at [`../../extensions/pi-interactive-subagents`](../../extensions/pi-interactive-subagents). The pinned revision includes the `auto-permissions-v1` launch contract and Pi 1.0.4 settlement/shortcut regressions.

Install the matching pinned revision:

```bash
git submodule update --init --recursive
pi install git:github.com/re-miranda/pi-interactive-subagents@526b22488be398fda60795bd6b8a09701b6fe147
```

Then install the skill from the repository root:

```bash
bash install.sh --skill tmux-subagents
```

The installer converges both first-class targets by default:

- `~/.claude/skills/tmux-subagents`
- `~/.pi/agent/skills/tmux-subagents`
- Pi's `claude-code` child definition when the installed extension passes the executable `auto-permissions-v1` capability probe
- Claude's canonical `/tmux-subagents` command
- Claude-to-Pi bridge helpers
- The marked Claude routing block

It recognizes every released legacy skill signature plus exact installer-generated backups. Retired `tmux-pi-subagents` trees are preserved under `backups/tmux-subagents/`, outside skill discovery roots; exact `/spawn-pi` and `/pi-subagents` files receive non-`.md` sibling backups. Ambiguous files or directories fail a complete destination preflight and remain unchanged. The retired Fable launcher is not installed or advertised by this workflow.

Optional tmux key configuration:

```bash
bash install.sh --skill tmux-subagents --with-tmux
```

Override targets during tests with `CLAUDE_HOME=/tmp/test-claude` and `PI_AGENT_DIR=/tmp/test-pi`. Override extension discovery with `PI_SUBAGENT_EXTENSION_DIR=/path/to/pi-interactive-subagents`; otherwise the installer checks Pi's local-package checkout and the known GitHub package checkouts.

**Restart required:** after installation or migration, open fresh Pi and Claude Code parent sessions so they load the new skill and commands. Existing agent panes are retained only for inspection; do not reuse their loaded workflow.

## Safety

- Pi parents use the extension; they never call Claude's watcher bridge.
- Claude parents use the native Agent tool for Claude children.
- Only Claude-to-Pi uses `result.md`, `question.md`, and the managed watcher.
- Claude children launched from Pi request `--permission-mode auto`: classifier-based approvals, not `bypassPermissions`. Remaining permission prompts stay interactive. The installer probes the truthful `auto-permissions-v1` contract and archives its managed child definition if the extension is stale or the arguments no longer match.
- Auto mode still requires support from Claude Code, the selected model and account policy; Claude may fall back to Manual when unavailable. Never work around that by disabling permission checks.
- Existing Pi parents retain loaded launch code until reload/restart; existing Claude children keep their current mode. Do not interrupt running work just to change the default.
- Stable `%<pane-id>` mappings are mandatory for the rare Claude-to-Pi reply.

Maintainer-only failures live in [`references/KNOWN_FAILURES.md`](references/KNOWN_FAILURES.md) and must never enter a child prompt.

## Validate

```bash
bash skills/tmux-subagents/test.sh
```

The suite covers install convergence and policy downgrade, every released migration signature, backup-safe discovery, atomic collision preflight, file-mode preservation, generated-prompt isolation, stable pane IDs, launch recovery, journal delivery verification, consumed watcher signals, stale-result re-arm and distinct second-round results, timeout handling, name reuse, and ambiguous-target rejection.

Pi 1.0.4 compatibility was checked with fresh offline startup, skill discovery and the companion regression suite. Automatic Pi-child completion waits for `agent_settled`, not a retryable `agent_end`. `interactive: true` controls parent stall nudges; keeping a Pi child open requires `auto-exit: false`. The bridge validation covers default Pi session storage; custom agent/session roots require separate delivery verification.

## Files

- `SKILL.md` — shared runtime router.
- `references/CLAUDE_TO_PI_BRIDGE.md` — private adapter procedure.
- `scripts/` — Claude-to-Pi bridge helpers.
- `integrations/claude/` — Claude command and routing addendum.
- `integrations/tmux/` — optional key-forwarding configuration.
- `references/KNOWN_FAILURES.md` — maintainer-only regression history.
- `references/legacy/` — exact migration signatures and unsupported historical regression fixtures.
- `install.sh` — convergent installer for both harnesses.
- `test.sh` — standalone regression suite.
