#!/usr/bin/env bash
set -euo pipefail

fail_test() {
  printf 'test.sh: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local pattern="$1" path="$2"
  grep -q -- "$pattern" "$path" || fail_test "expected '$pattern' in $path"
}

assert_fixed_contains() {
  local text="$1" path="$2"
  grep -Fq -- "$text" "$path" || fail_test "expected literal '$text' in $path"
}

assert_exit_code() {
  local expected="$1" actual="$2" label="$3"
  [ "$actual" -eq "$expected" ] || fail_test "$label returned $actual (expected $expected)"
}

run_expect_failure() {
  local output_path="$1" error_path="$2"
  shift 2
  set +e
  "$@" >"$output_path" 2>"$error_path"
  last_exit_code=$?
  set -e
}

test_shell_syntax() {
  bash -n "$SKILL_DIR/install.sh" "$SKILL_DIR/test.sh" \
    "$BIN_DIR/spawn-pi-agent" "$FABLE_HELPER" "$BIN_DIR/verify-pi-delivery" \
    "$BIN_DIR/watch-pi-agent" "$BIN_DIR/poll-pi-agent" \
    "$BIN_DIR/cleanup-pi-agent" "$BIN_DIR/probe-claude-child-policy" \
    "$SKILL_DIR/tests/migration-regressions.sh" \
    "$SKILL_DIR/tests/fakes/fake-runtime-command" \
    "$SKILL_DIR/tests/fakes/fake-delivery-verifier"
}

seed_safe_claude_policy_at() {
  local package_dir="$1" policy_dir
  policy_dir="$package_dir/pi-extension/subagents"
  mkdir -p "$policy_dir"
  cp "$SKILL_DIR/tests/fakes/fake-safe-package.json" "$package_dir/package.json"
  cp "$SKILL_DIR/tests/fakes/fake-safe-claude-command.ts" "$policy_dir/claude-command.ts"
  cp "$SKILL_DIR/tests/fakes/fake-safe-index.ts" "$policy_dir/index.ts"
}

seed_safe_claude_policy() {
  local pi_dir="$1"
  seed_safe_claude_policy_at "$pi_dir/local-packages/pi-interactive-subagents"
}

assert_generic_install_targets() {
  local claude_home="$1" pi_dir="$2"
  assert_fixed_contains '<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->' "$claude_home/CLAUDE.md"
  assert_fixed_contains 'native Agent lifecycle' "$claude_home/CLAUDE.md"
  grep -q 'OLD RULE' "$claude_home/CLAUDE.md" && fail_test "installer retained stale routing block"
  [ -x "$claude_home/bin/watch-pi-agent" ] || fail_test "installer did not install watcher"
  [ ! -e "$claude_home/bin/spawn-fable-agent" ] || fail_test "installer exposed legacy Fable helper"
  [ "$(stat -c '%a' "$claude_home/CLAUDE.md")" = 600 ] || \
    fail_test "installer broadened the Claude instruction mode"
  [ -f "$claude_home/skills/tmux-subagents/references/CLAUDE_TO_PI_BRIDGE.md" ] || \
    fail_test "installer did not install the bridge reference"
  [ -f "$pi_dir/skills/tmux-subagents/SKILL.md" ] || fail_test "installer did not install the Pi skill"
  [ -f "$pi_dir/agents/claude-code.md" ] || fail_test "installer did not install the Claude child definition"
}

test_installer_upgrade() {
  local claude_home="$SUITE_ROOT/upgrade-claude" pi_dir="$SUITE_ROOT/upgrade-pi"
  prepare_legacy_install_state "$claude_home" "$pi_dir"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" \
    > "$SUITE_ROOT/upgrade-install.out"
  assert_legacy_paths_archived "$claude_home" "$pi_dir"
  assert_generic_install_targets "$claude_home" "$pi_dir"
  assert_fixed_contains 'restart required: open fresh Pi and Claude Code' \
    "$SUITE_ROOT/upgrade-install.out"
}

