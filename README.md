# plazirhangar

Unified CLI ship unit for xbrd/xbgst-stack: helpers, configs, livepatch surface, and sekhmet L3.
One-command install for the exact stack used on patched binaries.
Marketplace-ready (ds4cc / grok-marketplace).

Formerly tracked as unifirf; renamed per operator request.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/VeigaPunk/plazirhangar/main/scripts/plazirhangar | bash -s -- install
# or
git clone https://github.com/VeigaPunk/plazirhangar.git && cd plazirhangar
chmod +x scripts/plazirhangar && ./scripts/plazirhangar install
./scripts/plazirhangar status
```

## What it materializes

- Both marketplaces (grok-marketplace + ds4cc-marketplace)
- xbgst-stack (agents, skills/xbgst, commands, livepatch)
- Livepatch assert (ban general-purpose/explore, timer)
- sekhmet / xbrd-spark on PATH (cargo)
- Exact grok-cli-config.toml + L3 env
- Thin wrappers: status | install | swarm | judge | config

Binary ownership stays with livepatch timer + cargo. No pre-patched upstream blobs.

## Status contract

- livepatch active + REPLACE_BIN
- sekhmet/xbrd-spark version on PATH
- xbgst skill + agents present
- max_depth=1, explore/general-purpose=false
- both marketplace sources
- L3 env loaded

## Curation

Repro demo: `plazirhangar install && plazirhangar status` → green on clean host.
Provenance: VeigaPunk only.
Claims limited to shipping the configs + helpers used with livepatched Grok + sekhmet L3.

See https://github.com/VeigaPunk/ds4cc-marketplace/blob/main/CURATION.md
