#!/bin/bash
# The exit status of `fab chroot` (fab#15).
#
# `fab chroot ROOT "command"` must exit with the status of the command, so
# that a failed fab-chroot line in a product recipe stops the build. The
# python3-chroot Chroot class is replaced by a stub that returns
# STUB_RC and logs the command it got; no real chroot is made, so the test
# runs without root. Output is TAP; the exit status is the number of failed
# checks.
#
#   tests/chroot-exit.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
top="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/py/chroot" "$work/py/debian" "$work/root/tmp"
cat > "$work/py/chroot/__init__.py" <<'EOF'
import os


class Chroot:
    def __init__(self, path, environ=None):
        self.path = path

    def system(self, command=None):
        with open(os.environ["STUB_LOG"], "a") as log:
            log.write(f"{command!r}\n")
        return int(os.environ["STUB_RC"])
EOF
# fab imports these at load time; cmd_chroot uses none of them.
: > "$work/py/debian/__init__.py"
echo 'class Deb822: pass' > "$work/py/debian/deb822.py"
: > "$work/py/debian/debfile.py"
: > "$work/py/debian/debian_support.py"
echo 'class Pool: pass' > "$work/py/pool_lib.py"

export PYTHONPATH="$work/py:$top"
export STUB_LOG="$work/calls.log"

n=0
failed=0
check() {
    local name="$1" want="$2" got="$3"
    n=$((n + 1))
    if [[ "$got" == "$want" ]]; then
        echo "ok $n - $name"
    else
        echo "not ok $n - $name (want $want, got $got)"
        failed=$((failed + 1))
    fi
}

run() {
    local rc="$1"
    shift
    STUB_RC="$rc" python3 "$top/fab" chroot "$work/root" "$@" >/dev/null 2>&1
    echo $?
}

check "command string, status 0" 0 "$(run 0 true)"
check "command string, status 1" 1 "$(run 1 false)"
check "command string, status 7" 7 "$(run 7 'exit 7')"
check "no command (shell), status 5" 5 "$(run 5)"
check "killed by signal 9 gives 137" 137 "$(run -9 'kill -9 $$')"

printf '#!/bin/sh\nexit 3\n' > "$work/script.sh"
check "--script, status 3" 3 "$(run 3 --script "$work/script.sh")"

: > "$STUB_LOG"
run 0 'a && b' >/dev/null
check "command string goes to the chroot unchanged" "'a && b'" "$(cat "$STUB_LOG")"

echo "1..$n"
exit "$failed"
