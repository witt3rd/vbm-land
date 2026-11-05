#!/usr/bin/env bash
# The harness must be able to fail: a failing check inside a ( subshell ) has to make `finish` exit non-zero.
. "$(dirname "$0")/lib.sh"
sandbox
cat > "$T/probe.sh" <<PROBE
. "$ROOT/tests/lib.sh"; sandbox
( expect_exit "must be 0" 0 false ) || true
finish
PROBE
rc=0; bash "$T/probe.sh" >"$T/out" 2>&1 || rc=$?
check "a failing check in a subshell fails the script" test "$rc" != 0
grep -q '1 failed' "$T/out" && pass "and is counted" || fail "failure not counted"
cat > "$T/probe2.sh" <<PROBE
. "$ROOT/tests/lib.sh"; sandbox
( expect_exit "must be 0" 0 true ) || true
finish
PROBE
check "a passing probe passes" bash "$T/probe2.sh"
# RAN-EVIDENCE: a script that ran no check has not passed (it prints no `ran:` line and fails), and a check on a tool that was refused is a failure, not a pass
cat > "$T/probe3.sh" <<PROBE
. "$ROOT/tests/lib.sh"; sandbox
finish
PROBE
rc=0; bash "$T/probe3.sh" >"$T/out" 2>&1 || rc=$?
check "a script that ran no check fails" test "$rc" != 0
check "and prints no ran-evidence" bash -c "! grep -q '^ran: ' '$T/out'"
cat > "$T/probe4.sh" <<PROBE
. "$ROOT/tests/lib.sh"; sandbox
expect_exit "the tool ran and answered" 0 bash -c 'echo "heavy: run elsewhere or inside the capped slice." >&2; exit 126'
finish
PROBE
rc=0; bash "$T/probe4.sh" >"$T/out" 2>&1 || rc=$?
check "a refused tool (exit 126) is not a pass" test "$rc" != 0
check "and prints no ran-evidence" bash -c "! grep -q '^ran: ' '$T/out'"
bash "$T/probe2.sh" >"$T/out" 2>&1; check "a passing probe prints its ran-evidence line" grep -qx 'ran: probe2: 1 cases' "$T/out" || true
finish
