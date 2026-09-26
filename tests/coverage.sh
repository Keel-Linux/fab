#!/bin/bash
# Coverage of the SOURCE_DATE_EPOCH code in share/product.mk.
#
# make has no line coverage tool, so the number here is the share of the
# checks in tests/source-date-epoch.sh that pass: one check per effect of
# the touched code (both arms of the ifneq, both xorriso recipes, isohybrid,
# FAB_CHROOT_ENV, fab-plan-resolve and the untouched mksquashfs options).
# Exits 1 when that share is below the threshold (default 95).
#
#   tests/coverage.sh [THRESHOLD]     (or COVERAGE_THRESHOLD in the environment)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
threshold="${1:-${COVERAGE_THRESHOLD:-95}}"

tap="$("$here/source-date-epoch.sh" || true)"
printf '%s\n' "$tap"
total="$(grep -cE '^(not )?ok [0-9]+ ' <<<"$tap")"
passed="$(grep -cE '^ok [0-9]+ ' <<<"$tap")"
percent="$(awk -v p="$passed" -v t="$total" 'BEGIN { printf "%.2f", (t ? 100 * p / t : 0) }')"

echo "product.mk SOURCE_DATE_EPOCH: $percent percent ($passed of $total checks) covered, threshold $threshold"
if ! awk -v p="$percent" -v t="$threshold" 'BEGIN { exit !(p + 0 >= t + 0) }'; then
    echo "coverage below threshold" >&2
    exit 1
fi
