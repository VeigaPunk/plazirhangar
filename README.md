# plazirhangar

Unified CLI ship for the xbrd + xbgst-stack surface used with livepatched Grok + sekhmet L3.

Origin (SSH): `git@github.com:VeigaPunk/plazirhangar.git`

## Quick start

```bash
git clone git@github.com:VeigaPunk/plazirhangar.git && cd plazirhangar
chmod +x scripts/plazirhangar && ./scripts/plazirhangar install
./scripts/plazirhangar status
```

`install` lands `plazirhangar` on `~/.local/bin` (ensure that dir is on `PATH`).

## Commands

- `plazirhangar install` — fail-closed, idempotent materialization
- `plazirhangar status` — 6-row PASS/FAIL contract (exit 0 iff all PASS)
- `plazirhangar swarm|judge|config` — thin wrappers

## Status contract

Six rows; prints `OK` / `BAD`. Exit **0** only when every row is PASS.

| Row | PASS when |
|---|---|
| `livepatch` | livepatch active: ban in binary + REPLACE_BIN (or active_cli=livepatch) + user timer active |
| `sekhmet` | `sekhmet` or `xbrd-spark` on PATH with a version |
| `xbgst` | xbgst skill + agents (incl. banned stubs) under `~/.grok` |
| `subagents` | `max_depth=1`, `explore=false`, `general-purpose=false`; `max_concurrent` ≤16 if set |
| `marketplaces` | both VeigaPunk grok-marketplace + ds4cc-marketplace git URLs in config |
| `l3env` | `~/.xbgst/env.l3-sekhmet.sh` assigns `XBRD_SPARK_JOBS=64` |

## Install contract (intended)

Fail-closed. Does **not** curl-overwrite `~/.grok/config.toml`.

- Merge required keys from vendored `configs/grok-cli-config.toml` (keep extra plugins/models)
- Host specialists: grok `[subagents].max_concurrent` ≤ **16**; L3 plane is independent (`XBRD_SPARK_JOBS=64`)
- Livepatch: `GROK_LIVEPATCH_FORCE=1` check-and-patch; timer only after patch ok; surface `needs-rebase` (no swallow)
- PATH install to `~/.local/bin`; write L3 env only if missing

## Curation

**Green** means all 6 rows PASS (`status` exit 0).

Stock / unpatched Grok CLI (e.g. this host grok **1.0.5** before install merge + livepatch) is expected **FAIL** on `livepatch` (and often `subagents`) — honest RED, not a green claim. Do not treat `install && status` as green on an unpatched host.

Provenance: VeigaPunk only. See https://github.com/VeigaPunk/ds4cc-marketplace/blob/main/CURATION.md
