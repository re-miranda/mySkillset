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
  [ "$(frontmatter_value "$AUDIT_SKILL" name)" = "rolling-code-audit" ] || \
    fail_test "audit SKILL.md frontmatter name drifted"
  [ "$(frontmatter_value "$REPLAN_SKILL" name)" = "rolling-code-audit-replan" ] || \
    fail_test "replan SKILL.md frontmatter name drifted"
  [ -n "$(frontmatter_value "$REPLAN_SKILL" description)" ] || \
    fail_test "replan SKILL.md is missing a description"
}

test_audit_invariants() {
  assert_file_contains 'score = max(drift ÷ budget, age ÷ floor)' "$AUDIT_SKILL"
  assert_file_contains 'Never fix findings during a run' "$AUDIT_SKILL"
  assert_file_contains 'stop and tell the user instead of creating one' "$AUDIT_SKILL"
}

test_replan_invariants() {
  assert_file_contains 'Derive independently first' "$REPLAN_SKILL"
  assert_file_contains 'Keep exactly two commands' "$REPLAN_SKILL"
  assert_file_contains 'Plan shaped by' "$REPLAN_SKILL"
}

test_installer_contract() {
  local home="$SUITE_ROOT/claude-home" reinstall_output
  CLAUDE_HOME="$home" bash "$SKILL_DIR/install.sh" >/dev/null
  [ -f "$home/skills/rolling-code-audit/SKILL.md" ] || fail_test "installer skipped audit skill"
  [ -f "$home/skills/rolling-code-audit-replan/SKILL.md" ] || fail_test "installer skipped replan skill"
  reinstall_output=$(CLAUDE_HOME="$home" bash "$SKILL_DIR/install.sh" --with-tmux)
  grep -Fq 'keep' <<<"$reinstall_output" || fail_test "reinstall is not idempotent"
  if ls "$home"/skills/rolling-code-audit/SKILL.md.bak.* >/dev/null 2>&1; then
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
  AUDIT_SKILL="$SKILL_DIR/SKILL.md"
  REPLAN_SKILL="$SKILL_DIR/integrations/claude/skills/rolling-code-audit-replan/SKILL.md"
  SUITE_ROOT=$(mktemp -d /tmp/rolling-code-audit-test.XXXXXX)
  trap 'rm -rf "$SUITE_ROOT"' EXIT
  test_shell_syntax
  test_skill_frontmatter
  test_audit_invariants
  test_replan_invariants
  test_installer_contract
  test_installer_dry_run
  printf 'PASS: rolling code audit skill pair\n'
}

main "$@"
