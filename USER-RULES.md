# User Rules

Environment invariants for this fork (two-machine workflow). These extend `AGENTS.md` and apply to all agents working in projects that use this ruleset.

## Two-machine layout

- **Windows PC** — 1C platform, configuration export (`DumpConfigToFiles`), Cursor, AI agent.
- **Mac mini** (`MCP_HOST` in `.dev.env`, default `mac-mini-al.local`) — OrbStack (Docker, **arm64** images only), MCP server containers, long-running RAG indexing.
- **SSH** — always via `MCP_SSH_CONFIG` + `MCP_SSH_HOST_ALIAS` (e.g. `mac-mini`); never hardcode `user@ip`.

## Sync conventions

- Configuration **file dump** → Mac: `{MCP_SYNC_BASE}/code-{ProjectName}/` (`ProjectName` = basename of project root).
- Configuration **text report** → Mac: `{MCP_SYNC_BASE}/metadata-{ProjectName}/` (sibling folder `{ProjectName}_report/` on Windows).
- After `/loadfrom1cbase` or `/getconfigfiles`, when `MCP_HOST` is remote — run `/synctomcp` before reindex/install on Mac.

## MCP ports and images

- Each project gets a **port decade**: `MCP_PORT_BASE` … `MCP_PORT_BASE+9` (`8000–8009`, `8010–8019`, …).
- **HelpSearchServer** is **platform-scoped** (not per project): id `1C-docs-mcp-<platform-version>`, port ≥8100; reuse index when the same platform version is already indexed on Mac.
- Docker images on Mac: tag **`arm64`** (`MCP_IMAGE_TAG`) — **`:latest` is forbidden**.
- **v1 scope:** no `1c-graph-metadata-mcp`, no Neo4j, no LM Studio embeddings (deferred v2).

## Source URL

Install/update rules from this fork: `https://github.com/AlexanderSergeev1C/ai_rules_1c` (see `AGENT-INSTALL.md`).

## Migrated content from a previous setup

<!-- start of migrated content -->
<!-- end of migrated content -->
