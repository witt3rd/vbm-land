#!/usr/bin/env bash
# The ran-evidence pair that the payload ships (docs/ran-evidence.md): bin/ran-evidence (the reader) and lib/ran.sh (ran_case, ran_done, must_fail). The class fix: a check that never ran must not pass, so
# every shape of "it did not run" is shown to FAIL (a refused tool, a missing one, a timeout, a silent exit 0, a zero count, a SKIPPED line, a malformed line) and each has a control that passes.
. "$(dirname "$0")/lib.sh"
sandbox
ev=$ROOT/bin/ran-evidence; lib=$ROOT/lib/ran.sh
log() { printf '%b' "$2" > "$T/$1.log"; }

echo "## the reader: ran-evidence check NAME LOG"
log good 'hello\nran: x: 7 cases\n';              expect_exit "a log with evidence passes" 0 "$ev" check good "$T/good.log"
log none 'hello\nok\n';                           expect_exit "a log with no ran line fails" 1 "$ev" check none "$T/none.log"; out_has "no 'ran: NAME: N cases' line"
log zero 'ran: x: 0 cases\n';                     expect_exit "zero executed cases fails" 1 "$ev" check zero "$T/zero.log"; out_has "zero executed cases"
log skip 'x: SKIPPED: sometool was not found\nran: x: 3 cases\n'; expect_exit "a skip-marker line fails even beside evidence" 1 "$ev" check skip "$T/skip.log"; out_has "reports SKIP.ED"
log skipall 'x: SKIPPED: sometool was not found\n'; expect_exit "a wholly skipped script fails" 1 "$ev" check skipall "$T/skipall.log"
expect_exit "VBM_ALLOW_SKIP=1 allows a wholly skipped script, loudly" 0 env VBM_ALLOW_SKIP=1 "$ev" check skipall "$T/skipall.log"; out_has "NOT RUN"
log garbled 'ran: x: many cases\nran:x: 3 cases\n'; expect_exit "a malformed evidence line fails" 1 "$ev" check garbled "$T/garbled.log"
expect_exit "a missing log fails" 1 "$ev" check nolog "$T/nothere.log"; out_has "no log"
log two 'ran: a: 3 cases\nran: b: 4 cases\n';     expect_exit "several lines are summed" 0 "$ev" check two "$T/two.log"

echo "## the gate wrapper: ran-evidence gate NAME REGEX CMD..."
refuse() { echo "heavy: run this elsewhere or inside the capped slice." >&2; exit 126; }; export -f refuse
expect_exit "a command refused by a guard (exit 126) fails" 1 "$ev" gate g 'n=([0-9]+)' bash -c refuse; out_has "exit 126"
expect_exit "a command that exits 0 and prints nothing fails (the vacuous pass)" 1 "$ev" gate g 'n=([0-9]+)' true; out_has "no line matching"
expect_exit "a count of zero fails" 1 "$ev" gate g 'n=([0-9]+)' echo n=0
expect_exit "a command that ran passes" 0 "$ev" gate g 'n=([0-9]+)' echo n=5; check "  and prints the evidence line" test "$(tail -n1 "$T/out")" = "ran: g: 5 cases"

echo "## check-dir DIR MAP"
mkdir "$T/cd"; printf 'a ^ledger: [0-9]+ proved of ([0-9]+)$\n' > "$T/cd.map"; printf 'ledger: 3 proved of 9\n' > "$T/cd/a.log"; printf 'hi\nran: b: 2 cases\n' > "$T/cd/b.log"
expect_exit "gate logs that carry evidence pass" 0 "$ev" check-dir "$T/cd" "$T/cd.map"; out_has "ran: a: 9 cases"
printf 'nothing to see\n' > "$T/cd/c.log"; expect_exit "a gate log with no evidence fails" 1 "$ev" check-dir "$T/cd" "$T/cd.map"; rm "$T/cd/c.log"
printf 'ledger: 3 proved of 0\n' > "$T/cd/a.log"; expect_exit "a zero count fails" 1 "$ev" check-dir "$T/cd" "$T/cd.map"
: > "$T/cd/a.log"; expect_exit "an empty (refused) gate log fails" 1 "$ev" check-dir "$T/cd" "$T/cd.map"
mkdir "$T/empty"; expect_exit "a directory with no logs fails" 1 "$ev" check-dir "$T/empty" "$T/cd.map"

echo "## lib/ran.sh: must_fail and ran_done"
mf() {   # mf NAME EXPECT(0|1) BODY: BODY runs under must_fail in its own shell; EXPECT 1 = the self-test must be FAILED by it
  local n=$1 want=$2 body=$3 rc=0
  printf '#!/usr/bin/env bash\nset -euo pipefail\n. %s\nmust_fail probe bash -c %q\nran_done probe\n' "$lib" "$body" > "$T/mf.sh"
  TMPDIR=$T bash "$T/mf.sh" >"$T/mf.out" 2>"$T/mf.err" || rc=$?
  if [ "$want" = 1 ]; then { [ "$rc" != 0 ] && ! grep -q '^ran: probe' "$T/mf.out"; } && pass "must_fail rejects: $n" || fail "must_fail ($n) passed (rc=$rc) but is not a failure the self-test may count: $(cat "$T/mf.err")"
  else { [ "$rc" = 0 ] && grep -q '^ran: probe: 1 cases' "$T/mf.out"; } && pass "must_fail accepts: $n" || fail "must_fail ($n): a real failure with a reason was not accepted (rc=$rc): $(cat "$T/mf.err")"; fi
}
mf "a real failure that says why" 0 'echo "the check failed: bad row" >&2; exit 1'
mf "the command succeeded" 1 'exit 0'
mf "silent failure" 1 'exit 1'
mf "refused by a guard (exit 126)" 1 'echo "heavy: run this elsewhere or inside the capped slice." >&2; exit 126'
mf "a refusal that exits 1 with the guard message" 1 'echo "heavy: run this elsewhere" >&2; exit 1'
mf "command not found (exit 127)" 1 'echo "no such tool" >&2; exit 127'
mf "a timeout (exit 124)" 1 'echo "timed out" >&2; exit 124'
expect_exit "ran_done with no case executed is not a pass" 1 env TMPDIR="$T" bash -c ". '$lib'; ran_done empty"; out_has "no case ran"
expect_exit "ran_done with a case prints the evidence line" 0 env TMPDIR="$T" bash -c ". '$lib'; ran_case; ran_case; ran_done two"; check "  with the count" test "$(tail -n1 "$T/out")" = "ran: two: 2 cases"
finish
