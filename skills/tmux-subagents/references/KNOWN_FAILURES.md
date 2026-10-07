# Known failures and rejected patterns

> Maintainer-only regression reference. The snippets marked **BAD** are evidence from failed iterations, not operating instructions. Do not copy this file into Pi's task, `system.md`, or `brief.md`. Do not load it during normal delegation.

Read this file before changing generic subagent routing or the Claude-to-Pi tmux bridge.

## Non-negotiable isolation rule

This reference must never be concatenated into, attached to, summarized inside, or otherwise exposed through Pi's generated `system.md` or `brief.md`. The negative examples are for maintainers only; exposing them to Pi can re-teach the exact behavior they document.

The repository test enforces this in `test_spawn_contract`: it generates a real dry-run `system.md` and `brief.md`, then fails if either contains tmux signaling terms or markers from this reference. From the repository root, every workflow revision must run:

```bash
bash skills/tmux-subagents/test.sh
```

A release is not valid unless that command prints `PASS: tmux-subagents workflow`. Do not remove or weaken the isolation assertion to make a revision pass; fix the prompt generator instead.

## 1. Pi signaling Claude through tmux

**BAD:**

```bash
tmux send-keys -t "$orchestrator" -l "/poll $name"
tmux send-keys -t "$orchestrator" C-m
```

Also rejected: having Pi send `[Pi/<name>] ...` into Claude's input.

**Observed failures:**

- The selected pane could be another split.
- `/poll` often remained in Claude's input without being submitted.
- Pi treated the send attempt as successful without verification.
- Claude's current input could be overwritten or disturbed.
- Pi kept using tmux even after a watcher was introduced because older prompts still taught this pattern.

**Invariant:** Pi communicates with Claude only by writing its assigned `result.md` or `question.md`. Pi receives no Claude pane address and no tmux recipe.

## 2. Choosing the currently active pane

**BAD:**

```bash
tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}'
```

**Observed failure:** with several windows or splits, tmux could report the client's active pane rather than the pane whose Claude process invoked the helper.

**Invariant:** spawn from the caller's `$TMUX_PANE`, require `%<number>`, and verify that `tmux display-message -t "$TMUX_PANE" -p '#{pane_id}'` resolves to the same ID.

## 3. Pane coordinates, titles, and fallback guessing

**BAD:**

```bash
tmux capture-pane -t '0.1'
tmux capture-pane -t ':agent-name'
tmux send-keys -t '<pane beside Claude>' ...
```

**Observed failures:** coordinates changed after splits closed or moved; titles were non-unique; fallback lookup could find a Claude window with the same name as a Pi agent.

**Invariant:** map each unique agent name to one stable `%<id>` in `/tmp/claude-agents/<name>.pane`. Never fall back to layout, title, active pane, or legacy agent windows.

## 4. Continuing after pane resolution failed

**BAD:**

```bash
pane=$(resolve_recorded_pane "$pane_file")
print_captured_pane "$pane"
```

This was especially dangerous when the caller used the function in an `if`/`&&` condition. Bash can suppress `set -e` behavior in conditional contexts; a failure inside command substitution may leave `pane` empty while execution continues.

**Observed failure:** a later tmux command with an empty target could operate on the current pane—the exact wrong-pane behavior the mapping was meant to prevent.

**Invariant:** validate in the current shell, stop explicitly on failure, require a non-empty `%<id>`, and compare the resolved ID before any capture, send, or kill.

## 5. Sending without preflight and journal evidence

**BAD:**

```bash
tmux send-keys -t "$pane" -l "$reply"
tmux send-keys -t "$pane" C-m
# assume success
```

**Observed failures:** the message went to the wrong pane, remained in the input field, or was sent while the target was not ready. Claude reported delivery anyway.

**Invariant:** resolve the recorded pane, capture it before sending, submit with the unmodified `Enter` key, and confirm a matching user-message record through `verify-pi-delivery`. Pane capture is secondary evidence only. On a journal miss, retry `Enter` exactly once and re-check; then stop and report `DELIVERY=failed` with the journal path.

## 6. Duplicating tmux recipes across prompts

**BAD:** maintaining slightly different send instructions in `CLAUDE.md`, `/spawn-pi`, `/poll`, aliases, README, and Pi's generated prompt.

**Observed failure:** models followed whichever copy was most salient, including obsolete Pi-to-Claude directions.

**Invariant:** the delivery recipe exists only in `references/CLAUDE_TO_PI_BRIDGE.md`. The canonical command contains routing but no pane recipe, legacy aliases are removed, and Pi's generated prompt contains only the positive file-channel contract.

