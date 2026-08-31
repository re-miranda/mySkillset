#!/usr/bin/env bash
set -euo pipefail

fail_test() {
  printf 'test.sh: %s\n' "$1" >&2
  exit 1
}

run_expect_failure() {
  local stdout_path="$1" stderr_path="$2"
  shift 2
  set +e
  "$@" >"$stdout_path" 2>"$stderr_path"
  LAST_EXIT=$?
  set -e
  [ "$LAST_EXIT" -ne 0 ] || fail_test "command unexpectedly succeeded: $*"
}

frontmatter_value() {
  local path="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { frontmatter=1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", ""); print; exit
    }
  ' "$path"
}

write_fake_ai_memory() {
  cat > "$FAKE_BIN/ai-memory" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
TOKEN=$(printf 'a%.0s' {1..64})
for argument in "$@"; do
  [[ "$argument" != *"$TOKEN"* ]] || { echo 'token leaked through ai-memory argv' >&2; exit 90; }
done
contains() { local wanted="$1" item; shift; for item in "$@"; do [ "$item" != "$wanted" ] || return 0; done; return 1; }
value_after() { local wanted="$1" previous="" item; shift; for item in "$@"; do [ "$previous" != "$wanted" ] || { printf '%s\n' "$item"; return; }; previous="$item"; done; return 1; }
if contains init "$@"; then
  config=$(value_after --config "$@")
  mkdir -p "$(dirname "$config")"
  cat > "$config" <<'CONFIG'
bind = "127.0.0.1:49374"
allowed_hosts = ["localhost", "127.0.0.1", "::1"]
[auth]
token_pepper = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
CONFIG
  exit
fi
if contains generate-auth-token "$@"; then
  count_file="$FAKE_STATE/token-count"
  count=0; [ ! -f "$count_file" ] || count=$(cat "$count_file")
  printf '%s\n' $((count + 1)) > "$count_file"
  printf '%s\n' "$TOKEN"
  exit
fi
if contains install-hooks "$@"; then
  [ "${AI_MEMORY_AUTH_TOKEN:-}" = "$TOKEN" ] || { echo 'missing token environment' >&2; exit 91; }
  target="$PI_AGENT_DIR/extensions/ai-memory.ts"
  mkdir -p "$(dirname "$target")"
  printf 'const SERVER = "http://127.0.0.1:49374";\nconst TOKEN = "%s";\nfunction registerTool() {}\n' "$TOKEN" > "$target"
  chmod 0600 "$target"
  exit
fi
if contains status "$@"; then
  [ "${AI_MEMORY_AUTH_TOKEN:-}" = "$TOKEN" ] || exit 92
  printf '{"version":"1.17.3","sessions":1,"observations":2}\n'
  exit
fi
if contains search "$@"; then
  [ "${AI_MEMORY_AUTH_TOKEN:-}" = "$TOKEN" ] || exit 93
  printf '[{"path":"sessions/known.md","title":"Known"}]\n'
  exit
fi
printf 'unexpected fake ai-memory invocation\n' >&2
exit 94
FAKE
  chmod +x "$FAKE_BIN/ai-memory"
}

write_fake_systemctl() {
  cat > "$FAKE_BIN/systemctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' daemon-reload '*) : ;;
  *' start ai-memory.service '*) : > "$FAKE_STATE/active" ;;
  *' enable ai-memory.service '*) : > "$FAKE_STATE/enabled" ;;
  *' is-active ai-memory.service '*) [ -f "$FAKE_STATE/active" ] && echo active || { echo inactive; exit 3; } ;;
  *' is-enabled ai-memory.service '*) [ -f "$FAKE_STATE/enabled" ] && echo enabled || { echo disabled; exit 1; } ;;
  *) echo "unexpected systemctl args: $*" >&2; exit 95 ;;
esac
FAKE
  chmod +x "$FAKE_BIN/systemctl"
}

write_fake_loginctl() {
  cat > "$FAKE_BIN/loginctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' enable-linger '*) : > "$FAKE_STATE/linger" ;;
  *' show-user '*' -p Linger --value '*) [ -f "$FAKE_STATE/linger" ] && echo yes || echo no ;;
  *) echo "unexpected loginctl args: $*" >&2; exit 96 ;;
esac
FAKE
  chmod +x "$FAKE_BIN/loginctl"
}

