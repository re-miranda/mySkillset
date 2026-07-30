# Known failures and rejected patterns

> Maintainer-only regression reference. The snippets marked **BAD** are evidence from failed iterations, not operating instructions. Do not copy this file into Pi's task, `system.md`, or `brief.md`. Do not load it during normal delegation.

Read this file before changing the Claude ↔ Pi tmux workflow.

## Non-negotiable isolation rule

This reference must never be concatenated into, attached to, summarized inside, or otherwise exposed through Pi's generated `system.md` or `brief.md`. The negative examples are for maintainers only; exposing them to Pi can re-teach the exact behavior they document.

The repository test enforces this in `test_spawn_contract`: it generates a real dry-run `system.md` and `brief.md`, then fails if either contains tmux signaling terms or markers from this reference. From the repository root, every workflow revision must run:

```bash
bash skills/tmux-pi-subagents/test.sh
```

A release is not valid unless that command prints `PASS: Claude ↔ Pi tmux workflow`. Do not remove or weaken the isolation assertion to make a revision pass; fix the prompt generator instead.

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

**Invariant:** the Claude-to-Pi delivery recipe exists only in `SKILL.md`. Aliases contain no implementation. Pi's generated prompt contains only the positive file-channel contract.

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

## Regression checklist

Before publishing a workflow revision, verify:

- **Isolation test passes:** generated Pi `system.md` and `brief.md` contain the two file paths but none of this reference's negative examples, headings, tmux terms, `/poll`, or pane-address instructions.
- Only `SKILL.md` contains the operator-facing `tmux send-keys` recipe; the spawn helper contains only its one-shot launch recovery implementation.
- Spawn uses a validated `$TMUX_PANE` `%<id>`.
- Poll, watcher, cleanup, and replies reject non-`%<id>` targets.
- An invalid mapping produces no pane capture or send.
- Live name reuse fails before links are replaced.
- Installer tests cover fresh install, marked-block upgrade, legacy migration, and idempotence.
- Watcher tests cover result, question, pane death, and timeout.
