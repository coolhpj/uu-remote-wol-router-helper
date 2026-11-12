#!/bin/sh
set -eu

# Fail CI if source files contain obvious live credentials/network identifiers.
# Synthetic API fixtures are excluded because they intentionally contain fake key1/key2 values.

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
PATTERN='gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|key1=[A-Fa-f0-9]{16,}|key2=[A-Fa-f0-9]{6,}|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'

set +e
output=$(git -c safe.directory="$ROOT_DIR" -C "$ROOT_DIR" grep -nE "$PATTERN" -- . ':(exclude)tests/test-api-parser.sh' 2>&1)
rc=$?
set -e

case "$rc" in
    0)
        # Git reports syntactically matching candidates. Only explicit test
        # fixture literals may be masked; then re-run the original strict rule.
        FILTER="$ROOT_DIR/tests/filter-remote-helper-fixtures.awk"
        [ -f "$FILTER" ] || { echo "Missing fixture filter" >&2; exit 2; }
        if ! filtered=$(printf '%s\n' "$output" | awk -f "$FILTER"); then
            echo "Fixture filter failed" >&2
            exit 2
        fi
        set +e
        remaining=$(printf '%s\n' "$filtered" | grep -E "$PATTERN")
        remaining_rc=$?
        set -e
        case "$remaining_rc" in
            0)
                printf '%s\n' "$remaining"
                echo "Sensitive-looking value detected. Review and redact before committing." >&2
                exit 1 ;;
            1) echo "sensitive scan passed (known synthetic fixtures checked)" ;;
            *) echo "Sensitive scan grep failed" >&2; exit "$remaining_rc" ;;
        esac
        ;;
    1)
        printf '%s\n' "sensitive scan passed"
        ;;
    *)
        printf '%s\n' "$output" >&2
        echo "Sensitive scan failed to execute correctly." >&2
        exit "$rc"
        ;;
esac