test_spawn_contract() {
  local root="$SUITE_ROOT/spawn" workdir="$SUITE_ROOT/neutral-workdir" system brief meta
  mkdir -p "$workdir"
  TMUX_PANE="$TMUX_PANE" "$BIN_DIR/spawn-pi-agent" --dry-run \
    --root "$root" --workdir "$workdir" test-agent 'inspect only' > "$SUITE_ROOT/spawn.out"
  system=$(find "$root/runs" -name system.md -print -quit)
  brief=$(find "$root/runs" -name brief.md -print -quit)
  meta=$(find "$root/runs" -name meta.env -print -quit)
  assert_contains 'only communication channel' "$system"
  assert_contains 'only communication channel' "$brief"
  assert_contains '^WATCH=.*watch-pi-agent' "$SUITE_ROOT/spawn.out"
  assert_fixed_contains '--session-id' "$SUITE_ROOT/spawn.out"
  assert_contains '^session_id=' "$meta"
  assert_contains '^pi_version=' "$meta"
  assert_contains '^tmux_version=' "$meta"
  if rg -q 'tmux|send-keys|/poll|KNOWN_FAILURES|Known failures and rejected patterns|\*\*BAD:\*\*' "$system" "$brief"; then
    fail_test "Pi prompt contains maintainer-only failure material"
  fi
}

test_installer_convergence() {
  local claude_home="$SUITE_ROOT/current-claude" pi_dir="$SUITE_ROOT/current-pi"
  local first_snapshot second_snapshot backup_count
  seed_safe_claude_policy "$pi_dir"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" >/dev/null
  cmp -s "$claude_home/skills/tmux-subagents/SKILL.md" \
    "$pi_dir/skills/tmux-subagents/SKILL.md" || fail_test "harness skill copies differ"
  [ "$(stat -c '%a' "$pi_dir/skills/tmux-subagents/SKILL.md")" = 644 ] || \
    fail_test "Pi skill mode is not 644"
  assert_fixed_contains 'cli: claude' "$pi_dir/agents/claude-code.md"
  first_snapshot=$(find "$claude_home" "$pi_dir" -type f -print0 | sort -z | xargs -0 sha256sum)
  backup_count=$(find "$claude_home" "$pi_dir" -name '*.bak.*' | wc -l)
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" \
    > "$SUITE_ROOT/reinstall.out"
  second_snapshot=$(find "$claude_home" "$pi_dir" -type f -print0 | sort -z | xargs -0 sha256sum)
  [ "$first_snapshot" = "$second_snapshot" ] || fail_test "reinstall changed managed content"
  [ "$backup_count" -eq "$(find "$claude_home" "$pi_dir" -name '*.bak.*' | wc -l)" ] || \
    fail_test "reinstall created unnecessary backups"
  assert_contains 'keep .*tmux-subagents/SKILL.md (current)' "$SUITE_ROOT/reinstall.out"
}

test_git_extension_discovery() {
  local claude_home="$SUITE_ROOT/git-claude" pi_dir="$SUITE_ROOT/git-pi"
  local package_dir="$pi_dir/git/github.com/re-miranda/pi-interactive-subagents"
  seed_safe_claude_policy_at "$package_dir"
  env -u PI_SUBAGENT_EXTENSION_DIR CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" \
    bash "$SKILL_DIR/install.sh" >/dev/null
  [ -f "$pi_dir/agents/claude-code.md" ] || \
    fail_test "installer did not discover the Git-installed extension"
}

make_claude_policy_unsafe() {
  local helper="$1/local-packages/pi-interactive-subagents/pi-extension/subagents/claude-command.ts"
  python3 - "$helper" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
unsafe = source.replace('["--permission-mode", "manual"]', '["--permission-mode", "bypassPermissions"]')
assert unsafe != source
path.write_text(unsafe)
PY
}

