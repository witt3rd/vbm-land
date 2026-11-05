#!/usr/bin/env bash
# Tier 1 of this repository: the lints, then every tests/test_*.sh (each in its own scratch sandbox, all in parallel). Run from anywhere.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd); out=$(mktemp -d "${TMPDIR:-/tmp}/vbm-land-run.XXXXXX"); reap_pids() { local p; for p in "$@"; do [ "$(ps -o pgid= -p "$p" 2>/dev/null | tr -d ' ')" = "$p" ] && kill -TERM -- "-$p" 2>/dev/null || true; done; }   # (as scripts/lib-reap.sh, inline: the runner tests copy this file alone) an abort or exit stops the test jobs by the pids held in pids[] (each `timeout` job is its own process group); never by pattern
pids=(); trap 'reap_pids "${pids[@]}"; rm -rf "$out"' EXIT; trap 'exit 143' INT TERM HUP
"$here/lint.sh"
names=()
for t in "$here"/test_*.sh; do
  n=$(basename "$t"); names+=("$n")
  timeout --kill-after=10 300 "$t" >"$out/$n.log" 2>&1 & pids+=($!)
done
fails=0
# RAN-EVIDENCE: a test script that exits 0 must also have printed `ran: NAME: N cases` with N > 0 (tests/lib.sh `finish` does) and no SKIPPED line: a script that ran nothing (a refused tool, a skip, an early exit) is a failure
evidence() {   # evidence LOG: 0 only with at least one valid ran line, a positive sum, and no SKIPPED line
  local total; grep -qE '(^|[^A-Za-z])SKIPPED' "$1" && return 1
  total=$(sed -nE 's/^ran: [A-Za-z0-9_.-]+: ([0-9]+) cases$/\1/p' "$1" | awk '{t += $1} END {print t + 0}'); [ "$total" -gt 0 ]
}
cases=0
for i in "${!pids[@]}"; do
  if wait "${pids[$i]}"; then
    if evidence "$out/${names[$i]}.log"; then echo "ok    ${names[$i]}: $(tail -n1 "$out/${names[$i]}.log")"; cases=$((cases + $(sed -nE 's/^ran: [A-Za-z0-9_.-]+: ([0-9]+) cases$/\1/p' "$out/${names[$i]}.log" | awk '{t += $1} END {print t + 0}')))
    else fails=$((fails + 1)); echo "FAILED ${names[$i]}: exit 0 but no ran-evidence (no 'ran: NAME: N cases' line with N > 0, or a SKIPPED line: it may have been refused, skipped or exited before it ran anything)" >&2; tail -20 "$out/${names[$i]}.log" >&2; fi
  else fails=$((fails + 1)); echo "FAILED ${names[$i]}" >&2; grep -v '^ok ' "$out/${names[$i]}.log" | tail -60 >&2; fi
done
[ "$fails" = 0 ] || { echo "tests/run.sh: $fails test script(s) failed" >&2; exit 1; }
echo "tests/run.sh: all test scripts passed"; echo "ran: tests: $cases cases"
