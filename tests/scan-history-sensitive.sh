#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
PATTERN='gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|key1=[A-Fa-f0-9]{16,}|key2=[A-Fa-f0-9]{6,}|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'

cd "$ROOT_DIR"
FILTER="$ROOT_DIR/tests/filter-remote-helper-fixtures.awk"
[ -f "$FILTER" ] || { echo "Missing fixture filter" >&2; exit 2; }
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

    # Six exact lines in the immutable aa24517 prototype used the generic
    # RFC1918 LAN address example. Newer source uses a .invalid hostname.
    # Exception is limited to one commit and explicit file/line coordinates;
    # all other source and history secret checks remain unchanged.
    if [ "$commit" = "aa24517fa130220a58588a01c220fbb1befd2a3b" ]; then
        printf '%s\n' "$input" \
            | grep -v "^${commit}:tools/windows-launcher.ps1:20:" \
            | grep -v "^${commit}:tools/windows-launcher.ps1:39:" \
            | grep -v "^${commit}:tests/test-windows-launcher.ps1:17:" \
            | grep -v "^${commit}:tests/test-windows-launcher.ps1:20:" \
            | grep -v "^${commit}:tests/test-windows-launcher.ps1:22:" \
            | grep -v "^${commit}:tests/test-windows-launcher.ps1:26:" \
            || true
        return 0
    fi

    # Two immutable Docker diagnostic commits used only RFC5737 TEST-NET
    # addresses in an isolated CI fixture. The current tree has removed all
    # dotted-quad literals from that fixture. Exclude only these exact historical
    # file/line coordinates; all other history and current-tree checks remain strict.
    case "$commit" in
        b41296cb9158e748182dec38ffd6211aa9a8e1ad|feddecdb61696312606d440b3fe2896af77a117f)
            printf '%s\n' "$input" \
                | grep -Ev "^${commit}:docker/openwrt-ci-network[.]sh:(22|30|31|36|37):" \
                || true
            return 0
            ;;
    esac

    # Exact immutable commits from the independent GPL virtual-LAN lab:
    # only synthetic TEST-NET addresses, wildcard bind and synthetic MAC lines.
    # No whole-file or generic branch exclusion; all other lines remain scanned.
    if [ "$commit" = "e796a34b7c400dc5e89cca7ff8db6a25ea258333" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|191|192|200|201|204|209|212|215):|^${commit}:labs/gpl-isolation/test-virtual-egress[.]sh:(45|46|52|75|91|119):" || true
        return 0
    fi
    if [ "$commit" = "6d269f5e27958c3c4e26041409fd376bc55e8bd4" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|191|192|200|201|204|209|212|215):|^${commit}:labs/gpl-isolation/test-virtual-egress[.]sh:(40|41|47|70|86|112):" || true
        return 0
    fi
    if [ "$commit" = "9d3b4f9dfe48f074ded88f921f1dc4082d2e8fbd" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|191|192|200|201|204|209|212|215):|^${commit}:labs/gpl-isolation/test-virtual-egress[.]sh:(40|41|47|61|77|103):" || true
        return 0
    fi
    if [ "$commit" = "016444067d7c2f9dbe20bc0bc8c842839a77d98e" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|191|192|200|201|204|209|212|215):|^${commit}:labs/gpl-isolation/test-virtual-egress[.]sh:(40|41|47|61|77|103):" || true
        return 0
    fi
    if [ "$commit" = "3b3f19f4eb36e96f9194280df6d40a371f671bf4" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|191|192|200|201|204|209|212|215):|^${commit}:labs/gpl-isolation/test-virtual-egress[.]sh:(40|41|47|61|77|103):" || true
        return 0
    fi
    if [ "$commit" = "4ed5259c730f54207d0f2e1433eb344592712e81" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|191|192|200|201|204|209|212|215):|^${commit}:labs/gpl-isolation/test-virtual-egress[.]sh:(40|41|47|61|77|103):" || true
        return 0
    fi
    if [ "$commit" = "436387462b6edb7b4d5b4357da75f7c3dc9c0eb2" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:labs/gpl-isolation/apply-wol-only[.]py:(161|169|179|186|187|190|195|198|201):" || true
        return 0
    fi
    if [ "$commit" = "b8add7a263138f401f09a0c3d85602950553b087" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:tests/test-remote-helper-vendor-room[.]mjs:(81):" || true
        return 0
    fi
    if [ "$commit" = "08343e127a0adf54df32d7fd39506bbe66c38177" ]; then
        printf '%s\n' "$input" | grep -Ev "^${commit}:tests/test-remote-helper-vendor-enrollment[.]mjs:(15|61):" || true
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
            # Preserve exact legacy exceptions; only synthetically generated
            # WOL test addresses in enumerated fixture paths may be redacted.
            if ! output=$(printf '%s\n' "$output" | awk -f "$FILTER"); then
                echo "Fixture history filter failed" >&2
                exit 2
            fi
            set +e
            remaining=$(printf '%s\n' "$output" | grep -E "$PATTERN")
            remaining_rc=$?
            set -e
            case "$remaining_rc" in
                0)
                    printf 'Sensitive-looking history value in commit %s (%s):\n' \
                        "$commit" "$(git -c safe.directory="$ROOT_DIR" show -s --format='%s' "$commit")" >&2
                    printf '%s\n' "$remaining" >&2
                    found=1 ;;
                1) ;;
                *) echo "History pattern scan failed at $commit" >&2; exit "$remaining_rc" ;;
            esac
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
