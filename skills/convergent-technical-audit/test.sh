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
  bash -n "$SKILL_DIR/test.sh"
}

test_skill_frontmatter() {
  [ "$(frontmatter_value "$SKILL_FILE" name)" = "convergent-technical-audit" ] || \
    fail_test "SKILL.md frontmatter name drifted"
  [ -n "$(frontmatter_value "$SKILL_FILE" description)" ] || \
    fail_test "SKILL.md is missing a description"
}

test_workflow_invariants() {
  assert_file_contains 'Five phases' "$SKILL_FILE"
  assert_file_contains 'Run discovery sequentially' "$SKILL_FILE"
  assert_file_contains 'A candidate may be deferred once' "$SKILL_FILE"
  assert_file_contains 'Only accepted material findings reset the clean streak' "$SKILL_FILE"
  assert_file_contains 'Append and validate' "$SKILL_FILE"
  assert_file_contains 'pauses the existing streak' "$SKILL_FILE"
  assert_file_contains 'supplement directory' "$SKILL_FILE"
  assert_file_contains 'least-privilege child profile' "$SKILL_FILE"
  assert_file_contains 'preflight-failure procedure' "$SKILL_FILE"
  assert_file_contains 'dedicated deep-dive' "$SKILL_FILE"
  assert_file_contains 'CONVERGED' "$SKILL_FILE"
  assert_file_contains 'CAPPED_NOT_CONVERGED' "$SKILL_FILE"
  assert_file_contains 'must not spawn subagents' "$SKILL_FILE"
}

test_reference_contract() {
  assert_file_contains 'candidate.discovered' "$REFERENCE_FILE"
  assert_file_contains 'rejection_deep_dive_required' "$REFERENCE_FILE"
  assert_file_contains 'effortComparison' "$REFERENCE_FILE"
  assert_file_contains 'supplemental-evidence.jsonl' "$REFERENCE_FILE"
  assert_file_contains 'git worktree add --detach --no-checkout' "$REFERENCE_FILE"
  assert_file_contains 'git diff --name-only "$BASE_SHA"' "$REFERENCE_FILE"
  assert_file_contains 'git checkout "$BASE_SHA"' "$REFERENCE_FILE"
  assert_file_contains 'NUL-delimited approved tracked list' "$REFERENCE_FILE"
  assert_file_contains 'resolves under `/tmp`' "$REFERENCE_FILE"
  assert_file_contains 'findings.jsonl' "$REFERENCE_FILE"
  assert_file_contains 'Generate this file from the complete canonical state' "$REFERENCE_FILE"
  assert_file_contains 'Preflight completion failure' "$REFERENCE_FILE"
  assert_file_contains 'restart the parent process' "$REFERENCE_FILE"
  assert_file_contains 'create a new audit ID after recovery' "$REFERENCE_FILE"
  assert_file_contains 'Never return deferred' "$REFERENCE_FILE"
}

initialize_git_fixture() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name Fixture
}

test_secret_safe_materialization() {
  local repo="$SUITE_ROOT/freeze-repo" staging="$SUITE_ROOT/staging" final="$SUITE_ROOT/final"
  local approved="$SUITE_ROOT/approved.zlist" patch="$SUITE_ROOT/safe.patch" base_sha
  initialize_git_fixture "$repo"
  printf 'safe base\n' > "$repo/safe.txt"; printf 'fixture-secret\n' > "$repo/.env"
  git -C "$repo" add safe.txt .env; git -C "$repo" commit -qm base
  base_sha=$(git -C "$repo" rev-parse HEAD)
  printf 'safe changed\n' > "$repo/safe.txt"; printf 'changed-secret\n' > "$repo/.env"
  printf 'safe.txt\0' > "$approved"
  git -C "$repo" worktree add -q --detach --no-checkout "$staging" "$base_sha"
  git -C "$staging" checkout -q "$base_sha" --pathspec-from-file="$approved" --pathspec-file-nul
  git -C "$repo" diff --binary "$base_sha" -- safe.txt > "$patch"; git -C "$staging" apply "$patch"
  [ ! -e "$staging/.env" ] || fail_test "excluded tracked secret entered staging"
  ! grep -R -Fq 'fixture-secret' "$staging" || fail_test "secret content entered staging"
  mkdir "$final"; cp "$staging/safe.txt" "$final/safe.txt"
  git -C "$repo" worktree remove -f "$staging"
  grep -Fq 'safe changed' "$final/safe.txt" || fail_test "approved dirty state was lost"
  [ ! -e "$final/.env" ] || fail_test "excluded tracked secret entered final freeze"
}

