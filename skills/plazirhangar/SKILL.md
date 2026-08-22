# plazirhangar

Unified ship/entrypoint for the exact xbrd + xbgst-stack surface used on livepatched binaries.

## When to use

- Fresh host needs the operator stack (marketplaces + xbgst-stack + livepatch + sekhmet + configs)
- Honest green/red status (6-row PASS/FAIL; exit 0 iff all PASS)
- Thin wrappers for swarm / judge without remembering paths

## Commands

- `plazirhangar install` — fail-closed; merge vendored toml (never curl-overwrite); PATH → `~/.local/bin`; livepatch timer only after patch ok
- `plazirhangar status` — rows: livepatch, sekhmet, xbgst, subagents, marketplaces, l3env
- `plazirhangar swarm|judge|config` — forward / show

## Hard locks

- Livepatch owns the ban on general-purpose/explore
- L3 concurrency plane independent (64)
- Host specialists ≤16 per wave (hard lock; overflow → spark substrates at `-j 64` same turn)
- Rust-only for new heavy tooling; this script is transitional

## Honesty

Green = 6 PASS. Unpatched stock CLI (e.g. grok 1.0.5 without merge+livepatch) is expected RED on livepatch (and often subagents). Do not claim `install && status` is green on that host until those rows pass.
