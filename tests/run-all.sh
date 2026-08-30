#!/bin/sh
set -eu

echo "== shell syntax =="
find . -type f -name '*.sh' -not -path './.git/*' -print | sort | while IFS= read -r file; do
    sh -n "$file"
    printf 'ok - %s\n' "$file"
done

echo "== unit / guard tests =="
for test_file in \
    tests/test-api-parser.sh \
    tests/test-helper-cli.sh \
    tests/test-stage-core.sh \
    tests/test-smoke-guard.sh \
    tests/test-asuswrt-adapter.sh
 do
    sh "$test_file"
done

echo "== sensitive scan =="
sh tests/scan-sensitive.sh

echo "all CI checks passed"
