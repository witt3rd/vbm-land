#!/usr/bin/env bash
# The landings record (docs/landings.md): bin/land-direct appends one typed line per terminal result, and bin/land-metrics reads it. Each check can fail: the
# last section runs the same checks against a lander with the append cut out and a reader with the rank rule changed, and they must be caught.
. "$(dirname "$0")/lib.sh"
sandbox
L=$ROOT/bin/land-direct; M=$ROOT/bin/land-metrics
rec() { echo "$1/.git/vbm-land/landings.jsonl"; }
fieldof() { sed -n "s/.*\"$2\":\\([^,}]*\\).*/\\1/p" "$1" | tail -n1; }   # fieldof FILE KEY: the value of KEY in the last line

echo "## a landing writes its line"
set_conf 'LAND_TEST_CMD=true'
worker a; commit "$T/a" one.txt 1; git -C "$T/a" commit -q --amend --no-edit --date="@1700000000 +0000"; commit "$T/a" two.txt 2
tip=$(git -C "$T/a" rev-parse HEAD); basebefore=$(remote_head)
( cd "$T/a" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "the landing lands (exit 0)" test "$rc" = 0
f=$(rec "$T/a"); check "the file exists in the git common dir" test -s "$f"
check "exactly one line" test "$(wc -l < "$f")" = 1
check "the line is valid JSON" bash -c "command -v jq >/dev/null && jq -e . '$f' >/dev/null || true"
check "v is 1" test "$(fieldof "$f" v)" = 1
check "result landed, exit 0" bash -c "grep -q '\"result\":\"landed\",\"exit\":0' '$f'"
check "commits is 2" test "$(fieldof "$f" commits)" = 2
check "sha is what main now has" test "$(fieldof "$f" sha)" = "\"$(remote_head)\""
check "base is the main it was validated on" test "$(fieldof "$f" base)" = "\"$basebefore\""
check "tier1_seconds is a number" bash -c "[[ \"$(fieldof "$f" tier1_seconds)\" =~ ^[0-9]+$ ]]"
check "at is UTC seconds now" bash -c "a=$(fieldof "$f" at); [ \$a -ge $(( $(date -u +%s) - 120 )) ] && [ \$a -le $(date -u +%s) ]"
check "first_commit_at is the author time of the OLDEST landed commit" test "$(fieldof "$f" first_commit_at)" = 1700000000
check "the same sha and result as the summary line" bash -c "tail -n1 '$T/out' | grep -q '\"sha\":$(fieldof "$f" sha),\"commits\":2,'"
git -C "$T/a" status --porcelain --untracked-files=all | grep -q . && fail "the record dirties the work tree" || pass "the work tree stays clean"

echo "## a refused Tier 1 writes its line, with the exit code"
set_conf 'LAND_TEST_CMD=false'
worker b; commit "$T/b" b.txt 1
( cd "$T/b" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "Tier 1 refuses (exit 13)" test "$rc" = 13
f=$(rec "$T/b"); check "result tier1, exit 13, in the line" bash -c "grep -q '\"result\":\"tier1\",\"exit\":13' '$f'"
check "tier1_seconds is null where Tier 1 did not pass" test "$(fieldof "$f" tier1_seconds)" = null
worker b2; commit "$T/b2" b2.txt 1; ( cd "$T/b2" && "$L" --hold x >/dev/null 2>&1; "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a held landing ends 14 and writes its line (result held)" bash -c "test $rc = 14 && tail -n1 '$(rec "$T/b2")' | grep -q '\"result\":\"held\",\"exit\":14'"
( cd "$T/b2" && "$L" --release >/dev/null 2>&1 )
check "hold and release themselves write nothing" bash -c "test \$(wc -l < '$(rec "$T/b2")') = 1"

echo "## a write that fails never changes the result or the exit code"
set_conf 'LAND_TEST_CMD=true'
worker c; commit "$T/c" c.txt 1; mkdir -p "$T/c/.git/vbm-land"; mkdir "$T/c/.git/vbm-land/landings.jsonl"   # a directory where the file goes: the append fails
( cd "$T/c" && "$L" >"$T/out" 2>"$T/err" ) && rc=0 || rc=$?
check "still lands, exit 0" test "$rc" = 0
check "main has the change" remote_has c.txt
check "the summary line is still the last line of stdout" bash -c "tail -n1 '$T/out' | grep -q '\"result\":\"landed\",\"exit\":0'"
check "nothing about the failed write on stderr" bash -c "! grep -qi 'landings\\|Is a directory' '$T/err'"
set_conf 'LAND_TEST_CMD=false'
worker c2; commit "$T/c2" c2.txt 1; mkdir -p "$T/c2/.git/vbm-land"; mkdir "$T/c2/.git/vbm-land/landings.jsonl"
( cd "$T/c2" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a refused landing keeps its exit 13 when the write fails" test "$rc" = 13
if [ "$(id -u)" != 0 ]; then   # the same with a really unwritable file
  set_conf 'LAND_TEST_CMD=true'; worker c3; commit "$T/c3" c3.txt 1; mkdir -p "$T/c3/.git/vbm-land"; : > "$T/c3/.git/vbm-land/landings.jsonl"; chmod 444 "$T/c3/.git/vbm-land/landings.jsonl"
  ( cd "$T/c3" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?; check "an unwritable file: still exit 0" test "$rc" = 0
fi

echo "## land-metrics over a fixture, by hand-computed nearest rank"
# 11 landed lines: ten ran Tier 1 for 5 1 9 3 7 2 8 4 10 6 s (sorted 1..10: p50 = rank 5 = 5, p90 = rank 9 = 9), one inert (no Tier 1: not counted);
# four have a first_commit_at, at - first = 100 20 300 40 (sorted 20 40 100 300: p50 = rank 2 = 40, p90 = rank ceil(3.6) = 4 = 300);
# plus 2 tier1, 1 conflict, one validated and one checked (the dry steps: not landings) and a line that is not a record.
fx=$T/fixture.jsonl; : > "$fx"
i=0; for t in 5 1 9 3 7 2 8 4 10 6; do
  i=$((i+1)); first=null; case $i in 1) first=900;; 2) first=1980;; 3) first=700;; 4) first=960;; esac
  at=1000; case $i in 2) at=2000;; 3) at=1000;; 4) at=1000;; esac
  printf '{"v":1,"at":%s,"sha":"%040d","base":"%040d","commits":1,"tier1_seconds":%s,"result":"landed","exit":0,"first_commit_at":%s}\n' "$at" "$i" "$i" "$t" "$first" >> "$fx"
