#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the convergent-technical-audit skill.

Options:
  --target <name>  Install to pi, claude, or both (default: both)
  --dry-run        Print actions without writing files
  --with-tmux      Accepted for repository-level compatibility; no effect
  --help, -h       Show this help

Environment:
  PI_HOME          Override the Pi agent directory (default: ~/.pi/agent)
  CLAUDE_HOME      Override the Claude config directory (default: ~/.claude)
USAGE
}

fail_install() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 2
}

log_install_step() {
  [ "$DRY_RUN" != "1" ] || { printf 'dry-run: %s\n' "$1"; return; }
  printf '%s\n' "$1"
}

reserve_backup_path() {
  local base_path="$1.bak.$STAMP" candidate_path counter="0"
  while :; do
    candidate_path="$base_path"
    [ "$counter" = "0" ] || candidate_path="$base_path.$counter"
    if [ "$DRY_RUN" = "1" ]; then
      if [ ! -e "$candidate_path" ] && [ ! -L "$candidate_path" ] && [ ! -e "$candidate_path.lock" ]; then
        printf '%s\n' "$candidate_path"
        return
      fi
    elif [ ! -e "$candidate_path" ] && [ ! -L "$candidate_path" ] && \
        mkdir "$candidate_path.lock" 2>/dev/null; then
      printf '%s\n' "$candidate_path"
      return
    fi
    counter=$((counter + 1))
  done
}

backup_existing_file() {
  local target_path="$1" backup_path
  backup_path=$(reserve_backup_path "$target_path")
  log_install_step "backup $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] && return
  cp -p "$target_path" "$backup_path" || {
    rmdir "$backup_path.lock" 2>/dev/null || true
    fail_install "failed to back up '$target_path' to '$backup_path'"
  }
  rmdir "$backup_path.lock"
}

install_skill_file() {
  local source_path="$1" target_path="$2"
  [ "$DRY_RUN" = "1" ] || mkdir -p "$(dirname "$target_path")"
  if [ -e "$target_path" ] && cmp -s "$source_path" "$target_path"; then
    log_install_step "keep $target_path (current)"
    return
  fi
  [ ! -e "$target_path" ] || backup_existing_file "$target_path"
  log_install_step "install $target_path"
  [ "$DRY_RUN" = "1" ] || install -m 0644 "$source_path" "$target_path"
}

install_target() {
  local agent_home="$1" target_dir="$1/skills/convergent-technical-audit"
  install_skill_file "$SKILL_DIR/SKILL.md" "$target_dir/SKILL.md"
  install_skill_file "$SKILL_DIR/references/STATE_AND_SCHEMAS.md" \
    "$target_dir/references/STATE_AND_SCHEMAS.md"
}

parse_args() {
  DRY_RUN="0"
  TARGET="both"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target)
        [ "$#" -ge 2 ] || fail_install "missing value for '--target' (expected pi, claude, or both)"
        TARGET="$2"; shift 2 ;;
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

main() {
  parse_args "$@"
  validate_target
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  PI_DIR="${PI_HOME:-$HOME/.pi/agent}"
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
  [ "$TARGET" = "claude" ] || install_target "$PI_DIR"
  [ "$TARGET" = "pi" ] || install_target "$CLAUDE_DIR"
  log_install_step "done"
}

main "$@"
