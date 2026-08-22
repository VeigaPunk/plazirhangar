#!/usr/bin/env bash
# Hermetic status contract: bash -n + green-home 6 PASS + red-home 6 FAIL + traps + Usage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PH="$ROOT/scripts/plazirhangar"
GREEN_HOME="$ROOT/tests/fixtures/green-home"
RED_HOME="$ROOT/tests/fixtures/red-home"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

chmod +x "$PH" \
  "$GREEN_HOME/.local/bin/sekhmet" \
  "$GREEN_HOME/.local/bin/systemctl" \
  "$GREEN_HOME/.local/opt/grok-build-livepatch/grok" \
  "$RED_HOME/.local/bin/systemctl" 2>/dev/null || true

# Ensure green active_cli path: ~/.grok/bin/grok → livepatch binary
mkdir -p "$GREEN_HOME/.grok/bin"
ln -sfn "$GREEN_HOME/.local/opt/grok-build-livepatch/grok" "$GREEN_HOME/.grok/bin/grok"

bash -n "$PH" || fail "bash -n scripts/plazirhangar"
pass "bash -n"

run_status() {
  local home="$1"
  shift
  env -i \
    HOME="$home" \
    PATH="$home/.local/bin:/usr/bin:/bin" \
    USER="${USER:-test}" \
    LANG=C \
    bash "$PH" status "$@"
}

# --- green-home → 6 PASS + exit 0 ---
set +e
green_out="$(run_status "$GREEN_HOME" 2>&1)"
green_ec=$?
set -e
echo "$green_out"
[[ "$green_ec" -eq 0 ]] || fail "green-home exit want 0 got $green_ec"
for row in livepatch sekhmet xbgst subagents marketplaces l3env; do
  echo "$green_out" | grep -qE "^PASS[[:space:]]+$row([[:space:]]|$)" \
    || fail "green-home missing PASS $row"
done
fail_count="$(echo "$green_out" | grep -cE '^FAIL[[:space:]]' || true)"
[[ "$fail_count" -eq 0 ]] || fail "green-home unexpected FAIL rows ($fail_count)"
echo "$green_out" | grep -qE '^OK([[:space:]]|$)' || fail "green-home missing OK"
pass "green-home 6 PASS exit 0"

# --- red-home → 6 FAIL + exit 1 ---
set +e
red_out="$(run_status "$RED_HOME" 2>&1)"
red_ec=$?
set -e
echo "$red_out"
[[ "$red_ec" -eq 1 ]] || fail "red-home exit want 1 got $red_ec"
for row in livepatch sekhmet xbgst subagents marketplaces l3env; do
  echo "$red_out" | grep -qE "^FAIL[[:space:]]+$row([[:space:]]|$)" \
    || fail "red-home missing FAIL $row"
done
pass_count="$(echo "$red_out" | grep -cE '^PASS[[:space:]]' || true)"
[[ "$pass_count" -eq 0 ]] || fail "red-home unexpected PASS rows ($pass_count)"
echo "$red_out" | grep -qE '^BAD([[:space:]]|$)' || fail "red-home missing BAD"
pass "red-home 6 FAIL exit 1"

# --- trap: max_concurrent=64 → FAIL subagents ---
trap_mc="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_mc/"
mkdir -p "$trap_mc/.grok/bin"
ln -sfn "$trap_mc/.local/opt/grok-build-livepatch/grok" "$trap_mc/.grok/bin/grok"
chmod +x "$trap_mc/.local/bin/"* "$trap_mc/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
sed -i 's/max_concurrent = 16/max_concurrent = 64/' "$trap_mc/.grok/config.toml"
set +e
mc_out="$(run_status "$trap_mc" 2>&1)"
mc_ec=$?
set -e
echo "$mc_out"
[[ "$mc_ec" -eq 1 ]] || fail "max_concurrent=64 exit want 1 got $mc_ec"
echo "$mc_out" | grep -qE '^FAIL[[:space:]]+subagents' || fail "max_concurrent=64 missing FAIL subagents"
pass "trap max_concurrent=64 → FAIL subagents"
rm -rf "$trap_mc"

# --- trap: decoy max_concurrent=16 above [subagents] max_concurrent=64 → FAIL subagents ---
trap_decoy="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_decoy/"
mkdir -p "$trap_decoy/.grok/bin"
ln -sfn "$trap_decoy/.local/opt/grok-build-livepatch/grok" "$trap_decoy/.grok/bin/grok"
chmod +x "$trap_decoy/.local/bin/"* "$trap_decoy/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
cat >"$trap_decoy/.grok/config.toml" <<'EOF'
# decoy first-match poison — status must read [subagents], not file-first
max_concurrent = 16
max_depth = 1
explore = false
general-purpose = false

[[marketplace.sources]]
name = "grok-marketplace"
git = "https://github.com/VeigaPunk/grok-marketplace.git"

