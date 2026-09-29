#!/bin/bash
# make-level test for the unit loop of share/product.mk: which units a build
# applies (UNITS) and where in root.patched they are applied.
#
# A minimal fake product with three units is built under a scratch FAB_PATH
# against the product.mk of this checkout. The four fab tools the recipe
# calls (fab-apply-overlay, fab-chroot, fab-apply-removelist,
# fab-plan-resolve) are stubs that append their arguments to a log, and the
# init step that would deck a real filesystem is overridden away, so the
# recipe runs for real and the log says what it did and in which order.
# Output is TAP; the exit status is the number of failed checks.
#
# product.mk includes /tmp/.build_env, written by share/load_env; the test
# runs load_env from the fake product, so that file is overwritten for the
# duration of the run and restored afterwards. Nothing else outside the
# scratch directory is touched and no real fab tool is executed.
#
#   tests/units.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
share="$(cd "$here/.." && pwd)/share"
work="$(mktemp -d)"
log="$work/calls.log"

restore_build_env() {
    if [[ -e "$work/build_env.saved" ]]; then
        cp -p "$work/build_env.saved" /tmp/.build_env
    else
        rm -f /tmp/.build_env
    fi
}
cleanup() {
    restore_build_env
    rm -rf "$work"
}
trap cleanup EXIT
[[ ! -e /tmp/.build_env ]] || cp -p /tmp/.build_env "$work/build_env.saved"

# --- stub fab tools -----------------------------------------------------------

mkdir -p "$work/stubs"
for tool in fab-apply-overlay fab-chroot fab-apply-removelist fab-plan-resolve \
        fab-apply-patch; do
    cat > "$work/stubs/$tool" <<EOF
#!/bin/sh
echo "$tool \$*" >> "$log"
if [ -n "\${STUB_FAIL:-}" ] && echo "$tool \$*" | grep -qE "\$STUB_FAIL"; then
    echo "$tool: refusing on purpose" >&2
    exit 1
fi
exit 0
EOF
    chmod 755 "$work/stubs/$tool"
done
export PATH="$work/stubs:$PATH"

# --- fake product with three units ---------------------------------------------

export FAB_PATH="$work/fab"
export FAB_SHARE_PATH="$share"
export RELEASE=debian/trixie
export FAB_ARCH=amd64
export NO_PROXY=true
unset SOURCE_DATE_EPOCH BOOTSTRAP O ISOLABEL CONF_VARS CHROOT_ONLY UNITS STUB_FAIL

product="$work/fakeprod"
mkdir -p "$FAB_PATH/bootstraps/trixie-amd64" \
    "$FAB_PATH/common/overlays/shared" \
    "$FAB_PATH/common/conf" \
    "$FAB_PATH/common/removelists" \
    "$product/plan" "$product/overlay"
: > "$product/plan/main"
: > "$FAB_PATH/common/conf/shared"
: > "$FAB_PATH/common/removelists/shared"

# unit "alpha" carries all of plan, overlay and conf; "beta" carries a plan
# and an overlay only; "gamma" carries a conf script that is not executable
for unit in alpha beta gamma; do
    mkdir -p "$product/unit.d/$unit/overlay"
    : > "$product/unit.d/$unit/plan"
done
printf '#!/bin/sh\ntrue\n' > "$product/unit.d/alpha/conf"
chmod 755 "$product/unit.d/alpha/conf"
printf '#!/bin/sh\ntrue\n' > "$product/unit.d/gamma/conf"
chmod 644 "$product/unit.d/gamma/conf"
echo '/usr/local/src/alpha' > "$product/unit.d/alpha/removelist"
mkdir -p "$product/unit.d/gamma/removelist"

cat > "$product/Makefile" <<'EOF'
COMMON_OVERLAYS = shared
COMMON_CONF = shared
COMMON_REMOVELISTS = shared
include $(FAB_SHARE_PATH)/product.mk
EOF

# The stamped rule is <init> <pre> <body> <post> <cleanup>; only the body is
# under test, and root.patched/init would deck a real filesystem.
neutral=(
    root.patched/init=
    root.patched/deps=
    root.spec/deps=
)

# build TARGET [VAR=VALUE ...]: run the recipe, leaving its calls in $log
build() {
    rm -f "$log"
    rm -rf "$product/build"
    (
        cd "$product" || exit 1
        "$share/load_env" 2>/dev/null
        make "$@" "${neutral[@]}" 2>&1
    ) > "$work/make.out"
    local rc=$?
    touch "$log"
    return $rc
}

# make_var VAR: the value make computes for VAR
make_var() {
    (
        cd "$product" || exit 1
        "$share/load_env" 2>/dev/null
        make debug V="$1" 2>&1 >/dev/null
    ) | sed -n "s|^.*: $1 = ||p" | head -n 1
}

# --- TAP helpers ------------------------------------------------------------

# shellcheck source=tests/tap.sh
. "$here/tap.sh"

