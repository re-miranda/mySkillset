#!/usr/bin/env bash
# Source from test.sh: keep permission-contract failures separate from bridge tests.

rewrite_fake_claude_policy() {
  local package_dir="$1" mode="$2" policy="$3"
  python3 - "$package_dir" "$mode" "$policy" <<'PY'
import json
import sys
from pathlib import Path
root, mode, policy = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
helper = root / "pi-extension/subagents/claude-command.ts"
source = helper.read_text()
updated = source.replace('"auto"', json.dumps(mode))
updated = updated.replace('"auto-permissions-v1"', json.dumps(policy))
assert updated != source, "expected a changed fake launch policy"
helper.write_text(updated)
manifest_path = root / "package.json"
manifest = json.loads(manifest_path.read_text())
manifest["pi"]["capabilities"]["claudeCodeLaunchPolicy"] = policy
manifest_path.write_text(json.dumps(manifest))
PY
}

make_claude_policy_unsafe() {
  # Derive the bypass regression from the accepted fixture to prevent fixture drift.
  local package_dir="$1/local-packages/pi-interactive-subagents"
  rewrite_fake_claude_policy "$package_dir" bypassPermissions auto-permissions-v1
}

# A truthful marker alone must not conceal changed launch arguments.
test_policy_capability_probe() {
  local pi_dir="$SUITE_ROOT/probe-pi"
  seed_safe_claude_policy "$pi_dir"
  "$BIN_DIR/probe-claude-child-policy" \
    "$pi_dir/local-packages/pi-interactive-subagents"
  make_claude_policy_unsafe "$pi_dir"
  run_expect_failure "$SUITE_ROOT/probe-unsafe.out" "$SUITE_ROOT/probe-unsafe.err" \
    "$BIN_DIR/probe-claude-child-policy" "$pi_dir/local-packages/pi-interactive-subagents"
  [ "$last_exit_code" -ne 0 ] || fail_test "policy probe accepted bypass permissions"
  assert_fixed_contains 'expected ["--permission-mode","auto"' "$SUITE_ROOT/probe-unsafe.err"
}

# Reject a Manual launcher even when it falsely advertises the new Auto marker.
test_manual_arguments_are_not_auto() {
  local package_dir="$SUITE_ROOT/manual-arguments"
  seed_safe_claude_policy_at "$package_dir"
  rewrite_fake_claude_policy "$package_dir" manual auto-permissions-v1
  run_expect_failure "$SUITE_ROOT/manual-args.out" "$SUITE_ROOT/manual-args.err" \
    "$BIN_DIR/probe-claude-child-policy" "$package_dir"
  [ "$last_exit_code" -ne 0 ] || fail_test "policy probe accepted Manual as Auto"
  assert_fixed_contains 'expected ["--permission-mode","auto"' "$SUITE_ROOT/manual-args.err"
}

# A previous release must fail closed rather than silently defeat the chosen mode.
test_old_manual_capability_is_disabled() {
  local claude_home="$SUITE_ROOT/manual-claude" pi_dir="$SUITE_ROOT/manual-pi"
  local package_dir="$pi_dir/local-packages/pi-interactive-subagents"
  seed_safe_claude_policy_at "$package_dir"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" >/dev/null
  rewrite_fake_claude_policy "$package_dir" manual manual-permissions-v1
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" \
    > "$SUITE_ROOT/manual-install.out"
  [ ! -e "$pi_dir/agents/claude-code.md" ] || fail_test "stale Manual extension stayed enabled"
  assert_fixed_contains 'expected verified auto-permissions-v1 capability' \
    "$SUITE_ROOT/manual-install.out"
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
  assert_fixed_contains 'expected verified auto-permissions-v1 capability' \
    "$SUITE_ROOT/downgrade-install.out"
}