[[marketplace.sources]]
name = "ds4cc-marketplace"
git = "https://github.com/VeigaPunk/ds4cc-marketplace.git"

[subagents]
enabled = true
max_depth = 1
max_concurrent = 64

[subagents.toggle]
explore = false
general-purpose = false
EOF
set +e
decoy_out="$(run_status "$trap_decoy" 2>&1)"
decoy_ec=$?
set -e
echo "$decoy_out"
[[ "$decoy_ec" -eq 1 ]] || fail "decoy max_concurrent exit want 1 got $decoy_ec"
echo "$decoy_out" | grep -qE '^FAIL[[:space:]]+subagents' || fail "decoy max_concurrent missing FAIL subagents"
echo "$decoy_out" | grep -qE '^PASS[[:space:]]+subagents' && fail "decoy max_concurrent incorrectly PASS subagents" || true
pass "trap decoy 16 then [subagents] 64 → FAIL subagents"
rm -rf "$trap_decoy"

# --- trap: invalid toml → FAIL subagents ---
trap_bad="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_bad/"
mkdir -p "$trap_bad/.grok/bin"
ln -sfn "$trap_bad/.local/opt/grok-build-livepatch/grok" "$trap_bad/.grok/bin/grok"
chmod +x "$trap_bad/.local/bin/"* "$trap_bad/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
cat >"$trap_bad/.grok/config.toml" <<'EOF'
[subagents]
max_depth = 1
max_concurrent = 16
this is not valid toml = 
EOF
set +e
bad_toml_out="$(run_status "$trap_bad" 2>&1)"
bad_toml_ec=$?
set -e
echo "$bad_toml_out"
[[ "$bad_toml_ec" -eq 1 ]] || fail "invalid toml exit want 1 got $bad_toml_ec"
echo "$bad_toml_out" | grep -qE '^FAIL[[:space:]]+subagents' || fail "invalid toml missing FAIL subagents"
pass "trap invalid toml → FAIL subagents"
rm -rf "$trap_bad"

# --- trap: absent max_concurrent → FAIL subagents ---
trap_abs="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_abs/"
mkdir -p "$trap_abs/.grok/bin"
ln -sfn "$trap_abs/.local/opt/grok-build-livepatch/grok" "$trap_abs/.grok/bin/grok"
chmod +x "$trap_abs/.local/bin/"* "$trap_abs/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
sed -i '/max_concurrent/d' "$trap_abs/.grok/config.toml"
set +e
abs_out="$(run_status "$trap_abs" 2>&1)"
abs_ec=$?
set -e
echo "$abs_out"
[[ "$abs_ec" -eq 1 ]] || fail "absent max_concurrent exit want 1 got $abs_ec"
echo "$abs_out" | grep -qE '^FAIL[[:space:]]+subagents' || fail "absent max_concurrent missing FAIL subagents"
pass "trap absent max_concurrent → FAIL subagents"
rm -rf "$trap_abs"

# --- trap: timer active, no ban, no REPLACE_BIN; planted install-timer lies → FAIL livepatch ---
trap_lp="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_lp/"
mkdir -p "$trap_lp/.grok/bin" \
  "$trap_lp/.grok/installed-plugins/xbgst-stack-planted/livepatch/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'echo grok-no-ban' >"$trap_lp/.local/opt/grok-build-livepatch/grok"
chmod +x "$trap_lp/.local/opt/grok-build-livepatch/grok"
ln -sfn "$trap_lp/.local/opt/grok-build-livepatch/grok" "$trap_lp/.grok/bin/grok"
sed -i '/REPLACE_BIN/d' "$trap_lp/.config/systemd/user/grok-build-livepatch.service"
cat >"$trap_lp/.grok/installed-plugins/xbgst-stack-planted/livepatch/scripts/install-timer.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--status" ]]; then
  echo "ban_in_binary=yes"
  echo "GROK_LIVEPATCH_REPLACE_BIN=1"
  echo "active_cli=livepatch"
  exit 0
fi
exit 0
EOF
chmod +x "$trap_lp/.grok/installed-plugins/xbgst-stack-planted/livepatch/scripts/install-timer.sh"
chmod +x "$trap_lp/.local/bin/"* 2>/dev/null || true
# Also put lying timer on PATH to ensure status ignores it
cp "$trap_lp/.grok/installed-plugins/xbgst-stack-planted/livepatch/scripts/install-timer.sh" \
  "$trap_lp/.local/bin/install-timer.sh"
