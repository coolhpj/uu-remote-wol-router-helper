#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/evidence.sh"

failures=0
ok() { printf 'ok - %s\n' "$1"; }
not_ok() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }

base="/tmp/uu-wol-helper-xq-persist-test-$$"
stage="/tmp/uu-wol-helper-xq-stage-$$"
root1="/tmp/uu-wol-helper-root-$$-xq-a"
root2="/tmp/uu-wol-helper-root-$$-xq-b"
fake_uci="$base/fake-uci"
uci_state="$base/uci-state"

cleanup() {
    rm -rf "$base" "$stage" "$root1" "$root2"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$base/pkg" "$stage/files" \
    "$root1/userdisk/appdata/2882303761518031252" \
    "$root1/userdisk/appdata/installPlugin" \
    "$root1/data/uu-v14" \
    "$root2/userdisk/appdata/2882303761518031252" \
    "$root2/userdisk/appdata/installPlugin"

cat > "$fake_uci" <<'EOF'
#!/bin/sh
state=${FAKE_UCI_STATE:?}
quiet=no
if [ "${1:-}" = "-q" ]; then quiet=yes; shift; fi
cmd=${1:-}; shift || true
get_value() {
    key=$1
    sed -n "s#^${key}=##p" "$state" 2>/dev/null | head -n 1
}
case "$cmd" in
    get)
        key=${1:-}
        value=$(get_value "$key")
        [ -n "$value" ] || exit 1
        printf '%s\n' "$value"
        ;;
    delete)
        key=${1:-}
        tmp="${state}.tmp.$$"
        grep -v "^${key}\(\.\|=\)" "$state" 2>/dev/null > "$tmp" || true
        mv "$tmp" "$state"
        ;;
    set)
        pair=${1:-}
        key=${pair%%=*}
        value=${pair#*=}
        tmp="${state}.tmp.$$"
        grep -v "^${key}=" "$state" 2>/dev/null > "$tmp" || true
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
        mv "$tmp" "$state"
        ;;
    commit) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod 0755 "$fake_uci"

# Current legacy firewall section that must be restored by rollback.
printf '%s\n' \
    'firewall.uuplugin=include' \
    'firewall.uuplugin.type=script' \
    'firewall.uuplugin.path=/data/legacy-uu/auto.sh' \
    'firewall.uuplugin.enabled=1' > "$uci_state"

# Build a staged official package fixture.
for file in uuplugin xuplugin-guardian xtables-nft-multi; do
    printf '#!/bin/sh\necho new-%s\n' "$file" > "$base/pkg/$file"
    chmod 0755 "$base/pkg/$file"
done
printf 'log_level=info\nversion=v-new\n' > "$base/pkg/uu.conf"
(
    cd "$base/pkg" || exit 1
    tar -czf "$stage/uu.tar.gz" uuplugin xuplugin-guardian uu.conf xtables-nft-multi
) || exit 1
cp -p "$base/pkg/"* "$stage/files/"
md5=$(md5sum "$stage/uu.tar.gz" | awk '{print $1}')
printf 'channel=openwrt-aarch64\nversion=v14.9.99\nmd5=%s\n' "$md5" > "$stage/metadata"

# Hardware-verified legacy metadata shape: preserve it, only update display version.
plugin1="$root1/userdisk/appdata/2882303761518031252"
printf 'legacy-plugin\n' > "$plugin1/uuplugin"
printf 'legacy-guardian\n' > "$plugin1/xuplugin-guardian"
printf 'legacy-nft\n' > "$plugin1/xtables-nft-multi"
printf 'log_level=info\nversion=v-old\n' > "$plugin1/uu.conf"
printf '#!/bin/sh\necho legacy-monitor\n' > "$plugin1/uuplugin_monitor.sh"
printf '#!/bin/sh\necho legacy-wrapper\n' > "$plugin1/xnetease-uu"
chmod 0755 "$plugin1/uuplugin" "$plugin1/xuplugin-guardian" "$plugin1/xtables-nft-multi" "$plugin1/uuplugin_monitor.sh" "$plugin1/xnetease-uu"
printf '%s\n' \
    'plugin_id = "2882303761518031252";' \
    'name = "UU";' \
    'version = "4.0.2";' \
    'control_url = "https://router.uu.163.com/xiaomi/index.html";' > "$plugin1/manifest"
printf 'RUN ./xnetease-uu plugon\nSTOP /userdisk/appdata/2882303761518031252/xnetease-uu plugoff\n' > "$plugin1/start_script"
printf '{"id":"2882303761518031252","version": "4.0.2","isEnable":true}\n' > "$root1/userdisk/appdata/installPlugin/2882303761518031252.json"
printf 'legacy-helper\n' > "$root1/data/uu-v14/legacy.txt"
printf '#!/bin/sh\necho legacy-auto\n' > "$root1/data/uu-v14/auto.sh"
chmod 0755 "$root1/data/uu-v14/auto.sh"

common_env="UU_TARGET_ROOT=$root1 UU_TEST_MODE=1 UU_XQ_PREFLIGHT_BYPASS=1 UU_STAGE_DIR=$stage UU_XQ_UCI_BIN=$fake_uci UU_XQ_TEST_UCI=1 FAKE_UCI_STATE=$uci_state"

