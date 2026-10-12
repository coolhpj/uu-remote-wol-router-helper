#!/bin/sh
# Test the beta service stop path with fake nft/fw4/ps. No router or UU binary.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
STOP="$ROOT/platforms/openwrt/runtime/mips-experimental-stop.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
ok() { echo "ok - $*"; }
fixture="/tmp/uu-wol-helper-stop-fixture-$$"
mkdir -p "$fixture/bin"
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
export MOCK_NFT_STATE="$fixture/nft.state"
export MOCK_FW_CALLS="$fixture/fw.calls"
cat > "$fixture/bin/nft" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "list tables " ] || exit 4
cat "$MOCK_NFT_STATE"
EOF
cat > "$fixture/bin/fw4" <<'EOF'
#!/bin/sh
[ "$1" = reload ] || exit 2
echo reload >> "$MOCK_FW_CALLS"
[ "${MOCK_FW_FAIL:-no}" = no ] || exit 3
echo 'table inet fw4' > "$MOCK_NFT_STATE"
EOF
cat > "$fixture/bin/ps" <<'EOF'
#!/bin/sh
if [ "${MOCK_OTHER_UU:-no}" = yes ]; then
    printf '123 /external/uuplugin some.conf\n'
fi
EOF
cat > "$fixture/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
echo 'table inet fw4' > "$MOCK_NFT_STATE"
out=$(sh "$STOP" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "no-change cleanup $out"
printf '%s\n' "$out" | grep -q MIPS_STOP_PASS || fail "clean finish"
[ ! -f "$MOCK_FW_CALLS" ] || fail "must not reload if unchanged"
ok "no XU marker causes no firewall reload"

printf 'table ip XU_TEST\n' > "$MOCK_NFT_STATE"
out=$(sh "$STOP" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "explicit XU reload $out"
[ "$(wc -l < "$MOCK_FW_CALLS")" -eq 1 ] || fail "one reload"
ok "XU marker triggers one reload"

printf 'table ip XU_TEST\n' > "$MOCK_NFT_STATE"
out=$(MOCK_FW_FAIL=yes sh "$STOP" 2>&1)
rc=$?
[ "$rc" -eq 8 ] || fail "failed reload must not pretend success"
ok "failed firewall cleanup is reported"

printf 'table ip XU_TEST\n' > "$MOCK_NFT_STATE"
out=$(MOCK_OTHER_UU=yes sh "$STOP" 2>&1)
rc=$?
[ "$rc" -eq 8 ] || fail "unknown UU should block firewall mutation"
[ "$(wc -l < "$MOCK_FW_CALLS")" -eq 2 ] || fail "unknown process must not trigger reload"
ok "unrelated UU process is never killed or reconfigured"
echo "all MIPS experimental stop tests passed"
