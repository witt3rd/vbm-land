#!/usr/bin/env bash
# Tier 1 of this repository: every tests/test_*.sh (each in its own scratch sandbox), plus the repo-level lints. Run from anywhere.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd); root=$(dirname "$here"); fails=0
for t in "$here"/test_*.sh; do
  echo "--- $(basename "$t")"
  timeout --kill-after=10 300 "$t" || { echo "FAILED: $(basename "$t")" >&2; fails=$((fails+1)); }
done
[ "$fails" = 0 ] || { echo "tests/run.sh: $fails test script(s) failed" >&2; exit 1; }
echo "tests/run.sh: all test scripts passed"
