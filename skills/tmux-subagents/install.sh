#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the generic tmux-subagents skill for both Claude Code and Pi.

Options:
  --with-tmux   Install or update the recommended block in ~/.tmux.conf
  --dry-run     Print actions without writing files
  --help, -h    Show this help

Environment:
  CLAUDE_HOME                Claude config directory (default: ~/.claude)
  PI_AGENT_DIR               Pi agent directory (default: ~/.pi/agent)
  PI_SUBAGENT_EXTENSION_DIR  interactive-subagents root (overrides checkout discovery)
USAGE
}

fail_install() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

log_install_step() {
  [ "$DRY_RUN" != "1" ] || { printf 'dry-run: %s\n' "$1"; return; }
  printf '%s\n' "$1"
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

ensure_parent_dir() {
  [ "$DRY_RUN" = "1" ] || mkdir -p "$(dirname "$1")"
}

next_backup_path() {
  local target_path="$1" candidate="${1}.bak.${STAMP}" suffix="0"
  while path_exists "$candidate"; do
    suffix=$((suffix + 1))
    candidate="${target_path}.bak.${STAMP}.${suffix}"
  done
  printf '%s\n' "$candidate"
}

backup_file() {
  local target_path="$1" backup_path
  backup_path=$(next_backup_path "$target_path")
  log_install_step "backup $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] || cp -p "$target_path" "$backup_path"
}

archive_legacy_path() {
  local target_path="$1" backup_path
  path_exists "$target_path" || return 0
  backup_path=$(next_backup_path "$target_path")
  log_install_step "archive legacy $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] || mv "$target_path" "$backup_path"
}

archive_discovery_path() {
  local target_path="$1" backup_root="$2" backup_path
  path_exists "$target_path" || return 0
  backup_path=$(next_backup_path "$backup_root/$(basename "$target_path")")
  log_install_step "archive retired discovery path $target_path -> $backup_path"
  [ "$DRY_RUN" = "1" ] || { mkdir -p "$backup_root"; mv "$target_path" "$backup_path"; }
}

require_replaceable_file() {
  local target_path="$1"
  path_exists "$target_path" || return 0
  [ -f "$target_path" ] && [ ! -L "$target_path" ] || \
    fail_install "collision at '$target_path' (expected a regular file, not a directory or symlink)"
}

preflight_parent_directory() {
  local target_path="$1" parent_path
  parent_path=$(dirname "$target_path")
  while ! path_exists "$parent_path"; do
    [ "$parent_path" != "$(dirname "$parent_path")" ] || break
    parent_path=$(dirname "$parent_path")
  done
  [ -d "$parent_path" ] && [ ! -L "$parent_path" ] && \
    [ -w "$parent_path" ] && [ -x "$parent_path" ] || \
    fail_install "parent collision at '$parent_path' for '$target_path' (expected a writable real directory)"
}

preflight_destination_file() {
  preflight_parent_directory "$1"
  require_replaceable_file "$1"
  path_exists "$1" && [ ! -r "$1" ] && \
    fail_install "collision at '$1' (expected a readable managed destination)"
  return 0
}

copy_workflow_file() {
  local source_path="$1" target_path="$2" file_mode="$3"
  ensure_parent_dir "$target_path"
  require_replaceable_file "$target_path"
  if path_exists "$target_path" && cmp -s "$source_path" "$target_path"; then
    log_install_step "keep $target_path (current)"
    return
  fi
  path_exists "$target_path" && backup_file "$target_path"
  log_install_step "install $target_path"
  [ "$DRY_RUN" = "1" ] || install -m "$file_mode" "$source_path" "$target_path"
}

strip_known_blocks() {
  local target_path="$1" output_path="$2" new_begin="$3" new_end="$4"
  local old_begin="$5" old_end="$6"
  awk -v nb="$new_begin" -v ne="$new_end" -v ob="$old_begin" -v oe="$old_end" '
    $0 == nb { if (kind != "") malformed=1; kind="new"; next }
    $0 == ob { if (kind != "") malformed=1; kind="old"; next }
    $0 == ne { if (kind != "new") malformed=1; kind=""; next }
    $0 == oe { if (kind != "old") malformed=1; kind=""; next }
    kind == "" { print }
    END { if (kind != "" || malformed) exit 4 }
  ' "$target_path" > "$output_path" || \
    fail_install "malformed managed block in '$target_path' (expected matching marker lines)"
}

trim_trailing_blank_lines() {
  awk '
    { lines[NR]=$0 }
    END {
      last=NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (line=1; line <= last; line++) print lines[line]
    }
  ' "$1" > "$2"
}

build_marked_candidate() {
  local source_path="$1" target_path="$2" candidate="$3" new_begin="$4"
  local new_end="$5" old_begin="$6" old_end="$7" stripped trimmed
  stripped=$(mktemp)
  trimmed=$(mktemp)
  strip_known_blocks "$target_path" "$stripped" "$new_begin" "$new_end" "$old_begin" "$old_end"
  trim_trailing_blank_lines "$stripped" "$trimmed"
  cat "$trimmed" > "$candidate"
  [ ! -s "$trimmed" ] || printf '\n\n' >> "$candidate"
  cat "$source_path" >> "$candidate"
  rm -f "$stripped" "$trimmed"
}

apply_marked_candidate() {
  local candidate="$1" target_path="$2"
  if cmp -s "$candidate" "$target_path"; then
    log_install_step "keep $target_path workflow block (current)"
    return
  fi
  [ "$DRY_RUN" = "1" ] || chmod --reference="$target_path" "$candidate"
  backup_file "$target_path"
  log_install_step "update workflow block in $target_path"
  [ "$DRY_RUN" = "1" ] || mv -f "$candidate" "$target_path"
}

upsert_marked_file() {
  local source_path="$1" target_path="$2" file_mode="$3" new_begin="$4"
  local new_end="$5" old_begin="$6" old_end="$7" candidate
  ensure_parent_dir "$target_path"
  require_replaceable_file "$target_path"
  if ! path_exists "$target_path"; then
    copy_workflow_file "$source_path" "$target_path" "$file_mode"
    return
  fi
  candidate=$(mktemp)
  build_marked_candidate "$source_path" "$target_path" "$candidate" \
    "$new_begin" "$new_end" "$old_begin" "$old_end"
  apply_marked_candidate "$candidate" "$target_path"
  rm -f "$candidate"
}

is_unmarked_legacy_protocol() {
  local target_path="$1"
  grep -Fq '# Collaboration Protocol' "$target_path" && \
    grep -Fq '## Receiving Pi messages' "$target_path" && \
    grep -Fq 'When `[Pi/<name>] <message>` appears' "$target_path"
}

has_claude_workflow_marker() {
  local target_path="$1"
  grep -Fxq '<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->' "$target_path" || \
    grep -Fxq '<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->' "$target_path"
}

preflight_claude_instructions() {
  local target_path="$CLAUDE_DIR/CLAUDE.md" scratch
  preflight_destination_file "$target_path"
  path_exists "$target_path" || return 0
  if is_unmarked_legacy_protocol "$target_path" && ! has_claude_workflow_marker "$target_path"; then
    fail_install "ambiguous legacy instructions in '$target_path' (preserved unchanged; move custom content or add an exact managed marker)"
  fi
  scratch=$(mktemp)
  strip_known_blocks "$target_path" "$scratch" \
    '<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->' '<!-- END TMUX-SUBAGENTS-WORKFLOW -->' \
    '<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->' '<!-- END CLAUDE-PI-TMUX-WORKFLOW -->'
  rm -f "$scratch"
}

preflight_tmux_instructions() {
  local target_path="$HOME/.tmux.conf" scratch
  [ "$INSTALL_TMUX" = "1" ] || return 0
  preflight_destination_file "$target_path"
  path_exists "$target_path" || return 0
  scratch=$(mktemp)
  strip_known_blocks "$target_path" "$scratch" \
    '# BEGIN TMUX-SUBAGENTS-WORKFLOW' '# END TMUX-SUBAGENTS-WORKFLOW' \
    '# BEGIN CLAUDE-PI-TMUX-WORKFLOW' '# END CLAUDE-PI-TMUX-WORKFLOW'
  rm -f "$scratch"
}

legacy_release_file_matches() {
  local target_path="$1" filename="$2" reference_path
  for reference_path in \
    "$SKILL_DIR/references/legacy/claude-skill/releases"/*/"$filename"; do
    cmp -s "$reference_path" "$target_path" && return 0
  done
  return 1
}

legacy_skill_entry_matches() {
  local target_dir="$1" entry_path="$2" relative
  relative=${entry_path#"$target_dir"/}
  [ -f "$entry_path" ] && [ ! -L "$entry_path" ] || return 1
  if [[ "$relative" =~ ^SKILL\.md(\.bak\.[0-9]{8}T[0-9]{6}Z(\.[0-9]+)?)?$ ]]; then
    legacy_release_file_matches "$entry_path" SKILL.signature
    return
  fi
  [[ "$relative" =~ ^references/KNOWN_FAILURES\.md(\.bak\.[0-9]{8}T[0-9]{6}Z(\.[0-9]+)?)?$ ]] || return 1
  legacy_release_file_matches "$entry_path" KNOWN_FAILURES.signature
}

legacy_skill_matches() {
  local target_path="$1" entry_path
  [ -d "$target_path" ] && [ ! -L "$target_path" ] && \
    [ -r "$target_path" ] && [ -x "$target_path" ] || return 1
  [ "$(find "$target_path" -mindepth 1 -type d | wc -l)" -eq 1 ] || return 1
  [ -f "$target_path/SKILL.md" ] || return 1
  [ -f "$target_path/references/KNOWN_FAILURES.md" ] || return 1
  while IFS= read -r -d '' entry_path; do
    legacy_skill_entry_matches "$target_path" "$entry_path" || return 1
  done < <(find "$target_path" -mindepth 1 ! -type d -print0)
}

preflight_legacy_file() {
  local target_path="$1" reference_path="$2"
  path_exists "$target_path" || return 0
  [ -f "$target_path" ] && [ ! -L "$target_path" ] && \
    cmp -s "$reference_path" "$target_path" || \
    fail_install "legacy collision at '$target_path' (preserved unchanged; expected an exact managed legacy file)"
}

preflight_legacy_skill() {
  local target_path="$1"
  path_exists "$target_path" || return 0
  legacy_skill_matches "$target_path" || \
    fail_install "legacy collision at '$target_path' (preserved unchanged; expected the released managed skill tree)"
}

preflight_legacy_paths() {
  local legacy="$SKILL_DIR/references/legacy"
  preflight_legacy_file "$CLAUDE_DIR/commands/spawn-pi.md" "$legacy/commands/spawn-pi.md"
  preflight_legacy_file "$CLAUDE_DIR/commands/pi-subagents.md" "$legacy/commands/pi-subagents.md"
  preflight_legacy_skill "$CLAUDE_DIR/skills/tmux-pi-subagents"
  preflight_legacy_skill "$PI_DIR/skills/tmux-pi-subagents"
}

archive_known_fable_helper() {
  local target_path="$CLAUDE_DIR/bin/spawn-fable-agent" actual
  # This is the released 1.2.1 helper; customized Fable tools must remain user-owned.
  local known_hash='2541aef00ea926919eef9603177c91ad99fa1ba74966f901719dbf9e1dd393d7'
  path_exists "$target_path" || return 0
  if [ -f "$target_path" ] && [ ! -L "$target_path" ]; then
    actual=$(sha256sum "$target_path" | awk '{print $1}')
    if [ "$actual" = "$known_hash" ]; then
      archive_legacy_path "$target_path"
      return
    fi
  fi
  log_install_step "keep unmanaged $target_path (not part of tmux-subagents)"
}

migrate_legacy_paths() {
  archive_legacy_path "$CLAUDE_DIR/commands/spawn-pi.md"
  archive_legacy_path "$CLAUDE_DIR/commands/pi-subagents.md"
  archive_discovery_path "$CLAUDE_DIR/skills/tmux-pi-subagents" \
    "$CLAUDE_DIR/backups/tmux-subagents/skills"
  archive_discovery_path "$PI_DIR/skills/tmux-pi-subagents" \
    "$PI_DIR/backups/tmux-subagents/skills"
  archive_known_fable_helper
}

install_claude_addendum() {
  upsert_marked_file "$SKILL_DIR/integrations/claude/CLAUDE.addendum.md" \
    "$CLAUDE_DIR/CLAUDE.md" 0644 \
    '<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->' '<!-- END TMUX-SUBAGENTS-WORKFLOW -->' \
    '<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->' '<!-- END CLAUDE-PI-TMUX-WORKFLOW -->'
}

install_tmux_addendum() {
  upsert_marked_file "$SKILL_DIR/integrations/tmux/tmux.conf.addendum" \
    "$HOME/.tmux.conf" 0644 \
    '# BEGIN TMUX-SUBAGENTS-WORKFLOW' '# END TMUX-SUBAGENTS-WORKFLOW' \
    '# BEGIN CLAUDE-PI-TMUX-WORKFLOW' '# END CLAUDE-PI-TMUX-WORKFLOW'
}

install_skill_tree() {
  local target_dir="$1"
  copy_workflow_file "$SKILL_DIR/SKILL.md" "$target_dir/SKILL.md" 0644
  copy_workflow_file "$SKILL_DIR/references/CLAUDE_TO_PI_BRIDGE.md" \
    "$target_dir/references/CLAUDE_TO_PI_BRIDGE.md" 0644
  copy_workflow_file "$SKILL_DIR/references/KNOWN_FAILURES.md" \
    "$target_dir/references/KNOWN_FAILURES.md" 0644
}

install_claude_bridge() {
  local command_dir="$CLAUDE_DIR/commands" bin_dir="$CLAUDE_DIR/bin" script
  copy_workflow_file "$SKILL_DIR/integrations/claude/commands/tmux-subagents.md" \
    "$command_dir/tmux-subagents.md" 0644
  copy_workflow_file "$SKILL_DIR/integrations/claude/commands/poll.md" "$command_dir/poll.md" 0644
  for script in spawn-pi-agent verify-pi-delivery watch-pi-agent poll-pi-agent cleanup-pi-agent; do
    copy_workflow_file "$SKILL_DIR/scripts/$script" "$bin_dir/$script" 0755
  done
}

has_safe_claude_child_policy() {
  "$SKILL_DIR/scripts/probe-claude-child-policy" "$PI_EXTENSION_DIR" >/dev/null 2>&1
}

is_managed_claude_definition() {
  local target_path="$1"
  [ -f "$target_path" ] && [ ! -L "$target_path" ] && \
    grep -Fxq '# tmux-subagents-managed: claude-code-v1' "$target_path"
}

disable_managed_claude_definition() {
  local target_path="$PI_DIR/agents/claude-code.md"
  path_exists "$target_path" || return 0
  if is_managed_claude_definition "$target_path"; then
    archive_discovery_path "$target_path" "$PI_DIR/backups/tmux-subagents/agents"
    return
  fi
  log_install_step "keep unmanaged $target_path; tmux-subagents cannot disable it"
}

install_pi_agent_definition() {
  local target_path="$PI_DIR/agents/claude-code.md"
  if ! has_safe_claude_child_policy; then
    disable_managed_claude_definition
    log_install_step "Claude child definition not installed; expected verified auto-permissions-v1 capability in $PI_EXTENSION_DIR"
    return
  fi
  copy_workflow_file "$SKILL_DIR/integrations/pi/agents/claude-code.md" "$target_path" 0644
}

parse_args() {
  INSTALL_TMUX="0"
  DRY_RUN="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --with-tmux) INSTALL_TMUX="1"; shift ;;
      --dry-run) DRY_RUN="1"; shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) fail_install "unknown option '$1'" ;;
    esac
  done
}

preflight_skill_destination() {
  local target_dir="$1" relative_path
  for relative_path in SKILL.md references/CLAUDE_TO_PI_BRIDGE.md \
    references/KNOWN_FAILURES.md; do
    preflight_destination_file "$target_dir/$relative_path"
  done
}

preflight_bridge_destinations() {
  local target_path script
  for target_path in "$CLAUDE_DIR/commands/tmux-subagents.md" \
    "$CLAUDE_DIR/commands/poll.md"; do
    preflight_destination_file "$target_path"
  done
  for script in spawn-pi-agent verify-pi-delivery watch-pi-agent poll-pi-agent cleanup-pi-agent; do
    preflight_destination_file "$CLAUDE_DIR/bin/$script"
  done
}

preflight_backup_destinations() {
  preflight_parent_directory "$CLAUDE_DIR/backups/tmux-subagents/skills/placeholder"
  preflight_parent_directory "$PI_DIR/backups/tmux-subagents/skills/placeholder"
  preflight_parent_directory "$PI_DIR/backups/tmux-subagents/agents/placeholder"
}

preflight_install() {
  preflight_claude_instructions
  preflight_tmux_instructions
  preflight_legacy_paths
  preflight_skill_destination "$CLAUDE_DIR/skills/tmux-subagents"
  preflight_skill_destination "$PI_DIR/skills/tmux-subagents"
  preflight_destination_file "$PI_DIR/agents/claude-code.md"
  preflight_bridge_destinations
  preflight_backup_destinations
}

resolve_pi_extension_dir() {
  local candidate
  if [ -n "${PI_SUBAGENT_EXTENSION_DIR:-}" ]; then
    printf '%s\n' "$PI_SUBAGENT_EXTENSION_DIR"
    return
  fi
  for candidate in "$PI_DIR/local-packages/pi-interactive-subagents" \
    "$PI_DIR/git/github.com/re-miranda/pi-interactive-subagents" \
    "$PI_DIR/git/github.com/HazAT/pi-interactive-subagents"; do
    [ ! -d "$candidate" ] || { printf '%s\n' "$candidate"; return; }
  done
  printf '%s\n' "$PI_DIR/local-packages/pi-interactive-subagents"
}

initialize_install_paths() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
  PI_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
  PI_EXTENSION_DIR=$(resolve_pi_extension_dir)
  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
}

main() {
  parse_args "$@"
  initialize_install_paths
  preflight_install
  migrate_legacy_paths
  install_skill_tree "$CLAUDE_DIR/skills/tmux-subagents"
  install_skill_tree "$PI_DIR/skills/tmux-subagents"
  install_pi_agent_definition
  install_claude_bridge
  install_claude_addendum
  [ "$INSTALL_TMUX" != "1" ] || install_tmux_addendum
  [ "$INSTALL_TMUX" = "1" ] || log_install_step "tmux config not changed; rerun with --with-tmux to manage it"
  log_install_step "restart required: open fresh Pi and Claude Code parent sessions before using the new routing"
  log_install_step "existing agent panes are retained for inspection only; do not reuse their loaded workflow"
  log_install_step "done"
}

main "$@"
