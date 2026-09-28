#!/bin/bash
# Packaging test: the package this repository builds is the Keel one, it
# takes over from the TurnKey one cleanly, and the rename changes nothing a
# caller can see.
#
# The second half is the point. Roughly 380 call sites across this
# organization name fab-chroot, fab-apply-overlay, FAB_PATH or
# /usr/share/fab, in buildtasks, in the shared makefiles and in every recipe
# Makefile. None of them reads the Debian package name, so the rename is
# invisible to all of them, provided the package still ships the same paths.
# debhelper keys .install, .links and .docs on the binary package name, so a
# rename that forgets to move those files produces a package containing no
# /usr/bin/fab* and no /usr/share/fab, and the first fab-chroot of the next
# build fails. Every shipped path is asserted here for that reason.
#
# Nothing is built and nothing is installed: the checks read debian/, the
# entry point and pyproject.toml, and drive fablib/version.py in a scratch
# directory. Output is TAP; the exit status is the number of failed checks.
#
#   tests/packaging.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# shellcheck source=tests/tap.sh
. "$here/tap.sh"

control="$root/debian/control"
changelog="$root/debian/changelog"

# field FILE NAME: the value of a debian control field, first occurrence.
field() {
    awk -v name="$2:" '$1 == name { $1 = ""; sub(/^ /, ""); print; exit }' "$1"
}

# binary_field NAME: a field of the binary package stanza, which is the one
# after the blank line that ends the source stanza.
binary_field() {
    awk -v name="$1:" '
        /^$/ { binary = 1 }
        binary && $1 == name { $1 = ""; sub(/^ /, ""); print; exit }
    ' "$control"
}

# --- the package is ours ------------------------------------------------------

is "the source package is keel-fab" "$(field "$control" Source)" "keel-fab"
is "the binary package is keel-fab" "$(binary_field Package)" "keel-fab"

top="$(head -1 "$changelog")"
is "the changelog names the same source" "${top%% *}" "keel-fab"

version="$(sed -nE '1s/^[^ ]+ \(([^)]+)\).*/\1/p' "$changelog")"
if [[ "$version" == *+keel* ]]; then
    not_ok "the version is ours, not upstream's with a suffix" \
        "the top changelog version is $version; a package this project owns
carries a version this project chose, with no +keelN suffix on somebody
else's version string"
else
    ok "the version is ours, not upstream's with a suffix"
fi

