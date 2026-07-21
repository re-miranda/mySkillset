#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the Claude ↔ Pi tmux companion workflow into ~/.claude.

Options:
  --with-tmux   Append the recommended tmux config to ~/.tmux.conf
  --dry-run     Print actions without writing files
  --help, -h    Show this help

Environment:
  CLAUDE_HOME   Override the Claude config directory (default: ~/.claude)
USAGE
}

log_install_step() {
  [ "${DRY_RUN:-0}" != "1" ] || { printf 'dry-run: %s\n' "$1"; return; }
  printf '%s\n' "$1"
}

ensure_parent_dir() {
  local target_path="$1"
  [ "$DRY_RUN" = "1" ] || mkdir -p "$(dirname "$target_path")"
}

backup_copy() {
  local target_path="$1" backup_path="${target_path}.bak.${STAMP}"
  log_install_step "backup $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] || cp -p "$target_path" "$backup_path"
}

copy_workflow_file() {
  local source_path="$1" target_path="$2" file_mode="$3"
  ensure_parent_dir "$target_path"
  if [ -e "$target_path" ] && cmp -s "$source_path" "$target_path"; then
    log_install_step "keep $target_path (current)"
    return
  fi
  [ ! -e "$target_path" ] || backup_copy "$target_path"
  log_install_step "install $target_path"
  [ "$DRY_RUN" = "1" ] || install -m "$file_mode" "$source_path" "$target_path"
}

extract_marked_block() {
  local target_path="$1" begin_marker="$2" end_marker="$3" output_path="$4"
  awk -v begin="$begin_marker" -v end="$end_marker" '
    index($0, begin) { copying=1 }
    copying { print }
    copying && index($0, end) { exit }
  ' "$target_path" > "$output_path"
}

strip_marked_block() {
  local target_path="$1" begin_marker="$2" end_marker="$3" output_path="$4"
  awk -v begin="$begin_marker" -v end="$end_marker" '
    index($0, begin) { skipping=1; next }
    skipping && index($0, end) { skipping=0; next }
    !skipping { print }
  ' "$target_path" > "$output_path"
}

is_legacy_pi_protocol() {
  local target_path="$1"
  grep -Fq '# Collaboration Protocol' "$target_path" && \
    grep -Fq '## Receiving Pi messages' "$target_path" && \
    grep -Fq 'When `[Pi/<name>] <message>` appears' "$target_path"
}

write_candidate_with_block() {
  local source_path="$1" target_path="$2" begin_marker="$3" end_marker="$4" output_path="$5"
  strip_marked_block "$target_path" "$begin_marker" "$end_marker" "$output_path"
  printf '\n' >> "$output_path"
  cat "$source_path" >> "$output_path"
}

install_claude_addendum() {
  local source_path="$SKILL_DIR/integrations/claude/CLAUDE.addendum.md" target_path="$CLAUDE_DIR/CLAUDE.md"
  local begin='<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->' end='<!-- END CLAUDE-PI-TMUX-WORKFLOW -->'
  ensure_parent_dir "$target_path"
  if [ ! -f "$target_path" ]; then
    log_install_step "install $target_path"
    [ "$DRY_RUN" = "1" ] || cp "$source_path" "$target_path"
    return
  fi
  install_existing_claude_addendum "$source_path" "$target_path" "$begin" "$end"
}

replace_marked_claude_block() {
  local source_path="$1" target_path="$2" begin="$3" end="$4" candidate="$5"
  write_candidate_with_block "$source_path" "$target_path" "$begin" "$end" "$candidate"
  backup_copy "$target_path"
  log_install_step "replace workflow block in $target_path"
  [ "$DRY_RUN" = "1" ] || mv "$candidate" "$target_path"
}