## 7. Skipping an existing installed workflow block

**BAD:**

```bash
if grep -q 'BEGIN CLAUDE-PI-TMUX-WORKFLOW' "$HOME/.claude/CLAUDE.md"; then
  exit 0
fi
```

**Observed failure:** reinstalling a newer export left the old marked block active, so Claude remained unaware of the watcher.

**Invariant:** compare and replace the marked block, preserve unrelated user content, back up the old file, and migrate only the specifically recognized unmarked legacy protocol.

## 8. Unmanaged watcher processes

**BAD:**

```bash
watch-pi-agent "$name" &
```

**Observed risk:** an ordinary shell background process is not necessarily tracked by Claude Code's harness, so its exit may not re-invoke Claude.

**Invariant:** run the exact printed `WATCH=` command using Claude Code's managed background Bash execution and require a returned task handle before claiming the watcher is active.

## 9. Reusing a live agent name

**BAD:** spawning another agent named `review` while `/tmp/claude-agents/review.pane` still points to a live pane.

**Observed failure:** the mapping and watcher could refer to different generations of the same name.

**Invariant:** every live agent has a unique name. The spawn helper refuses to replace a mapping that resolves to a live pane.

## 10. Testing with sessions that loaded old instructions

**BAD:** reinstalling the workflow, then continuing to test an already-running Claude or Pi session.

**Observed failure:** existing sessions retained their old system/context instructions and continued using the rejected tmux signaling behavior.

**Invariant:** after an upgrade, start a fresh Claude session and spawn fresh Pi agents. Preserve old panes only for inspection, not validation.

## 11. Submitting with `send-keys C-m` to an enhanced-keyboard TUI

**BAD:**

```bash
tmux send-keys -t "$pane" C-m
```

**Observed failure:** after Pi enables keyboard enhancement inside tmux, tmux with extended keys encodes this explicitly Ctrl-modified key as `ESC[109;5u`. Pi parses that CSI-u sequence as unbound `ctrl+m`, so the queued text remains in the composer. Sending the named unmodified `Enter` key delivers the submission key instead.

**Invariant:** submission uses the unmodified `Enter` key (or the byte-exact `-H 0d` equivalent) and is confirmed by a session-journal user-message record, never by assumption.

## 12. Confusing model provider with child runtime

**BAD:** treating a Pi agent configured with `model: anthropic/claude-*` as a Claude Code process.

**Observed risk:** routing, lifecycle, interruption, and permission assumptions are selected from the model name even though the child still runs inside Pi.

**Invariant:** child runtime is explicit. Pi's extension defaults to Pi; only an agent definition with `cli: claude` selects Claude Code.

## 13. Forcing one lifecycle onto every orchestrator

**BAD:** making a Pi parent launch Claude's file watcher bridge, or making a Claude parent use that bridge for a native Claude child.

**Observed risk:** duplicate supervisors race, completion is delivered twice or not at all, and harness-native cancellation or resumption is bypassed.

**Invariant:** Pi parents use the interactive-subagents extension, Claude parents use native Agents for Claude children, and the file/watcher bridge is limited to Claude-to-Pi.

## 14. Trusting a stale Claude-child permission marker

**BAD:** enabling `claude-code.md` because launcher source contains the word `manual`, then leaving the definition active after the extension changes.

**Observed risk:** a policy downgrade can expose a managed Claude child to option injection or bypassed permission prompts.

**Invariant:** the installer executes the declared launch-policy capability probe with option-shaped task and resume values; a marker alone is insufficient. The original contract was `manual-permissions-v1`. After explicit user selection of Auto for all new Claude sessions, the current contract is `auto-permissions-v1`, with exact `--permission-mode auto` arguments and no bypass. If it fails, the installer archives its managed Claude definition.

## 15. Migrating legacy paths by broad text match

**BAD:** archiving an entire instruction file or same-named skill directory because it contains a few historical phrases.

**Observed risk:** unrelated safety rules and user-owned configuration disappear from the active path.

**Invariant:** only exact managed markers, every released file/tree signature, and recognized installer-generated backups migrate automatically. Retired skills move outside discovery roots. All old and new destinations pass preflight before any target changes; ambiguous collisions leave the whole install untouched.

## 16. Broadening config permissions during a marked update

**BAD:** replacing an existing mode-`0600` `CLAUDE.md` with a mode-`0644` candidate.

**Observed risk:** instructions that were private to the account become readable by other local users.

**Invariant:** marked updates preserve the target's existing mode; only newly created config files receive the documented default mode.

