#!/usr/bin/env bash
# The runner (tests/run.sh) fails a test script that exits 0 WITHOUT ran-evidence (`ran: NAME: N cases`, N > 0), with zero cases, or that reports SKIPPED, and passes one that has it.
# The class fix of a vacuous pass: a check that never ran (a refused tool, a skip, an early exit) must not count as a pass.
. "$(dirname "$0")/lib.sh"
sandbox
mkdir -p "$T/r/tests" "$T/r/bin"; cp "$ROOT/tests/run.sh" "$T/r/tests/run.sh"; cp "$ROOT/bin/ran-evidence" "$T/r/bin/ran-evidence"; mkdir -p "$T/r/lib"; cp "$ROOT/lib/reap.sh" "$T/r/lib/reap.sh"; cp "$ROOT/bin/run-tests-parallel" "$T/r/bin/";   # the runner reads evidence with the payload reader beside it
   printf '#!/usr/bin/env bash\nexit 0\n' > "$T/r/tests/lint.sh"; chmod +x "$T/r/tests/"*.sh
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/r/tests/test_$1.sh"; chmod +x "$T/r/tests/test_$1.sh"; }
run() { rm -f "$T/r/tests/test_"*.sh; for n in "$@"; do mk "$n" "${BODY[$n]}"; done; rc=0; "$T/r/tests/run.sh" >"$T/out" 2>&1 || rc=$?; }
declare -A BODY=( [ok]='echo "ran: ok: 3 cases"' [none]='echo fine' [zero]='echo "ran: zero: 0 cases"' [skip]='echo "x: SKIPPED: no tool"; echo "ran: skip: 1 cases"' [refused]='echo "heavy: run elsewhere" >&2; exit 126' )
run ok; [ "$rc" = 0 ] && pass "the runner passed it (exit $rc)" || fail "the runner refused a script with evidence: $(cat "$T/out")"
out_has "ran: tests: 3 cases"
for n in none zero skip refused; do
  run ok "$n"
  [ "$rc" != 0 ] && pass "the runner fails $n (exit $rc)" || fail "the runner passed $n"
  grep -q "FAIL .*test_$n.sh" "$T/out" && pass "and names test_$n.sh" || fail "it did not name test_$n.sh: $(cat "$T/out")"
done

echo "## the runner itself (bin/run-tests-parallel): what had no test anywhere"
P=$T/r/bin/run-tests-parallel; cd "$T/r"
ok1() { printf '#!/usr/bin/env bash\necho "ran: %s: 1 cases"\n' "$1" > "$T/r/$1.sh"; }
ok1 a; ok1 b
expect_exit "no scripts given is refused" 1 "$P"; out_has "no scripts given"
expect_exit "a script listed twice is refused" 1 "$P" a.sh a.sh; out_has "listed twice"
expect_exit "a script that does not exist fails and is named" 1 "$P" a.sh nothere.sh; out_has "FAIL nothere.sh: no such script"
printf '#!/usr/bin/env bash\nsleep 30\necho "ran: hang: 1 cases"\n' > hang.sh
expect_exit "TEST_TIMEOUT kills a script that hangs, and it is a failure that says so" 1 env TEST_TIMEOUT=1 "$P" a.sh hang.sh; out_has "exit 124"; out_has "TEST_TIMEOUT=1"
printf '#!/usr/bin/env bash\nsleep 2\necho "ran: slow: 1 cases"\n' > slow.sh
expect_exit "with no TEST_TIMEOUT there is no limit (a slow script passes)" 0 "$P" slow.sh
printf '#!/usr/bin/env bash\necho start >> "$SER"; sleep 1; echo end >> "$SER"; echo "ran: %s: 1 cases"\n' s1 > s1.sh; sed 's/s1/s2/g' s1.sh > s2.sh
: > "$T/ser"; expect_exit "TEST_JOBS=1 runs one at a time (start end start end)" 0 env SER="$T/ser" TEST_JOBS=1 "$P" s1.sh s2.sh; check "  in that order" test "$(tr '\n' ' ' < "$T/ser")" = "start end start end "
: > "$T/ser"; expect_exit "the default runs them together (start start end end)" 0 env SER="$T/ser" TEST_JOBS=2 "$P" s1.sh s2.sh; check "  in that order" test "$(tr '\n' ' ' < "$T/ser")" = "start start end end "
expect_exit "a nearly full temp directory is refused, and says it is the environment" 1 env MIN_TMP_KIB=999999999999 "$P" a.sh; out_has "the ENVIRONMENT is the failure"
expect_exit "the batch prints its own evidence line" 0 "$P" a.sh b.sh; out_has "ran: tests: 2 cases"
finish
