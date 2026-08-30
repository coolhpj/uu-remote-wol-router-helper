#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/evidence.sh"

STAGE_DIR="/tmp/uu-wol-helper-evidence-test-$$"
GOOD_MD5="0123456789abcdef0123456789abcdef"
OTHER_MD5="abcdef0123456789abcdef0123456789"

cleanup() {
    rm -rf "$STAGE_DIR"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$STAGE_DIR"

if ! uu_write_smoke_pass "$STAGE_DIR" xiaoqiang "$GOOD_MD5"; then
    echo "not ok - write smoke-pass marker" >&2
    exit 1
fi
printf 'ok - write smoke-pass marker\n'

if ! uu_check_smoke_pass "$STAGE_DIR" xiaoqiang "$GOOD_MD5"; then
    echo "not ok - matching smoke-pass should validate" >&2
    exit 1
fi
printf 'ok - validate matching smoke-pass\n'

if uu_check_smoke_pass "$STAGE_DIR" openwrt "$GOOD_MD5"; then
    echo "not ok - wrong platform must invalidate smoke-pass" >&2
    exit 1
fi
printf 'ok - reject mismatched platform\n'

if uu_check_smoke_pass "$STAGE_DIR" xiaoqiang "$OTHER_MD5"; then
    echo "not ok - wrong MD5 must invalidate smoke-pass" >&2
    exit 1
fi
printf 'ok - reject mismatched MD5\n'

if uu_write_smoke_pass /tmp/not-uu-helper-stage xiaoqiang "$GOOD_MD5"; then
    echo "not ok - unsafe stage path must be rejected" >&2
    exit 1
fi
printf 'ok - reject unsafe evidence path\n'

if ! uu_clear_smoke_pass "$STAGE_DIR"; then
    echo "not ok - clear smoke-pass marker" >&2
    exit 1
fi
if [ -e "$STAGE_DIR/smoke-pass" ]; then
    echo "not ok - smoke-pass marker should be removed" >&2
    exit 1
fi
printf 'ok - clear smoke-pass marker\n'

printf 'all smoke evidence tests passed\n'