write_fake_curl() {
  cat > "$FAKE_BIN/curl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
TOKEN=$(printf 'a%.0s' {1..64})
config="" previous=""
for argument in "$@"; do
  [[ "$argument" != *"$TOKEN"* ]] || { echo 'token leaked through curl argv' >&2; exit 97; }
  [ "$previous" != --config ] || config="$argument"
  previous="$argument"
done
if [ -n "$config" ]; then
  [ "$(stat -c %a "$config")" = 600 ] || exit 98
  grep -Fq "$TOKEN" "$config" || exit 99
  printf '200'
else
  printf '401'
fi
FAKE
  chmod +x "$FAKE_BIN/curl"
}

write_fake_observers() {
  cat > "$FAKE_BIN/ss" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FAKE_NON_LOOPBACK:-0}" = 1 ]; then
  printf 'LISTEN 0 128 0.0.0.0:49374 0.0.0.0:*\n'
else
  printf 'LISTEN 0 128 127.0.0.1:49374 0.0.0.0:*\n'
fi
FAKE
  cat > "$FAKE_BIN/journalctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
exit 0
FAKE
  chmod +x "$FAKE_BIN/ss" "$FAKE_BIN/journalctl"
}

create_fakes() {
  FAKE_BIN="$SUITE_ROOT/fakes"
  FAKE_STATE="$SUITE_ROOT/fake-state"
  mkdir -p "$FAKE_BIN" "$FAKE_STATE"
  export FAKE_STATE
  write_fake_ai_memory
  write_fake_systemctl
  write_fake_loginctl
  write_fake_curl
  write_fake_observers
}

bootstrap_env() {
  local root="$1"
  shift
  env HOME="$root/home" USER=tester FAKE_NON_LOOPBACK="${FAKE_NON_LOOPBACK:-0}" \
    AI_MEMORY_BIN="$FAKE_BIN/ai-memory" \
    AI_MEMORY_DATA_DIR="$root/data" \
    AI_MEMORY_CONFIG_DIR="$root/config" \
    AI_MEMORY_SYSTEMD_DIR="$root/systemd" \
    PI_AGENT_DIR="$root/pi" \
    AI_MEMORY_SYSTEMCTL="$FAKE_BIN/systemctl" \
    AI_MEMORY_LOGINCTL="$FAKE_BIN/loginctl" \
    AI_MEMORY_CURL="$FAKE_BIN/curl" \
    AI_MEMORY_SS="$FAKE_BIN/ss" \
    AI_MEMORY_JOURNALCTL="$FAKE_BIN/journalctl" \
    "$@"
}

prepare_root() {
  mkdir -p "$1/home" "$1/data/hook-spool"
}

test_shell_and_metadata() {
  bash -n "$SKILL_DIR/install.sh" "$SKILL_DIR/test.sh" \
    "$SKILL_DIR/scripts/bootstrap.sh" "$SKILL_DIR/scripts/verify.sh"
  [ "$(frontmatter_value "$SKILL_DIR/SKILL.md" name)" = ai-memory-vps-bootstrap ] || \
    fail_test 'SKILL.md frontmatter name drifted'
  [ -n "$(frontmatter_value "$SKILL_DIR/SKILL.md" description)" ] || \
    fail_test 'SKILL.md is missing a description'
}

test_installer() {
  local root="$SUITE_ROOT/install" output
  PI_AGENT_DIR="$root/pi" CLAUDE_HOME="$root/claude" bash "$SKILL_DIR/install.sh" >/dev/null
  cmp -s "$SKILL_DIR/SKILL.md" "$root/pi/skills/ai-memory-vps-bootstrap/SKILL.md" || fail_test 'Pi skill missing'
  cmp -s "$SKILL_DIR/scripts/bootstrap.sh" "$root/claude/skills/ai-memory-vps-bootstrap/scripts/bootstrap.sh" || fail_test 'Claude setup script missing'
  [ -x "$root/pi/skills/ai-memory-vps-bootstrap/scripts/verify.sh" ] || fail_test 'installed verifier is not executable'
  output=$(PI_AGENT_DIR="$root/pi" CLAUDE_HOME="$root/claude" bash "$SKILL_DIR/install.sh")
  [ "$(grep -Fc ' (current)' <<<"$output")" -eq 8 ] || fail_test 'installer rerun was not idempotent'
  PI_AGENT_DIR="$root/dry-pi" CLAUDE_HOME="$root/dry-claude" bash "$SKILL_DIR/install.sh" --dry-run >/dev/null
  [ ! -e "$root/dry-pi" ] && [ ! -e "$root/dry-claude" ] || fail_test 'installer dry-run wrote files'
}

