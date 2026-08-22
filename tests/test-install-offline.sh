#!/usr/bin/env bash
# Offline install: fake HOME, stub grok/curl/cargo/systemctl; curl dies if invoked.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PH="$ROOT/scripts/plazirhangar"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

bash -n "$PH" || fail "bash -n"
pass "bash -n"

FAKE="$(mktemp -d)"
STUBS="$FAKE/stubs"
STACK="$FAKE/stack"
HOME_FAKE="$FAKE/home"
mkdir -p "$STUBS" "$STACK/scripts" "$STACK/livepatch/scripts" \
  "$HOME_FAKE/.grok" "$HOME_FAKE/.local/bin" "$HOME_FAKE/.xbgst"

# Pre-existing config with extra plugin — must survive merge
cat >"$HOME_FAKE/.grok/config.toml" <<'EOF'
[plugins]
enabled = [
    "exa",
    "keep-me-plugin",
]

[models]
default = "custom-model"

[subagents]
enabled = true
max_depth = 9
max_concurrent = 64

[subagents.toggle]
explore = true
general-purpose = true
EOF

# Existing L3 must not be clobbered
cat >"$HOME_FAKE/.xbgst/env.l3-sekhmet.sh" <<'EOF'
export XBRD_SPARK_JOBS=64
export KEEP_MARKER=1
EOF

cat >"$STACK/plugin.json" <<'EOF'
{"name": "xbgst-stack", "version": "0.0.0-test"}
EOF

cat >"$STACK/scripts/install-host.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${INSTALL_HOST_LOG:?}"
echo "install-host args:$*" >>"$LOG"
mkdir -p "${GROK_HOME}/skills/xbgst" "${GROK_HOME}/agents"
: >"${GROK_HOME}/skills/xbgst/SKILL.md"
: >"${GROK_HOME}/agents/the-planner.md"
: >"${GROK_HOME}/agents/explore.md"
EOF
chmod +x "$STACK/scripts/install-host.sh"

# Default check-and-patch exit 0 for timer path probe (separate section)
cat >"$STACK/livepatch/scripts/check-and-patch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "check-and-patch stub ok"
exit 0
EOF
chmod +x "$STACK/livepatch/scripts/check-and-patch.sh"