test_policy_capability_probe() {
  local pi_dir="$SUITE_ROOT/probe-pi"
  seed_safe_claude_policy "$pi_dir"
  "$BIN_DIR/probe-claude-child-policy" \
    "$pi_dir/local-packages/pi-interactive-subagents"
  make_claude_policy_unsafe "$pi_dir"
  run_expect_failure "$SUITE_ROOT/probe-unsafe.out" "$SUITE_ROOT/probe-unsafe.err" \
    "$BIN_DIR/probe-claude-child-policy" "$pi_dir/local-packages/pi-interactive-subagents"
  [ "$last_exit_code" -ne 0 ] || fail_test "policy probe accepted bypass permissions"
  assert_fixed_contains 'expected ["--permission-mode","manual"' "$SUITE_ROOT/probe-unsafe.err"
}

test_unsafe_extension_guard() {
  local claude_home="$SUITE_ROOT/unsafe-claude" pi_dir="$SUITE_ROOT/unsafe-pi"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" \
    > "$SUITE_ROOT/unsafe-install.out"
  [ ! -e "$pi_dir/agents/claude-code.md" ] || fail_test "unsafe extension enabled Claude children"
  assert_fixed_contains 'Claude child definition not installed' "$SUITE_ROOT/unsafe-install.out"
}

test_policy_downgrade_convergence() {
  local claude_home="$SUITE_ROOT/downgrade-claude" pi_dir="$SUITE_ROOT/downgrade-pi"
  seed_safe_claude_policy "$pi_dir"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" >/dev/null
  [ -f "$pi_dir/agents/claude-code.md" ] || fail_test "safe policy did not enable Claude child"
  make_claude_policy_unsafe "$pi_dir"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" \
    > "$SUITE_ROOT/downgrade-install.out"
  [ ! -e "$pi_dir/agents/claude-code.md" ] || fail_test "policy downgrade left Claude child active"
  find "$pi_dir/agents" -name 'claude-code.md*' -print -quit | grep -q . && \
    fail_test "policy downgrade left a discoverable Claude definition"
  find "$pi_dir/backups/tmux-subagents/agents" -name 'claude-code.md.bak.*' \
    -print -quit | grep -q . || fail_test "policy downgrade did not preserve the managed definition"
  assert_fixed_contains 'expected verified manual-permissions-v1 capability' \
    "$SUITE_ROOT/downgrade-install.out"
}

test_ambiguous_claude_instructions() {
  local claude_home="$SUITE_ROOT/ambiguous-claude" pi_dir="$SUITE_ROOT/ambiguous-pi" before
  mkdir -p "$claude_home"
  printf '%s\n' '# Collaboration Protocol' '## Receiving Pi messages' \
    'When `[Pi/<name>] <message>` appears' 'CUSTOM SAFETY: never publish secrets' \
    > "$claude_home/CLAUDE.md"
  before=$(sha256sum "$claude_home/CLAUDE.md")
  run_expect_failure "$SUITE_ROOT/ambiguous.out" "$SUITE_ROOT/ambiguous.err" \
    env CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh"
  [ "$last_exit_code" -ne 0 ] || fail_test "ambiguous legacy instructions were replaced"
  [ "$before" = "$(sha256sum "$claude_home/CLAUDE.md")" ] || \
    fail_test "ambiguous Claude instructions changed"
  [ ! -e "$claude_home/skills/tmux-subagents" ] || fail_test "preflight changed files before failing"
  assert_fixed_contains 'ambiguous legacy instructions' "$SUITE_ROOT/ambiguous.err"
}

test_unowned_legacy_collisions() {
  local claude_home="$SUITE_ROOT/collision-claude" pi_dir="$SUITE_ROOT/collision-pi"
  mkdir -p "$claude_home/commands"
  printf 'custom command\n' > "$claude_home/commands/spawn-pi.md"
  run_expect_failure "$SUITE_ROOT/collision-file.out" "$SUITE_ROOT/collision-file.err" \
    env CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh"
  [ "$last_exit_code" -ne 0 ] || fail_test "unowned legacy command was archived"
  assert_fixed_contains 'custom command' "$claude_home/commands/spawn-pi.md"
  rm -rf "$claude_home"
  mkdir -p "$pi_dir/skills/tmux-pi-subagents"
  printf 'custom skill\n' > "$pi_dir/skills/tmux-pi-subagents/SKILL.md"
  run_expect_failure "$SUITE_ROOT/collision-dir.out" "$SUITE_ROOT/collision-dir.err" \
    env CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh"
  [ "$last_exit_code" -ne 0 ] || fail_test "unowned legacy skill was archived"
  assert_fixed_contains 'custom skill' "$pi_dir/skills/tmux-pi-subagents/SKILL.md"
}

