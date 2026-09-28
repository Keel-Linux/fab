# Test coverage baseline

Measured on 2026-09-24 against upstream master (d7a314d), following the
project decision 0003 (90 percent floor per repository, 95 percent for every
file our changes touch).

## Measured baseline on the default branch: 100 percent (2026-09-26)

Pull request #1 merged on 2026-09-26 (merge commit e79be43) and brought
`tests/coverage.sh` with it: 19 of 19 checks of tests/source-date-epoch.sh on share/product.mk, 100 percent (make has no line tool). The gate in
`.github/workflows/tests.yml` is set to 100, the measured number rounded
down, and is only ever raised. The sections that follow record the state
before the merge.

## 2026-09-27: the unit loop and where it runs

`tests/coverage.sh` now runs two suites and counts the checks of both:

| Suite | Checks | What it measures |
|-------|--------|------------------|
| tests/source-date-epoch.sh | 19 of 19 | the `SOURCE_DATE_EPOCH` handling |
| tests/units.sh | 56 of 56 | the unit loop, `UNITS`, the position of the units in `root.patched`, the per-unit removelist and `UNIT_CONF_VARS` |

Total 75 of 75, 100 percent. The gate stays at 100.

`tests/units.sh` does not dry run. It builds a fake product with three
units against this checkout's `product.mk` with the four fab tools replaced
by stubs that log their arguments, and asserts on the log: what was
applied, in which order, and what a failing tool does. That is why it can
tell that a unit whose `conf` is not executable is skipped, which a
`make -n` of the same recipe cannot, since the `[ -x ]` guard is resolved
by the shell and not by make.

## 2026-09-28: the package, and the tag that resolves a manifest

`tests/coverage.sh` now runs four suites:

| Suite | Checks | What it measures |
|-------|--------|------------------|
| tests/source-date-epoch.sh | 19 of 19 | the `SOURCE_DATE_EPOCH` handling |
| tests/units.sh | 56 of 56 | the unit loop, `UNITS`, the position of the units in `root.patched`, the per-unit removelist and `UNIT_CONF_VARS` |
| tests/packaging.sh | 35 of 35 | the package identity and relationships, every path the package ships, and `fablib/version.py` |
| tests/release-tags.sh | 15 of 15 | `bin/check-release-tags`: each verdict and each exit code |

Total 125 of 125, 100 percent. The gate stays at 100.

`tests/packaging.sh` exists for one reason. Roughly 380 call sites across
this organization name `fab-chroot`, `fab-apply-overlay`, `FAB_PATH` or
`/usr/share/fab`, and none of them reads the Debian package name, so
renaming the package to `keel-fab` is invisible to all of them, provided
the package still ships the same paths. debhelper keys `.install`, `.links`
and `.docs` on the binary package name, so a rename that forgets to move
those three files builds a package with no `/usr/bin/fab*` and no
`/usr/share/fab` at all, and the failure appears at the first `fab-chroot`
of the next build rather than at packaging time. Each of the nine
`/usr/bin/fab-*` aliases is therefore one check of its own, and so is each
line of the install file.

The five branches of `fablib/version.py` (absent file, empty file,
whitespace, a value, and the default and overridden share path) are driven
directly rather than through the `fab` entry point, which imports `chroot`
and `python3-debian` and so cannot run on the coverage runner.

What the suite cannot assert is that the built package is the same package,
so that was measured instead, by building both in a `debian:trixie`
container and comparing. `keel-fab 0.1.0` against the `fab 1.1.1+keel2`
installed on the build host: the same 26 paths, 24 of them byte identical,
`/usr/bin/fab` differing only by the `get_version` change and
`runtime.d/*.rtupdate` only by the package name inside it, plus the two new
files `fablib/version.py` and `/usr/share/fab/version`. All nine
`/usr/bin/fab-*` symlinks and `share/product.mk` are byte identical. The
two `debian/rules` overrides were each measured on their own and together,
which is how the `dh_python3` interaction below was found.

`tests/release-tags.sh` builds throwaway git repositories under `mktemp -d`
and runs the script against them, so the suite does not depend on the tags
of this repository: a tagged history, a missing tag, a tag on the wrong
commit, an `UNRELEASED` entry, a source rename, and the three unusable
inputs each get a check.

The TAP helpers moved to `tests/tap.sh` when the third suite wanted them.
The handbook records copying a test library instead of sharing it as
something this project did wrong and would do again unless it was written
down.

## Baseline before the merge: 0 percent, nothing measured

