#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the visual-parity-walkthrough Claude skill.

Options:
  --dry-run     Print actions without writing files
  --with-tmux   Accepted for repository-level compatibility; no effect
  --help, -h    Show this help

Environment:
  CLAUDE_HOME   Override the Claude config directory (default: ~/.claude)
USAGE
}

log_install_step() {
  [ "${DRY_RUN:-0}" != "1" ] || { printf 'dry-run: %s\n' "$1"; return; }
  printf '%s\n' "$1"
}

backup_existing_target() {
  local target_path="$1" backup_path="$1.bak.${STAMP}"
  log_install_step "backup $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] || cp -p "$target_path" "$backup_path"
}

install_skill_file() {
  local source_path="$1" target_path="$2"
  [ "$DRY_RUN" = "1" ] || mkdir -p "$(dirname "$target_path")"
  if [ -e "$target_path" ] && cmp -s "$source_path" "$target_path"; then
    log_install_step "keep $target_path (current)"
    return
  fi
  [ ! -e "$target_path" ] || backup_existing_target "$target_path"
  log_install_step "install $target_path"
  [ "$DRY_RUN" = "1" ] || install -m 0644 "$source_path" "$target_path"
}

parse_args() {
  DRY_RUN="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN="1"; shift ;;
      --with-tmux) shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) printf 'install.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
  done
}

main() {
  parse_args "$@"
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
  install_skill_file "$SKILL_DIR/SKILL.md" \
    "$CLAUDE_DIR/skills/visual-parity-walkthrough/SKILL.md"
  log_install_step "done"
}

main "$@"
