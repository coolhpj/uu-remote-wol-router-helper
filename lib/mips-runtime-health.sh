#!/bin/sh
# Pure result predicate for the experimental one-session MIPS runtime test.
# A previously observed cloud/guardian connection is never sufficient.
uu_mips_runtime_window_pass() {
    [ "$1" -ge "$2" ] &&
        [ "$3" = no ] &&
        [ "$4" = yes ] &&
        [ "$5" = yes ] &&
        [ "$6" = yes ]
}
