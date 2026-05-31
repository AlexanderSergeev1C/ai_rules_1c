---
description: Sync configuration dump and metadata report from Windows to the remote Mac MCP host via SSH/scp
alwaysApply: false
category: workflow
---

# Sync to remote MCP host

Load this rule when `MCP_HOST` in `.dev.env` points to a remote Mac (not `localhost`) and configuration files need to be copied for MCP indexing on OrbStack/Docker.

## Parameters (from `.dev.env`)

| Key | Purpose |
|---|---|
| `MCP_HOST` | Remote Mac IP/hostname; empty or `localhost` = skip (upstream single-machine mode) |
| `MCP_SSH_CONFIG` | Path to SSH config on Windows (default `%USERPROFILE%\.ssh\config`) |
| `MCP_SSH_HOST_ALIAS` | Host alias for `ssh`/`scp -F … alias:` (e.g. `mac-mini`) |
| `MCP_SYNC_BASE` | Base directory on Mac (default `/Users/al/1c/sync`) |
| `MCP_SYNC_CODE_SUFFIX` | Prefix for code dump: `{MCP_SYNC_BASE}/code-{ProjectName}/` |
| `MCP_SYNC_METADATA_SUFFIX` | Prefix for config report: `{MCP_SYNC_BASE}/metadata-{ProjectName}/` |
| `EXPORT_PATH` | Local configuration dump; empty = project root |
| `METADATA_REPORT_SUFFIX` | Sibling report folder suffix (default `_report`) |

**ProjectName** = basename of the project root (the folder opened in Cursor).

**Local paths:**

- Code dump: `{EXPORT_PATH}` or project root — must contain `Configuration.xml` or `ConfigurationExtension.xml`.
- Report: `{ParentOfProject}\{ProjectName}{METADATA_REPORT_SUFFIX}\` — optional; if missing, WARN and skip report sync (do not block code sync).

**Remote paths:**

- Code: `{MCP_SYNC_BASE}/code-{ProjectName}/` — `DumpConfigToFiles` output for CodeMetadataSearchServer.
- Report: `{MCP_SYNC_BASE}/metadata-{ProjectName}/` — configuration report for future GraphMetadata (v2); synced in v1 but not consumed yet.

## Steps

1. Read `.dev.env`. If `MCP_HOST` is empty or `localhost` — stop silently (upstream mode).
2. Compute `ProjectName`, local export path, local report path, remote code/metadata paths.
3. Verify configuration dump exists in export path.
4. **SSH preflight:** `ssh -F $MCP_SSH_CONFIG -o BatchMode=yes $MCP_SSH_HOST_ALIAS "echo ok"`. On failure — show stderr and stop.
5. **mkdir on Mac:** `ssh … "mkdir -p '<RemoteCodePath>' '<RemoteMetadataPath>'"`.
6. **Sync code:** `scp -F $MCP_SSH_CONFIG -r "<ExportPath>\*" $MCP_SSH_HOST_ALIAS:<RemoteCodePath>`.
7. **Sync report** (if folder exists): `scp -F $MCP_SSH_CONFIG -r "<ReportDir>\*" $MCP_SSH_HOST_ALIAS:<RemoteMetadataPath>`. If folder missing — WARN only.
8. Report per transfer: exit code, file count, approximate size, elapsed time.

## Deterministic script

From project root:

```powershell
& '<rules-repo>/tools/sync-to-mcp-host.ps1'
```

The script walks up to find `.dev.env` / `Configuration.xml` when `-ProjectRoot` is omitted.

## Integration

After `/loadfrom1cbase` or `/getconfigfiles`, when `MCP_HOST` is set and not `localhost`, run this rule or `/synctomcp` as an optional post-step before `/installmcp` or reindex.

## Limits

- Do not hardcode `user@192.168.x.x` — always use `MCP_SSH_HOST_ALIAS` and `MCP_SSH_CONFIG`.
- Do not log secrets from `.dev.env`.
- Partial scp failure → non-zero exit; show stderr to the user.
- Large configs may take minutes — inform the user; do not assume instant completion.
