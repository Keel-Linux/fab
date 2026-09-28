# shellcheck shell=bash
# TAP helpers shared by the suites under tests/. Source it, never run it:
#
#     . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tap.sh"
#
# It defines count, failed, ok, not_ok and is. A suite ends with
#
#     echo "1..$count"
#     exit "$failed"
#
# so the exit status is the number of failed checks, and tests/coverage.sh
# can count the "ok" and "not ok" lines of every suite the same way.
#
# This file exists because three suites wanted the same twenty lines. The
# handbook records copying a test library instead of sharing it as something
# this project did wrong and would do again unless it was written down.

count=0
failed=0

ok() {
    count=$((count + 1))
    echo "ok $count - $1"
}

not_ok() {
    count=$((count + 1))
    failed=$((failed + 1))
    echo "not ok $count - $1"
    printf '%s\n' "$2" | sed 's/^/# /'
}

is() {
    if [[ "$2" == "$3" ]]; then
        ok "$1"
    else
        not_ok "$1" "got:  $2
want: $3"
    fi
}
