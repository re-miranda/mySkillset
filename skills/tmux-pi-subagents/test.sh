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
    "$BIN_DIR/spawn-pi-agent" "$BIN_DIR/verify-pi-delivery" \
    "$BIN_DIR/watch-pi-agent" "$BIN_DIR/poll-pi-agent" \
    "$BIN_DIR/cleanup-pi-agent" \
    "$SKILL_DIR/tests/fakes/fake-runtime-command" \
    "$SKILL_DIR/tests/fakes/fake-delivery-verifier"
}

test_installer_upgrade() {
  local home="$SUITE_ROOT/claude-home"
  mkdir -p "$home"
  printf '%s\n' 'custom' '<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->' \
    'OLD RULE' '<!-- END CLAUDE-PI-TMUX-WORKFLOW -->' > "$home/CLAUDE.md"
  CLAUDE_HOME="$home" bash "$SKILL_DIR/install.sh" >/dev/null
  assert_contains 'managed background Bash task' "$home/CLAUDE.md"
  grep -q 'OLD RULE' "$home/CLAUDE.md" && fail_test "installer retained stale workflow block"
  [ -x "$home/bin/watch-pi-agent" ] || fail_test "installer did not install watcher"
  [ -x "$home/bin/verify-pi-delivery" ] || fail_test "installer did not install delivery verifier"
  [ -f "$home/skills/tmux-pi-subagents/references/KNOWN_FAILURES.md" ] || \
    fail_test "installer did not install known-failures reference"
}

test_spawn_contract() {
  local root="$SUITE_ROOT/spawn" system brief meta
  TMUX_PANE="$TMUX_PANE" "$BIN_DIR/spawn-pi-agent" --dry-run \
    --root "$root" --workdir "$PWD" test-agent 'inspect only' > "$SUITE_ROOT/spawn.out"
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

test_skill_delivery_recipe() {
  assert_fixed_contains 'send-keys -t "$pane" Enter' "$SKILL_DIR/SKILL.md"
  if grep -Fq -- 'C-m' "$SKILL_DIR/SKILL.md"; then
    fail_test "SKILL.md contains the rejected C-m submission key"
  fi
  assert_fixed_contains 'verify-pi-delivery "$name"' "$SKILL_DIR/SKILL.md"
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
  printf 'question\n' > "$root/ask.question.md"
  "$BIN_DIR/watch-pi-agent" --root "$root" --timeout 1 ask > "$SUITE_ROOT/watch-question.out"
  assert_contains '^SIGNAL=question' "$SUITE_ROOT/watch-question.out"
  assert_contains '^QUESTION_PATH=.*pending-' "$SUITE_ROOT/watch-question.out"
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

main() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  BIN_DIR="$SKILL_DIR/scripts"
  SUITE_ROOT=$(mktemp -d /tmp/claude-pi-workflow-test.XXXXXX)
  TEST_TMUX_SESSION=""
  trap cleanup_suite EXIT
  start_test_tmux_if_needed
  test_shell_syntax
  test_installer_upgrade
  test_spawn_contract
  test_skill_delivery_recipe
  test_verify_delivery
  prepare_fake_spawn_runtime
  test_spawn_launch_recovery
  test_spawn_launch_failure
  test_spawn_preflight_failure
  test_live_name_guard
  test_watcher_signals
  test_watcher_rejects_ambiguous_pane
  test_poll_rejects_ambiguous_pane
  test_cleanup_rejects_ambiguous_pane
  test_failure_reference
  printf 'PASS: Claude ↔ Pi tmux workflow\n'
}

main "$@"
