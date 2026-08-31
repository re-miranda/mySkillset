#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Install the ai-memory-vps-bootstrap skill for Pi and Claude Code.

Options:
  --target <name>  Install to pi, claude, or both (default: both)
  --dry-run        Print actions without writing files
  --with-tmux      Accepted for repository-level compatibility; no effect
  --help, -h       Show this help

Environment:
  PI_AGENT_DIR     Pi agent directory (default: ~/.pi/agent)
  CLAUDE_HOME      Claude config directory (default: ~/.claude)
USAGE
}

fail_install() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

parse_args() {
  DRY_RUN="0" TARGET="both"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target) [ "$#" -ge 2 ] || fail_install "missing value for '--target'"; TARGET="$2"; shift 2 ;;
      --dry-run) DRY_RUN="1"; shift ;;
      --with-tmux) shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) fail_install "unknown option '$1' (expected --target, --dry-run, --with-tmux, or --help)" ;;
    esac
  done
}

validate_target() {
  case "$TARGET" in
    pi|claude|both) return ;;
    *) fail_install "invalid target '$TARGET' (expected pi, claude, or both)" ;;
  esac
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

preflight_file() {
  local target_path="$1" parent_path
  parent_path=$(nearest_existing_parent "$target_path")
  [ -d "$parent_path" ] && [ ! -L "$parent_path" ] && [ -w "$parent_path" ] || \
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

log_step() {
  [ "$DRY_RUN" != "1" ] || { printf 'dry-run: %s\n' "$1"; return; }
  printf '%s\n' "$1"
}

install_file() {
  local source_path="$1" target_path="$2" mode="$3" backup_path
  if path_exists "$target_path" && cmp -s "$source_path" "$target_path"; then
    log_step "keep $target_path (current)"
    return
  fi
  if path_exists "$target_path"; then
    backup_path=$(next_backup_path "$target_path")
    log_step "backup $target_path -> $backup_path"
    [ "$DRY_RUN" = "1" ] || cp -p "$target_path" "$backup_path"
  fi
  log_step "install $target_path"
  [ "$DRY_RUN" = "1" ] || mkdir -p "$(dirname "$target_path")"
  [ "$DRY_RUN" = "1" ] || install -m "$mode" "$source_path" "$target_path"
}

preflight_target() {
  local target_dir="$1" relative_path
  for relative_path in SKILL.md scripts/bootstrap.sh scripts/verify.sh templates/ai-memory.service.in; do
    preflight_file "$target_dir/$relative_path"
  done
}

install_target() {
  local target_dir="$1"
  install_file "$SKILL_DIR/SKILL.md" "$target_dir/SKILL.md" 0644
  install_file "$SKILL_DIR/scripts/bootstrap.sh" "$target_dir/scripts/bootstrap.sh" 0755
  install_file "$SKILL_DIR/scripts/verify.sh" "$target_dir/scripts/verify.sh" 0755
  install_file "$SKILL_DIR/templates/ai-memory.service.in" \
    "$target_dir/templates/ai-memory.service.in" 0644
}

main() {
  parse_args "$@"
  validate_target
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  PI_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}/skills/ai-memory-vps-bootstrap"
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}/skills/ai-memory-vps-bootstrap"
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
  [ "$TARGET" = "claude" ] || preflight_target "$PI_DIR"
  [ "$TARGET" = "pi" ] || preflight_target "$CLAUDE_DIR"
  [ "$TARGET" = "claude" ] || install_target "$PI_DIR"
  [ "$TARGET" = "pi" ] || install_target "$CLAUDE_DIR"
  log_step 'restart Pi and Claude Code to reload skill discovery'
  log_step 'done'
}

main "$@"