done
printf '%s\n' '{"v":1,"at":1000,"sha":null,"base":null,"commits":1,"tier1_seconds":0,"result":"landed","exit":0,"first_commit_at":null,"validation":"inert"}' \
  '{"v":1,"at":1000,"sha":null,"base":null,"commits":1,"tier1_seconds":null,"result":"tier1","exit":13,"first_commit_at":null}' \
  '{"v":1,"at":1000,"sha":null,"base":null,"commits":1,"tier1_seconds":null,"result":"tier1","exit":13,"first_commit_at":null}' \
  '{"v":1,"at":1000,"sha":null,"base":null,"commits":1,"tier1_seconds":null,"result":"conflict","exit":11,"first_commit_at":null}' \
  '{"v":1,"at":1000,"sha":null,"base":null,"commits":1,"tier1_seconds":3,"result":"validated","exit":0,"first_commit_at":null}' \
  '{"v":1,"at":1000,"sha":null,"base":null,"commits":1,"tier1_seconds":null,"result":"checked","exit":0,"first_commit_at":null}' \
  'this is not a record' >> "$fx"
want=$'landings 14\nlanded 11\ntier1-seconds-p50 5\ntier1-seconds-p90 9\ncommit-to-main-seconds-p50 40\ncommit-to-main-seconds-p90 300\nrefused-tier1 2'
got=$("$M" "$fx") && pass "land-metrics exits 0" || fail "land-metrics failed"
[ "$got" = "$want" ] && pass "the seven lines are exactly the hand-computed ones" || { fail "land-metrics printed:"; echo "$got" | sed 's/^/     | /' >&2; }
# the first_commit_at / at pairs above: (1000-900)=100 (2000-1980)=20 (1000-700)=300 (1000-960)=40
one=$T/one.jsonl; printf '{"v":1,"at":50,"sha":null,"base":null,"commits":1,"tier1_seconds":7,"result":"landed","exit":0,"first_commit_at":20}\n' > "$one"
check "one value: both percentiles are that value" bash -c "'$M' '$one' | grep -qx 'tier1-seconds-p90 7' && '$M' '$one' | grep -qx 'commit-to-main-seconds-p50 30'"
printf '{"v":1,"at":50,"sha":null,"base":null,"commits":1,"tier1_seconds":null,"result":"tier1","exit":13,"first_commit_at":null}\n' > "$T/none.jsonl"
check "a file with no landed line: counts are 0, percentiles unmeasured" bash -c "'$M' '$T/none.jsonl' | tr '\n' ' ' | grep -q 'landings 1 landed 0 tier1-seconds-p50 unmeasured tier1-seconds-p90 unmeasured commit-to-main-seconds-p50 unmeasured commit-to-main-seconds-p90 unmeasured refused-tier1 1'"
: > "$T/empty.jsonl"; check "an empty file: landings 0, percentiles unmeasured" bash -c "'$M' '$T/empty.jsonl' | head -3 | tr '\n' ' ' | grep -q 'landings 0 landed 0 tier1-seconds-p50 unmeasured'"