# Stubs: curl must fail if invoked; cargo/grok/systemctl no-op or record
cat >"$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: curl invoked in offline install: $*" >&2
exit 97
EOF
cat >"$STUBS/cargo" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: cargo invoked despite --skip-cargo: $*" >&2
exit 96
EOF
cat >"$STUBS/grok" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: grok network path invoked with --from-tree: $*" >&2
exit 95
EOF
cat >"$STUBS/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUBS"/*

export INSTALL_HOST_LOG="$FAKE/install-host.log"
: >"$INSTALL_HOST_LOG"

run_install() {
  env -i \
    HOME="$HOME_FAKE" \
    PATH="$STUBS:/usr/bin:/bin" \
    USER="${USER:-test}" \
    LANG=C \
    INSTALL_HOST_LOG="$INSTALL_HOST_LOG" \
    PLAZIRHANGAR_ROOT="$ROOT" \
    bash "$PH" install "$@"
}

# --- offline --from-tree --skip-livepatch --skip-cargo ---
set +e
out="$(run_install --from-tree "$STACK" --skip-livepatch --skip-cargo 2>&1)"
ec=$?
set -e
echo "$out"
[[ "$ec" -eq 0 ]] || fail "offline install exit want 0 got $ec"

[[ -x "$HOME_FAKE/.local/bin/plazirhangar" ]] || fail "plazirhangar not installed to ~/.local/bin"
pass "~/.local/bin/plazirhangar executable"

cfg="$HOME_FAKE/.grok/config.toml"
grep -q 'keep-me-plugin' "$cfg" || fail "extra plugin dropped"
grep -q 'custom-model' "$cfg" || fail "extra model dropped"
grep -qE '^[[:space:]]*max_depth[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$cfg" || fail "max_depth not merged to 1"
grep -qE '^[[:space:]]*max_concurrent[[:space:]]*=[[:space:]]*16[[:space:]]*$' "$cfg" || fail "max_concurrent not clamped to 16"
grep -qE '^[[:space:]]*explore[[:space:]]*=[[:space:]]*false' "$cfg" || fail "explore not false"
grep -qE '^[[:space:]]*general-purpose[[:space:]]*=[[:space:]]*false' "$cfg" || fail "general-purpose not false"
grep -q 'github.com/VeigaPunk/grok-marketplace.git' "$cfg" || fail "grok-marketplace URL missing"
grep -q 'github.com/VeigaPunk/ds4cc-marketplace.git' "$cfg" || fail "ds4cc-marketplace URL missing"
grep -q '"xbgst-stack"' "$cfg" || fail "xbgst-stack not merge-enabled"
pass "config merge preserves extras + locks max_concurrent=16"

grep -q 'KEEP_MARKER=1' "$HOME_FAKE/.xbgst/env.l3-sekhmet.sh" || fail "L3 env was clobbered"
pass "L3 env left untouched when present"

# L3 created only when absent
rm -f "$HOME_FAKE/.xbgst/env.l3-sekhmet.sh"
set +e
out2="$(run_install --from-tree "$STACK" --skip-livepatch --skip-cargo 2>&1)"
ec2=$?
set -e
[[ "$ec2" -eq 0 ]] || fail "re-install for L3 create exit want 0 got $ec2"
[[ -f "$HOME_FAKE/.xbgst/env.l3-sekhmet.sh" ]] || fail "L3 env not created when absent"
grep -q 'XBRD_SPARK_JOBS=64' "$HOME_FAKE/.xbgst/env.l3-sekhmet.sh" || fail "L3 missing JOBS=64"
grep -q 'XBRD_SPARK_SERVICE_TIER=fast' "$HOME_FAKE/.xbgst/env.l3-sekhmet.sh" \
  || fail "L3 missing SERVICE_TIER=fast"
pass "L3 env created when absent (JOBS=64 + TIER=fast)"

# --skip-livepatch must NOT invoke install-timer
if grep -q 'install-timer' "$INSTALL_HOST_LOG"; then
  fail "install-timer invoked despite --skip-livepatch"
fi
pass "--skip-livepatch does not enable timer"

# --- check-and-patch exit 2 → install exit 2, no timer ---
: >"$INSTALL_HOST_LOG"
cat >"$STACK/livepatch/scripts/check-and-patch.sh" <<'EOF'
#!/usr/bin/env bash
echo "needs-rebase stub"
exit 2
EOF
chmod +x "$STACK/livepatch/scripts/check-and-patch.sh"
set +e
out3="$(run_install --from-tree "$STACK" --skip-cargo 2>&1)"
ec3=$?
set -e
echo "$out3"
[[ "$ec3" -eq 2 ]] || fail "check-and-patch exit 2 → install want 2 got $ec3"
echo "$out3" | grep -qi 'needs-rebase' || fail "missing needs-rebase message"
if grep -qF -- '--install-timer' "$INSTALL_HOST_LOG"; then
  fail "timer enabled after needs-rebase"
fi
pass "check-and-patch exit 2 → install exit 2, timer not enabled"

# --- check-and-patch exit 0 → --install-timer invoked ---
: >"$INSTALL_HOST_LOG"
cat >"$STACK/livepatch/scripts/check-and-patch.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STACK/livepatch/scripts/check-and-patch.sh"
set +e
out4="$(run_install --from-tree "$STACK" --skip-cargo 2>&1)"
ec4=$?
set -e
echo "$out4"
[[ "$ec4" -eq 0 ]] || fail "check-and-patch exit 0 → install want 0 got $ec4"
grep -qF -- '--install-timer' "$INSTALL_HOST_LOG" || fail "install-host --install-timer not invoked after patch ok"
pass "check-and-patch exit 0 → install-host --install-timer"

# Forbidden patterns in script
if grep -nE 'curl[[:space:]]+[^|]*-o[[:space:]]+.*config\.toml|curl.*config\.toml' "$PH" | grep -v '^#' | grep -q .; then
  # allow comments only
  if grep -nE 'curl .*-o .*config\.toml' "$PH" | grep -vE '^[[:space:]]*#' | grep -q curl; then
    fail "script still curls config.toml"
  fi
fi
grep -nE 'curl .*-o .*config\.toml' "$PH" >/dev/null 2>&1 && {
  # precise: any non-comment curl -o config
  if grep -n 'curl' "$PH" | grep 'config\.toml' | grep -vE '^\s*#' | grep -q .; then
    fail "forbidden curl config.toml still present"
  fi
} || true
# Stronger: no curl -o targeting config.toml as an install action
if grep -nE 'curl[[:space:]].*-o[[:space:]]+"\$HOME/\.grok/config\.toml"|curl[[:space:]].*-o[[:space:]]+.*/config\.toml' "$PH"; then
  fail "forbidden curl -o config.toml"
fi
if grep -nE 'ls -d.*xbgst-stack|ls -d.*"\$HOME".*installed-plugins' "$PH"; then
  fail "forbidden ls -d plugin glob"
fi
if grep -nE 'head -1' "$PH" | grep -E 'ls|installed-plugins|STACK'; then
  fail "forbidden head -1 on plugin resolve"
fi
# no || true on marketplace/plugin/livepatch/curl required steps
if grep -nE 'marketplace add.*\|\| true|plugin install.*\|\| true|check-and-patch.*\|\| true|curl .*\|\| true' "$PH"; then
  fail "forbidden || true on required install steps"
fi
pass "no forbidden curl/ls|head/|| true patterns"

rm -rf "$FAKE"
echo "All install-offline tests passed."
