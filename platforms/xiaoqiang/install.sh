#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"
. "$ROOT_DIR/lib/evidence.sh"
. "$ROOT_DIR/platforms/xiaoqiang/persist-common.sh"

TARGET_ROOT="${UU_TARGET_ROOT:-/}"
STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
CONFIRM="${UU_XQ_INSTALL_CONFIRM:-}"
TEST_MODE="${UU_TEST_MODE:-0}"
PREFLIGHT_BYPASS="${UU_XQ_PREFLIGHT_BYPASS:-0}"
UCI_BIN="${UU_XQ_UCI_BIN:-uci}"
TEST_UCI="${UU_XQ_TEST_UCI:-0}"

if [ "$CONFIRM" != "MIGRATE_XIAOQIANG_UU" ]; then
    cat >&2 <<'EOF'
XiaoQiang persistent migration is disabled by default.
This adapter currently supports only the hardware-verified legacy-migration path.
To run after reviewing the script, set:
  UU_XQ_INSTALL_CONFIRM=MIGRATE_XIAOQIANG_UU
A matching XiaoQiang smoke-pass marker is also required.
EOF
    exit 64
fi

if ! xq_validate_target_root "$TARGET_ROOT"; then
    echo "Unsafe target root." >&2
    exit 2
fi

case "$STAGE_DIR" in
    /tmp/uu-wol-helper-*) ;;
    *) echo "Unsafe stage directory." >&2; exit 2 ;;
esac

if [ "$TARGET_ROOT" = "/" ] && [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    echo "Root is required for XiaoQiang persistent migration." >&2
    exit 3
fi

if [ "$TEST_MODE" != "1" ] || [ "$PREFLIGHT_BYPASS" != "1" ]; then
    if ! sh "$ROOT_DIR/platforms/xiaoqiang/preflight.sh" >/dev/null; then
        echo "XiaoQiang preflight failed; migration aborted." >&2
        exit 3
    fi
fi

plugin_dir=$(xq_plugin_dir "$TARGET_ROOT")
helper_dir=$(xq_helper_dir "$TARGET_ROOT")
state_dir=$(xq_state_dir "$TARGET_ROOT")
install_json=$(xq_install_json "$TARGET_ROOT")

if ! xq_legacy_metadata_ready "$TARGET_ROOT"; then
    cat >&2 <<'EOF'
Legacy XiaoQiang plugin metadata is incomplete.
This first installer intentionally refuses a fresh/bare-device install because that path has not been hardware-verified.
Required existing items: manifest, start_script, installPlugin JSON, and an xnetease-uu start_script reference.
EOF
    exit 66
fi

metadata="$STAGE_DIR/metadata"
package="$STAGE_DIR/uu.tar.gz"
[ -f "$metadata" ] || { echo "Stage metadata is missing." >&2; exit 4; }
[ -f "$package" ] || { echo "Staged official package is missing." >&2; exit 4; }

stage_channel=$(sed -n 's/^channel=//p' "$metadata" | head -n 1)
stage_version=$(sed -n 's/^version=//p' "$metadata" | head -n 1)
stage_md5=$(sed -n 's/^md5=//p' "$metadata" | head -n 1 | tr 'A-F' 'a-f')

[ "$stage_channel" = "openwrt-aarch64" ] || {
    printf 'Staged channel mismatch: expected=openwrt-aarch64 actual=%s\n' "$stage_channel" >&2
    exit 4
}

uu_verify_md5 "$package" "$stage_md5" || { echo "Staged package MD5 mismatch." >&2; exit 4; }
uu_validate_uu_package "$package" || { echo "Staged package structure invalid." >&2; exit 4; }
uu_check_smoke_pass "$STAGE_DIR" xiaoqiang "$stage_md5" || {
    echo "A matching XiaoQiang smoke-pass marker is required before persistent migration." >&2
    exit 5
}

for required in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    [ -f "$STAGE_DIR/files/$required" ] || { printf 'Staged file missing: %s\n' "$required" >&2; exit 4; }
done

for cmd in cp mv rm mkdir chmod date grep sed; do
    command -v "$cmd" >/dev/null 2>&1 || { printf 'Required command missing: %s\n' "$cmd" >&2; exit 3; }
done

mkdir -p "$state_dir/backups" || exit 6
stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || printf unknown)
backup_dir="$state_dir/backups/$stamp-$$"
mkdir -p "$backup_dir/plugin" "$backup_dir/helper" "$backup_dir/installPlugin" || exit 6

