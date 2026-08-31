# ai-memory-vps-bootstrap

A guarded operational skill for converging an already-installed native ai-memory binary and an existing authoritative data directory into a minimal Pi-on-VPS loop.

## Scope

The bootstrap codifies the proven local topology:

- native ai-memory binary;
- authoritative state at `~/.local/share/ai-memory`;
- config and fresh VPS-local bearer state under `~/.config/ai-memory`;
- hardened user service on `127.0.0.1:49374`;
- generated Pi lifecycle/MCP extension;
- optional user-service enablement and lingering.

It does not migrate or drain state, rotate credentials, restore over live data, configure Claude Code, install ai-memory managed guidance, add an LLM provider, or expose the service beyond loopback.

## Install the skill

From the repository root:

```bash
bash install.sh --skill ai-memory-vps-bootstrap --dry-run
bash install.sh --skill ai-memory-vps-bootstrap
```

The installer copies the skill, scripts, and service template to both Pi and Claude Code skill roots. It does **not** run the VPS bootstrap or modify ai-memory.

## Preview and apply

Run from this directory or from an installed skill directory:

```bash
bash scripts/bootstrap.sh
bash scripts/bootstrap.sh --apply
```

The no-argument command is a read-only preview. `--apply`:

1. keeps the authoritative data directory untouched;
2. generates config through an isolated temporary data directory only when config is absent;
3. generates a fresh local bearer token only when the env file is absent;
4. keeps compatible existing config, env, and unit files and rejects incompatible collisions;
5. starts the loopback user service;
6. installs the generated Pi integration using environment-based token delivery;
7. runs the read-only verifier.

After backup and restore gates pass, promote persistence:

```bash
bash scripts/bootstrap.sh --apply --enable-persistence
```

`loginctl enable-linger` may require local interactive authorization. The script never invokes `sudo`.

## Verify

```bash
bash scripts/verify.sh
bash scripts/verify.sh --expect-persistent
```

The verifier checks file modes, config and unit invariants, active service state, the exact loopback listener, unauthenticated `401` and authenticated `200` MCP behavior, authenticated status, Pi extension wiring, an empty JSON spool, and current-boot journal errors. The bearer token is never printed or placed in curl's argument list.

Optionally require a known compiled-wiki result:

```bash
bash scripts/verify.sh \
  --expect-persistent \
  --workspace default \
  --project known-project \
  --historical-query 'known phrase'
```

Lifecycle acceptance still requires a fresh Pi session using `memory_status` and a real memory query. Reboot acceptance remains manual: record the boot ID, reboot, reconnect, rerun verification, and confirm that the boot ID changed.

## Overrides

Tests and non-default XDG layouts can override:

- `AI_MEMORY_BIN`
- `AI_MEMORY_DATA_DIR`
- `AI_MEMORY_CONFIG_DIR`
- `AI_MEMORY_SYSTEMD_DIR`
- `PI_AGENT_DIR`

Named command fakes can be injected with `AI_MEMORY_SYSTEMCTL`, `AI_MEMORY_LOGINCTL`, `AI_MEMORY_CURL`, `AI_MEMORY_SS`, and `AI_MEMORY_JOURNALCTL`.

## Validate

```bash
bash skills/ai-memory-vps-bootstrap/test.sh
```
