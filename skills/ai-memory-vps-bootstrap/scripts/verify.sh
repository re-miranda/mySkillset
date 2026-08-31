#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'USAGE'
Usage: verify.sh [options]

Read-only verification for the loopback ai-memory user service.

Options:
  --expect-persistent       Require enabled service and user lingering
  --historical-query <q>    Require one compiled-wiki search hit
  --workspace <name>        Search workspace (default: default)
  --project <name>          Search project (default: derive from cwd)
  --help, -h                Show this help
USAGE
}

fail_verify() {
  printf 'verify.sh: %s\n' "$1" >&2
  exit 1
}

parse_args() {
  EXPECT_PERSISTENT="0" HISTORICAL_QUERY="" WORKSPACE="default" PROJECT=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --expect-persistent) EXPECT_PERSISTENT="1"; shift ;;
      --historical-query) [ "$#" -ge 2 ] || fail_verify "missing value for '--historical-query'"; HISTORICAL_QUERY="$2"; shift 2 ;;
      --workspace) [ "$#" -ge 2 ] || fail_verify "missing value for '--workspace'"; WORKSPACE="$2"; shift 2 ;;
      --project) [ "$#" -ge 2 ] || fail_verify "missing value for '--project'"; PROJECT="$2"; shift 2 ;;
      --help|-h) show_usage; exit 0 ;;
      *) fail_verify "unknown option '$1' (expected --expect-persistent, --historical-query, --workspace, --project, or --help)" ;;
    esac
  done
}

initialize_paths() {
  DATA_DIR="${AI_MEMORY_DATA_DIR:-$HOME/.local/share/ai-memory}"
  CONFIG_DIR="${AI_MEMORY_CONFIG_DIR:-$HOME/.config/ai-memory}"
  SYSTEMD_DIR="${AI_MEMORY_SYSTEMD_DIR:-$HOME/.config/systemd/user}"
  PI_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
  ENV_FILE="$CONFIG_DIR/env"
  UNIT_FILE="$SYSTEMD_DIR/ai-memory.service"
  PI_EXTENSION="$PI_DIR/extensions/ai-memory.ts"
  SYSTEMCTL="${AI_MEMORY_SYSTEMCTL:-systemctl}"
  LOGINCTL="${AI_MEMORY_LOGINCTL:-loginctl}"
  CURL="${AI_MEMORY_CURL:-curl}"
  SS="${AI_MEMORY_SS:-ss}"
  JOURNALCTL="${AI_MEMORY_JOURNALCTL:-journalctl}"
}

resolve_ai_memory() {
  local candidate
  candidate=$(command -v "${AI_MEMORY_BIN:-ai-memory}" 2>/dev/null) || \
    fail_verify "ai-memory executable '${AI_MEMORY_BIN:-ai-memory}' was not found"
  AI_MEMORY_EXEC=$(readlink -f "$candidate")
  [ -x "$AI_MEMORY_EXEC" ] || fail_verify "resolved ai-memory path '$AI_MEMORY_EXEC' is not executable"
}

read_auth_token() {
  local token_line token_count
  [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ] || \
    fail_verify "env '$ENV_FILE' has the wrong shape (expected a regular file)"
  token_count=$(grep -Ec '^AI_MEMORY_AUTH_TOKEN=[0-9a-f]{64}$' "$ENV_FILE" || true)
  [ "$token_count" -eq 1 ] || \
    fail_verify "env '$ENV_FILE' has the wrong token shape (expected exactly one 64-character lowercase hexadecimal AI_MEMORY_AUTH_TOKEN)"
  token_line=$(grep -E '^AI_MEMORY_AUTH_TOKEN=[0-9a-f]{64}$' "$ENV_FILE")
  printf '%s\n' "${token_line#*=}"
}

verify_files() {
  local config_mode env_mode unit_mode extension_mode
  [ -f "$CONFIG_FILE" ] && [ ! -L "$CONFIG_FILE" ] || fail_verify "missing regular config '$CONFIG_FILE'"
  [ -f "$UNIT_FILE" ] && [ ! -L "$UNIT_FILE" ] || fail_verify "missing regular unit '$UNIT_FILE'"
  [ -f "$PI_EXTENSION" ] && [ ! -L "$PI_EXTENSION" ] || fail_verify "missing regular Pi extension '$PI_EXTENSION'"
  config_mode=$(stat -c %a "$CONFIG_FILE")
  env_mode=$(stat -c %a "$ENV_FILE")
  unit_mode=$(stat -c %a "$UNIT_FILE")
  extension_mode=$(stat -c %a "$PI_EXTENSION")
  [ "$config_mode" = 600 ] || fail_verify "config '$CONFIG_FILE' has mode '$config_mode' (expected 600)"
  [ "$env_mode" = 600 ] || fail_verify "env '$ENV_FILE' has mode '$env_mode' (expected 600)"
  [ "$unit_mode" = 600 ] || fail_verify "unit '$UNIT_FILE' has mode '$unit_mode' (expected 600)"
  [ "$extension_mode" = 600 ] || fail_verify "Pi extension '$PI_EXTENSION' has mode '$extension_mode' (expected 600)"
}

verify_config() {
  grep -Fxq 'bind = "127.0.0.1:49374"' "$CONFIG_FILE" || \
    fail_verify "config '$CONFIG_FILE' has the wrong bind (expected 127.0.0.1:49374)"
  grep -Eq '^token_pepper[[:space:]]*=[[:space:]]*"[0-9a-fA-F]+"[[:space:]]*$' "$CONFIG_FILE" || \
    fail_verify "config '$CONFIG_FILE' has no generated token pepper"
  grep -Fq -- '--bind 127.0.0.1:49374' "$UNIT_FILE" || \
    fail_verify "unit '$UNIT_FILE' has the wrong bind (expected 127.0.0.1:49374)"
}