test_tmux_block_convergence() {
  local fake_home="$SUITE_ROOT/tmux-home" claude_home="$SUITE_ROOT/tmux-claude"
  local pi_dir="$SUITE_ROOT/tmux-pi" checksum backup_count
  mkdir -p "$fake_home"
  printf '%s\n' 'custom' '# BEGIN CLAUDE-PI-TMUX-WORKFLOW' 'OLD TMUX RULE' \
    '# END CLAUDE-PI-TMUX-WORKFLOW' > "$fake_home/.tmux.conf"
  HOME="$fake_home" CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" \
    bash "$SKILL_DIR/install.sh" --with-tmux >/dev/null
  assert_fixed_contains 'custom' "$fake_home/.tmux.conf"
  assert_fixed_contains '# BEGIN TMUX-SUBAGENTS-WORKFLOW' "$fake_home/.tmux.conf"
  grep -q 'OLD TMUX RULE' "$fake_home/.tmux.conf" && fail_test "installer retained stale tmux block"
  checksum=$(sha256sum "$fake_home/.tmux.conf")
  backup_count=$(find "$fake_home" -name '.tmux.conf.bak.*' | wc -l)
  HOME="$fake_home" CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" \
    bash "$SKILL_DIR/install.sh" --with-tmux >/dev/null
  [ "$checksum" = "$(sha256sum "$fake_home/.tmux.conf")" ] || fail_test "tmux reinstall changed content"
  [ "$backup_count" -eq "$(find "$fake_home" -name '.tmux.conf.bak.*' | wc -l)" ] || \
    fail_test "tmux reinstall created another backup"
}

test_skill_routing_contract() {
  local bridge="$SKILL_DIR/references/CLAUDE_TO_PI_BRIDGE.md"
  assert_fixed_contains '| Pi | Pi or Claude Code | Pi' "$SKILL_DIR/SKILL.md"
  assert_fixed_contains '| Claude Code | Claude Code | Claude Code' "$SKILL_DIR/SKILL.md"
  assert_fixed_contains 'send-keys -t "$pane" Enter' "$bridge"
  assert_fixed_contains 'verify-pi-delivery "$name"' "$bridge"
  if rg -q 'send-keys|verify-pi-delivery' "$SKILL_DIR/SKILL.md" \
    "$SKILL_DIR/integrations/claude/commands/tmux-subagents.md"; then
    fail_test "bridge delivery recipe leaked into generic routing"
  fi
  grep -Fq -- 'C-m' "$bridge" && fail_test "bridge reference contains rejected C-m submission"
  [ ! -e "$SKILL_DIR/integrations/claude/commands/spawn-pi.md" ] || fail_test "source retained /spawn-pi"
  [ ! -e "$SKILL_DIR/integrations/claude/commands/pi-subagents.md" ] || fail_test "source retained /pi-subagents"
  [ ! -e "$BIN_DIR/spawn-fable-agent" ] || fail_test "generic scripts retained Fable launcher"
  grep -Fq 'spawn-fable-agent' "$SKILL_DIR/manifest.json" && fail_test "manifest advertises Fable"
  assert_fixed_contains 'extensions/pi-interactive-subagents' "$SKILL_DIR/manifest.json"
  assert_fixed_contains 'ee3b47fd42cadeb77fb7decb01fd1ba693ea6ab0' "$SKILL_DIR/manifest.json"
  find "$SKILL_DIR/references/legacy" -name SKILL.md -print -quit | grep -q . && \
    fail_test "legacy signature fixture is discoverable as an active skill"
  assert_fixed_contains 'manual-permissions-v1' "$SKILL_DIR/integrations/pi/agents/claude-code.md"
}