cp -pR "$plugin_dir/." "$backup_dir/plugin/" || exit 6
if [ -d "$helper_dir" ]; then
    cp -pR "$helper_dir/." "$backup_dir/helper/" || exit 6
    had_helper=yes
else
    had_helper=no
fi
cp -p "$install_json" "$backup_dir/installPlugin/2882303761518031252.json" || exit 6

previous_runtime=no
if [ "$TARGET_ROOT" = "/" ] && xq_runtime_active; then
    previous_runtime=yes
fi

firewall_exists=no
firewall_type=""
firewall_path=""
firewall_enabled=""
if { [ "$TARGET_ROOT" = "/" ] || { [ "$TEST_MODE" = "1" ] && [ "$TEST_UCI" = "1" ]; }; } && command -v "$UCI_BIN" >/dev/null 2>&1; then
    if "$UCI_BIN" -q get firewall.uuplugin >/dev/null 2>&1; then
        firewall_exists=yes
        firewall_type=$("$UCI_BIN" -q get firewall.uuplugin.type 2>/dev/null || true)
        firewall_path=$("$UCI_BIN" -q get firewall.uuplugin.path 2>/dev/null || true)
        firewall_enabled=$("$UCI_BIN" -q get firewall.uuplugin.enabled 2>/dev/null || true)
    fi
fi

{
    printf 'had_helper=%s\n' "$had_helper"
    printf 'previous_runtime=%s\n' "$previous_runtime"
    printf 'firewall_exists=%s\n' "$firewall_exists"
    printf 'firewall_type=%s\n' "$firewall_type"
    printf 'firewall_path=%s\n' "$firewall_path"
    printf 'firewall_enabled=%s\n' "$firewall_enabled"
} > "$backup_dir/manifest"
printf '%s\n' "$backup_dir" > "$state_dir/last-backup"

rollback_failed_install() {
    reason="$1"
    printf 'install_failure: %s\n' "$reason" >&2
    if UU_TARGET_ROOT="$TARGET_ROOT" UU_TEST_MODE="$TEST_MODE" UU_XQ_ROLLBACK_CONFIRM=AUTO_ROLLBACK_AFTER_FAILED_INSTALL \
       sh "$ROOT_DIR/platforms/xiaoqiang/rollback.sh" >/dev/null 2>&1; then
        echo "automatic_rollback: pass" >&2
    else
        echo "automatic_rollback: failed; manual recovery is required" >&2
    fi
}

if [ "$TARGET_ROOT" = "/" ] && [ "$TEST_MODE" != "1" ]; then
    if [ ! -x "$plugin_dir/xnetease-uu" ]; then
        echo "Existing verified xnetease-uu restore wrapper is missing." >&2
        exit 6
    fi
    "$plugin_dir/xnetease-uu" plugoff >/dev/null 2>&1 || true
    sleep 2
fi

# Preserve legacy XiaoQiang metadata, but replace runtime with the staged official package and verified wrappers.
for file in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    cp -p "$STAGE_DIR/files/$file" "$plugin_dir/$file" || { rollback_failed_install "failed to copy $file"; exit 7; }
done
cp -p "$ROOT_DIR/platforms/xiaoqiang/runtime/uuplugin_monitor.sh" "$plugin_dir/uuplugin_monitor.sh" || { rollback_failed_install "failed to copy monitor"; exit 7; }
cp -p "$ROOT_DIR/platforms/xiaoqiang/runtime/xnetease-uu" "$plugin_dir/xnetease-uu" || { rollback_failed_install "failed to copy wrapper"; exit 7; }
chmod 0755 "$plugin_dir/uuplugin" "$plugin_dir/xuplugin-guardian" "$plugin_dir/xtables-nft-multi" "$plugin_dir/uuplugin_monitor.sh" "$plugin_dir/xnetease-uu" || { rollback_failed_install "chmod failed"; exit 7; }

