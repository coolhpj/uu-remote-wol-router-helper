#!/bin/sh
# Read-only MIPS persistence budget tests; never start UU or change a router.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
CHECK="$ROOT/platforms/openwrt/mips-persist-capacity.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
ok() { echo "ok - $*"; }

BASE="/tmp/uu-wol-helper-capacity-test-$$"
mkdir -p "$BASE/bin" "$BASE/files"
trap 'rm -rf "$BASE"' EXIT HUP INT TERM
cat > "$BASE/bin/uname" <<'EOF'
#!/bin/sh
printf 'mips\n'
EOF
cat > "$BASE/bin/opkg" <<'EOF'
#!/bin/sh
printf 'arch all 1\narch mipsel_24kc 10\n'
EOF
cat > "$BASE/bin/df" <<'EOF'
#!/bin/sh
[ "$1:$2" = '-k:/overlay' ] || exit 2
printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\n'
printf 'overlay 15000 2000 %s 20%% /overlay\n' "${MOCK_FREE_KB:-0}"
EOF
chmod +x "$BASE/bin/uname" "$BASE/bin/opkg" "$BASE/bin/df"
cat > "$BASE/release" <<'EOF'
DISTRIB_ARCH='mipsel_24kc'
EOF

# Missing stage must not be misinterpreted as sufficient capacity.
out=$(PATH="$BASE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$BASE/release" MOCK_FREE_KB=10000 UU_STAGE_DIR="$BASE" sh "$CHECK") || fail "capacity inventory read-only success"
printf '%s\n' "$out" | grep -F 'overlay_free_kb: 10000' >/dev/null || fail "df free value"
printf '%s\n' "$out" | grep -F 'direct_install_budget: unknown' >/dev/null || fail "missing stage means unknown"
printf '%s\n' "$out" | grep -F 'persistent_install: blocked' >/dev/null || fail "no install permission"
ok "read-only missing stage reports unknown"

printf 'binary\n' > "$BASE/files/uuplugin"
printf 'guardian\n' > "$BASE/files/xuplugin-guardian"
printf 'config\n' > "$BASE/files/uu.conf"
printf 'xtables\n' > "$BASE/files/xtables-nft-multi"
out=$(PATH="$BASE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$BASE/release" MOCK_FREE_KB=10000 UU_STAGE_DIR="$BASE" sh "$CHECK") || fail "inventory with staged files"
printf '%s\n' "$out" | grep -F 'direct_install_budget: capacity_only_enough' >/dev/null || fail "enough is capacity-only"
printf '%s\n' "$out" | grep -F 'decision: do_not_install' >/dev/null || fail "enough must not enable install"
ok "capacity estimate does not unlock persistence"

out=$(PATH="$BASE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$BASE/release" MOCK_FREE_KB=10 UU_STAGE_DIR="$BASE" sh "$CHECK") || fail "low-space inventory"
printf '%s\n' "$out" | grep -F 'direct_install_budget: insufficient' >/dev/null || fail "insufficient overlay"
ok "insufficient overlay fails closed"

rm -f "$BASE/files/uuplugin"
ln -s "$BASE/files/uu.conf" "$BASE/files/uuplugin"
out=$(PATH="$BASE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$BASE/release" MOCK_FREE_KB=10000 UU_STAGE_DIR="$BASE" sh "$CHECK") || fail "symlink inventory"
printf '%s\n' "$out" | grep -F 'direct_install_budget: unknown' >/dev/null || fail "symlink cannot establish capacity"
ok "symlinked stage never passes budget"

cat > "$BASE/bin/uname" <<'EOF'
#!/bin/sh
printf 'x86_64\n'
EOF
out=$(PATH="$BASE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$BASE/release" UU_STAGE_DIR="$BASE" sh "$CHECK" 2>&1)
rc=$?
[ "$rc" -eq 3 ] || fail "unknown/non-MIPS must reject"
printf '%s\n' "$out" | grep -F 'unsupported_arch' >/dev/null || fail "arch block"
ok "non-MIPS rejected"
echo "all MIPS capacity tests passed"