test_recorded_sha_materialization() {
  local repo="$SUITE_ROOT/sha-repo" staging="$SUITE_ROOT/sha-staging"
  local approved="$SUITE_ROOT/sha-approved.zlist" base_sha
  initialize_git_fixture "$repo"
  printf 'recorded revision\n' > "$repo/safe.txt"
  git -C "$repo" add safe.txt; git -C "$repo" commit -qm recorded
  base_sha=$(git -C "$repo" rev-parse HEAD)
  printf 'moving head\n' > "$repo/safe.txt"
  git -C "$repo" add safe.txt; git -C "$repo" commit -qm later
  printf 'safe.txt\0' > "$approved"
  git -C "$repo" worktree add -q --detach --no-checkout "$staging" "$base_sha"
  git -C "$staging" checkout -q "$base_sha" --pathspec-from-file="$approved" --pathspec-file-nul
  grep -Fq 'recorded revision' "$staging/safe.txt" || fail_test "freeze rebound to moving HEAD"
  ! grep -Fq 'moving head' "$staging/safe.txt" || fail_test "later revision entered freeze"
  git -C "$repo" worktree remove -f "$staging"
}

test_manifest() {
  python3 - "$SKILL_DIR/manifest.json" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert manifest["name"] == "convergent-technical-audit"
assert manifest["entrypoint"] == "SKILL.md"
assert manifest["validationCommand"] == "bash test.sh"
assert manifest["version"] == "0.1.1"
assert "native-subagent-session-facility" in manifest["requirements"]
PY
}

