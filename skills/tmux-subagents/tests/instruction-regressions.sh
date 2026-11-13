#!/usr/bin/env bash

assert_generic_install_targets() {
  local claude_home="$1" pi_dir="$2"
  assert_fixed_contains '<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->' "$pi_dir/AGENTS.md"
  assert_fixed_contains 'native Agent lifecycle' "$pi_dir/AGENTS.md"
  assert_fixed_contains 'custom' "$pi_dir/AGENTS.md"
  grep -q 'OLD RULE' "$pi_dir/AGENTS.md" && fail_test "installer retained stale routing block"
  [ -L "$claude_home/rules/AGENTS.md" ] || fail_test "installer lost native alias"
  [ "$(readlink -f "$claude_home/rules/AGENTS.md")" = "$pi_dir/AGENTS.md" ] || fail_test "wrong alias"
  [ ! -e "$claude_home/CLAUDE.md" ] && [ ! -L "$claude_home/CLAUDE.md" ] || fail_test "legacy output"
  [ -x "$claude_home/bin/watch-pi-agent" ] || fail_test "installer did not install watcher"
  [ ! -e "$claude_home/bin/spawn-fable-agent" ] || fail_test "installer exposed legacy Fable helper"
  [ "$(stat -c '%a' "$pi_dir/AGENTS.md")" = 600 ] || fail_test "installer broadened instruction mode"
  [ -f "$claude_home/skills/tmux-subagents/references/CLAUDE_TO_PI_BRIDGE.md" ] || fail_test "missing bridge"
  [ -f "$pi_dir/skills/tmux-subagents/SKILL.md" ] || fail_test "missing Pi skill"
  [ -f "$pi_dir/agents/claude-code.md" ] || fail_test "missing Claude child definition"
}

test_instruction_producer() {
  # -B also prevents a supposedly dry-run fixture from leaving source __pycache__.
  python3 -B -I -m unittest discover -s "$SKILL_DIR/tests/instructions" -p 'test_*.py' -v
}