install_existing_claude_addendum() {
  local source_path="$1" target_path="$2" begin="$3" end="$4" current candidate
  current=$(mktemp)
  candidate=$(mktemp)
  extract_marked_block "$target_path" "$begin" "$end" "$current"
  if cmp -s "$source_path" "$current"; then
    log_install_step "keep $target_path workflow block (current)"
  elif [ -s "$current" ]; then
    replace_marked_claude_block "$source_path" "$target_path" "$begin" "$end" "$candidate"
  elif is_legacy_pi_protocol "$target_path"; then
    backup_copy "$target_path"
    log_install_step "replace legacy Pi protocol in $target_path"
    [ "$DRY_RUN" = "1" ] || cp "$source_path" "$target_path"
  else
    log_install_step "append workflow block to $target_path"
    [ "$DRY_RUN" = "1" ] || { printf '\n'; cat "$source_path"; } >> "$target_path"
  fi
  rm -f "$current" "$candidate"
}

append_tmux_addendum_once() {
  local source_path="$SKILL_DIR/integrations/tmux/tmux.conf.addendum" target_path="$HOME/.tmux.conf"
  ensure_parent_dir "$target_path"
  if [ -f "$target_path" ] && grep -Fq 'BEGIN CLAUDE-PI-TMUX-WORKFLOW' "$target_path"; then
    log_install_step "keep $target_path workflow block (current)"
    return
  fi
  log_install_step "append $source_path -> $target_path"
  [ "$DRY_RUN" = "1" ] || { printf '\n'; cat "$source_path"; } >> "$target_path"
}

parse_args() {
  INSTALL_TMUX="0"
  DRY_RUN="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --with-tmux) INSTALL_TMUX="1"; shift ;;
      --dry-run) DRY_RUN="1"; shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) printf 'install.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
  done
}

install_claude_files() {
  copy_workflow_file "$SKILL_DIR/SKILL.md" "$CLAUDE_DIR/skills/tmux-pi-subagents/SKILL.md" 0644
  copy_workflow_file "$SKILL_DIR/references/KNOWN_FAILURES.md" "$CLAUDE_DIR/skills/tmux-pi-subagents/references/KNOWN_FAILURES.md" 0644
  copy_workflow_file "$SKILL_DIR/integrations/claude/commands/spawn-pi.md" "$CLAUDE_DIR/commands/spawn-pi.md" 0644
  copy_workflow_file "$SKILL_DIR/integrations/claude/commands/pi-subagents.md" "$CLAUDE_DIR/commands/pi-subagents.md" 0644
  copy_workflow_file "$SKILL_DIR/integrations/claude/commands/tmux-subagents.md" "$CLAUDE_DIR/commands/tmux-subagents.md" 0644
  copy_workflow_file "$SKILL_DIR/integrations/claude/commands/poll.md" "$CLAUDE_DIR/commands/poll.md" 0644
  copy_workflow_file "$SKILL_DIR/scripts/spawn-pi-agent" "$CLAUDE_DIR/bin/spawn-pi-agent" 0755
  copy_workflow_file "$SKILL_DIR/scripts/verify-pi-delivery" "$CLAUDE_DIR/bin/verify-pi-delivery" 0755
  copy_workflow_file "$SKILL_DIR/scripts/watch-pi-agent" "$CLAUDE_DIR/bin/watch-pi-agent" 0755
  copy_workflow_file "$SKILL_DIR/scripts/poll-pi-agent" "$CLAUDE_DIR/bin/poll-pi-agent" 0755
  copy_workflow_file "$SKILL_DIR/scripts/cleanup-pi-agent" "$CLAUDE_DIR/bin/cleanup-pi-agent" 0755
}

main() {
  parse_args "$@"
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
  install_claude_files
  install_claude_addendum
  [ "$INSTALL_TMUX" != "1" ] || append_tmux_addendum_once
  [ "$INSTALL_TMUX" = "1" ] || log_install_step "tmux config not changed; rerun with --with-tmux to append it"
  log_install_step "done"
}

main "$@"