test_verify_delivery() {
  local root="$SUITE_ROOT/delivery-state" sessions="$SUITE_ROOT/pi-sessions"
  local session_id="123e4567-e89b-42d3-a456-426614174000"
  local journal="$sessions/project/session-$session_id.jsonl"
  mkdir -p "$root" "$(dirname "$journal")"
  printf 'session_id=%s\n' "$session_id" > "$root/delivery.meta"
  printf '%s\n' '{"type":"message","message":{"role":"user","content":"distinctive-marker"}}' > "$journal"
  "$BIN_DIR/verify-pi-delivery" delivery --root "$root" \
    --sessions-root "$sessions" --marker 'distinctive-marker' --timeout 1 \
    > "$SUITE_ROOT/delivery-ok.out"
  assert_contains '^DELIVERY=ok' "$SUITE_ROOT/delivery-ok.out"

  : > "$journal"
  run_expect_failure "$SUITE_ROOT/delivery-failed.out" "$SUITE_ROOT/delivery-failed.err" \
    "$BIN_DIR/verify-pi-delivery" delivery --root "$root" \
    --sessions-root "$sessions" --marker 'missing-marker' --timeout 1 --interval 1
  assert_exit_code 2 "$last_exit_code" "delivery timeout"
  assert_contains '^DELIVERY=failed' "$SUITE_ROOT/delivery-failed.out"
}

prepare_fake_spawn_runtime() {
  FAKE_SPAWN_BIN="$SUITE_ROOT/fake-spawn-bin"
  FAKE_TMUX_LOG="$SUITE_ROOT/fake-tmux.log"
  FAKE_VERIFY_COUNT="$SUITE_ROOT/fake-verify.count"
  mkdir -p "$FAKE_SPAWN_BIN"
  cp "$BIN_DIR/spawn-pi-agent" "$FAKE_SPAWN_BIN/spawn-pi-agent"
  cp "$SKILL_DIR/tests/fakes/fake-delivery-verifier" "$FAKE_SPAWN_BIN/verify-pi-delivery"
  ln -s "$SKILL_DIR/tests/fakes/fake-runtime-command" "$FAKE_SPAWN_BIN/pi"
  ln -s "$SKILL_DIR/tests/fakes/fake-runtime-command" "$FAKE_SPAWN_BIN/tmux"
  ln -s "$SKILL_DIR/tests/fakes/fake-runtime-command" "$FAKE_SPAWN_BIN/sleep"
  export FAKE_TMUX_LOG FAKE_VERIFY_COUNT
}

test_legacy_fable_orchestrator_resolution() {
  local root="$SUITE_ROOT/fable" packet="$SUITE_ROOT/fable-packet.md"
  printf 'Inspect only.\n' > "$packet"
  : > "$FAKE_TMUX_LOG"
  ln -s "$SKILL_DIR/tests/fakes/fake-runtime-command" "$FAKE_SPAWN_BIN/claude"
  TMUX_PANE=%900 PATH="$FAKE_SPAWN_BIN:$PATH" "$FABLE_HELPER" \
    --root "$root" --workdir "$PWD" --packet-file "$packet" fable-default > "$SUITE_ROOT/fable.out"
  assert_contains '^PANE=%99' "$SUITE_ROOT/fable.out"
  assert_contains '^RESULT=.*/fable-default.answer.md' "$SUITE_ROOT/fable.out"
  grep -Fq 'POLL=/poll' "$SUITE_ROOT/fable.out" && fail_test "legacy Fable used Pi bridge polling"
  assert_fixed_contains 'display-message -t %900 -p #{pane_id}' "$FAKE_TMUX_LOG"
  assert_fixed_contains 'split-window -v -t %900' "$FAKE_TMUX_LOG"
  : > "$FAKE_TMUX_LOG"
  run_expect_failure "$SUITE_ROOT/fable-invalid.out" "$SUITE_ROOT/fable-invalid.err" \
    env PATH="$FAKE_SPAWN_BIN:$PATH" "$FABLE_HELPER" --dry-run \
    --orchestrator 0.1 --root "$root-invalid" --packet-file "$packet" fable-invalid
  [ "$last_exit_code" -ne 0 ] || fail_test "Fable spawn accepted an ambiguous orchestrator pane"
  assert_contains "invalid orchestrator pane '0.1'" "$SUITE_ROOT/fable-invalid.err"
  [ ! -s "$FAKE_TMUX_LOG" ] || fail_test "invalid Fable target reached tmux"
}