mkdir -p "$helper_dir" || { rollback_failed_install "helper directory creation failed"; exit 7; }
cp -p "$ROOT_DIR/platforms/xiaoqiang/runtime/auto.sh" "$helper_dir/auto.sh" || { rollback_failed_install "failed to copy boot helper"; exit 7; }
chmod 0755 "$helper_dir/auto.sh" || { rollback_failed_install "boot helper chmod failed"; exit 7; }

{
    printf 'managed_by=uu-remote-wol-router-helper\n'
    printf 'mode=legacy-migration\n'
    printf 'channel=%s\n' "$stage_channel"
    printf 'version=%s\n' "$stage_version"
    printf 'md5=%s\n' "$stage_md5"
} > "$helper_dir/install.meta"

# The verified RB06 path retained Xiaomi metadata and only updated its display version.
display_version=${stage_version#v}
manifest_tmp="$plugin_dir/manifest.new.$$"
json_tmp="$install_json.new.$$"
sed "s/^version = \"[^\"]*\";/version = \"$display_version\";/" "$plugin_dir/manifest" > "$manifest_tmp" || { rollback_failed_install "manifest update failed"; exit 7; }
mv "$manifest_tmp" "$plugin_dir/manifest" || { rollback_failed_install "manifest replace failed"; exit 7; }
sed "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$display_version\"/" "$install_json" > "$json_tmp" || { rollback_failed_install "installPlugin JSON update failed"; exit 7; }
mv "$json_tmp" "$install_json" || { rollback_failed_install "installPlugin JSON replace failed"; exit 7; }

if [ "$TARGET_ROOT" != "/" ] || [ "$TEST_MODE" = "1" ]; then
    if [ "$TEST_MODE" = "1" ] && [ "$TEST_UCI" = "1" ]; then
        "$UCI_BIN" -q delete firewall.uuplugin
        "$UCI_BIN" set firewall.uuplugin=include || exit 8
        "$UCI_BIN" set firewall.uuplugin.type='script' || exit 8
        "$UCI_BIN" set firewall.uuplugin.path='/data/uu-v14/auto.sh' || exit 8
        "$UCI_BIN" set firewall.uuplugin.enabled='1' || exit 8
        "$UCI_BIN" commit firewall || exit 8
    fi
    printf '%s\n' "XiaoQiang legacy migration"
    printf 'target_root: %s\n' "$TARGET_ROOT"
    printf 'backup_dir: %s\n' "$backup_dir"
    printf '%s\n' "service_activation: skipped(test-root)"
    printf '%s\n' "INSTALL_FILES_READY"
    exit 0
fi

"$UCI_BIN" -q delete firewall.uuplugin
"$UCI_BIN" set firewall.uuplugin=include || { rollback_failed_install "failed to create firewall include"; exit 8; }
"$UCI_BIN" set firewall.uuplugin.type='script' || { rollback_failed_install "failed to set firewall include type"; exit 8; }
"$UCI_BIN" set firewall.uuplugin.path='/data/uu-v14/auto.sh' || { rollback_failed_install "failed to set firewall include path"; exit 8; }
"$UCI_BIN" set firewall.uuplugin.enabled='1' || { rollback_failed_install "failed to enable firewall include"; exit 8; }
"$UCI_BIN" commit firewall || { rollback_failed_install "failed to commit firewall include"; exit 8; }

"$plugin_dir/xnetease-uu" plugon >/dev/null 2>&1 || { rollback_failed_install "failed to start migrated UU runtime"; exit 9; }

health_ok=no
elapsed=0
while [ "$elapsed" -lt 45 ]; do
    if UU_PLUGIN_DIR="$plugin_dir" sh "$ROOT_DIR/platforms/xiaoqiang/health.sh" >/dev/null 2>&1; then
        health_ok=yes
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ "$health_ok" != "yes" ]; then
    rollback_failed_install "migrated runtime did not reach monitor + uuplugin + guardian + :16000 health"
    exit 10
fi

printf '%s\n' "XiaoQiang legacy migration"
printf 'plugin_dir: %s\n' "$plugin_dir"
printf 'helper_dir: %s\n' "$helper_dir"
printf 'channel: %s\n' "$stage_channel"
printf 'version: %s\n' "$stage_version"
printf 'backup_dir: %s\n' "$backup_dir"
printf 'service_activation: healthy_after_%ss\n' "$elapsed"
printf '%s\n' "INSTALL_OK"