verify_service() {
  local active listener_count listener
  active=$("$SYSTEMCTL" --user is-active ai-memory.service)
  [ "$active" = active ] || fail_verify "ai-memory.service is '$active' (expected active)"
  listener=$("$SS" -ltnH '( sport = :49374 )')
  listener_count=$(grep -Fc '127.0.0.1:49374' <<<"$listener" || true)
  [ "$listener_count" -eq 1 ] || \
    fail_verify "listener check found '$listener_count' loopback entries (expected exactly one 127.0.0.1:49374 listener)"
  if grep -Ev '127\.0\.0\.1:49374([[:space:]]|$)' <<<"$listener" | grep -q .; then
    fail_verify "port 49374 has a non-loopback listener (expected only 127.0.0.1:49374)"
  fi
}

verify_authentication() {
  local token rpc unauth_http auth_http curl_config
  token=$(read_auth_token)
  rpc='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"vps-verify","version":"1"}}}'
  unauth_http=$("$CURL" -sS -o /dev/null -w '%{http_code}' \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    --data "$rpc" http://127.0.0.1:49374/mcp)
  curl_config=$(mktemp "${TMPDIR:-/tmp}/ai-memory-curl.XXXXXX")
  trap "rm -f -- '$curl_config'" EXIT
  chmod 0600 "$curl_config"
  printf 'header = "Authorization: Bearer %s"\n' "$token" > "$curl_config"
  auth_http=$("$CURL" --config "$curl_config" -sS -o /dev/null -w '%{http_code}' \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    --data "$rpc" http://127.0.0.1:49374/mcp)
  rm -f "$curl_config"
  trap - EXIT
  unset token
  [ "$unauth_http" = 401 ] || fail_verify "unauthenticated MCP returned HTTP '$unauth_http' (expected 401)"
  [ "$auth_http" = 200 ] || fail_verify "authenticated MCP returned HTTP '$auth_http' (expected 200)"
}

verify_status() {
  local token status_json
  token=$(read_auth_token)
  status_json=$(AI_MEMORY_SERVER_URL=http://127.0.0.1:49374 \
    AI_MEMORY_AUTH_TOKEN="$token" "$AI_MEMORY_EXEC" --data-dir "$DATA_DIR" \
    --config "$CONFIG_FILE" status --json)
  unset token
  grep -Eq '"(sessions|observations|pages|version)"' <<<"$status_json" || \
    fail_verify "authenticated status returned an unexpected payload (expected status JSON)"
}

verify_pi_extension() {
  local token
  token=$(read_auth_token)
  grep -Fq 'http://127.0.0.1:49374' "$PI_EXTENSION" || \
    fail_verify "Pi extension '$PI_EXTENSION' has the wrong server URL"
  grep -Fq "$token" "$PI_EXTENSION" || \
    fail_verify "Pi extension '$PI_EXTENSION' is not wired to the local bearer token"
  unset token
  grep -Fq 'registerTool' "$PI_EXTENSION" || \
    fail_verify "Pi extension '$PI_EXTENSION' has no MCP tool bridge"
}

verify_spool_and_journal() {
  local spool_count journal_errors
  spool_count=$(find "$DATA_DIR/hook-spool" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l)
  [ "$spool_count" -eq 0 ] || \
    fail_verify "hook spool contains '$spool_count' JSON files (expected 0; review a separate drain plan)"
  journal_errors=$("$JOURNALCTL" --user -u ai-memory.service -b -p err --no-pager -q | wc -l)
  [ "$journal_errors" -eq 0 ] || fail_verify "current-boot journal has '$journal_errors' errors (expected 0)"
}

verify_persistence() {
  local enabled linger
  [ "$EXPECT_PERSISTENT" = "1" ] || return 0
  enabled=$("$SYSTEMCTL" --user is-enabled ai-memory.service)
  linger=$("$LOGINCTL" show-user "$USER" -p Linger --value)
  [ "$enabled" = enabled ] || fail_verify "ai-memory.service is '$enabled' (expected enabled)"
  [ "$linger" = yes ] || fail_verify "user lingering is '$linger' (expected yes)"
}

verify_historical_query() {
  local token search_json
  [ -n "$HISTORICAL_QUERY" ] || return 0
  token=$(read_auth_token)
  local args=(search --json --workspace "$WORKSPACE" --limit 1)
  [ -z "$PROJECT" ] || args+=(--project "$PROJECT")
  args+=("$HISTORICAL_QUERY")
  search_json=$(AI_MEMORY_SERVER_URL=http://127.0.0.1:49374 \
    AI_MEMORY_AUTH_TOKEN="$token" "$AI_MEMORY_EXEC" --data-dir "$DATA_DIR" \
    --config "$CONFIG_FILE" "${args[@]}")
  unset token
  grep -Eq '"(path|title)"' <<<"$search_json" || \
    fail_verify "historical query '$HISTORICAL_QUERY' returned no compiled-wiki hit in workspace '$WORKSPACE'"
}

main() {
  parse_args "$@"
  initialize_paths
  resolve_ai_memory
  verify_files
  verify_config
  verify_service
  verify_authentication
  verify_status
  verify_pi_extension
  verify_spool_and_journal
  verify_persistence
  verify_historical_query
  printf '%s\n' 'PASS: loopback ai-memory VPS bootstrap'
}

main "$@"