test_spawn_launch_recovery() {
  local root="$SUITE_ROOT/recovery-success"
  : > "$FAKE_TMUX_LOG"
  rm -f "$FAKE_VERIFY_COUNT"
  PATH="$FAKE_SPAWN_BIN:$PATH" "$FAKE_SPAWN_BIN/spawn-pi-agent" \
    --source-pane %900 --root "$root" --workdir "$PWD" recovery-ok 'inspect only' \
    > "$SUITE_ROOT/recovery-success.out"
  assert_contains '^LAUNCH=ok' "$SUITE_ROOT/recovery-success.out"
  assert_fixed_contains 'start work on it now.' "$FAKE_TMUX_LOG"
  assert_fixed_contains 'send-keys -t %99 Enter' "$FAKE_TMUX_LOG"
  [ "$(<"$FAKE_VERIFY_COUNT")" -eq 2 ] || fail_test "launch recovery did not verify exactly twice"
}

test_spawn_launch_failure() {
  local root="$SUITE_ROOT/recovery-failure" enter_count
  : > "$FAKE_TMUX_LOG"
  rm -f "$FAKE_VERIFY_COUNT"
  run_expect_failure "$SUITE_ROOT/recovery-failure.out" "$SUITE_ROOT/recovery-failure.err" \
    env PATH="$FAKE_SPAWN_BIN:$PATH" FAKE_VERIFY_ALWAYS_FAIL=1 \
    "$FAKE_SPAWN_BIN/spawn-pi-agent" --source-pane %900 --root "$root" \
    --workdir "$PWD" recovery-failed 'inspect only'
  assert_exit_code 1 "$last_exit_code" "failed launch recovery"
  assert_contains '^LAUNCH=failed' "$SUITE_ROOT/recovery-failure.out"
  enter_count=$(grep -Fc -- 'send-keys -t %99 Enter' "$FAKE_TMUX_LOG")
  [ "$enter_count" -eq 1 ] || fail_test "launch recovery sent Enter $enter_count times (expected exactly one)"
  [ "$(<"$FAKE_VERIFY_COUNT")" -eq 2 ] || fail_test "failed launch did not verify exactly twice"
}

test_spawn_preflight_failure() {
  local root="$SUITE_ROOT/preflight-failure"
  : > "$FAKE_TMUX_LOG"
  rm -f "$FAKE_VERIFY_COUNT"
  run_expect_failure "$SUITE_ROOT/preflight-failure.out" "$SUITE_ROOT/preflight-failure.err" \
    env PATH="$FAKE_SPAWN_BIN:$PATH" FAKE_VERIFY_ALWAYS_FAIL=1 FAKE_TMUX_CAPTURE_FAIL=1 \
    "$FAKE_SPAWN_BIN/spawn-pi-agent" --source-pane %900 --root "$root" \
    --workdir "$PWD" preflight-failed 'inspect only'
  assert_exit_code 1 "$last_exit_code" "failed launch preflight"
  assert_contains '^LAUNCH=failed' "$SUITE_ROOT/preflight-failure.out"
  assert_fixed_contains "could not capture pane '%99'" "$SUITE_ROOT/preflight-failure.err"
  [ "$(<"$FAKE_VERIFY_COUNT")" -eq 1 ] || fail_test "preflight failure unexpectedly re-verified delivery"
}

test_live_name_guard() {
  local root="$SUITE_ROOT/name-guard"
  mkdir -p "$root"
  printf '%s\n' "$TMUX_PANE" > "$root/reused.pane"
  run_expect_failure "$SUITE_ROOT/reused.out" "$SUITE_ROOT/reused.err" \
    "$BIN_DIR/spawn-pi-agent" --dry-run --root "$root" --workdir "$PWD" reused 'inspect only'
  [ "$last_exit_code" -ne 0 ] || fail_test "spawn accepted a live reused name"
  assert_contains 'expected a unique name' "$SUITE_ROOT/reused.err"
}

