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

found=0
for commit in $commits; do
    set +e
    output=$(git -c safe.directory="$ROOT_DIR" grep -nE "$PATTERN" "$commit" -- . ':(exclude)tests/test-api-parser.sh' 2>&1)
    rc=$?
    set -e

    case "$rc" in
        0)
            printf 'Sensitive-looking history value in commit %s (%s):\n' \
                "$commit" "$(git -c safe.directory="$ROOT_DIR" show -s --format='%s' "$commit")" >&2
            printf '%s\n' "$output" >&2
            found=1
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
