#!/usr/bin/env bash
set -euo pipefail

fail_validation() {
  printf 'validate.sh: %s\n' "$1" >&2
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

validate_skill_metadata() {
  local skill_dir="$1" skill_file="$1/SKILL.md" expected name description
  expected=$(basename "$skill_dir")
  name=$(frontmatter_value "$skill_file" name)
  description=$(frontmatter_value "$skill_file" description)
  [ "$name" = "$expected" ] || fail_validation "$skill_file has name '$name' (expected '$expected')"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail_validation "$skill_file has invalid skill name '$name'"
  [ -n "$description" ] || fail_validation "$skill_file is missing a description"
}

validate_skill() {
  local skill_dir="$1" test_script="$1/test.sh"
  [ -f "$skill_dir/SKILL.md" ] || fail_validation "$skill_dir is missing SKILL.md"
  validate_skill_metadata "$skill_dir"
  if [ -f "$test_script" ]; then
    printf '==> testing %s\n' "$(basename "$skill_dir")"
    bash "$test_script"
  fi
}

validate_submodules() {
  local repo_dir="$1" status
  status=$(git -C "$repo_dir" submodule status --recursive)
  ! grep -Eq '^[-+U]' <<<"$status" || \
    fail_validation "companion submodule is missing or not at its pinned commit: $status"
}

main() {
  local repo_dir skill_dir found="0"
  repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  validate_submodules "$repo_dir"
  for skill_dir in "$repo_dir"/skills/*; do
    [ -d "$skill_dir" ] || continue
    found="1"
    validate_skill "$skill_dir"
  done
  [ "$found" = "1" ] || printf 'No skills found; repository foundation is valid.\n'
  printf 'PASS: agent-skills repository\n'
}

main "$@"
