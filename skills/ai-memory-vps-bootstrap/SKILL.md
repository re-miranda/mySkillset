---
name: ai-memory-vps-bootstrap
description: "Bootstrap or verify a native ai-memory user service on a single-user Linux VPS with loopback-only bearer authentication and Pi lifecycle hooks. Use for an already-installed ai-memory binary and an existing authoritative data directory. Do not use for state migration, remote exposure, provider setup, Claude wiring, or destructive recovery."
compatibility: "Linux with systemd user services, loginctl, curl, ss, and a native ai-memory binary."
metadata:
  version: "0.1.0"
  scope: global
---

# ai-memory VPS bootstrap

Establish the smallest persistent Pi/ai-memory loop without widening network exposure or touching migration boundaries.

## Preconditions

- Treat the existing ai-memory data directory as authoritative.
- Never copy credentials from another machine. Generate the bearer token locally.
- Keep the server on `127.0.0.1:49374`; this procedure does not configure remote access or TLS.
- Do not drain, rewrite, migrate, restore over, or clean state as part of bootstrap.
- Obtain explicit approval before running the mutating command.

## Procedure

1. Inspect `git status`, the configured paths, the ai-memory version, service state, listener, and spool count.
2. Preview the bootstrap:
   `bash scripts/bootstrap.sh`
3. Explain every proposed mutation and obtain explicit approval.
4. Apply the canary bootstrap:
   `bash scripts/bootstrap.sh --apply`
5. Verify the non-persistent canary:
   `bash scripts/verify.sh`
6. After backup and recovery gates are satisfied, promote persistence:
   `bash scripts/bootstrap.sh --apply --enable-persistence`
7. Verify persistence:
   `bash scripts/verify.sh --expect-persistent`
8. Restart Pi, then use `memory_status` and a known historical query to confirm lifecycle capture and retrieval.
9. Perform a real reboot acceptance test before declaring the VPS loop persistent.

## Safety rules

- The setup script creates config in an isolated temporary data directory, then installs only the generated config.
- Existing compatible config, bearer env, and service unit files are kept. Incompatible files cause a fail-closed error; they are never overwritten.
- Tokens are passed directly to ai-memory and curl but never printed.
- `--enable-persistence` may require local authorization for `loginctl enable-linger`; do not bypass that authorization.
- A non-empty hook spool is a failed verification and requires a separate reviewed drain plan.
- Keep Pi managed memory guidance, Claude Code wiring, LLM providers, Tailscale/public exposure, scheduled operations, and cleanup as separate changes.

## Files

- `scripts/bootstrap.sh` — preview-by-default, idempotent setup and optional persistence promotion.
- `scripts/verify.sh` — read-only service, bind, auth, status, Pi hook, spool, and journal checks.
- `templates/ai-memory.service.in` — hardened user-service template used only when no unit exists.
