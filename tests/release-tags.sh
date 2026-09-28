#!/bin/bash
# Test for bin/check-release-tags: the rule that every version this
# repository has released is reachable from a git tag.
#
# Why the rule exists. A layer manifest records the builder as a version
# string and nothing else: core.manifest on the mirror carries
# "fab_version 1.1.1+keel1". On 2026-09-27 a package was built at 17:14:56
# UTC from a commit that reached the default branch at 19:58:53 UTC, two
# hours and forty four minutes later, and was never tagged at all. A version
# string is provenance only if it maps to a commit, and a tag is what makes
# that map total.
#
# The rule has to be as strong as the reverse direction it promises. That
# direction is "git describe --match '*/*'", which refuses a lightweight tag
# outright, so a lightweight tag must not satisfy the forward direction
# either; and a tag on a commit that is not in the branch names nothing.
# Both are checked here, as are the exemption for the entry a pull request
# is proposing and the fact that --require-newest revokes it.
#
# The script is driven against git repositories built in a scratch
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

# tag DIR NAME: an annotated tag on the current commit, the only kind the
# rule accepts
tag() {
    git -C "$1" tag -a -m "release $2" "$2"
}

# lightweight_tag DIR NAME
lightweight_tag() {
    git -C "$1" tag "$2"
}

# run ARG...: run the script, leaving its output in $out and its exit status
# in $status
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

# --- the exemption for the proposed release, and revoking it ------------------

# On a pull request the newest entry cannot be tagged, because the commit it
# will be tagged on does not exist yet. On the default branch it can, and
# must: a merged and built but untagged release is the state issue #7 was
# filed about, one version further on.
run --require-newest "$repo"
is "--require-newest refuses an untagged newest release" "$status" "1"
if grep -q 'keel-fab/0.3.0' <<<"$out"; then
    ok "it names the newest release as the one missing a tag"
else
    not_ok "it names the newest release as the one missing a tag" "$out"
fi

tag "$repo" keel-fab/0.3.0
run --require-newest "$repo"
is "--require-newest passes once the newest release is tagged" "$status" "0"

# An UNRELEASED entry on top must not confer the exemption on the release
# below it, or the newest real release stays exempt for as long as somebody
# leaves a work in progress entry at the top of the file.
repo="$(fixture unreleased_top)"
release "$repo" keel-fab 0.1.0
tag "$repo" keel-fab/0.1.0
release "$repo" keel-fab 0.2.0
release "$repo" keel-fab 0.3.0 UNRELEASED

run "$repo"
is "an UNRELEASED entry on top does not exempt the release below it" \
    "$status" "1"
if grep -q 'keel-fab/0.2.0' <<<"$out" && ! grep -q 'keel-fab/0.3.0' <<<"$out"; then
    ok "the UNRELEASED entry is not itself required to be tagged"
else
    not_ok "the UNRELEASED entry is not itself required to be tagged" "$out"
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

# --- a lightweight tag is not a release ---------------------------------------

# The reverse direction this rule promises is "git describe --match '*/*'",
# and git describe refuses a lightweight tag: "No annotated tags can
# describe". A forward direction that accepts one is weaker than the reverse
# direction it is paired with, so it does not.
repo="$(fixture lightweight)"
release "$repo" keel-fab 0.1.0
lightweight_tag "$repo" keel-fab/0.1.0
release "$repo" keel-fab 0.2.0

run "$repo"
is "a lightweight tag does not satisfy the rule" "$status" "1"
if grep -qi 'annotated' <<<"$out"; then
    ok "the failure says the tag has to be annotated"
else
    not_ok "the failure says the tag has to be annotated" "$out"
fi

# --- a tag that is not in this branch -----------------------------------------

repo="$(fixture unreachable)"
release "$repo" keel-fab 0.1.0
release "$repo" keel-fab 0.2.0
# An orphan branch with entirely different content, tagged as if it were the
# 0.1.0 release. Its changelog says 0.1.0, so only reachability catches it.
git -C "$repo" checkout -q --orphan elsewhere
git -C "$repo" rm -q -rf . >/dev/null 2>&1
mkdir -p "$repo/debian"
{
    printf 'keel-fab (0.1.0) trixie; urgency=low\n\n  * not the same code\n\n'
    printf ' -- Tests <tests@example.invalid>  Mon, 01 Jan 2029 00:00:00 +0000\n'
} > "$repo/debian/changelog"
git -C "$repo" add -A
git -C "$repo" commit -qm orphan
tag "$repo" keel-fab/0.1.0
git -C "$repo" checkout -q main

run "$repo"
is "a tag that is not an ancestor of HEAD does not satisfy the rule" \
    "$status" "1"
if grep -qi 'not in this branch' <<<"$out"; then
    ok "the failure says the tag is not in this branch"
else
    not_ok "the failure says the tag is not in this branch" "$out"
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
release "$repo" keel-fab 2.0.0

run "$repo"
is "a rename does not orphan the versions released before it" "$status" "0"
if grep -q 'fab/1.1.1+keel2' <<<"$out"; then
    ok "a version released under the old source name is checked under it"
else
    not_ok "a version released under the old source name is checked under it" \
        "$out"
fi

# --- the floor ----------------------------------------------------------------

# A fork's changelog carries the upstream entries it was forked from, and
# upstream tags those its own way: fab's are v1.1.0 and v1.0.3, not
# fab/1.1.0. Without a floor the rule would demand a tag for every version
# anybody ever released, and a merge from upstream that brought real entries
# into the file would break the build.
repo="$(fixture floor)"
release "$repo" fab 1.0.3
release "$repo" fab 1.1.0
release "$repo" keel-fab 2.0.0
tag "$repo" keel-fab/2.0.0
release "$repo" keel-fab 2.1.0

run --since 2.0.0 "$repo"
is "entries below the floor are not required to be tagged" "$status" "0"
if ! grep -q '1\.1\.0' <<<"$out"; then
    ok "an entry below the floor is not mentioned at all"
else
    not_ok "an entry below the floor is not mentioned at all" "$out"
fi

run "$repo"
is "without a floor every entry below the newest is a release" "$status" "1"

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

repo="$(fixture allunreleased)"
release "$repo" keel-fab 0.1.0 UNRELEASED
run "$repo"
is "a changelog with no released entry is an error" "$status" "2"

run --nonsense "$repo"
is "an unknown option is an error" "$status" "2"

# --- the default argument -----------------------------------------------------

repo="$(fixture default)"
release "$repo" keel-fab 0.1.0
( cd "$repo" && "$script" >/dev/null 2>&1 )
is "with no argument it reads the current directory" "$?" "0"

echo "1..$count"
exit "$failed"