# builds DESC TARGET [VAR=VALUE ...]: the recipe runs to the end
builds() {
    local desc=$1
    shift
    if build "$@"; then
        ok "$desc"
    else
        not_ok "$desc" "$(cat "$work/make.out")"
    fi
}

# build_fails DESC TARGET [VAR=VALUE ...]: the recipe stops with an error
build_fails() {
    local desc=$1
    shift
    if build "$@"; then
        not_ok "$desc" "make returned 0
$(cat "$work/make.out")"
    else
        ok "$desc"
    fi
}

# called DESC REGEX: the log has a line matching REGEX
called() {
    if grep -qE -e "$2" "$log"; then
        ok "$1"
    else
        not_ok "$1" "no call matches: $2
$(cat "$log")"
    fi
}

# not_called DESC REGEX: no line of the log matches REGEX
not_called() {
    if grep -qE -e "$2" "$log"; then
        not_ok "$1" "$(grep -E -e "$2" "$log")"
    else
        ok "$1"
    fi
}

# before DESC REGEX_A REGEX_B: the first call matching A precedes the first
# matching B, and both are there
before() {
    local a b
    a=$(grep -nE -e "$2" "$log" | head -n 1 | cut -d : -f 1)
    b=$(grep -nE -e "$3" "$log" | head -n 1 | cut -d : -f 1)
    if [[ -z "$a" || -z "$b" ]]; then
        not_ok "$1" "not both called: $2 and $3
$(cat "$log")"
    elif [[ "$a" -lt "$b" ]]; then
        ok "$1"
    else
        not_ok "$1" "line $a is not before line $b
$(cat "$log")"
    fi
}

alpha_overlay='^fab-apply-overlay unit\.d/alpha/overlay build/root\.patched$'
beta_overlay='^fab-apply-overlay unit\.d/beta/overlay build/root\.patched$'
gamma_overlay='^fab-apply-overlay unit\.d/gamma/overlay build/root\.patched$'
alpha_conf='^fab-chroot build/root\.patched --script unit\.d/alpha/conf$'
alpha_removelist='^fab-apply-removelist unit\.d/alpha/removelist build/root\.patched$'
common_overlay='^fab-apply-overlay .*/common/overlays/shared '
common_conf='^fab-chroot build/root\.patched --script .*/common/conf/shared$'
common_removelist='^fab-apply-removelist .*/common/removelists/shared '
local_overlay='^fab-apply-overlay overlay build/root\.patched$'

# --- every unit is applied by default -----------------------------------------

is "UNITS defaults to every unit directory, sorted" \
    "$(make_var UNITS)" "unit.d/alpha unit.d/beta unit.d/gamma"

builds "the default build succeeds" build/stamps/root.patched
called "the overlay of a unit is applied" "$alpha_overlay"
called "the conf script of a unit is run" "$alpha_conf"
called "a unit without a conf script contributes its overlay" "$beta_overlay"
not_called "a unit conf script that is not executable is not run" \
    'script unit\.d/gamma/conf'
called "a unit whose conf is not executable still contributes its overlay" \
    "$gamma_overlay"

# --- the position in root.patched ---------------------------------------------

before "unit overlays come after the common overlays" \
    "$common_overlay" "$alpha_overlay"
before "unit overlays come after the common conf scripts" \
    "$common_conf" "$alpha_overlay"
before "every unit overlay comes before any unit conf script" \
    "$gamma_overlay" "$alpha_conf"
called "the removelist of a unit is applied" "$alpha_removelist"
not_called "a unit whose removelist is a directory contributes none" \
    'unit\.d/gamma/removelist'
not_called "a unit without a removelist contributes none" \
    'unit\.d/beta/removelist'
before "unit removelists come after the unit conf scripts" \
    "$alpha_conf" "$alpha_removelist"
before "unit removelists come before the common removelists" \
    "$alpha_removelist" "$common_removelist"
before "unit conf scripts come before the common removelists" \
    "$alpha_conf" "$common_removelist"
before "unit overlays come before the product-local overlay" \
    "$alpha_overlay" "$local_overlay"
before "the common removelists come before the product-local overlay" \
    "$common_removelist" "$local_overlay"

# --- a failing unit stops the build ---------------------------------------------
# Without the "|| exit" the loop is one shell line per phase, so a unit that
# fails in the middle of it is swallowed and the layer ships half applied.

export STUB_FAIL='overlay unit\.d/alpha/overlay'
build_fails "a unit overlay that fails stops the build" \
    build/stamps/root.patched
not_called "nothing after a failed unit overlay runs" "$local_overlay"

export STUB_FAIL='script unit\.d/alpha/conf'
build_fails "a unit conf script that fails stops the build" \
    build/stamps/root.patched
not_called "nothing after a failed unit conf script runs" "$local_overlay"

export STUB_FAIL='removelist unit\.d/alpha/removelist'
build_fails "a unit removelist that fails stops the build" \
    build/stamps/root.patched
not_called "nothing after a failed unit removelist runs" "$local_overlay"
unset STUB_FAIL

# --- a layered build applies only the units the parent has not applied ---------

