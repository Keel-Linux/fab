#!/bin/bash
# Coverage of the project-authored code in share/product.mk:
#   tests/source-date-epoch.sh   the SOURCE_DATE_EPOCH handling
#   tests/units.sh               the unit loop and UNITS
#
# make has no line coverage tool, so the number here is the share of the
# checks in those scripts that pass: one check per effect of the touched
# code (both arms of the ifneq, both xorriso recipes, isohybrid,
# FAB_CHROOT_ENV, fab-plan-resolve and the untouched mksquashfs options for
# the first; each unit input, each position in root.patched, each value of
# UNITS and each failure path for the second).
# Exits 1 when that share is below the threshold (default 95).
#
#   tests/coverage.sh [THRESHOLD]     (or COVERAGE_THRESHOLD in the environment)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
threshold="${1:-${COVERAGE_THRESHOLD:-95}}"

suites=(source-date-epoch units)

total=0
passed=0
for suite in "${suites[@]}"; do
    echo "# $suite"
    tap="$("$here/$suite.sh" || true)"
    printf '%s\n' "$tap"
    total=$((total + $(grep -cE '^(not )?ok [0-9]+ ' <<<"$tap")))
    passed=$((passed + $(grep -cE '^ok [0-9]+ ' <<<"$tap")))
done

percent="$(awk -v p="$passed" -v t="$total" 'BEGIN { printf "%.2f", (t ? 100 * p / t : 0) }')"

echo "product.mk: $percent percent ($passed of $total checks) covered, threshold $threshold"
if ! awk -v p="$percent" -v t="$threshold" 'BEGIN { exit !(p + 0 >= t + 0) }'; then
    echo "coverage below threshold" >&2
    exit 1
fi
