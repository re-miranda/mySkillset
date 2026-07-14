#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Install every skill, or one named skill.

Options:
  --skill <name>  Install only this skill
  --dry-run       Print actions without changing targets
  --with-tmux     Allow skills to install optional tmux configuration
  --list          List installable skills
  --help, -h      Show help
USAGE
}

fail_install() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

parse_args() {
  skill_name="" dry_run="0" with_tmux="0" list_only="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skill) skill_name="${2:-}"; shift 2 ;;
      --dry-run) dry_run="1"; shift ;;
      --with-tmux) with_tmux="1"; shift ;;
      --list) list_only="1"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) fail_install "unknown option '$1'" ;;
    esac
  done
}

list_skills() {
  local installer
  for installer in "$REPO_DIR"/skills/*/install.sh; do
    [ -f "$installer" ] || continue
    basename "$(dirname "$installer")"
  done
}

install_skill() {
  local name="$1" installer="$REPO_DIR/skills/$1/install.sh"
  [ -f "$installer" ] || fail_install "skill '$name' has no installer at $installer"
  local args=()
  [ "$dry_run" != "1" ] || args+=(--dry-run)
  [ "$with_tmux" != "1" ] || args+=(--with-tmux)
  printf '==> installing %s\n' "$name"
  bash "$installer" "${args[@]}"
}

install_selected_skills() {
  local name found="0"
  if [ -n "$skill_name" ]; then
    install_skill "$skill_name"
    return
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    found="1"
    install_skill "$name"
  done < <(list_skills)
  [ "$found" = "1" ] || fail_install "no installable skills found under $REPO_DIR/skills"
}

main() {
  REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  parse_args "$@"
  if [ "$list_only" = "1" ]; then
    list_skills
    exit 0
  fi
  install_selected_skills
}

main "$@"