out=$(env $common_env sh "$ROOT_DIR/platforms/xiaoqiang/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 64 ] && printf '%s' "$out" | grep 'disabled by default' >/dev/null 2>&1; then
    ok "XiaoQiang migration is disabled by default"
else
    not_ok "XiaoQiang migration is disabled by default"
fi

out=$(env $common_env UU_XQ_INSTALL_CONFIRM=MIGRATE_XIAOQIANG_UU sh "$ROOT_DIR/platforms/xiaoqiang/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 5 ] && printf '%s' "$out" | grep 'smoke-pass' >/dev/null 2>&1; then
    ok "XiaoQiang migration requires smoke-pass evidence"
else
    not_ok "XiaoQiang migration requires smoke-pass evidence"
fi

uu_write_smoke_pass "$stage" xiaoqiang "$md5" || exit 1

# A bare/fresh target is intentionally rejected until hardware verified.
cp -p "$root1/userdisk/appdata/installPlugin/2882303761518031252.json" "$root2/userdisk/appdata/installPlugin/2882303761518031252.json"
out=$(UU_TARGET_ROOT="$root2" UU_TEST_MODE=1 UU_XQ_PREFLIGHT_BYPASS=1 UU_STAGE_DIR="$stage" UU_XQ_INSTALL_CONFIRM=MIGRATE_XIAOQIANG_UU sh "$ROOT_DIR/platforms/xiaoqiang/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 66 ] && printf '%s' "$out" | grep 'fresh/bare-device' >/dev/null 2>&1; then
    ok "fresh XiaoQiang install fails closed without verified legacy metadata"
else
    not_ok "fresh XiaoQiang install fails closed without verified legacy metadata"
fi

out=$(env $common_env UU_XQ_INSTALL_CONFIRM=MIGRATE_XIAOQIANG_UU sh "$ROOT_DIR/platforms/xiaoqiang/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep 'INSTALL_FILES_READY' >/dev/null 2>&1; then
    ok "legacy XiaoQiang migration writes staged runtime under test root"
else
    printf '%s\n' "$out" >&2
    not_ok "legacy XiaoQiang migration writes staged runtime under test root"
fi

if grep 'new-uuplugin' "$plugin1/uuplugin" >/dev/null 2>&1 && \
   [ -x "$plugin1/uuplugin_monitor.sh" ] && [ -x "$plugin1/xnetease-uu" ] && \
   [ -x "$root1/data/uu-v14/auto.sh" ] && \
   grep '^managed_by=uu-remote-wol-router-helper$' "$root1/data/uu-v14/install.meta" >/dev/null 2>&1; then
    ok "migration installs official runtime plus verified RB06 wrappers"
else
    not_ok "migration installs official runtime plus verified RB06 wrappers"
fi

if grep 'version = "14.9.99";' "$plugin1/manifest" >/dev/null 2>&1 && \
   grep '"version": "14.9.99"' "$root1/userdisk/appdata/installPlugin/2882303761518031252.json" >/dev/null 2>&1 && \
   grep 'xnetease-uu plugon' "$plugin1/start_script" >/dev/null 2>&1; then
    ok "migration preserves XiaoQiang metadata while updating display version"
else
    not_ok "migration preserves XiaoQiang metadata while updating display version"
fi

if grep '^firewall.uuplugin=include$' "$uci_state" >/dev/null 2>&1 && \
   grep '^firewall.uuplugin.type=script$' "$uci_state" >/dev/null 2>&1 && \
   grep '^firewall.uuplugin.path=/data/uu-v14/auto.sh$' "$uci_state" >/dev/null 2>&1 && \
   grep '^firewall.uuplugin.enabled=1$' "$uci_state" >/dev/null 2>&1; then
    ok "migration registers the hardware-verified firewall include"
else
    not_ok "migration registers the hardware-verified firewall include"
fi

out=$(env UU_TARGET_ROOT="$root1" UU_TEST_MODE=1 UU_XQ_UCI_BIN="$fake_uci" UU_XQ_TEST_UCI=1 FAKE_UCI_STATE="$uci_state" UU_XQ_ROLLBACK_CONFIRM=ROLLBACK_XIAOQIANG_UU sh "$ROOT_DIR/platforms/xiaoqiang/rollback.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep 'ROLLBACK_OK' >/dev/null 2>&1; then
    ok "XiaoQiang rollback restores the pre-migration snapshot"
else
    printf '%s\n' "$out" >&2
    not_ok "XiaoQiang rollback restores the pre-migration snapshot"
fi

if grep '^legacy-plugin$' "$plugin1/uuplugin" >/dev/null 2>&1 && \
   grep 'version = "4.0.2";' "$plugin1/manifest" >/dev/null 2>&1 && \
   grep '"version": "4.0.2"' "$root1/userdisk/appdata/installPlugin/2882303761518031252.json" >/dev/null 2>&1 && \
   [ -f "$root1/data/uu-v14/legacy.txt" ]; then
    ok "rollback restores plugin, metadata and helper files"
else
    not_ok "rollback restores plugin, metadata and helper files"
fi

if grep '^firewall.uuplugin.path=/data/legacy-uu/auto.sh$' "$uci_state" >/dev/null 2>&1; then
    ok "rollback restores the previous firewall include path"
else
    not_ok "rollback restores the previous firewall include path"
fi

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all XiaoQiang persistence tests passed\n'
