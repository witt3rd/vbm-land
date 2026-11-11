#!/usr/bin/env bash
# The runner (tests/run.sh) fails a test script that exits 0 WITHOUT ran-evidence (`ran: NAME: N cases`, N > 0), with zero cases, or that reports SKIPPED, and passes one that has it.
# The class fix of a vacuous pass: a check that never ran (a refused tool, a skip, an early exit) must not count as a pass.
. "$(dirname "$0")/lib.sh"
sandbox
mkdir -p "$T/r/tests" "$T/r/bin"; cp "$ROOT/tests/run.sh" "$T/r/tests/run.sh"; cp "$ROOT/bin/ran-evidence" "$T/r/bin/ran-evidence"; mkdir -p "$T/r/lib"; cp "$ROOT/lib/reap.sh" "$T/r/lib/reap.sh";   # the runner reads evidence with the payload reader beside it
   printf '#!/usr/bin/env bash\nexit 0\n' > "$T/r/tests/lint.sh"; chmod +x "$T/r/tests/"*.sh
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/r/tests/test_$1.sh"; chmod +x "$T/r/tests/test_$1.sh"; }
run() { rm -f "$T/r/tests/test_"*.sh; for n in "$@"; do mk "$n" "${BODY[$n]}"; done; rc=0; "$T/r/tests/run.sh" >"$T/out" 2>&1 || rc=$?; }
declare -A BODY=( [ok]='echo "ran: ok: 3 cases"' [none]='echo fine' [zero]='echo "ran: zero: 0 cases"' [skip]='echo "x: SKIPPED: no tool"; echo "ran: skip: 1 cases"' [refused]='echo "heavy: run elsewhere" >&2; exit 126' )
run ok; [ "$rc" = 0 ] && pass "the runner passed it (exit $rc)" || fail "the runner refused a script with evidence: $(cat "$T/out")"
out_has "ran: tests: 3 cases"
for n in none zero skip refused; do
  run ok "$n"
  [ "$rc" != 0 ] && pass "the runner fails $n (exit $rc)" || fail "the runner passed $n"
  grep -q "FAILED test_$n.sh" "$T/out" && pass "and names test_$n.sh" || fail "it did not name test_$n.sh: $(cat "$T/out")"
done
finish
