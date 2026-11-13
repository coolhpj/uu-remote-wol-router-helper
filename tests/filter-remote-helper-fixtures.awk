# This filter is used ONLY after git grep has already identified candidate lines.
# It substitutes fixed, non-secret test identities inside explicitly scoped
# Remote Helper fixtures. It NEVER substitutes tokens, key1/key2 or arbitrary
# private IP / MAC identifiers. The second grep runs on this filtered text.
#
# Input: path:line:content OR commit:path:line:content (git grep -n).
# Output: corresponding lines with only verified fixture literals masked.
{
    count = split($0, parts, ":")
    filepath = parts[1]
    if (length(filepath) == 40 && filepath ~ /^[0-9a-f]+$/) filepath = parts[2]
    fixture = index(filepath, "tests/fixtures/remote-helper-") == 1 \
        || index(filepath, "tests/test-remote-helper-") == 1 \
        || filepath == "experiments/remote-helper/README.md"
    line = $0
    if (fixture) {
        # RFC 5737 TEST-NET examples and a dedicated synthetic /23 test.
        gsub(/(198[.]51[.](100|101)|203[.]0[.]113|192[.]0[.]2)[.][0-9][0-9]?[0-9]?/, "FIXTURE_IP", line)
        # Special-purpose test-only link-local, loopback, multicast and malformed addresses.
        gsub(/127[.]0[.]0[.][12]/, "FIXTURE_LOOPBACK", line)
        gsub(/169[.]254[.](0|1)[.](10|20|40)/, "FIXTURE_LINK_LOCAL", line)
        gsub(/239[.]1[.]2[.][34]/, "FIXTURE_MULTICAST", line)
        gsub(/0[.]2[.]3[.]4/, "FIXTURE_BAD_IP", line)
        gsub(/001[.]2[.]3[.]4/, "FIXTURE_BAD_IP", line)
        gsub(/010[.]1[.]2[.]3/, "FIXTURE_BAD_IP", line)
        # Test masks and invalid-mask negative fixtures: none identify a host.
        gsub(/255[.]255[.]255[.](0|128|254|255)/, "FIXTURE_MASK", line)
        gsub(/255[.]255[.](254|0)[.]0/, "FIXTURE_MASK", line)
        gsub(/255[.]0[.]255[.]0/, "FIXTURE_MASK", line)
        gsub(/0[.]0[.]0[.]0/, "FIXTURE_MASK", line)
        # Test-only fake MAC identifiers (globally/local administered, unicast,
        # multicast and invalid boundary cases); do not allow arbitrary MACs.
        gsub(/0[12]:[aA][aA]:[bB][bB]:[cC][cC]:[dD][dD]:[eE][eE]/, "FIXTURE_MAC", line)
        gsub(/02:10:20:30:40:5[02]/, "FIXTURE_MAC", line)
        gsub(/[0]1:10:20:30:40:50/, "FIXTURE_MAC", line)
        gsub(/[0]0:00:00:00:00:00/, "FIXTURE_MAC", line)
        gsub(/[fF][fF]:[fF][fF]:[fF][fF]:[fF][fF]:[fF][fF]:[fF][fF]/, "FIXTURE_MAC", line)
        # The documented test transport version isn't a network IP.
        if (filepath == "experiments/remote-helper/README.md")
            gsub(/1[.]8[.]0[.]3/, "SOCAT_FIXTURE_VERSION", line)
    }
    # Only these three GPL virtual-LAN test files contain the fixed sample
    # address/MAC literals below. This also covers immutable historical revisions
    # without excluding any commit, whole file, unrelated MAC, IP or token.
    gpl_fixture = filepath == "labs/gpl-isolation/apply-wol-only.py" \
        || filepath == "labs/gpl-isolation/test-virtual-egress.sh" \
        || filepath == ".github/workflows/isolated-gpl-wol-only.yml"
    if (gpl_fixture) {
        gsub(/02:11:22:33:44:5[56]/, "GPL_SYNTHETIC_MAC", line)
        gsub(/198[.]51[.]100[.](1|40)([^0-9]|$)/, "GPL_TEST_NET", line)
        gsub(/203[.]0[.]113[.]1([^0-9]|$)/, "GPL_TEST_NET", line)
        gsub(/255[.]255[.]255[.]0([^0-9]|$)/, "GPL_TEST_MASK", line)
        gsub(/255[.]255[.]0[.]0([^0-9]|$)/, "GPL_TEST_MASK", line)
        gsub(/0[.]0[.]0[.]0([^0-9]|$)/, "GPL_WILDCARD_BIND", line)
    }
    print line
}
