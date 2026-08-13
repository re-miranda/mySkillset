#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the failure-we-fear-most skill and command for Pi and Claude Code.

Options:
  --dry-run     Print actions without writing files
  --with-tmux   Accepted for repository-level compatibility; no effect
  --help, -h    Show this help

Environment:
  PI_AGENT_DIR  Pi agent directory (default: ~/.pi/agent)
  CLAUDE_HOME   Claude config directory (default: ~/.claude)
USAGE
}

fail_install() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

log_install_step() {
  if [ "$DRY_RUN" = "1" ]; then
    printf 'dry-run: %s\n' "$1"
    return
  fi
  printf '%s\n' "$1"
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

nearest_existing_parent() {
  local parent_path
  parent_path=$(dirname "$1")
  while ! path_exists "$parent_path"; do
    [ "$parent_path" != "$(dirname "$parent_path")" ] || break
    parent_path=$(dirname "$parent_path")
  done
  printf '%s\n' "$parent_path"
}

preflight_target() {
  local target_path="$1" parent_path
  parent_path=$(nearest_existing_parent "$target_path")
  [ -d "$parent_path" ] && [ ! -L "$parent_path" ] && \
    [ -w "$parent_path" ] && [ -x "$parent_path" ] || \
    fail_install "parent collision at '$parent_path' for '$target_path' (expected a writable real directory)"
  path_exists "$target_path" || return 0
  [ -f "$target_path" ] && [ ! -L "$target_path" ] && [ -r "$target_path" ] || \
    fail_install "collision at '$target_path' (expected a readable regular file)"
}

next_backup_path() {
  local target_path="$1" candidate="${1}.bak.${STAMP}" suffix="0"
  while path_exists "$candidate"; do
    suffix=$((suffix + 1))
    candidate="${target_path}.bak.${STAMP}.${suffix}"
  done
  printf '%s\n' "$candidate"
}

backup_target() {
  local target_path="$1" backup_path
  backup_path=$(next_backup_path "$target_path")
  log_install_step "backup $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] || cp -p "$target_path" "$backup_path"
}

install_file() {
  local source_path="$1" target_path="$2"
  if path_exists "$target_path" && cmp -s "$source_path" "$target_path"; then
    log_install_step "keep $target_path (current)"
    return
  fi
  path_exists "$target_path" && backup_target "$target_path"
  log_install_step "install $target_path"
  [ "$DRY_RUN" = "1" ] || mkdir -p "$(dirname "$target_path")"
  [ "$DRY_RUN" = "1" ] || install -m 0644 "$source_path" "$target_path"
}

parse_args() {
  DRY_RUN="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN="1"; shift ;;
      --with-tmux) shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) fail_install "unknown option '$1'" ;;
    esac
  done
}

preflight_sources() {
  local source_path
  for source_path in "$SKILL_FILE" "$COMMAND_FILE"; do
    [ -f "$source_path" ] && [ -r "$source_path" ] || \
      fail_install "missing readable source file '$source_path'"
  done
}

preflight_destinations() {
  local target_path
  for target_path in "$PI_SKILL" "$PI_PROMPT" "$CLAUDE_SKILL" "$CLAUDE_COMMAND"; do
    preflight_target "$target_path"
  done
}

install_managed_files() {
  install_file "$SKILL_FILE" "$PI_SKILL"
  install_file "$COMMAND_FILE" "$PI_PROMPT"
  install_file "$SKILL_FILE" "$CLAUDE_SKILL"
  install_file "$COMMAND_FILE" "$CLAUDE_COMMAND"
}

initialize_paths() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  PI_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
  SKILL_FILE="$SKILL_DIR/SKILL.md"
  COMMAND_FILE="$SKILL_DIR/templates/failure-we-fear-most.md"
  PI_SKILL="$PI_DIR/skills/failure-we-fear-most/SKILL.md"
  PI_PROMPT="$PI_DIR/prompts/failure-we-fear-most.md"
  CLAUDE_SKILL="$CLAUDE_DIR/skills/failure-we-fear-most/SKILL.md"
  CLAUDE_COMMAND="$CLAUDE_DIR/commands/failure-we-fear-most.md"
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
}

main() {
  parse_args "$@"
  initialize_paths
  preflight_sources
  preflight_destinations
  install_managed_files
  log_install_step "restart Pi and Claude Code to reload skill discovery"
  log_install_step "done"
}

main "$@"