test_preview_is_read_only() {
  local root="$SUITE_ROOT/preview"
  prepare_root "$root"
  bootstrap_env "$root" "$SKILL_DIR/scripts/bootstrap.sh" > "$root/output"
  [ ! -e "$root/config" ] && [ ! -e "$root/systemd" ] && [ ! -e "$root/pi" ] || \
    fail_test 'bootstrap preview mutated destinations'
  grep -Fq 'Preview only' "$root/output" || fail_test 'bootstrap preview omitted its safety label'
}

test_fresh_apply_and_idempotence() {
  local root="$SUITE_ROOT/apply" before after
  prepare_root "$root"
  bootstrap_env "$root" "$SKILL_DIR/scripts/bootstrap.sh" --apply > "$root/first.out"
  [ "$(stat -c %a "$root/config/config.toml")" = 600 ] || fail_test 'config mode is not 600'
  [ "$(stat -c %a "$root/config/env")" = 600 ] || fail_test 'env mode is not 600'
  [ "$(stat -c %a "$root/systemd/ai-memory.service")" = 600 ] || fail_test 'unit mode is not 600'
  before=$(sha256sum "$root/config/config.toml" "$root/config/env" "$root/systemd/ai-memory.service")
  bootstrap_env "$root" "$SKILL_DIR/scripts/bootstrap.sh" --apply > "$root/second.out"
  after=$(sha256sum "$root/config/config.toml" "$root/config/env" "$root/systemd/ai-memory.service")
  [ "$before" = "$after" ] || fail_test 'idempotent apply changed managed state'
  [ "$(cat "$FAKE_STATE/token-count")" = 1 ] || fail_test 'idempotent apply generated another token'
  bootstrap_env "$root" "$SKILL_DIR/scripts/bootstrap.sh" --apply --enable-persistence > "$root/persistent.out"
  grep -Fq 'PASS: loopback ai-memory VPS bootstrap' "$root/persistent.out" || fail_test 'persistent verification did not pass'
  bootstrap_env "$root" "$SKILL_DIR/scripts/verify.sh" --expect-persistent \
    --project known --historical-query known > "$root/verify.out"
}

test_incompatible_config_fails_closed() {
  local root="$SUITE_ROOT/collision"
  prepare_root "$root"
  mkdir -p "$root/config"
  printf 'bind = "0.0.0.0:49374"\n' > "$root/config/config.toml"
  run_expect_failure "$root/out" "$root/err" \
    bootstrap_env "$root" "$SKILL_DIR/scripts/bootstrap.sh" --apply
  [ ! -e "$root/config/env" ] && [ ! -e "$root/systemd" ] || fail_test 'config collision caused partial setup'
  grep -Fq 'wrong bind' "$root/err" || fail_test 'config collision error was not specific'
}

test_non_loopback_listener_fails() {
  local root="$SUITE_ROOT/apply"
  FAKE_NON_LOOPBACK=1 run_expect_failure "$root/nonloop.out" "$root/nonloop.err" \
    bootstrap_env "$root" "$SKILL_DIR/scripts/verify.sh" --expect-persistent
  grep -Fq 'expected exactly one 127.0.0.1:49374 listener' "$root/nonloop.err" || \
    fail_test 'non-loopback listener error was not specific'
}

cleanup_suite() {
  if [ "${KEEP_TEST_TMP:-0}" = 1 ]; then
    printf 'kept test workspace: %s\n' "$SUITE_ROOT" >&2
    return
  fi
  rm -rf "$SUITE_ROOT"
}

main() {
  SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  SUITE_ROOT=$(mktemp -d /tmp/ai-memory-vps-bootstrap-test.XXXXXX)
  trap cleanup_suite EXIT
  create_fakes
  test_shell_and_metadata
  test_installer
  test_preview_is_read_only
  test_fresh_apply_and_idempotence
  test_incompatible_config_fails_closed
  test_non_loopback_listener_fails
  printf '%s\n' 'PASS: ai-memory-vps-bootstrap skill'
}

main "$@"
