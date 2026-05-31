---
description: Sync 1C configuration dump and metadata report to the remote Mac MCP host (SSH/scp)
---

# /synctomcp — sync configuration to Mac MCP host

Copies the local configuration file dump and (optionally) the configuration report to the Mac mini used as the remote MCP Docker host. Uses SSH config from `.dev.env` — no raw `user@ip`.

Load `content/rules/sync-to-mcp-host.md` for path conventions and edge cases.

## When to run

- After `/loadfrom1cbase` or manual `DumpConfigToFiles` when `MCP_HOST` in `.dev.env` is set and not `localhost`.
- Before `/installmcp` on a remote Mac (first time or after a fresh dump).
- After partial `/getconfigfiles` when the remote CodeMetadata index should be refreshed (follow with container reindex per `/installmcp`).

If `MCP_HOST` is empty or `localhost` — stop and tell the user sync is only for the two-machine fork workflow.

## Steps

### 1. Verify `.dev.env` remote parameters

Required for remote sync:

| Key | Blocking when empty |
|---|---|
| `MCP_HOST` | Yes (must not be localhost) |
| `MCP_SSH_HOST_ALIAS` | Yes |
| `MCP_SSH_CONFIG` | Uses default `%USERPROFILE%\.ssh\config` if missing |

Optional with defaults: `MCP_SYNC_BASE`, suffix keys, `METADATA_REPORT_SUFFIX`, `EXPORT_PATH`.

### 2. Run the sync script

From the project root:

```powershell
& '<path-to-rules>/tools/sync-to-mcp-host.ps1'
```

Or invoke the same logic manually per `content/rules/sync-to-mcp-host.md`.

### 3. Report to the user

Summary table:

| Target | Remote path | Exit | Files | Size | Time |
|---|---|---|---|---|---|
| code | `…/code-{ProjectName}/` | … | … | … | … |
| metadata | `…/metadata-{ProjectName}/` | … / skipped | … | … | … |

If report folder `{Parent}\{ProjectName}_report\` is missing, state clearly that GraphMetadata (v2) will lack report data until the user exports **Конфигурация → Отчёт по конфигурации** to that folder.

### 4. Next steps (suggest briefly)

- First-time remote MCP: `/installmcp` (allocates ports, starts containers on Mac).
- Containers already running: reindex CodeMetadata on Mac per distribution docs; docs MCP reindex only if platform bin changed.

## Limits

- Does not install or restart Docker containers — use `/installmcp` or `/updatemcp`.
- Does not allocate ports — use `tools/allocate-mcp-ports.ps1` or `/installmcp` step 0.
- Idempotent: repeated sync overwrites remote files.
