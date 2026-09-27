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
| tests/units.sh | 38 of 38 | the unit loop, `UNITS` and the position of the units in `root.patched` |

Total 57 of 57, 100 percent. The gate stays at 100.

`tests/units.sh` does not dry run. It builds a fake product with three
units against this checkout's `product.mk` with the four fab tools replaced
by stubs that log their arguments, and asserts on the log: what was
applied, in which order, and what a failing tool does. That is why it can
tell that a unit whose `conf` is not executable is skipped, which a
`make -n` of the same recipe cannot, since the `[ -x ]` guard is resolved
by the shell and not by make.

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
