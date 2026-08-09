# plazirhangar

Unified ship/entrypoint for the exact xbrd + xbgst-stack surface used on livepatched binaries.

## When to use

- Fresh host needs the full operator stack (marketplaces + xbgst-stack + livepatch + sekhmet + configs)
- Status check that the patched surface is coherent
- Thin wrappers for swarm / judge without remembering paths

## Commands

- `plazirhangar install` — idempotent full materialization
- `plazirhangar status` — contract green/red
- `plazirhangar swarm ...` — forward to sekhmet
- `plazirhangar config` — show active config

## Hard locks preserved

- Livepatch owns the ban on general-purpose/explore
- L3 concurrency plane independent (64)
- Host specialists ≤16
- Rust-only for new heavy tooling; this script is transitional
