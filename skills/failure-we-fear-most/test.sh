#!/usr/bin/env bash
set -euo pipefail

fail_test() {
  printf 'test.sh: %s\n' "$1" >&2
  exit 1
}

frontmatter_value() {
  local path="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { frontmatter=1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", ""); print; exit
    }
  ' "$path"
}

prompt_body() {
  awk '
    $0 == "---" { delimiters++; next }
    delimiters >= 2 { print }
  ' "$1"
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
  bash -n "$SKILL_DIR/install.sh" "$SKILL_DIR/test.sh"
}

test_metadata() {
  [ "$(frontmatter_value "$SKILL_FILE" name)" = "failure-we-fear-most" ] || \
    fail_test "SKILL.md frontmatter name drifted"
  [ -n "$(frontmatter_value "$SKILL_FILE" description)" ] || \
    fail_test "SKILL.md is missing a description"
}

test_exact_prompt() {
  local expected actual
  expected='Identify the single failure we fear most. Then outline how to prevent catastrophic damage, detect it quickly, recover reliably, and test that recovery before shipping.'
  actual=$(prompt_body "$COMMAND_FILE")
  [ "$actual" = "$expected" ] || fail_test "shared command no longer preserves the recovered prompt"
}

assert_installed_files() {
  local pi_dir="$1" claude_home="$2"
  cmp -s "$SKILL_FILE" "$pi_dir/skills/failure-we-fear-most/SKILL.md" || \
    fail_test "Pi skill was not installed"
  cmp -s "$COMMAND_FILE" "$pi_dir/prompts/failure-we-fear-most.md" || \
    fail_test "Pi prompt was not installed"
  cmp -s "$SKILL_FILE" "$claude_home/skills/failure-we-fear-most/SKILL.md" || \
    fail_test "Claude skill was not installed"
  cmp -s "$COMMAND_FILE" "$claude_home/commands/failure-we-fear-most.md" || \
    fail_test "Claude command was not installed"
}

test_installer_contract() {
  local pi_dir="$SUITE_ROOT/pi" claude_home="$SUITE_ROOT/claude" output
  PI_AGENT_DIR="$pi_dir" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh" >/dev/null
  assert_installed_files "$pi_dir" "$claude_home"
  output=$(PI_AGENT_DIR="$pi_dir" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh")
  [ "$(grep -Fc ' (current)' <<<"$output")" -eq 4 ] || fail_test "reinstall was not idempotent"
  if find "$pi_dir" "$claude_home" -name '*.bak.*' -print -quit | grep -q .; then
    fail_test "idempotent reinstall created a backup"
  fi
}

test_conflict_backups() {
  local pi_dir="$SUITE_ROOT/conflict-pi" claude_home="$SUITE_ROOT/conflict-claude"
  mkdir -p "$pi_dir/prompts" "$claude_home/commands"
  printf 'custom Pi prompt\n' > "$pi_dir/prompts/failure-we-fear-most.md"
  printf 'custom Claude command\n' > "$claude_home/commands/failure-we-fear-most.md"
  PI_AGENT_DIR="$pi_dir" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh" >/dev/null
  grep -Fl 'custom Pi prompt' "$pi_dir/prompts/failure-we-fear-most.md.bak."* >/dev/null || \
    fail_test "Pi prompt conflict was not backed up"
  grep -Fl 'custom Claude command' "$claude_home/commands/failure-we-fear-most.md.bak."* >/dev/null || \
    fail_test "Claude command conflict was not backed up"
  assert_installed_files "$pi_dir" "$claude_home"
}

test_dry_run() {
  local pi_dir="$SUITE_ROOT/dry-pi" claude_home="$SUITE_ROOT/dry-claude"
  PI_AGENT_DIR="$pi_dir" CLAUDE_HOME="$claude_home" \
    bash "$SKILL_DIR/install.sh" --dry-run >/dev/null
  [ ! -e "$pi_dir" ] || fail_test "dry-run created the Pi directory"
  [ ! -e "$claude_home" ] || fail_test "dry-run created the Claude directory"
}

test_atomic_preflight() {
  local pi_dir="$SUITE_ROOT/atomic-pi" claude_home="$SUITE_ROOT/atomic-claude"
  mkdir -p "$claude_home/commands/failure-we-fear-most.md"
  run_expect_failure "$SUITE_ROOT/atomic.out" "$SUITE_ROOT/atomic.err" \
    env PI_AGENT_DIR="$pi_dir" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh"
  [ "$last_exit_code" -ne 0 ] || fail_test "installer accepted a directory command collision"
  [ ! -e "$pi_dir" ] || fail_test "failed preflight partially installed Pi files"
  [ ! -e "$claude_home/skills" ] || fail_test "failed preflight partially installed Claude files"
}

cleanup_suite() {
  rm -rf "$SUITE_ROOT"
}

main() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  SKILL_FILE="$SKILL_DIR/SKILL.md"
  COMMAND_FILE="$SKILL_DIR/templates/failure-we-fear-most.md"
  SUITE_ROOT=$(mktemp -d /tmp/failure-we-fear-most-test.XXXXXX)
  trap cleanup_suite EXIT
  test_shell_syntax
  test_metadata
  test_exact_prompt
  test_installer_contract
  test_conflict_backups
  test_dry_run
  test_atomic_preflight
  printf 'PASS: failure-we-fear-most skill and commands\n'
}

main "$@"
