#!/usr/bin/env bash

seed_legacy_skill() {
  local target_dir="$1" release="${2:-240f677}"
  local reference_dir="$SKILL_DIR/references/legacy/claude-skill/releases/$release"
  mkdir -p "$target_dir/references"
  cp "$reference_dir/SKILL.signature" "$target_dir/SKILL.md"
  cp "$reference_dir/KNOWN_FAILURES.signature" "$target_dir/references/KNOWN_FAILURES.md"
}

prepare_legacy_install_state() {
  local claude_home="$1" pi_dir="$2" legacy="$SKILL_DIR/references/legacy"
  mkdir -p "$claude_home/commands"
  printf '%s\n' 'custom' '<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->' \
    'OLD RULE' '<!-- END CLAUDE-PI-TMUX-WORKFLOW -->' > "$claude_home/CLAUDE.md"
  chmod 0600 "$claude_home/CLAUDE.md"
  cp "$legacy/commands/spawn-pi.md" "$claude_home/commands/spawn-pi.md"
  cp "$legacy/commands/pi-subagents.md" "$claude_home/commands/pi-subagents.md"
  seed_legacy_skill "$claude_home/skills/tmux-pi-subagents"
  seed_legacy_skill "$pi_dir/skills/tmux-pi-subagents"
  seed_safe_claude_policy "$pi_dir"
}

assert_skill_archived_outside_discovery() {
  local config_root="$1"
  [ ! -e "$config_root/skills/tmux-pi-subagents" ] || fail_test "installer retained legacy skill"
  find "$config_root/skills" -maxdepth 1 -name 'tmux-pi-subagents*' -print -quit | \
    grep -q . && fail_test "retired skill remains under discovery root"
  find "$config_root/backups/tmux-subagents/skills" -maxdepth 1 \
    -name 'tmux-pi-subagents.bak.*' -print -quit | grep -q . || \
    fail_test "installer did not preserve legacy skill outside discovery"
}

assert_legacy_paths_archived() {
  local claude_home="$1" pi_dir="$2"
  [ ! -e "$claude_home/commands/spawn-pi.md" ] || fail_test "installer retained /spawn-pi"
  [ ! -e "$claude_home/commands/pi-subagents.md" ] || fail_test "installer retained /pi-subagents"
  find "$claude_home/commands" -name 'spawn-pi.md.bak.*' -print -quit | grep -q . || \
    fail_test "installer did not archive /spawn-pi"
  assert_skill_archived_outside_discovery "$claude_home"
  assert_skill_archived_outside_discovery "$pi_dir"
}

test_older_legacy_migration() {
  local claude_home="$SUITE_ROOT/older-claude" pi_dir="$SUITE_ROOT/older-pi"
  local legacy="$SKILL_DIR/references/legacy"
  mkdir -p "$claude_home/commands"
  cp "$legacy/commands/spawn-pi.md" "$claude_home/commands/spawn-pi.md"
  seed_legacy_skill "$claude_home/skills/tmux-pi-subagents" 6d37921
  cp "$legacy/claude-skill/releases/240f677/SKILL.signature" \
    "$claude_home/skills/tmux-pi-subagents/SKILL.md.bak.20250101T000000Z"
  cp "$legacy/claude-skill/releases/240f677/KNOWN_FAILURES.signature" \
    "$claude_home/skills/tmux-pi-subagents/references/KNOWN_FAILURES.md.bak.20250101T000000Z.1"
  seed_safe_claude_policy "$pi_dir"
  CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh" >/dev/null
  assert_skill_archived_outside_discovery "$claude_home"
  [ -f "$claude_home/skills/tmux-subagents/SKILL.md" ] || fail_test "older migration missed generic skill"
}

test_unknown_legacy_extra_fails() {
  local claude_home="$SUITE_ROOT/legacy-extra-claude" pi_dir="$SUITE_ROOT/legacy-extra-pi"
  seed_legacy_skill "$claude_home/skills/tmux-pi-subagents"
  printf 'user note\n' > "$claude_home/skills/tmux-pi-subagents/notes.md"
  run_expect_failure "$SUITE_ROOT/legacy-extra.out" "$SUITE_ROOT/legacy-extra.err" \
    env CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh"
  [ "$last_exit_code" -ne 0 ] || fail_test "unknown legacy extra migrated"
  assert_fixed_contains 'user note' "$claude_home/skills/tmux-pi-subagents/notes.md"
  [ ! -e "$claude_home/backups/tmux-subagents" ] || \
    fail_test "unknown legacy extra produced a backup before failure"
}

test_destination_preflight_is_atomic() {
  local claude_home="$SUITE_ROOT/destination-claude" pi_dir="$SUITE_ROOT/destination-pi"
  local legacy="$SKILL_DIR/references/legacy"
  mkdir -p "$claude_home/commands" "$claude_home/skills/tmux-subagents/SKILL.md"
  cp "$legacy/commands/spawn-pi.md" "$claude_home/commands/spawn-pi.md"
  run_expect_failure "$SUITE_ROOT/destination.out" "$SUITE_ROOT/destination.err" \
    env CLAUDE_HOME="$claude_home" PI_AGENT_DIR="$pi_dir" bash "$SKILL_DIR/install.sh"
  [ "$last_exit_code" -ne 0 ] || fail_test "destination collision passed preflight"
  cmp -s "$legacy/commands/spawn-pi.md" "$claude_home/commands/spawn-pi.md" || \
    fail_test "destination failure mutated the legacy command"
  find "$claude_home/commands" -name 'spawn-pi.md.bak.*' -print -quit | grep -q . && \
    fail_test "destination failure archived a path before preflight completed"
  assert_fixed_contains "collision at '$claude_home/skills/tmux-subagents/SKILL.md'" \
    "$SUITE_ROOT/destination.err"
}
