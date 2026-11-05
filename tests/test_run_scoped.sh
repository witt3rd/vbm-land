#!/usr/bin/env bash
# scripts/run-scoped.sh (a bounded transient scope; setsid + timeout fallback without a systemd user manager) and the abort reaper of tests/run.sh: the exit status passes through, the bound
# holds, a dollar in an argument arrives as written, and an ABORTED run (SIGTERM to the pid started here) leaves neither its child nor its grandchild. Both paths always run (the fallback by
# RUN_SCOPED_NO_SYSTEMD=1; the systemd path where a user manager works): never a skip.
. "$(dirname "$0")/lib.sh"
rs=$ROOT/scripts/run-scoped.sh; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
modes="fallback"; if systemctl --user is-system-running >/dev/null 2>&1 || [ "$(systemctl --user is-system-running 2>/dev/null)" = degraded ]; then modes="scope fallback"; fi
for mode in $modes; do
  if [ $mode = fallback ]; then export RUN_SCOPED_NO_SYSTEMD=1; else unset RUN_SCOPED_NO_SYSTEMD; fi
  [ "$("$rs" t 5 echo ok)" = ok ] && pass "$mode: output passes through" || fail "$mode: output lost"
  rc=0; "$rs" t 5 sh -c 'exit 7' || rc=$?; [ $rc = 7 ] && pass "$mode: exit status passes through" || fail "$mode: exit status $rc"
  rc=0; "$rs" t 1 sleep 30 || rc=$?; [ $rc = 124 ] && pass "$mode: the bound holds" || fail "$mode: the bound did not hold ($rc)"
  [ "$("$rs" d 5 echo 'a$b $$ ${x}')" = 'a$b $$ ${x}' ] && pass "$mode: a dollar in an argument is not altered" || fail "$mode: a dollar was altered"
  rm -f "$tmp/pid" "$tmp/gpid"
  "$rs" abort 120 sh -c 'echo $$ > "$1"; sleep 100 & echo $! > "$2"; wait' sh "$tmp/pid" "$tmp/gpid" & w=$!
  for _ in $(seq 50); do [ -s "$tmp/gpid" ] && break; sleep 0.1; done
  if [ -s "$tmp/gpid" ]; then
    c=$(cat "$tmp/pid"); g=$(cat "$tmp/gpid"); kill -TERM "$w"; wait "$w" || true
    for _ in $(seq 50); do kill -0 "$c" 2>/dev/null || kill -0 "$g" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$c" 2>/dev/null || kill -0 "$g" 2>/dev/null; then fail "$mode: an aborted run left its child or grandchild alive"; else pass "$mode: an aborted run leaves no child and no grandchild"; fi
  else fail "$mode: the scoped child never started"; fi
done
# tests/run.sh: aborted, it stops the test jobs it started (a copy of run.sh with a fake lint and one fake test that has a grandchild)
mkdir -p "$tmp/t/tests" "$tmp/t/scripts"; cp "$ROOT/tests/run.sh" "$tmp/t/tests/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/t/tests/lint.sh"
printf '#!/usr/bin/env bash\nsleep 300 & echo $! > "$1/g"\nwait\n' > "$tmp/t/tests/test_x.sh"; sed -i 's|"\$1/g"|'"$tmp"'/rg|' "$tmp/t/tests/test_x.sh"; chmod +x "$tmp/t/tests/"*.sh
unset RUN_SCOPED_NO_SYSTEMD; rm -f "$tmp/rg"
bash "$tmp/t/tests/run.sh" >/dev/null 2>&1 & w=$!
for _ in $(seq 50); do [ -s "$tmp/rg" ] && break; sleep 0.1; done
if [ -s "$tmp/rg" ]; then g=$(cat "$tmp/rg"); kill -TERM "$w"; wait "$w" || true; for _ in $(seq 50); do kill -0 "$g" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$g" 2>/dev/null; then fail "tests/run.sh: an aborted run left a test's child alive"; kill "$g"; else pass "tests/run.sh: an aborted run leaves no test child"; fi
else fail "tests/run.sh: the fake test never started"; fi
# the check can fail: the same run without the reaper leaves the child (it is then stopped here by its recorded pid)
sed -i 's|reap_pids "${pids\[@\]}"; ||' "$tmp/t/tests/run.sh"; grep -q "trap 'reap_pids" "$tmp/t/tests/run.sh" && fail "self-test: the reaper was not removed from the copy"
rm -f "$tmp/rg"; bash "$tmp/t/tests/run.sh" >/dev/null 2>&1 & w=$!
for _ in $(seq 50); do [ -s "$tmp/rg" ] && break; sleep 0.1; done
g=$(cat "$tmp/rg"); kill -TERM "$w"; wait "$w" || true; sleep 0.5
if kill -0 "$g" 2>/dev/null; then kill "$g"; pass "self-test: without the reaper an aborted run leaves the child (the check can fail)"; else fail "self-test: the child died without the reaper (the check cannot fail)"; fi
finish
