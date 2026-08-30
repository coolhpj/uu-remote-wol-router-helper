#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
PATTERN='gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|key1=[A-Fa-f0-9]{16,}|key2=[A-Fa-f0-9]{6,}|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'

cd "$ROOT_DIR"
commits=$(git -c safe.directory="$ROOT_DIR" rev-list --all)
[ -n "$commits" ] || {
    echo "No Git history found." >&2
    exit 2
}

# One private-history commit briefly used two deterministic QEMU-only MAC
# fixtures in the ARM64 lab before the lab switched to QEMU-generated MACs.
# They were never physical/user device identifiers. Keep the current-tree
# scanner strict; only suppress those two exact historical fixture lines so
# public-release review can still detect every other MAC/IP/token match.
KNOWN_QEMU_FIXTURE_COMMIT='edff1da2c78f2c9e31bfc2a2f2a67848d17e7257'

filter_known_history_fixture() {
    commit="$1"
    input="$2"

    if [ "$commit" = "$KNOWN_QEMU_FIXTURE_COMMIT" ]; then
        printf '%s\n' "$input" \
            | grep -v "^${commit}:labs/qemu/openwrt-aarch64/network-smoke.exp:21:" \
            | grep -v "^${commit}:labs/qemu/openwrt-aarch64/network-smoke.exp:23:" \
            || true
        return 0
    fi

    printf '%s\n' "$input"
}

found=0
for commit in $commits; do
    set +e
    output=$(git -c safe.directory="$ROOT_DIR" grep -nE "$PATTERN" "$commit" -- . ':(exclude)tests/test-api-parser.sh' 2>&1)
    rc=$?
    set -e

    case "$rc" in
        0)
            output=$(filter_known_history_fixture "$commit" "$output")
            if [ -n "$output" ]; then
                printf 'Sensitive-looking history value in commit %s (%s):\n' \
                    "$commit" "$(git -c safe.directory="$ROOT_DIR" show -s --format='%s' "$commit")" >&2
                printf '%s\n' "$output" >&2
                found=1
            fi
            ;;
        1) ;;
        *)
            printf '%s\n' "$output" >&2
            printf 'History scan failed at commit %s.\n' "$commit" >&2
            exit "$rc"
            ;;
    esac
done

if [ "$found" -ne 0 ]; then
    echo "Sensitive-looking value exists in Git history. Do not make the repository public." >&2
    exit 1
fi

printf 'history sensitive scan passed (%s commits)\n' "$(printf '%s\n' "$commits" | wc -l | tr -d ' ')"
