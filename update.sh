#!/usr/bin/env bash
set -euo pipefail

fail_update() {
  printf 'update.sh: %s\n' "$1" >&2
  exit 1
}

require_clean_tree() {
  local repo_dir="$1" changes
  changes=$(git -C "$repo_dir" status --porcelain)
  [ -z "$changes" ] || fail_update "working tree is dirty; commit or resolve changes before pulling:\n$changes"
}

require_upstream() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1 || \
    fail_update "current branch has no upstream; add the GitHub remote and set upstream first"
}

main() {
  local repo_dir commit
  repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  require_clean_tree "$repo_dir"
  require_upstream "$repo_dir"
  git -C "$repo_dir" pull --ff-only
  bash "$repo_dir/validate.sh"
  bash "$repo_dir/install.sh" "$@"
  commit=$(git -C "$repo_dir" rev-parse HEAD)
  printf 'UPDATED_COMMIT=%s\n' "$commit"
}

main "$@"
