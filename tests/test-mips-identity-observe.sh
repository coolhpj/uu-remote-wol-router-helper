#!/bin/sh
# Synthetic-only privacy and path inventory tests for Y1 read-only observer.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/mips-identity-observe.sh"
BASE="/tmp/uu-wol-helper-root-identity-observe-$$"
trap 'rm -rf "$BASE"' EXIT HUP INT TERM
mkdir -p "$BASE/tmp/uu-wol-helper-mips-persist/files" \
    "$BASE/usr/sbin/uu" "$BASE/etc/uu-mips-wol-helper" "$BASE/proc/432" \
    "$BASE/tmp/uu"
fail() { echo "not ok - $1" >&2; exit 1; }
SECRET='synthetic-private-identity-01234'
printf '%s' "$SECRET" > "$BASE/tmp/uu-wol-helper-mips-persist/files/.uuplugin_uuid"
printf '%s' "$SECRET" > "$BASE/usr/sbin/uu/.uuplugin_uuid"
printf 'uuplugin\n' > "$BASE/proc/432/comm"
ln -s "$BASE/tmp/uu-wol-helper-mips-persist/files" "$BASE/proc/432/cwd"
out=$(UU_TEST_MODE=1 UU_DIAG_TEST_ROOT="$BASE" sh "$SCRIPT") || fail "observer failed"
printf '%s\n' "$out" | grep -q '^mode: read-only$' || fail "read-only declaration absent"
printf '%s\n' "$out" | grep -q '^managed_ram: present size_bytes=' || fail "managed RAM identifier not detected"
printf '%s\n' "$out" | grep -q '^official_dir: present size_bytes=' || fail "official directory identifier not detected"
printf '%s\n' "$out" | grep -q '^compare_managed_ram_to_official_dir: same$' || fail "equivalent files not identified"
printf '%s\n' "$out" | grep -q '^uuplugin_cwd_1: managed_ram$' || fail "plugin working directory not reported"
printf '%s\n' "$out" | grep -q '^uuplugin_process_count: 1$' || fail "plugin count incorrect"
if printf '%s\n' "$out" | grep -qF "$SECRET"; then fail "identity leaked in output"; fi
if printf '%s\n' "$out" | grep -qE '(token|passwd|cookie|credential)=[^ ]+'; then fail "sensitive data leaked"; fi
[ "$(cat "$BASE/usr/sbin/uu/.uuplugin_uuid")" = "$SECRET" ] || fail "observer mutated input"
echo 'ok - observer is read-only and never reveals opaque identity values'

printf 'another-private-identity-888' > "$BASE/usr/sbin/uu/.uuplugin_uuid"
out=$(UU_TEST_MODE=1 UU_DIAG_TEST_ROOT="$BASE" sh "$SCRIPT") || fail "observer failed on mismatch"
printf '%s\n' "$out" | grep -q '^compare_managed_ram_to_official_dir: different$' || fail "mismatching identities not classified"
echo 'ok - mismatched candidate identities are reported without contents'

rm "$BASE/usr/sbin/uu/.uuplugin_uuid"
ln -s /etc/passwd "$BASE/usr/sbin/uu/.uuplugin_uuid"
out=$(UU_TEST_MODE=1 UU_DIAG_TEST_ROOT="$BASE" sh "$SCRIPT") || fail "observer failed on symlink"
printf '%s\n' "$out" | grep -q '^official_dir: symlink_not_followed$' || fail "symlink should not be followed"
if printf '%s\n' "$out" | grep -q 'root:x:'; then fail "symlink target leaked"; fi
echo 'ok - symlink is refused without reading the target'

if UU_TEST_MODE=1 UU_DIAG_TEST_ROOT=/etc sh "$SCRIPT" >/dev/null 2>&1; then fail "unsafe test-root override should be refused"; fi
echo 'ok - untrusted test-root override is refused'
echo 'all MIPS identity observer tests passed'
