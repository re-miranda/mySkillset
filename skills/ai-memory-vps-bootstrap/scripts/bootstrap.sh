#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: bootstrap.sh [options]

Preview or apply a loopback-only native ai-memory VPS bootstrap.

Options:
  --apply                 Perform the planned mutations
  --enable-persistence    Enable the user service and user lingering
  --help, -h              Show this help

Environment:
  AI_MEMORY_BIN           ai-memory executable (default: command lookup)
  AI_MEMORY_DATA_DIR      authoritative data directory
  AI_MEMORY_CONFIG_DIR    config directory
  AI_MEMORY_SYSTEMD_DIR   user unit directory
  PI_AGENT_DIR            Pi agent directory
USAGE
}

fail_bootstrap() {
  printf 'bootstrap.sh: %s\n' "$1" >&2
  exit 1
}

parse_args() {
  APPLY="0" ENABLE_PERSISTENCE="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply) APPLY="1"; shift ;;
      --enable-persistence) ENABLE_PERSISTENCE="1"; shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) fail_bootstrap "unknown option '$1' (expected --apply, --enable-persistence, or --help)" ;;
    esac
  done
}

initialize_paths() {
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  SKILL_DIR=$(dirname "$SCRIPT_DIR")
  DATA_DIR="${AI_MEMORY_DATA_DIR:-$HOME/.local/share/ai-memory}"
  CONFIG_DIR="${AI_MEMORY_CONFIG_DIR:-$HOME/.config/ai-memory}"
  SYSTEMD_DIR="${AI_MEMORY_SYSTEMD_DIR:-$HOME/.config/systemd/user}"
  PI_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
  ENV_FILE="$CONFIG_DIR/env"
  UNIT_FILE="$SYSTEMD_DIR/ai-memory.service"
  TEMPLATE_FILE="$SKILL_DIR/templates/ai-memory.service.in"
  VERIFY_SCRIPT="$SCRIPT_DIR/verify.sh"
  SYSTEMCTL="${AI_MEMORY_SYSTEMCTL:-systemctl}"
  LOGINCTL="${AI_MEMORY_LOGINCTL:-loginctl}"
}

resolve_ai_memory() {
  local candidate
  candidate=$(command -v "${AI_MEMORY_BIN:-ai-memory}" 2>/dev/null) || \
    fail_bootstrap "ai-memory executable '${AI_MEMORY_BIN:-ai-memory}' was not found"
  AI_MEMORY_EXEC=$(readlink -f "$candidate")
  [ -x "$AI_MEMORY_EXEC" ] || \
    fail_bootstrap "resolved ai-memory path '$AI_MEMORY_EXEC' is not executable"
  AI_MEMORY_EXEC_DIR=$(dirname "$AI_MEMORY_EXEC")
}

require_safe_unit_path() {
  local path="$1"
  [[ "$path" =~ ^/[A-Za-z0-9._/-]+$ ]] || \
    fail_bootstrap "path '$path' cannot be rendered safely (expected an absolute path containing only letters, digits, dot, underscore, slash, or hyphen)"
}

preflight_paths() {
  local path
  [ -d "$DATA_DIR" ] || \
    fail_bootstrap "authoritative data directory '$DATA_DIR' is missing (expected an existing migrated or initialized data directory)"
  [ -r "$TEMPLATE_FILE" ] || fail_bootstrap "service template '$TEMPLATE_FILE' is missing or unreadable"
  [ -x "$VERIFY_SCRIPT" ] || fail_bootstrap "verification script '$VERIFY_SCRIPT' is missing or not executable"
  for path in "$AI_MEMORY_EXEC" "$AI_MEMORY_EXEC_DIR" "$DATA_DIR" "$CONFIG_DIR" \
    "$CONFIG_FILE" "$ENV_FILE"; do
    require_safe_unit_path "$path"
  done
}

