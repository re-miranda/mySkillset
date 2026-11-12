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
pi install git:github.com/re-miranda/pi-interactive-subagents@ae20d01024b4bf75a9536887d48f1e13649808b5
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
- The Claude-only marked routing block in regular `$PI_AGENT_DIR/AGENTS.md`, with a verified native `$CLAUDE_HOME/rules/AGENTS.md` alias

It recognizes every released legacy skill signature plus exact installer-generated backups. Retired `tmux-pi-subagents` trees are preserved under `backups/tmux-subagents/`, outside skill discovery roots; exact `/spawn-pi` and `/pi-subagents` files receive non-`.md` sibling backups. Ambiguous files or directories fail a complete destination preflight and remain unchanged. The retired Fable launcher is not installed or advertised by this workflow.

Instruction updates require Python 3.10+ (standard library), POSIX no-follow filesystem support an atomic rename-exchange (Linux `renameat2(RENAME_EXCHANGE)`, macOS `renameatx_np(RENAME_SWAP)`) and, for rollback of a newly created document or link, an atomic no-replace rename (Linux `renameat2(RENAME_NOREPLACE)`, macOS `renameatx_np(RENAME_EXCL)`). Whole-install preflight rejects missing prerequisites and collisions before any target writes. The helper updates the regular canonical document directly; it never writes through or replaces an existing alias. Unowned bytes, other producer blocks and existing owner/group/mode survive; current pairs retain mtimes and create no backups. New private documents/directories default to 0600/0700. No `CLAUDE.md`, import shim or duplicate legacy instruction output is generated.

Legacy instruction filenames are read-only review inputs. Exact current/previous marker pairs are recognized, but any new withdrawal still requires separately authorized fresh native loading proof; this installer stops unchanged rather than manufacturing that proof. Mixed user rules require a reviewed complete-content merge plan. Released skill/command migration fixtures and signatures remain supported independently.

Changed instructions have private journals under `$PI_AGENT_DIR/backups/tmux-subagents/instructions/`, outside discovery. Only ordinary instruction bytes and link metadata are retained, with verified holding/payload recovery. Explicit recovery is `python3 -B -I skills/tmux-subagents/scripts/instructions/cli.py rollback JOURNAL`; use it only with authority for those targets. It refuses concurrent edits.

Replacing an existing document swaps the staged file into place and then checks the displaced one. If that is not the preflighted file (a late in-place save or an editor's rename-over), it is swapped back and the run fails with nothing published; if the swap back fails, the document name holds the new installer content, the displaced version is kept at `.tmux-agents-conflict-<token>` beside it, and the error says both and names that path instead of claiming nothing was published. A failed directory sync after a good swap back is reported in the same error and does not change the path it names. If another save lands in the scratch file `.tmux-agents-<token>` during the swap (in place or by rename-over), that entry is kept and the error names its full path. Without swap support (kernel, platform or filesystem) the helper refuses and leaves the document untouched; there is no plain-rename fallback.

After publishing, the helper records the result only if the entry at the name is the file or link it staged (same device and inode, with the staged mtime and content). If a save took the name first, it stays in place, the run fails and nothing is recorded as installer output, so a later rollback refuses instead of overwriting it. Restored group, mode and mtime are set on the staged entry before it is published; nothing touches the name afterwards. Rollback removes a document or link it created by moving it to a scratch name without overwriting, checking the moved entry, and unlinking it only if it is the recorded one. Otherwise the entry is returned to its name; if the name was re-created meanwhile, both versions are kept, the moved one at `.tmux-agents-conflict-<token>`, and the error names both paths. Without no-replace rename support the removal refuses and leaves the entry untouched.

Residual risk: a program that opened an entry before one of our renames and writes through that descriptor after our check of that entry writes into a file we then remove, and that write is lost. Preventing it needs cooperative locking, which editors do not use.

Each document publish is atomic, not the entire installer: later skill/command failure can leave a partial install, reported with the instruction journal. Native/global precedence and linked-worktree acceptance require a separate authorized rollout; local fixture PASS is not that acceptance.

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

The suite covers AGENTS-only fixture creation, exact-byte preservation, alias/ownership/collision preflight, missing Python, no-op metadata, publication drift/failure, late in-place and rename-over saves during publish and rollback, unsupported or failing rename-exchange, and conditional holding/payload/link recovery; plus install convergence and policy downgrade, every released skill migration signature, backup-safe discovery, generated-prompt isolation, stable pane IDs, launch recovery, journal delivery verification, consumed watcher signals, stale-result re-arm and distinct second-round results, timeout handling, name reuse, and ambiguous-target rejection.

Pi 1.0.4 compatibility was checked with fresh offline startup from both repository roots, skill discovery and the companion regression suite. The companion's development config suppresses installed upstream/fork copies so the local extension loads without tool-name collisions. Automatic Pi-child completion waits for `agent_settled`, not a retryable `agent_end`. `interactive: true` controls parent stall nudges; keeping a Pi child open requires `auto-exit: false`. The bridge validation covers default Pi session storage; custom agent/session roots require separate delivery verification.

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
