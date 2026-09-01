#!/usr/bin/env bash
set -euo pipefail

fail_test() {
  printf 'test.sh: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local literal="$1" path="$2"
  grep -Fq "$literal" "$path" || fail_test "expected '$literal' in $path"
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

test_shell_syntax() {
  bash -n "$SKILL_DIR/install.sh"
}

test_skill_frontmatter() {
  [ "$(frontmatter_value "$WALKTHROUGH_SKILL" name)" = "visual-parity-walkthrough" ] || \
    fail_test "SKILL.md frontmatter name drifted"
  [ -n "$(frontmatter_value "$WALKTHROUGH_SKILL" description)" ] || \
    fail_test "SKILL.md is missing a description"
}

test_walkthrough_invariants() {
  assert_file_contains 'Every finding needs three legs' "$WALKTHROUGH_SKILL"
  assert_file_contains 'Analyze live, never batch' "$WALKTHROUGH_SKILL"
  assert_file_contains 'Motion verdict is the user' "$WALKTHROUGH_SKILL"
  assert_file_contains 'Decisions ledger' "$WALKTHROUGH_SKILL"
  assert_file_contains 'bright background' "$WALKTHROUGH_SKILL"
}

test_installer_contract() {
  local home="$SUITE_ROOT/claude-home" reinstall_output
  CLAUDE_HOME="$home" bash "$SKILL_DIR/install.sh" >/dev/null
  [ -f "$home/skills/visual-parity-walkthrough/SKILL.md" ] || \
    fail_test "installer skipped the walkthrough skill"
  reinstall_output=$(CLAUDE_HOME="$home" bash "$SKILL_DIR/install.sh" --with-tmux)
  grep -Fq 'keep' <<<"$reinstall_output" || fail_test "reinstall is not idempotent"
  if ls "$home"/skills/visual-parity-walkthrough/SKILL.md.bak.* >/dev/null 2>&1; then
    fail_test "idempotent reinstall created a backup"
  fi
}

test_installer_dry_run() {
  local home="$SUITE_ROOT/dry-home"
  CLAUDE_HOME="$home" bash "$SKILL_DIR/install.sh" --dry-run >/dev/null
  [ ! -e "$home" ] || fail_test "dry-run created files"
}

main() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  WALKTHROUGH_SKILL="$SKILL_DIR/SKILL.md"
  SUITE_ROOT=$(mktemp -d /tmp/visual-parity-walkthrough-test.XXXXXX)
  trap 'rm -rf "$SUITE_ROOT"' EXIT
  test_shell_syntax
  test_skill_frontmatter
  test_walkthrough_invariants
  test_installer_contract
  test_installer_dry_run
  printf 'PASS: visual parity walkthrough skill\n'
}

main "$@"