preflight_existing_files() {
  if [ -e "$CONFIG_FILE" ] || [ -L "$CONFIG_FILE" ]; then
    validate_config
  fi
  if [ -e "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
    read_auth_token >/dev/null
  fi
  if [ -e "$UNIT_FILE" ] || [ -L "$UNIT_FILE" ]; then
    validate_existing_unit
  fi
}

validate_config() {
  [ -f "$CONFIG_FILE" ] && [ ! -L "$CONFIG_FILE" ] || \
    fail_bootstrap "config '$CONFIG_FILE' has the wrong shape (expected a regular file)"
  grep -Fxq 'bind = "127.0.0.1:49374"' "$CONFIG_FILE" || \
    fail_bootstrap "config '$CONFIG_FILE' has the wrong bind (expected 127.0.0.1:49374)"
  grep -Eq '^token_pepper[[:space:]]*=[[:space:]]*"[0-9a-fA-F]+"[[:space:]]*$' "$CONFIG_FILE" || \
    fail_bootstrap "config '$CONFIG_FILE' has no generated token pepper (expected a non-empty hexadecimal token_pepper)"
}

read_auth_token() {
  local token_line token_count
  [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ] || \
    fail_bootstrap "env '$ENV_FILE' has the wrong shape (expected a regular file)"
  token_count=$(grep -Ec '^AI_MEMORY_AUTH_TOKEN=[0-9a-f]{64}$' "$ENV_FILE" || true)
  [ "$token_count" -eq 1 ] || \
    fail_bootstrap "env '$ENV_FILE' has the wrong token shape (expected exactly one 64-character lowercase hexadecimal AI_MEMORY_AUTH_TOKEN)"
  token_line=$(grep -E '^AI_MEMORY_AUTH_TOKEN=[0-9a-f]{64}$' "$ENV_FILE")
  printf '%s\n' "${token_line#*=}"
}

create_config() {
  local staging_root
  if [ -e "$CONFIG_FILE" ] || [ -L "$CONFIG_FILE" ]; then
    validate_config
    chmod 0600 "$CONFIG_FILE"
    printf 'keep %s (compatible)\n' "$CONFIG_FILE"
    return
  fi
  staging_root=$(mktemp -d "${TMPDIR:-/tmp}/ai-memory-config.XXXXXX")
  trap "rm -rf -- '$staging_root'" EXIT
  "$AI_MEMORY_EXEC" --data-dir "$staging_root/data" --config "$staging_root/config.toml" init >/dev/null
  install -m 0600 "$staging_root/config.toml" "$CONFIG_FILE"
  validate_config
  rm -rf -- "$staging_root"
  trap - EXIT
  printf 'install %s\n' "$CONFIG_FILE"
}

create_env() {
  local token temporary_env
  if [ -e "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
    read_auth_token >/dev/null
    chmod 0600 "$ENV_FILE"
    printf 'keep %s (compatible)\n' "$ENV_FILE"
    return
  fi
  token=$("$AI_MEMORY_EXEC" generate-auth-token)
  [[ "$token" =~ ^[0-9a-f]{64}$ ]] || \
    fail_bootstrap "generated token has the wrong shape (expected 64 lowercase hexadecimal characters)"
  temporary_env=$(mktemp "$CONFIG_DIR/.env.XXXXXX")
  printf 'AI_MEMORY_AUTH_TOKEN=%s\n' "$token" > "$temporary_env"
  chmod 0600 "$temporary_env"
  mv -f "$temporary_env" "$ENV_FILE"
  unset token
  printf 'install %s\n' "$ENV_FILE"
}

render_unit() {
  local target="$1"
  awk -v executable="$AI_MEMORY_EXEC" -v executable_dir="$AI_MEMORY_EXEC_DIR" \
    -v data_dir="$DATA_DIR" -v config_dir="$CONFIG_DIR" \
    -v config_file="$CONFIG_FILE" -v env_file="$ENV_FILE" '
      { gsub(/@AI_MEMORY_EXEC@/, executable)
        gsub(/@AI_MEMORY_EXEC_DIR@/, executable_dir)
        gsub(/@DATA_DIR@/, data_dir)
        gsub(/@CONFIG_DIR@/, config_dir)
        gsub(/@CONFIG_FILE@/, config_file)
        gsub(/@ENV_FILE@/, env_file)
        print }
    ' "$TEMPLATE_FILE" > "$target"
}

validate_existing_unit() {
  [ -f "$UNIT_FILE" ] && [ ! -L "$UNIT_FILE" ] || \
    fail_bootstrap "unit '$UNIT_FILE' has the wrong shape (expected a regular file)"
  grep -Fq -- '--bind 127.0.0.1:49374' "$UNIT_FILE" || \
    fail_bootstrap "unit '$UNIT_FILE' has the wrong bind (expected 127.0.0.1:49374)"
  grep -Fq "EnvironmentFile=$ENV_FILE" "$UNIT_FILE" || \
    grep -Fq 'EnvironmentFile=%h/.config/ai-memory/env' "$UNIT_FILE" || \
    fail_bootstrap "unit '$UNIT_FILE' has the wrong environment file (expected '$ENV_FILE')"
}

install_unit() {
  local rendered_unit
  if [ -e "$UNIT_FILE" ] || [ -L "$UNIT_FILE" ]; then
    validate_existing_unit
    chmod 0600 "$UNIT_FILE"
    printf 'keep %s (compatible)\n' "$UNIT_FILE"
    return
  fi
  rendered_unit=$(mktemp "$SYSTEMD_DIR/.ai-memory.service.XXXXXX")
  render_unit "$rendered_unit"
  install -m 0600 "$rendered_unit" "$UNIT_FILE"
  rm -f "$rendered_unit"
  printf 'install %s\n' "$UNIT_FILE"
}

start_service() {
  "$SYSTEMCTL" --user daemon-reload
  "$SYSTEMCTL" --user start ai-memory.service
  printf 'start ai-memory.service\n'
}

install_pi_extension() {
  local token
  token=$(read_auth_token)
  AI_MEMORY_SERVER_URL=http://127.0.0.1:49374 AI_MEMORY_AUTH_TOKEN="$token" \
    "$AI_MEMORY_EXEC" --data-dir "$DATA_DIR" --config "$CONFIG_FILE" \
    install-hooks --agent pi --apply >/dev/null
  unset token
  printf 'install %s/extensions/ai-memory.ts\n' "$PI_DIR"
}

enable_persistence() {
  [ "$ENABLE_PERSISTENCE" = "1" ] || return 0
  "$LOGINCTL" enable-linger "$USER" || \
    fail_bootstrap "loginctl could not enable lingering for '$USER' (expected local authorization; rerun it interactively)"
  "$SYSTEMCTL" --user enable ai-memory.service
  printf 'enable ai-memory.service and lingering for %s\n' "$USER"
}

show_plan() {
  printf '%s\n' 'Preview only; no files or services were changed.'
  printf 'data: %s (kept authoritative)\n' "$DATA_DIR"
  printf 'config: %s (create if absent; refuse incompatible)\n' "$CONFIG_FILE"
  printf 'bearer env: %s (generate locally if absent; never print)\n' "$ENV_FILE"
  printf 'unit: %s (create if absent; refuse incompatible)\n' "$UNIT_FILE"
  printf 'Pi hooks: install generated loopback integration\n'
  [ "$ENABLE_PERSISTENCE" != "1" ] || printf 'persistence: enable service and user lingering\n'
  printf '%s\n' 'Run again with --apply after explicit approval.'
}

apply_bootstrap() {
  mkdir -p -m 0700 "$CONFIG_DIR"
  mkdir -p "$SYSTEMD_DIR"
  create_config
  create_env
  install_unit
  start_service
  install_pi_extension
  enable_persistence
  local verify_args=()
  [ "$ENABLE_PERSISTENCE" != "1" ] || verify_args+=(--expect-persistent)
  "$VERIFY_SCRIPT" "${verify_args[@]}"
}

main() {
  parse_args "$@"
  initialize_paths
  resolve_ai_memory
  preflight_paths
  preflight_existing_files
  if [ "$APPLY" != "1" ]; then
    show_plan
    return
  fi
  apply_bootstrap
}

main "$@"
