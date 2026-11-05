#!/usr/bin/env bash
# Tier 1 of this repository: the lints, then every tests/test_*.sh (each in its own scratch sandbox, all in parallel). Run from anywhere.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd); out=$(mktemp -d "${TMPDIR:-/tmp}/vbm-land-run.XXXXXX"); trap 'rm -rf "$out"' EXIT
"$here/lint.sh"
pids=(); names=()
for t in "$here"/test_*.sh; do
  n=$(basename "$t"); names+=("$n")
  timeout --kill-after=10 300 "$t" >"$out/$n.log" 2>&1 & pids+=($!)
done
fails=0
for i in "${!pids[@]}"; do
  if wait "${pids[$i]}"; then echo "ok    ${names[$i]}: $(tail -n1 "$out/${names[$i]}.log")"
  else fails=$((fails + 1)); echo "FAILED ${names[$i]}" >&2; grep -v '^ok ' "$out/${names[$i]}.log" | tail -60 >&2; fi
done
[ "$fails" = 0 ] || { echo "tests/run.sh: $fails test script(s) failed" >&2; exit 1; }
echo "tests/run.sh: all test scripts passed"