set +e
lp_out="$(run_status "$trap_lp" 2>&1)"
lp_ec=$?
set -e
echo "$lp_out"
[[ "$lp_ec" -eq 1 ]] || fail "planted-timer trap exit want 1 got $lp_ec"
echo "$lp_out" | grep -qE '^FAIL[[:space:]]+livepatch' || fail "planted-timer trap missing FAIL livepatch"
echo "$lp_out" | grep -qE '^PASS[[:space:]]+livepatch' && fail "planted-timer trap incorrectly PASS livepatch" || true
pass "trap planted install-timer + no ban → FAIL livepatch"
rm -rf "$trap_lp"

# --- amber: JOBS=32 → FAIL l3env ---
trap_jobs="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_jobs/"
mkdir -p "$trap_jobs/.grok/bin"
ln -sfn "$trap_jobs/.local/opt/grok-build-livepatch/grok" "$trap_jobs/.grok/bin/grok"
chmod +x "$trap_jobs/.local/bin/"* "$trap_jobs/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
cat >"$trap_jobs/.xbgst/env.l3-sekhmet.sh" <<'EOF'
export XBRD_SPARK_JOBS=32
export XBRD_SPARK_SERVICE_TIER=fast
EOF
set +e
jobs_out="$(run_status "$trap_jobs" 2>&1)"
jobs_ec=$?
set -e
echo "$jobs_out"
[[ "$jobs_ec" -eq 1 ]] || fail "JOBS=32 exit want 1 got $jobs_ec"
echo "$jobs_out" | grep -qE '^FAIL[[:space:]]+l3env' || fail "JOBS=32 missing FAIL l3env"
pass "amber JOBS=32 → FAIL l3env"
rm -rf "$trap_jobs"

# --- amber: only grok-marketplace URL → FAIL marketplaces ---
trap_mp="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_mp/"
mkdir -p "$trap_mp/.grok/bin"
ln -sfn "$trap_mp/.local/opt/grok-build-livepatch/grok" "$trap_mp/.grok/bin/grok"
chmod +x "$trap_mp/.local/bin/"* "$trap_mp/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
# Keep a minimal config that has grok-marketplace only (no ds4cc).
cat >"$trap_mp/.grok/config.toml" <<'EOF'
[plugins]
enabled = ["xbgst-stack"]

[subagents]
enabled = true
max_depth = 1
max_concurrent = 16

[subagents.toggle]
explore = false
general-purpose = false

[marketplace]
auto_update = false

[[marketplace.sources]]
name = "grok-marketplace"
git = "https://github.com/VeigaPunk/grok-marketplace.git"
EOF
grep -q 'grok-marketplace.git' "$trap_mp/.grok/config.toml" || fail "amber mp fixture lost grok URL"
if grep -q 'ds4cc-marketplace.git' "$trap_mp/.grok/config.toml"; then
  fail "amber mp fixture still has ds4cc URL"
fi
set +e
mp_out="$(run_status "$trap_mp" 2>&1)"
mp_ec=$?
set -e
echo "$mp_out"
[[ "$mp_ec" -eq 1 ]] || fail "only grok-marketplace exit want 1 got $mp_ec"
echo "$mp_out" | grep -qE '^FAIL[[:space:]]+marketplaces' || fail "only grok-marketplace missing FAIL marketplaces"
pass "amber only grok-marketplace URL → FAIL marketplaces"
rm -rf "$trap_mp"

# --- quoted explore/general-purpose "false" → PASS subagents (strip quotes) ---
trap_q="$(mktemp -d)"
cp -a "$GREEN_HOME/." "$trap_q/"
mkdir -p "$trap_q/.grok/bin"
ln -sfn "$trap_q/.local/opt/grok-build-livepatch/grok" "$trap_q/.grok/bin/grok"
chmod +x "$trap_q/.local/bin/"* "$trap_q/.local/opt/grok-build-livepatch/grok" 2>/dev/null || true
sed -i 's/^explore = false$/explore = "false"/; s/^general-purpose = false$/general-purpose = "false"/' \
  "$trap_q/.grok/config.toml"
set +e
q_out="$(run_status "$trap_q" 2>&1)"
q_ec=$?
set -e
echo "$q_out"
[[ "$q_ec" -eq 0 ]] || fail "quoted false toggles exit want 0 got $q_ec"
echo "$q_out" | grep -qE '^PASS[[:space:]]+subagents' || fail "quoted false toggles missing PASS subagents"
pass "quoted explore/gp \"false\" → PASS subagents"
rm -rf "$trap_q"

# --- bad cmd → Usage + exit 1 ---
set +e
bad_out="$(env -i HOME="$RED_HOME" PATH="/usr/bin:/bin" LANG=C bash "$PH" not-a-command 2>&1)"
bad_ec=$?
set -e
echo "$bad_out"
[[ "$bad_ec" -eq 1 ]] || fail "bad cmd exit want 1 got $bad_ec"
echo "$bad_out" | grep -qi 'Usage' || fail "bad cmd missing Usage: $bad_out"
pass "bad cmd Usage exit 1"

echo "All status contract tests passed."