test_installer_contract() {
  local pi_home="$SUITE_ROOT/pi-home" claude_home="$SUITE_ROOT/claude-home" output
  PI_HOME="$pi_home" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh" >/dev/null
  [ -f "$pi_home/skills/convergent-technical-audit/SKILL.md" ] || fail_test "Pi skill missing"
  [ -f "$claude_home/skills/convergent-technical-audit/SKILL.md" ] || fail_test "Claude skill missing"
  [ -f "$pi_home/skills/convergent-technical-audit/references/STATE_AND_SCHEMAS.md" ] || \
    fail_test "Pi reference missing"
  output=$(PI_HOME="$pi_home" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh" --with-tmux)
  grep -Fq 'keep' <<<"$output" || fail_test "reinstall is not idempotent"
}

write_fixed_date_fake() {
  local fake_bin="$1"
  mkdir -p "$fake_bin"
  printf '#!/usr/bin/env bash\nprintf "20260101T000000Z\\n"\n' > "$fake_bin/date"
  chmod 0755 "$fake_bin/date"
}

test_conflict_backups_unique() {
  local pi_home="$SUITE_ROOT/conflict-pi" target backup_dir backup_path fake_bin="$SUITE_ROOT/fake-bin"
  local -a backups=()
  write_fixed_date_fake "$fake_bin"
  PI_HOME="$pi_home" bash "$SKILL_DIR/install.sh" --target pi >/dev/null
  target="$pi_home/skills/convergent-technical-audit/SKILL.md"
  backup_dir=$(dirname "$target")
  printf 'conflict one\n' > "$target"
  PATH="$fake_bin:$PATH" PI_HOME="$pi_home" bash "$SKILL_DIR/install.sh" --target pi >/dev/null
  printf 'conflict two\n' > "$target"
  PATH="$fake_bin:$PATH" PI_HOME="$pi_home" bash "$SKILL_DIR/install.sh" --target pi >/dev/null
  while IFS= read -r backup_path; do
    backups[${#backups[@]}]="$backup_path"
  done < <(find "$backup_dir" -maxdepth 1 -name 'SKILL.md.bak.*' -type f | sort)
  [ "${#backups[@]}" = "2" ] || fail_test "expected two unique same-second backups"
  grep -Fl 'conflict one' "${backups[@]}" >/dev/null || fail_test "first conflict was overwritten"
  grep -Fl 'conflict two' "${backups[@]}" >/dev/null || fail_test "second conflict was not preserved"
  cmp -s "$SKILL_FILE" "$target" || fail_test "installer did not restore canonical skill"
}

test_installer_dry_run() {
  local pi_home="$SUITE_ROOT/dry-pi" claude_home="$SUITE_ROOT/dry-claude"
  PI_HOME="$pi_home" CLAUDE_HOME="$claude_home" bash "$SKILL_DIR/install.sh" --dry-run >/dev/null
  [ ! -e "$pi_home" ] || fail_test "dry-run created Pi files"
  [ ! -e "$claude_home" ] || fail_test "dry-run created Claude files"
}

test_invalid_installer_args() {
  local error_path="$SUITE_ROOT/install-error.txt"
  ! bash "$SKILL_DIR/install.sh" --target 2>"$error_path" || fail_test "missing target value succeeded"
  grep -Fq "missing value for '--target'" "$error_path" || fail_test "missing target error is unclear"
  ! bash "$SKILL_DIR/install.sh" --target invalid 2>"$error_path" || fail_test "invalid target succeeded"
  grep -Fq "expected pi, claude, or both" "$error_path" || fail_test "invalid target error is unclear"
}

test_optional_private_markers() {
  local marker marker_file="${PRIVATE_MARKERS_FILE:-}"
  local -a public_files=("$@")
  [ -n "$marker_file" ] || return 0
  [ -r "$marker_file" ] || fail_test "private marker file '$marker_file' is unreadable (expected a readable file)"
  while IFS= read -r marker; do
    [ -z "$marker" ] && continue
    ! grep -Fq "$marker" "${public_files[@]}" || fail_test "content matched a private marker"
  done < "$marker_file"
}

test_public_content() {
  local output_path="$SUITE_ROOT/public-scan.txt" path slash='/' backslash='\\'
  local machine_path_pattern
  local -a public_files=()
  while IFS= read -r path; do
    public_files[${#public_files[@]}]="$path"
  done < <(find "$SKILL_DIR" -type f -not -name '*.bak.*' | sort)
  machine_path_pattern="(${slash}root${slash}|${slash}(home|Users)${slash}[^/[:space:]]+${slash}|[A-Za-z]:${backslash}${backslash}Users${backslash}${backslash})"
  if grep -En "$machine_path_pattern" "${public_files[@]}" > "$output_path"; then
    fail_test "machine-specific absolute path found: $(head -n 1 "$output_path")"
  fi
  test_optional_private_markers "${public_files[@]}"
}

test_file_sizes() {
  local path lines
  while IFS= read -r path; do
    lines=$(wc -l < "$path")
    [ "$lines" -le 500 ] || fail_test "$path has $lines lines (expected at most 500)"
  done < <(find "$SKILL_DIR" -type f -not -name '*.bak.*' | sort)
}

test_audit_protocol() {
  test_skill_frontmatter
  test_workflow_invariants
  test_reference_contract
  test_secret_safe_materialization
  test_recorded_sha_materialization
}

test_package_contracts() {
  test_manifest
  test_installer_contract
  test_conflict_backups_unique
  test_installer_dry_run
  test_invalid_installer_args
  test_public_content
  test_file_sizes
}

main() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  SKILL_FILE="$SKILL_DIR/SKILL.md"
  REFERENCE_FILE="$SKILL_DIR/references/STATE_AND_SCHEMAS.md"
  SUITE_ROOT=$(mktemp -d /tmp/convergent-technical-audit-test.XXXXXX)
  trap 'rm -rf "$SUITE_ROOT"' EXIT
  test_shell_syntax
  test_audit_protocol
  test_package_contracts
  printf 'PASS: convergent technical audit skill\n'
}

main "$@"