`tests/` holds `regtest.sh` (77 lines), `override.sh`, `parseopts.py` and
`ptyfork.py`: a regression harness that expects a fab checkout at a hard
coded path (`/turnkey/projects/fab/fab`), a network and root. It is not a
unit suite, is not run by any tool here, and has no assertions we can
count. No `pytest` or `unittest` suite exists and no coverage tool is wired
up, so nothing is measured. Line counts are lines neither blank nor
comment; `.mk` files are counted the same way.

Inventory command (shebang or extension decides the kind):

    find . -type f -not -path './.git/*' -not -path './debian/*' \
      | while read f; do h=$(head -1 "$f"); case "$f$h" in *.py*|*python*) k=py;; \
      *sh*) k=sh;; *.mk) k=mk;; *) continue;; esac; echo "$k $(grep -cvE '^\s*(#|$)' "$f") $f"; done

| Group | Files | Lines | Measured |
|-------|-------|-------|----------|
| fab (command line entry point) | 1 | 679 | 0 percent, no test |
| fablib/*.py (plan 314, installer 285, resolve 68, annotate 64, removelist 49, cpp 26, common 14, help 14, __init__ 0) | 9 | 834 | 0 percent, no test |
| share/product.mk | 1 | 449 | 0 percent, no test |
| share/ other (initctl.dummy 118 sh, load_env 83 sh, make-release-deb.py 95, turnkey-version.py 74) | 4 | 370 | 0 percent, no test |
| contrib/ (iso2usb.py 120, fab-rewind 81 sh, cryptpass.py 38, fab-investigate 34 sh) | 4 | 273 | 0 percent, no test |
| tests/ harness (regtest.sh 77, ptyfork.py 24, parseopts.py 8, override.sh 5) | 4 | 114 | harness, excluded |

Total: 16 Python files (1872 lines), 6 shell files (398 lines), 1
Makefile include (449 lines), 0 percent measured.

## Our branches and the 95 percent bar

| Branch | File touched | Automated test |
|--------|--------------|----------------|
| feat/source-date-epoch | share/product.mk | None. `SOURCE_DATE_EPOCH` added to `CONF_VARS_BUILTIN`, `XORRISO_DATE_OPTS` and `ISOHYBRID_OPTS` derived from it and passed to `xorriso` and `isohybrid`: verified by hand by building an image on a VM. 0 percent, below the 95 percent bar. |

## Plan to reach 90 percent per file

Method: Python with `coverage run --branch` and `pytest`, `fail_under`
committed in `pyproject.toml`. Shell with test files under `tests/` and
`bash -x` trace counting (kcov when the decision 0003 open item settles).
Makefile logic is tested by running `make -n` (dry run) against a fixture
product directory with stub `xorriso`, `isohybrid`, `mksquashfs` and
`fab-*` commands on `PATH`, and asserting the expanded command lines; the
counted unit is each `ifeq`/`ifneq` branch and each `define` block. Hosts
in fixtures are IPv6 (`2001:db8::/32`).

Priority order (size: small under 30 lines of test, medium under 150,
large above):

1. `share/product.mk` (medium). Target 95 percent. Tests: with
   `SOURCE_DATE_EPOCH` unset, `xorriso` gets no `--set_all_file_dates` and
   `isohybrid` no `--id`; with it set, both options appear with the epoch
   and the id is the low 32 bits; the variable is exported into the chroot
   through `CONF_VARS_BUILTIN`; every other conditional (`CHROOT_ONLY`,
   `DEBUG`, UEFI versus BIOS `run-genisoimage`, relative `CDROOT`) gets a
   dry run per branch.
2. `fablib/plan.py` 314 (medium) and `fablib/resolve.py` 68 (small): plan
   parsing, includes, cpp defines, unresolved package error paths.
3. `fablib/installer.py` 285 (medium): mock `subprocess` and the chroot;
   every apt failure mode and the `removelist` interaction.
4. `fablib/annotate.py` 64, `removelist.py` 49, `cpp.py` 26, `common.py` 14,
   `help.py` 14 (small each).
5. `fab` 679 (large): one test per subcommand and per exit code, invoked
   in-process; split the subcommand table from the entry point if needed.
6. `share/make-release-deb.py` 95 (medium) and `share/turnkey-version.py`
   74 (small): fixture control files and version strings.
7. `share/load_env` 83 and `share/initctl.dummy` 118 (medium each, shell):
   environment export cases and each dummy verb.
8. `contrib/`: iso2usb.py 120 (medium, mock block device calls), fab-rewind
   81 (medium), cryptpass.py 38 and fab-investigate 34 (small).
9. `tests/regtest.sh` and helpers: keep as the end to end check behind the
   LXC runner, or retire once steps 1 to 8 cover its paths.