echo "## a missing file prints unmeasured, never 0"
"$M" "$T/no-such-file" > "$T/out" 2>&1 && pass "exit 0" || fail "land-metrics failed on a missing file"
check "the seven lines, each unmeasured" bash -c "[ \$(grep -c ' unmeasured\$' '$T/out') = 7 ] && ! grep -q ' 0\$' '$T/out'"
worker m; ( cd "$T/m" && "$M" > "$T/out" 2>&1 ); check "with no argument it reads the clone's own file (none yet: unmeasured)" bash -c "grep -qx 'landings unmeasured' '$T/out'"
check "with no argument it reads the clone's record" bash -c "cd '$T/a' && '$M' | grep -qx 'landed 1'"

echo "## the checks can fail (mutants)"
sandbox; set_conf 'LAND_TEST_CMD=true'
mk=$T/mut; mkdir -p "$mk"; cp -r "$ROOT/bin" "$ROOT/lib" "$mk/"; cp "$ROOT/VERSION" "$mk/"
sed -i 's|>> "\$state/landings.jsonl"|>> /dev/null|' "$mk/bin/land-direct"; cmp -s "$mk/bin/land-direct" "$L" && fail "the lander mutant changed nothing"
worker d; commit "$T/d" d.txt 1; ( cd "$T/d" && "$mk/bin/land-direct" >/dev/null 2>&1 ) || true
check "a lander that does not append is caught (no file)" test ! -s "$(rec "$T/d")"
cp "$M" "$mk/bin/land-metrics"; sed -i 's|r = int((p \* n + 99) / 100)|r = int(p * n / 100)|' "$mk/bin/land-metrics"; cmp -s "$mk/bin/land-metrics" "$M" && fail "the reader mutant changed nothing"
check "a reader with another rank rule prints other numbers (commit-to-main p90 of the fixture: 3rd value, not the 4th)" bash -c "[ \"\$('$mk/bin/land-metrics' '$fx' | grep commit-to-main-seconds-p90)\" != 'commit-to-main-seconds-p90 300' ]"
cp "$M" "$mk/bin/land-metrics"; sed -i 's|for n in \$names; do echo "\$n unmeasured"|for n in $names; do echo "$n 0"|' "$mk/bin/land-metrics"; cmp -s "$mk/bin/land-metrics" "$M" && fail "the missing-file mutant changed nothing"
check "a reader that prints 0 for a missing file is caught" bash -c "'$mk/bin/land-metrics' '$T/no-such-file' | grep -q ' 0\$'"
cp "$L" "$mk/bin/land-direct"; sed -i 's|2>/dev/null \|\| true\n  fi||; s|"\$first_at")" "\$vjson" >> "\$state/landings.jsonl"; } 2>/dev/null \|\| true|"$first_at")" "$vjson" >> "$state/landings.jsonl"; }|' "$mk/bin/land-direct"; cmp -s "$mk/bin/land-direct" "$L" && fail "the write-failure mutant changed nothing"
worker e; commit "$T/e" e.txt 1; mkdir -p "$T/e/.git/vbm-land"; mkdir "$T/e/.git/vbm-land/landings.jsonl"
( cd "$T/e" && "$mk/bin/land-direct" >"$T/out" 2>"$T/err" ) && rc=0 || rc=$?
check "a lander that does not guard the write is caught (the failed write leaks to stderr)" bash -c "grep -q 'landings.jsonl' '$T/err'"
finish