## 17. Treating the historical Fable launcher as a generic child route

**BAD:** installing a direct Claude tmux launcher that reports `/poll`, even though `/poll` reads only Claude-to-Pi bridge state.

**Observed failure:** status checks look in the wrong state root, and Claude's native Agent lifecycle is bypassed.

**Invariant:** the Fable launcher is not installed or advertised. Its historical fixture remains only to protect the stable orchestrator-pane regression and reports its own result path.

## 18. Re-arming a watcher with a stale terminal file

**BAD:** starting a second managed watcher for a reused Pi child while the
previous round's `result.md` still exists.

**Observed failure:** the new watcher immediately emitted `SIGNAL=result` with
`ELAPSED=0`, treating the previous round as the new completion. The parent could
then report stale work or miss the actual second-round result.

**Invariant:** the watcher consumes every result and question before it exits.
It moves results to a unique `completed-*` path and questions to a unique
`pending-*` path, reports that preserved path, and leaves the active signal link
dangling. Re-arming without new output must wait or time out; a later write from
the same child must produce a distinct preserved result.

## 19. Changing a global default while managed launches still force Manual

**Observed failure:** setting Claude's global `permissions.defaultMode` cannot
override the extension's explicit `--permission-mode manual`, and a running Pi
parent retains its loaded argument builder after files change on disk.

**Invariant:** an explicit user-approved switch to Auto updates the actual
argument builder, its declared capability, the executable probe and the managed
agent definition together. Tests reject both a stale Manual capability and a
Manual argument array falsely labeled Auto. Validate new launches from a fresh
parent; never force a running child into another mode. Auto is classifier-based
permission checking, not permission bypass; unsupported accounts/models may
fall back to Manual and must not be reported as verified Auto.

## 20. Treating a low-level run end as terminal completion

**Observed failure:** the automatic child reporter wrote an error exit signal and requested shutdown on `agent_end`, before Pi's automatic retry or a continuation could finish. A later successful response could not undo the already-consumed failure signal. Pi 1.0.4 (`7c10bd4337495ee613f2224843ecdf349b80d1df`) retains this distinction between run end and settlement; it is not an upgrade-only regression.

**Invariant:** `agent_end` records the latest outcome. Automatic exit signals, final activity state and shutdown wait for `agent_settled`; explicit `caller_ping` and `subagent_done` retain their separate contracts. Tests cover retry recovery, exhaustion, aborts and continuations without pre-settlement terminal side effects.

## 21. Confusing interactive reporting with permanent takeover

**Observed failure:** the README promised that user input permanently disabled auto-exit, while the implementation and regression test intentionally kept auto-exit active. `interactive: true` controls parent stall notifications, not the child's exit policy.

**Invariant:** document the actual policy. Keeping a Pi child open requires an agent definition with `auto-exit: false`; neither user input nor `interactive: true` guarantees that. Widget shortcuts must also avoid Pi's default newline key (`ctrl+j`).

## 22. Loading installed and local companion copies together

**Observed failure:** the companion's development config suppressed the upstream package but not the installed fork. Pi 1.0.4 startup inside that checkout rejected four colliding subagent tools before creating a session. Adding empty arrays to an `autoload: false` delta did not suppress anything.

**Invariant:** local development uses explicit exclusion patterns for both upstream and fork identities. `autoload: false` reuses the personal installation; `!**` suppresses its resources. Tests check the config contract and fresh startup from both repository roots. Published Git install pins use full commit SHAs, and package-lock root versions match the package version to keep managed installs clean.

## Regression checklist

Before publishing a workflow revision, verify:

- **Isolation test passes:** generated Pi `system.md` and `brief.md` contain the two file paths but none of this reference's negative examples, headings, tmux terms, `/poll`, or pane-address instructions.
- Only `references/CLAUDE_TO_PI_BRIDGE.md` contains the operator-facing `tmux send-keys` recipe; the spawn helper contains only its one-shot launch recovery implementation.
- Spawn uses a validated `$TMUX_PANE` `%<id>`.
- Poll, watcher, cleanup, and replies reject non-`%<id>` targets.
- An invalid mapping produces no pane capture or send.
- Live name reuse fails before links are replaced.
- Installer tests cover fresh install, marked-block upgrade, every released legacy signature, installer-generated backups, discovery-safe archival, whole-install collision preflight, mode preservation, safe-to-unsafe policy transition, and idempotence.
- Watcher tests cover consumed result/question paths, stale-result re-arm, a distinct second-round result, pane death, and timeout.