test_watcher_signals() {
  local root="$SUITE_ROOT/watch"
  mkdir -p "$root"
  printf 'done\n' > "$root/done.result.md"
  "$BIN_DIR/watch-pi-agent" --root "$root" --timeout 1 done > "$SUITE_ROOT/watch-result.out"
  assert_contains '^SIGNAL=result' "$SUITE_ROOT/watch-result.out"
  assert_contains '^RESULT_PATH=.*completed-' "$SUITE_ROOT/watch-result.out"
  printf 'question\n' > "$root/ask.question.md"
  "$BIN_DIR/watch-pi-agent" --root "$root" --timeout 1 ask > "$SUITE_ROOT/watch-question.out"
  assert_contains '^SIGNAL=question' "$SUITE_ROOT/watch-question.out"
  assert_contains '^QUESTION_PATH=.*pending-' "$SUITE_ROOT/watch-question.out"
}

test_watcher_result_rearm() {
  local root="$SUITE_ROOT/watch-rearm" run_dir="$SUITE_ROOT/watch-rearm-run" first_path second_path
  mkdir -p "$root" "$run_dir"
  ln -s "$run_dir/result.md" "$root/reused.result.md"
  printf 'round one\n' > "$run_dir/result.md"
  "$BIN_DIR/watch-pi-agent" --root "$root" --timeout 1 reused > "$SUITE_ROOT/watch-rearm-first.out"
  first_path=$(awk -F= '/^RESULT_PATH=/{print $2}' "$SUITE_ROOT/watch-rearm-first.out")
  [ -f "$first_path" ] || fail_test "first watcher did not preserve its result"
  [ -L "$root/reused.result.md" ] && [ ! -e "$root/reused.result.md" ] || \
    fail_test "result watcher did not leave the active link dangling"
  run_expect_failure "$SUITE_ROOT/watch-rearm-wait.out" "$SUITE_ROOT/watch-rearm-wait.err" \
    "$BIN_DIR/watch-pi-agent" --root "$root" --interval 0 --timeout 0 reused
  assert_exit_code 2 "$last_exit_code" "re-armed watcher with no new result"
  assert_contains '^SIGNAL=timeout' "$SUITE_ROOT/watch-rearm-wait.out"
  printf 'round two\n' > "$run_dir/result.md"
  "$BIN_DIR/watch-pi-agent" --root "$root" --timeout 1 reused > "$SUITE_ROOT/watch-rearm-second.out"
  second_path=$(awk -F= '/^RESULT_PATH=/{print $2}' "$SUITE_ROOT/watch-rearm-second.out")
  [ -f "$second_path" ] && [ "$second_path" != "$first_path" ] || \
    fail_test "second watcher did not preserve a distinct result"
}

test_watcher_timeout() {
  local root="$SUITE_ROOT/watch-timeout"
  mkdir -p "$root"
  run_expect_failure "$SUITE_ROOT/watch-timeout.out" "$SUITE_ROOT/watch-timeout.err" \
    "$BIN_DIR/watch-pi-agent" --root "$root" --interval 0 --timeout 0 absent
  assert_exit_code 2 "$last_exit_code" "watcher timeout"
  assert_contains '^SIGNAL=timeout' "$SUITE_ROOT/watch-timeout.out"
}

test_watcher_rejects_ambiguous_pane() {
  local root="$SUITE_ROOT/watch-ambiguous"
  mkdir -p "$root"
  printf '0.1\n' > "$root/bad.pane"
  run_expect_failure "$SUITE_ROOT/watch-bad.out" "$SUITE_ROOT/watch-bad.err" \
    "$BIN_DIR/watch-pi-agent" --root "$root" --timeout 1 bad
  assert_exit_code 3 "$last_exit_code" "watcher pane-died signal"
  assert_contains '^SIGNAL=pane-died' "$SUITE_ROOT/watch-bad.out"
}