builds "a build with a selected unit succeeds" \
    build/stamps/root.patched UNITS=unit.d/beta
called "a selected unit is applied" "$beta_overlay"
not_called "a unit left out of UNITS is not applied" 'unit\.d/alpha/overlay'
not_called "the conf script of a unit left out of UNITS is not run" \
    'unit\.d/alpha/conf'
not_called "the removelist of a unit left out of UNITS is not applied" \
    'unit\.d/alpha/removelist'
called "the common removelists are applied with a selected unit" \
    "$common_removelist"

builds "a build with no unit selected succeeds" build/stamps/root.patched UNITS=
not_called "an empty UNITS applies no unit overlay" 'unit\.d/[a-z]+/overlay'
not_called "an empty UNITS runs no unit conf script" 'unit\.d/[a-z]+/conf'
called "an empty UNITS still applies the common removelists" \
    "$common_removelist"
called "an empty UNITS still applies the product-local overlay" "$local_overlay"

# --- the plan of every unit is resolved, whatever UNITS says --------------------

builds "root.spec is resolved with every unit" build/stamps/root.spec
called "every unit plan reaches fab-plan-resolve" \
    'fab-plan-resolve plan/main unit\.d/alpha/plan unit\.d/beta/plan unit\.d/gamma/plan '

builds "root.spec is resolved with one unit selected" \
    build/stamps/root.spec UNITS=unit.d/beta
called "the plan of a unit left out of UNITS is still resolved" \
    'fab-plan-resolve plan/main unit\.d/alpha/plan unit\.d/beta/plan unit\.d/gamma/plan '

builds "root.spec is resolved with no unit selected" \
    build/stamps/root.spec UNITS=
called "an empty UNITS still resolves every unit plan" \
    'fab-plan-resolve plan/main unit\.d/alpha/plan unit\.d/beta/plan unit\.d/gamma/plan '

# --- a unit contributes a CONF_VARS entry ---------------------------------------
# _CONF_VARS is settled before any unit is looked at, so a conf-vars file is
# the only way a unit can ask for a build-time variable. mk/turnkey/mysql.mk
# line 1 is "CONF_VARS += MYSQL_PASS"; this is that line, in unit form.

printf '# the database password\nMYSQL_PASS\n\n' \
    > "$product/unit.d/alpha/conf-vars"
printf 'BETA_ONE\nBETA_TWO\n' > "$product/unit.d/beta/conf-vars"

is "a variable a unit names but nobody sets is left out" \
    "$(make_var UNIT_CONF_VARS)" "MYSQL_PASS BETA_ONE BETA_TWO"
is "an unset unit variable stays out of the chroot environment" \
    "$(make_var FAB_CHROOT_ENV | grep -c MYSQL_PASS)" "0"

export MYSQL_PASS=secret BETA_TWO=2
is "a unit variable that is set reaches the chroot environment" \
    "$(make_var FAB_CHROOT_ENV | tr : '\n' | grep -cE '^(MYSQL_PASS|BETA_TWO)$')" "2"
is "the unit variable nobody set is still left out" \
    "$(make_var FAB_CHROOT_ENV | tr : '\n' | grep -c '^BETA_ONE$')" "0"
is "a unit variable does not change with UNITS" \
    "$(cd "$product" && "$share/load_env" 2>/dev/null; make debug V=FAB_CHROOT_ENV UNITS= 2>&1 >/dev/null \
        | sed -n 's|^.*: FAB_CHROOT_ENV = ||p' | head -n 1 | tr : '\n' | grep -cE '^(MYSQL_PASS|BETA_TWO)$')" "2"

builds "a build with unit variables succeeds" build/stamps/root.patched
called "the unit conf script still runs" "$alpha_conf"
unset MYSQL_PASS BETA_TWO

printf 'MYSQL-PASS\n' > "$product/unit.d/gamma/conf-vars"
if build build/stamps/root.patched; then
    not_ok "a conf-vars entry that is not a variable name stops make" \
        "make returned 0"
else
    ok "a conf-vars entry that is not a variable name stops make"
fi
if grep -q 'not a variable name in .*unit\.d/gamma/conf-vars: MYSQL-PASS' "$work/make.out"; then
    ok "the error names the offending file and entry"
else
    not_ok "the error names the offending file and entry" "$(cat "$work/make.out")"
fi
rm "$product/unit.d/gamma/conf-vars" "$product/unit.d/alpha/conf-vars" \
    "$product/unit.d/beta/conf-vars"
is "no conf-vars file means no unit variable" "$(make_var UNIT_CONF_VARS)" ""

# --- a product without units ----------------------------------------------------

rm -rf "$product/unit.d"
is "UNITS is empty without a unit.d" "$(make_var UNITS)" ""
builds "a product without unit.d builds" build/stamps/root.patched
not_called "a product without unit.d applies no unit" 'unit\.d'
called "a product without unit.d applies the common overlays" "$common_overlay"
called "a product without unit.d applies the common removelists" \
    "$common_removelist"

echo "1..$count"
exit "$failed"