if [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    ok "the version is a plain Debian version"
else
    not_ok "the version is a plain Debian version" "got: $version"
fi

maintainer="$(field "$control" Maintainer)"
if [[ "$maintainer" == *turnkeylinux.org* ]]; then
    not_ok "the maintainer is this project" \
        "a package this project builds and publishes cannot list another
project's maintainer as the person to report its bugs to; got: $maintainer"
else
    ok "the maintainer is this project"
fi

# --- it takes over from the TurnKey package, and the two never coexist --------

for relation in Provides Conflicts Replaces; do
    value="$(binary_field "$relation")"
    if [[ ",${value// /}," == *,fab,* ]]; then
        ok "the package declares $relation on fab"
    else
        not_ok "the package declares $relation on fab" "got: ${value:-<absent>}"
    fi
done

# --- the shipped surface is unchanged -----------------------------------------

for helper in install links docs; do
    if [[ -f "$root/debian/keel-fab.$helper" ]]; then
        ok "debian/keel-fab.$helper is named for the binary package"
    else
        not_ok "debian/keel-fab.$helper is named for the binary package" \
            "debhelper keys this file on the binary package name; without it
dh_$helper does nothing and the package ships no $helper"
    fi
done

stale="$(find "$root/debian" -maxdepth 1 -name 'fab.*' -printf '%f\n')"
is "no debhelper file is left under the old package name" "$stale" ""

install_file="$root/debian/keel-fab.install"
if grep -qE '^share/\*[[:space:]]+usr/share/fab$' "$install_file" 2>/dev/null; then
    ok "share/ is still installed into /usr/share/fab"
else
    not_ok "share/ is still installed into /usr/share/fab" \
        "$(cat "$install_file" 2>/dev/null)"
fi

if grep -qE '^contrib/fab-\*[[:space:]]+usr/bin$' "$install_file" 2>/dev/null; then
    ok "the contrib commands are still installed into /usr/bin"
else
    not_ok "the contrib commands are still installed into /usr/bin" \
        "$(cat "$install_file" 2>/dev/null)"
fi

# The nine names the dispatcher answers to. product.mk and the shared
# makefiles call them unqualified on PATH; losing one is losing a build
# phase.
links_file="$root/debian/keel-fab.links"
for command in fab-query fab-cpp fab-chroot fab-install fab-plan-annotate \
        fab-plan-resolve fab-apply-overlay fab-apply-patch \
        fab-apply-removelist; do
    if grep -qE "^/usr/bin/fab[[:space:]]+/usr/bin/$command\$" "$links_file" \
            2>/dev/null; then
        ok "/usr/bin/$command still links to /usr/bin/fab"
    else
        not_ok "/usr/bin/$command still links to /usr/bin/fab" \
            "$(cat "$links_file" 2>/dev/null)"
    fi
done

strays="$(grep -cvE '^/usr/bin/fab[[:space:]]+/usr/bin/fab-' "$links_file" \
    2>/dev/null)"
is "every declared link is a /usr/bin/fab-* alias of /usr/bin/fab" \
    "$strays" "0"

if grep -qE '^script-files = \["fab"\]$' "$root/pyproject.toml"; then
    ok "the dispatcher is still installed as /usr/bin/fab"
else
    not_ok "the dispatcher is still installed as /usr/bin/fab" \
        "$(grep script-files "$root/pyproject.toml")"
fi

# --- the version it reports is the version it was built as --------------------

# It used to run "apt-cache policy fab". That answers a question about
# whatever package is called fab on this machine, which after the rename is
# either nothing or, if Provides is read, "(none)". bt-layer writes the
# answer into every layer manifest as fab_version, so a wrong answer there
# is a wrong provenance record on every image built afterwards.
if grep -q 'apt-cache' "$root/fab"; then
    not_ok "the entry point does not ask apt for its own version" \
        "$(grep -n 'apt-cache' "$root/fab")"
else
    ok "the entry point does not ask apt for its own version"
fi

if grep -qE 'dpkg-query|dpkg -s' "$root/fab"; then
    not_ok "the entry point does not name a Debian package to find its version" \
        "$(grep -nE 'dpkg-query|dpkg -s' "$root/fab")"
else
    ok "the entry point does not name a Debian package to find its version"
fi

rules="$root/debian/rules"
if grep -q 'dpkg-parsechangelog' "$rules" \
        && grep -q 'usr/share/fab/version' "$rules"; then
    ok "the build records the changelog version in the package"
else
    not_ok "the build records the changelog version in the package" \
        "$(cat "$rules")"
fi

# dh_python3 finds a private directory by the binary package name, so it
# picked up /usr/share/fab on its own while the package was called fab.
# Measured by building both: without the directory named explicitly, the
# keel-fab package loses the byte-compilation registration in
# /usr/share/python3/runtime.d and the shebang rewrite of the two scripts
# under /usr/share/fab, and so differs from the package it replaces for a
# reason nobody chose.
if grep -q 'dh_python3 /usr/share/fab' "$rules"; then
    ok "the build still treats /usr/share/fab as a private python directory"
else
    not_ok "the build still treats /usr/share/fab as a private python directory" \
        "$(cat "$rules")"
fi

# fablib/version.py is what reads it back. It imports os and pathlib only,
# so it can be driven here without the chroot and python3-debian modules the
# entry point needs.
recorded() {
    FAB_SHARE_PATH="$1" python3 -c \
        'from fablib.version import package_version; print(package_version())' \
        2>&1
}

mkdir -p "$work/share" "$work/empty"
cd "$root" || exit 3

echo "0.1.0" > "$work/share/version"
is "the recorded version is what fab reports" "$(recorded "$work/share")" "0.1.0"

printf '  2.3.4  \n' > "$work/share/version"
is "surrounding whitespace is not part of the version" \
    "$(recorded "$work/share")" "2.3.4"

is "an absent version file reports unknown, not a wrong answer" \
    "$(recorded "$work/empty")" "unknown"

: > "$work/share/version"
is "an empty version file reports unknown" "$(recorded "$work/share")" "unknown"

is "the default share path is the packaged one" \
    "$(env -u FAB_SHARE_PATH python3 -c \
        'from fablib.version import share_path; print(share_path())')" \
    "/usr/share/fab"

echo "1..$count"
exit "$failed"
