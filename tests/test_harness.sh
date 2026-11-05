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
finish
