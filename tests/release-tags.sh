#!/bin/bash
# Test for bin/check-release-tags: the rule that every version this
# repository has released is reachable from a git tag.
#
# Why the rule exists. A layer manifest records the builder as a version
# string and nothing else: core.manifest on the mirror carries
# "fab_version 1.1.1+keel1". On 2026-09-27 a package was built at 17:14 from
# a commit that reached the default branch at 19:58 and was never tagged, so
# for three hours the machine that builds every layer ran a version that no
# clone of this repository could name a commit for. A version string is only
# provenance if it maps to a commit, and a tag is what makes that map total.
#
# The script is driven here against git repositories built in a scratch
# directory, so the checks do not depend on the tags of this repository.
# Output is TAP; the exit status is the number of failed checks.
#
#   tests/release-tags.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
script="$root/bin/check-release-tags"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# shellcheck source=tests/tap.sh
. "$here/tap.sh"

# --- fixtures -----------------------------------------------------------------

# fixture NAME: a fresh repository at $work/NAME, printed
fixture() {
    local dir="$work/$1"
    mkdir -p "$dir/debian"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email tests@example.invalid
    git -C "$dir" config user.name Tests
    printf '%s\n' "$dir"
}

# release DIR SOURCE VERSION [DISTRIBUTION]: prepend a changelog entry and
# commit it
release() {
    local dir=$1 source=$2 version=$3 dist=${4:-trixie} old=""
    [[ -f "$dir/debian/changelog" ]] && old="$(cat "$dir/debian/changelog")"
    {
        printf '%s (%s) %s; urgency=low\n\n  * a change\n\n' \
            "$source" "$version" "$dist"
        printf ' -- Tests <tests@example.invalid>  Mon, 01 Jan 2029 00:00:00 +0000\n'
        [[ -n "$old" ]] && printf '\n%s\n' "$old"
    } > "$dir/debian/changelog"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "$source $version"
}

# tag DIR NAME: tag the current commit
tag() {
    git -C "$1" tag "$2"
}

# run DIR...: run the script, leaving stdout and stderr in $out and the
# exit status in $status
run() {
    out="$("$script" "$@" 2>&1)"
    status=$?
}

# --- every released version is tagged -----------------------------------------

repo="$(fixture tagged)"
release "$repo" keel-fab 0.1.0
tag "$repo" keel-fab/0.1.0
release "$repo" keel-fab 0.2.0
tag "$repo" keel-fab/0.2.0
release "$repo" keel-fab 0.3.0

run "$repo"
is "a repository whose releases are all tagged passes" "$status" "0"
if grep -q 'keel-fab/0.1.0' <<<"$out" && grep -q 'keel-fab/0.2.0' <<<"$out"; then
    ok "it names every tag it verified"
else
    not_ok "it names every tag it verified" "$out"
fi
if grep -q '0.3.0' <<<"$out"; then
    ok "it says the top entry is the one being proposed"
else
    not_ok "it says the top entry is the one being proposed" "$out"
fi

# --- a released version with no tag -------------------------------------------

repo="$(fixture untagged)"
release "$repo" keel-fab 0.1.0
release "$repo" keel-fab 0.2.0

run "$repo"
is "a released version with no tag fails" "$status" "1"
if grep -q 'keel-fab/0.1.0' <<<"$out"; then
    ok "the failure names the tag that is missing"
else
    not_ok "the failure names the tag that is missing" "$out"
fi

# --- a tag that does not carry the version it names ---------------------------

repo="$(fixture mistagged)"
release "$repo" keel-fab 0.1.0
release "$repo" keel-fab 0.2.0
tag "$repo" keel-fab/0.2.0
tag "$repo" keel-fab/0.1.0   # also on the 0.2.0 commit, which is the mistake
release "$repo" keel-fab 0.3.0

run "$repo"
is "a tag on the wrong commit fails" "$status" "1"
if grep -q '0.2.0' <<<"$out"; then
    ok "the failure says which version the tag actually carries"
else
    not_ok "the failure says which version the tag actually carries" "$out"
fi

# --- entries that are not releases --------------------------------------------

repo="$(fixture unreleased)"
release "$repo" keel-fab 0.1.0 UNRELEASED
release "$repo" keel-fab 0.2.0
release "$repo" keel-fab 0.3.0

run "$repo"
is "a released entry below the top is still required to be tagged" \
    "$status" "1"
if grep -q 'keel-fab/0.2.0' <<<"$out" && ! grep -q 'keel-fab/0.1.0' <<<"$out"; then
    ok "only the released entry below the top is required to have a tag"
else
    not_ok "only the released entry below the top is required to have a tag" \
        "$out"
fi

# --- an older source name is checked under that name --------------------------

# This repository's changelog carries fab (1.1.1+keel1) and fab
# (1.1.1+keel2) below the first keel-fab entry. Those versions were built
# and installed, so they are releases and the rule covers them; the tag they
# need is fab/1.1.1+keel1, not keel-fab/1.1.1+keel1.
repo="$(fixture renamed)"
release "$repo" fab 1.1.1+keel1
tag "$repo" fab/1.1.1+keel1
release "$repo" fab 1.1.1+keel2
tag "$repo" fab/1.1.1+keel2
release "$repo" keel-fab 0.1.0

run "$repo"
is "a rename does not orphan the versions released before it" "$status" "0"
if grep -q 'fab/1.1.1+keel2' <<<"$out"; then
    ok "a version released under the old source name is checked under it"
else
    not_ok "a version released under the old source name is checked under it" \
        "$out"
fi

# --- unusable input -----------------------------------------------------------

repo="$(fixture nochangelog)"
git -C "$repo" commit -q --allow-empty -m empty
run "$repo"
is "a repository with no debian/changelog is an error" "$status" "2"

mkdir -p "$work/notgit"
run "$work/notgit"
is "a directory that is not a git repository is an error" "$status" "2"

repo="$(fixture emptychangelog)"
: > "$repo/debian/changelog"
git -C "$repo" add -A
git -C "$repo" commit -qm empty
run "$repo"
is "a changelog with no entries is an error" "$status" "2"

# --- the default argument -----------------------------------------------------

repo="$(fixture default)"
release "$repo" keel-fab 0.1.0
( cd "$repo" && "$script" >/dev/null 2>&1 )
is "with no argument it reads the current directory" "$?" "0"

echo "1..$count"
exit "$failed"
