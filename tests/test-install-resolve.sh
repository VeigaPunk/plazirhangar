#!/usr/bin/env bash
# resolve_plugin_dir: unique OK; 0 dirs FAIL; 2 dirs FAIL (no head -1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PH="$ROOT/scripts/plazirhangar"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

bash -n "$PH" || fail "bash -n"
pass "bash -n"

FAKE="$(mktemp -d)"
STUBS="$FAKE/stubs"
HOME_FAKE="$FAKE/home"
GROK="$HOME_FAKE/.grok"
mkdir -p "$STUBS" "$GROK/installed-plugins" "$HOME_FAKE/.local/bin" "$HOME_FAKE/.xbgst"

cat >"$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: curl invoked: $*" >&2
exit 97
EOF
cat >"$STUBS/cargo" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: cargo invoked: $*" >&2
exit 96
EOF
cat >"$STUBS/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
# grok: marketplace/install succeed; details empty so resolve falls through to dirs
cat >"$STUBS/grok" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUBS"/*

plant_stack() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/livepatch/scripts"
  cat >"$dir/plugin.json" <<'EOF'
{"name": "xbgst-stack"}
EOF
  cat >"$dir/scripts/install-host.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$dir/scripts/install-host.sh"
  cat >"$dir/livepatch/scripts/check-and-patch.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$dir/livepatch/scripts/check-and-patch.sh"
}

run_install() {
  env -i \
    HOME="$HOME_FAKE" \
    GROK_HOME="$GROK" \
    PATH="$STUBS:/usr/bin:/bin" \
    USER="${USER:-test}" \
    LANG=C \
    PLAZIRHANGAR_ROOT="$ROOT" \
    bash "$PH" install --skip-livepatch --skip-cargo "$@"
}

# --- 0 dirs → FAIL ---
rm -rf "$GROK/installed-plugins"
mkdir -p "$GROK/installed-plugins"
set +e
out0="$(run_install 2>&1)"
ec0=$?
set -e
echo "$out0"
[[ "$ec0" -ne 0 ]] || fail "0 plugin dirs should FAIL"
echo "$out0" | grep -qiE 'no installed plugin|FAIL' || fail "0 dirs missing fail message"
pass "0 plugin dirs FAIL"

# --- unique dir → OK ---
rm -rf "$GROK/installed-plugins"
mkdir -p "$GROK/installed-plugins"
plant_stack "$GROK/installed-plugins/xbgst-stack-abc123"
set +e
out1="$(run_install 2>&1)"
ec1=$?
set -e
echo "$out1"
[[ "$ec1" -eq 0 ]] || fail "unique plugin dir want exit 0 got $ec1"
[[ -x "$HOME_FAKE/.local/bin/plazirhangar" ]] || fail "PATH install missing after unique resolve"
pass "unique plugin dir OK"

# --- 2 dirs → FAIL (refuse head -1) ---
rm -rf "$GROK/installed-plugins"
mkdir -p "$GROK/installed-plugins"
plant_stack "$GROK/installed-plugins/xbgst-stack-one"
plant_stack "$GROK/installed-plugins/xbgst-stack-two"
set +e
out2="$(run_install 2>&1)"
ec2=$?
set -e
echo "$out2"
[[ "$ec2" -ne 0 ]] || fail "2 plugin dirs should FAIL"
echo "$out2" | grep -qiE 'multiple plugin dirs|ambiguous|refuse' || fail "2 dirs missing ambiguity message"
pass "2 plugin dirs FAIL (no head -1)"

# --- --from-tree marketplace root shape ---
MP="$FAKE/marketplace"
mkdir -p "$MP/plugins"
plant_stack "$MP/plugins/xbgst-stack"
rm -rf "$GROK/installed-plugins"
mkdir -p "$GROK/installed-plugins"
set +e
out3="$(run_install --from-tree "$MP" 2>&1)"
ec3=$?
set -e
echo "$out3"
[[ "$ec3" -eq 0 ]] || fail "--from-tree marketplace root want 0 got $ec3"
pass "--from-tree marketplace root OK"

# Confirm script has no ls|head resolve
if grep -nE 'ls -d.*xbgst-stack' "$PH"; then
  fail "ls -d still used for plugin resolve"
fi
pass "no ls -d resolve"

# --- marketplace already configured (exit 1) → install continues ---
rm -rf "$GROK/installed-plugins"
mkdir -p "$GROK/installed-plugins"
plant_stack "$GROK/installed-plugins/xbgst-stack-already"
cat >"$STUBS/grok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "add" ]]; then
  echo "Error: Marketplace source already configured: https://github.com/VeigaPunk/grok-marketplace.git" >&2
  exit 1
fi
# plugin install / details: succeed / empty
exit 0
EOF
chmod +x "$STUBS/grok"
set +e
out_ac="$(run_install 2>&1)"
ec_ac=$?
set -e
echo "$out_ac"
[[ "$ec_ac" -eq 0 ]] || fail "already-configured marketplace add want exit 0 got $ec_ac"
echo "$out_ac" | grep -qiE 'already configured|marketplace already' \
  || fail "already-configured path missing acknowledgment"
# Must not swallow unrelated failures: ensure script has no marketplace add || true
if grep -nE 'marketplace add.*\|\| true' "$PH"; then
  fail "forbidden || true on marketplace add"
fi
pass "marketplace already-configured → install continues"

# Unrelated marketplace failure must still abort (not || true)
cat >"$STUBS/grok" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "add" ]]; then
  echo "Error: network unreachable" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$STUBS/grok"
rm -rf "$GROK/installed-plugins"
mkdir -p "$GROK/installed-plugins"
plant_stack "$GROK/installed-plugins/xbgst-stack-netfail"
set +e
out_nf="$(run_install 2>&1)"
ec_nf=$?
set -e
echo "$out_nf"
[[ "$ec_nf" -ne 0 ]] || fail "unrelated marketplace failure must abort"
pass "unrelated marketplace add failure still aborts"

rm -rf "$FAKE"
echo "All install-resolve tests passed."