test_poll_rejects_ambiguous_pane() {
  local root="$SUITE_ROOT/poll"
  mkdir -p "$root"
  printf '0.1\n' > "$root/bad.pane"
  run_expect_failure "$SUITE_ROOT/poll-bad.out" "$SUITE_ROOT/poll-bad.err" \
    "$BIN_DIR/poll-pi-agent" --root "$root" bad
  [ "$last_exit_code" -ne 0 ] || fail_test "poll accepted an ambiguous pane target"
  [ ! -s "$SUITE_ROOT/poll-bad.out" ] || fail_test "poll captured an unintended pane"
  assert_contains 'invalid pane mapping' "$SUITE_ROOT/poll-bad.err"
}

test_cleanup_rejects_ambiguous_pane() {
  local root="$SUITE_ROOT/cleanup"
  mkdir -p "$root"
  printf '0.1\n' > "$root/bad.pane"
  run_expect_failure "$SUITE_ROOT/cleanup-bad.out" "$SUITE_ROOT/cleanup-bad.err" \
    "$BIN_DIR/cleanup-pi-agent" --root "$root" --kill-pane -y bad
  [ "$last_exit_code" -ne 0 ] || fail_test "cleanup accepted an ambiguous pane target"
  [ -f "$root/bad.pane" ] || fail_test "cleanup removed state after target validation failed"
}

test_failure_reference() {
  local reference="$SKILL_DIR/references/KNOWN_FAILURES.md"
  assert_contains 'Pi signaling Claude through tmux' "$reference"
  assert_contains 'Continuing after pane resolution failed' "$reference"
  assert_contains 'Skipping an existing installed workflow block' "$reference"
  assert_contains 'Testing with sessions that loaded old instructions' "$reference"
}

start_test_tmux_if_needed() {
  [ -z "${TMUX_PANE:-}" ] || return 0
  command -v tmux >/dev/null 2>&1 || fail_test "tmux is required"
  TEST_TMUX_SESSION="agent-skills-test-$$"
  tmux new-session -d -s "$TEST_TMUX_SESSION" -n test 'sleep 120'
  TMUX_PANE=$(tmux list-panes -t "$TEST_TMUX_SESSION:0" -F '#{pane_id}' | head -1)
  export TMUX_PANE
}

cleanup_suite() {
  rm -rf "$SUITE_ROOT"
  [ -z "${TEST_TMUX_SESSION:-}" ] || tmux kill-session -t "$TEST_TMUX_SESSION" 2>/dev/null || true
}

run_installer_tests() {
  test_policy_capability_probe
  test_ambiguous_claude_instructions
  test_unowned_legacy_collisions
  test_unknown_legacy_extra_fails
  test_destination_preflight_is_atomic
  test_older_legacy_migration
  test_installer_upgrade
  test_installer_convergence
  test_git_extension_discovery
  test_unsafe_extension_guard
  test_policy_downgrade_convergence
  test_tmux_block_convergence
}

run_bridge_launch_tests() {
  test_spawn_contract
  test_verify_delivery
  prepare_fake_spawn_runtime
  test_legacy_fable_orchestrator_resolution
  test_spawn_launch_recovery
  test_spawn_launch_failure
  test_spawn_preflight_failure
  test_live_name_guard
}

run_bridge_state_tests() {
  test_watcher_signals
  test_watcher_result_rearm
  test_watcher_timeout
  test_watcher_rejects_ambiguous_pane
  test_poll_rejects_ambiguous_pane
  test_cleanup_rejects_ambiguous_pane
}

main() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  BIN_DIR="$SKILL_DIR/scripts"
  FABLE_HELPER="$SKILL_DIR/references/legacy/scripts/spawn-fable-agent"
  source "$SKILL_DIR/tests/migration-regressions.sh"
  SUITE_ROOT=$(mktemp -d /tmp/agent-workflow-test.XXXXXX)
  TEST_TMUX_SESSION=""
  trap cleanup_suite EXIT
  start_test_tmux_if_needed
  test_shell_syntax
  run_installer_tests
  test_skill_routing_contract
  run_bridge_launch_tests
  run_bridge_state_tests
  test_failure_reference
  printf 'PASS: tmux-subagents workflow\n'
}

main "$@"
