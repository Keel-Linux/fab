#!/bin/bash
# make-level test for SOURCE_DATE_EPOCH in share/product.mk.
#
# Builds a minimal fake product under a scratch FAB_PATH and dry-runs
# (make -n) the product.iso recipe against the product.mk of this checkout,
# once with SOURCE_DATE_EPOCH unset and once with it set. Output is TAP; the
# exit status is the number of failed checks.
#
# product.mk includes /tmp/.build_env, written by share/load_env; the test
# runs load_env from the fake product, so that file is overwritten for the
# duration of the run and restored afterwards. Nothing else outside the
# scratch directory is touched and no fab tool is executed.
#
#   tests/source-date-epoch.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
share="$(cd "$here/.." && pwd)/share"
work="$(mktemp -d)"

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

# --- fake product -----------------------------------------------------------

export FAB_PATH="$work/fab"
export FAB_SHARE_PATH="$share"
export RELEASE=debian/trixie
export FAB_ARCH=amd64
export NO_PROXY=true
unset SOURCE_DATE_EPOCH BOOTSTRAP O ISOLABEL CONF_VARS CHROOT_ONLY

product="$work/fakeprod"
mkdir -p "$FAB_PATH/bootstraps/trixie-amd64" "$FAB_PATH/cdroots/generic" \
    "$product/plan"
: > "$product/plan/main"
printf 'include $(FAB_SHARE_PATH)/product.mk\n' > "$product/Makefile"

# dry_run TARGET [VAR=VALUE ...]: stdout and stderr of make -n in the product
dry_run() {
    (
        cd "$product" || exit 1
        "$share/load_env" 2>/dev/null
        make -n "$@" 2>&1
    )
}

# --- TAP helpers ------------------------------------------------------------

# shellcheck source=tests/tap.sh
. "$here/tap.sh"

# check DESC TEXT REGEX: a line of TEXT matches REGEX
check() {
    if grep -qE -e "$3" <<<"$2"; then
        ok "$1"
    else
        not_ok "$1" "no line matches: $3"
    fi
}

# check_not DESC TEXT REGEX: no line of TEXT matches REGEX
check_not() {
    if grep -qE -e "$3" <<<"$2"; then
        not_ok "$1" "$(grep -E -e "$3" <<<"$2")"
    else
        ok "$1"
    fi
}

mksquashfs_line='^/usr/bin/mksquashfs build/root.patched build/cdroot/live/10root.squashfs -no-sparse$'
plan_resolve_epoch="fab-plan-resolve .* -D 'SOURCE_DATE_EPOCH="

# --- SOURCE_DATE_EPOCH unset --------------------------------------------------

out="$(dry_run product.iso)"
check_not "unset: xorriso gets no --set_all_file_dates" "$out" '--set_all_file_dates'
check "unset: xorriso volume id is followed by nothing" "$out" '^xorriso -as mkisofs -o build/product.iso -r -J -V fakeprod +-b isolinux/isolinux.bin '
check_not "unset: isohybrid gets no --id" "$out" '--id'
check "unset: isohybrid gets the iso only" "$out" '^isohybrid +build/product.iso$'
check "unset: mksquashfs options are unchanged" "$out" "$mksquashfs_line"
check_not "unset: fab-plan-resolve gets no -D SOURCE_DATE_EPOCH" "$out" "$plan_resolve_epoch"

debug="$(dry_run debug V=FAB_CHROOT_ENV)"
check "unset: FAB_CHROOT_ENV holds the other builtins" "$debug" 'product.mk:[0-9]+: FAB_CHROOT_ENV = FAB_ARCH:'
check_not "unset: FAB_CHROOT_ENV has no SOURCE_DATE_EPOCH" "$debug" 'SOURCE_DATE_EPOCH'

out="$(SOURCE_DATE_EPOCH= dry_run product.iso)"
check "empty: isohybrid gets the iso only" "$out" '^isohybrid +build/product.iso$'
check_not "empty: xorriso gets no --set_all_file_dates" "$out" '--set_all_file_dates'

# --- SOURCE_DATE_EPOCH set ----------------------------------------------------

export SOURCE_DATE_EPOCH=1700000000

out="$(dry_run product.iso)"
check "set: xorriso gets --set_all_file_dates @epoch" "$out" \
    '^xorriso -as mkisofs -o build/product.iso -r -J -V fakeprod --set_all_file_dates @1700000000 -b isolinux/isolinux.bin '
check "set: isohybrid gets --id epoch" "$out" '^isohybrid --id 1700000000 build/product.iso$'
check "set: mksquashfs options are unchanged" "$out" "$mksquashfs_line"
check "set: fab-plan-resolve gets -D SOURCE_DATE_EPOCH" "$out" "${plan_resolve_epoch}1700000000'"

debug="$(dry_run debug V=FAB_CHROOT_ENV)"
check "set: FAB_CHROOT_ENV ends with SOURCE_DATE_EPOCH" "$debug" \
    'product.mk:[0-9]+: FAB_CHROOT_ENV = FAB_ARCH:.*:SOURCE_DATE_EPOCH$'

out="$(dry_run product.iso 'product.iso/body=$(run-genisoimage-uefi)')"
check "set: the UEFI xorriso recipe is the one used" "$out" '^xorriso .* -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin .* -e efi.img '
check "set: the UEFI xorriso recipe gets --set_all_file_dates @epoch" "$out" \
    '^xorriso -as mkisofs -o build/product.iso -r -J -V fakeprod --set_all_file_dates @1700000000 -b isolinux/isolinux.bin '

# the MBR id is 32 bits wide: decimal value of epoch & 0xffffffff
out="$(SOURCE_DATE_EPOCH=5000000000 dry_run product.iso)"
check "set: isohybrid id is epoch & 0xffffffff" "$out" '^isohybrid --id 705032704 build/product.iso$'
out="$(SOURCE_DATE_EPOCH=4294967296 dry_run product.iso)"
check "set: isohybrid id wraps to 0 at 2^32" "$out" '^isohybrid --id 0 build/product.iso$'

echo "1..$count"
exit "$failed"
