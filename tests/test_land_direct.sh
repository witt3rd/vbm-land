#!/usr/bin/env bash
# bin/land-direct against scratch repositories with a bare remote. Every refusal has a negative test: what must be refused is refused (with
# its exit code and a message naming the cause), and NOTHING reaches the remote when it is refused.
. "$(dirname "$0")/lib.sh"
sandbox
L=$ROOT/bin/land-direct
export LAND_LOCK_WAIT_SECONDS=5 RED_SLEEP=true
nothing_landed() { test "$(remote_head)" = "$before"; }    # `before=$(remote_head)` precedes each refusal test
refused() {   # refused DESC CODE DIR [ENV=VAL...]: land from DIR, it must exit CODE and leave the remote untouched
  local d=$1 want=$2 dir=$3; shift 3; before=$(remote_head)
  ( cd "$dir" && env "$@" "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
  if [ "$rc" = "$want" ]; then pass "$d (exit $rc)"; else fail "$d: wanted exit $want, got $rc"; sed 's/^/     | /' "$T/out" >&2; fi
  check "$d: nothing reached the remote" nothing_landed
}
lands() { local d=$1 dir=$2; shift 2; ( cd "$dir" && env "$@" "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?; if [ "$rc" = 0 ]; then pass "$d (exit 0)"; else fail "$d: exit $rc"; sed 's/^/     | /' "$T/out" >&2; fi; }

echo "## configuration"
worker c0   # a clone with no configuration anywhere
commit "$T/c0" x.txt 1
refused "no configuration refuses" 2 "$T/c0"; out_has "no configuration"
set_conf 'LAND_TEST_CMD=true' 'LAND_TYPO_KEY=1'
worker c1; commit "$T/c1" x.txt 1
refused "an unknown key refuses (a typo must not turn a gate off)" 2 "$T/c1"; out_has "unknown key LAND_TYPO_KEY"
set_conf '# no tier 1 at all' 'LAND_BASE=main'
worker c2; commit "$T/c2" x.txt 1
refused "a config without any Tier 1 command refuses" 2 "$T/c2"; out_has "no Tier 1"
set_conf 'LAND_TEST_CMD=true' 'LAND_RED_MODE=sometimes'
worker c3; commit "$T/c3" x.txt 1
refused "a bad red mode refuses" 2 "$T/c3"; out_has LAND_RED_MODE
set_conf 'LAND_TEST_CMD=true' 'LAND_REGEN_CMD=$(touch /tmp/vbm-land-injected)'   # data, never evaluated at read time (and a regeneration command only runs after a conflict)
worker c4; commit "$T/c4" x.txt 1
( cd "$T/c4" && "$L" >"$T/out" 2>&1 ) || true; check "reading the config executes nothing" test ! -e /tmp/vbm-land-injected; rm -f /tmp/vbm-land-injected

echo "## first landing: the base has no config yet, the working tree's is used"
sandbox
worker f1; mkdir -p "$T/f1/scripts"; echo 'LAND_TEST_CMD=true' > "$T/f1/scripts/land.conf"; git -C "$T/f1" add scripts/land.conf; git -C "$T/f1" commit -qm "chore: add land.conf"
lands "the first landing (config only in the working tree) lands" "$T/f1"; out_has "has no scripts/land.conf yet"

echo "## landing"
sandbox
set_conf 'LAND_TEST_CMD=test ! -e BAD' 'LAND_REQUIRE_TRAILERS=Task-ID'
worker a; commit "$T/a" one.txt 1
lands "lands one commit" "$T/a"; out_has '"result":"landed"'
check "main has it" remote_has one.txt
check "JSON last line names sha, commits, tier1_seconds, result, exit" bash -c "tail -n1 '$T/out' | grep -qE '^\\{\"sha\":\"[0-9a-f]{40}\",\"commits\":1,\"tier1_seconds\":[0-9]+,\"result\":\"landed\",\"exit\":0\\}$'"
check "a metrics line is written" bash -c "grep -q '\"result\":\"landed\"' '$T/a/.git/vbm-land/metrics.jsonl'"
worker a2; commit "$T/a2" two.txt 2; before=$(remote_head)
( cd "$T/a2" && "$L" --dry-run >"$T/out" 2>&1 ) || true; out_has "would land"; check "--dry-run pushes nothing" nothing_landed
( cd "$T/a2" && "$L" --check >"$T/out" 2>&1 ) || true; out_has '"result":"checked"'; check "--check pushes nothing" nothing_landed
worker a3; git -C "$T/a3" commit -q --allow-empty -m "chore: nothing" -m "Task-ID: t"; git -C "$T/a3" reset -q --hard origin/main
refused "nothing to land refuses" 2 "$T/a3"
worker a4; commit "$T/a4" m1.txt 1; git -C "$T/a4" checkout -q -b side HEAD~1; commit "$T/a4" m2.txt 2; git -C "$T/a4" merge -q --no-ff --no-edit main 2>/dev/null || git -C "$T/a4" merge -q --no-ff -m "chore: merge" -m "Task-ID: m" main 2>/dev/null || true
git -C "$T/a4" checkout -q main 2>/dev/null; git -C "$T/a4" merge -q --no-ff -m "chore: merge" side 2>/dev/null || true
if [ -n "$(git -C "$T/a4" rev-list --merges origin/main..HEAD)" ]; then refused "merge commits are refused (history lands linear)" 2 "$T/a4"; else pass "merge-commit setup unavailable here (skipped)"; fi

echo "## config comes from the base branch, never from the change"
worker g1; mkdir -p "$T/g1"; : > "$T/g1/BAD"; printf 'LAND_TEST_CMD=true\n' > "$T/g1/scripts/land.conf"
git -C "$T/g1" add -A; git -C "$T/g1" commit -qm "feat: bad file and a loosened config" -m "Task-ID: t"
refused "a change that loosens land.conf is still judged by main's" 13 "$T/g1"

echo "## land-time checks"
worker k; echo 1 > "$T/k/x.txt"; git -C "$T/k" add x.txt; git -C "$T/k" commit -qm "not conventional" -m "Task-ID: t"
refused "a non-Conventional subject refuses" 1 "$T/k"; out_has "not a Conventional Commit"
worker k2; echo 1 > "$T/k2/x.txt"; git -C "$T/k2" add x.txt; git -C "$T/k2" commit -qm "feat: no trailer"
refused "a missing required trailer refuses" 1 "$T/k2"; out_has "no 'Task-ID:' trailer"
worker k3; commit "$T/k3" r.txt 1 'Revert "feat: something"'
lands "git's own Revert \"...\" subject is accepted (no divergence between the subject check and the red rule)" "$T/k3"
set_conf 'LAND_TEST_CMD=true' 'LAND_PROD_PATHS=src' 'LAND_BUDGET_LINES=5'
worker k4; mkdir -p "$T/k4/src"; seq 1 20 > "$T/k4/src/big.txt"; git -C "$T/k4" add src; git -C "$T/k4" commit -qm "feat: big" -m "Task-ID: t"
refused "over the size budget refuses" 1 "$T/k4"; out_has "exceed the 5-line budget"
git -C "$T/k4" commit -q --amend -m "feat: big" -m "Diff-Budget: part 1 of 3, the rest follows" -m "Task-ID: t"
lands "a Diff-Budget trailer waives the budget" "$T/k4"
worker k5; mkdir -p "$T/k5/other"; seq 1 20 > "$T/k5/other/big.txt"; git -C "$T/k5" add other; git -C "$T/k5" commit -qm "feat: big elsewhere" -m "Task-ID: t"
lands "paths outside LAND_PROD_PATHS are not counted" "$T/k5"

echo "## Tier 1"
set_conf 'LAND_GATES_CMD=echo gate-ran; test ! -e GATE_BAD' 'LAND_TEST_CMD=echo test-ran; test ! -e TEST_BAD'
worker t1; commit "$T/t1" GATE_BAD 1; refused "a failing gate refuses" 13 "$T/t1"; out_has "Tier 1 (gates) fails"
worker t2; commit "$T/t2" TEST_BAD 1; refused "a failing test refuses" 13 "$T/t2"; out_has "Tier 1 (tests) fails"
worker t3; commit "$T/t3" ok.txt 1; lands "gates then tests, both run on the combination" "$T/t3"
set_conf 'LAND_TEST_CMD=sleep 30' 'LAND_TIER1_TIMEOUT=2'
worker t4; commit "$T/t4" slow.txt 1; refused "a Tier 1 that runs over its bound is killed and refuses" 13 "$T/t4"; out_has "TIMED OUT: Tier 1 tests"
set_conf 'LAND_TEST_CMD=true'

echo "## rebase, conflicts, main moving"
worker m1; worker m2; commit "$T/m1" shared.txt first; commit "$T/m2" shared.txt second
lands "first of two conflicting changes lands" "$T/m1"
refused "the second conflicts: refused and the file is named" 11 "$T/m2"; out_has shared.txt
worker mv2; commit "$T/mv2" mv2.txt 2
set_conf "LAND_TEST_CMD=[ -e $T/moved ] || { touch $T/moved; git -C $T/mv2 pull -q --rebase origin main && git -C $T/mv2 push -q origin HEAD:main; }"
worker mv1; commit "$T/mv1" mv1b.txt 1
lands "main moving during Tier 1 re-rebases and lands" "$T/mv1"; out_has "moved during Tier 1"
check "both are on main" bash -c "git -C '$T/remote.git' cat-file -e main:mv2.txt && git -C '$T/remote.git' cat-file -e main:mv1b.txt"
set_conf 'LAND_TEST_CMD=true'

echo "## generated files"
seed_push gen/list.txt "gen/out.txt"
seed_push gen/out.txt "base"
set_conf 'LAND_TEST_CMD=true' 'LAND_GENERATED_LIST=gen/list.txt' 'LAND_REGEN_CMD=echo regenerated > gen/out.txt'
worker ge1; worker ge2; commit "$T/ge1" gen/out.txt one "feat: gen one"; commit "$T/ge2" gen/out.txt two "feat: gen two"
lands "a generated-file change lands" "$T/ge1"
lands "a conflict only in a generated file is regenerated" "$T/ge2"; out_has "regenerating"
check "the regenerated content is what main has" bash -c "[ \"\$(git -C '$T/remote.git' show main:gen/out.txt)\" = regenerated ]"
set_conf 'LAND_TEST_CMD=true' 'LAND_GENERATED_LIST=gen/list.txt' 'LAND_REGEN_CMD=exit 4'
worker ge3; worker ge4; commit "$T/ge3" gen/out.txt three "feat: gen three"; commit "$T/ge4" gen/out.txt four "feat: gen four"
lands "setup: another generated-file change" "$T/ge3"
refused "a failing regeneration refuses (exit 12)" 12 "$T/ge4"
set_conf 'LAND_TEST_CMD=true' 'LAND_GENERATED_LIST=gen/list.txt'
worker ge5; worker ge6; commit "$T/ge5" gen/out.txt five "feat: gen five"; commit "$T/ge6" gen/out.txt six "feat: gen six"
lands "setup: and one more" "$T/ge5"
refused "generated files conflict but no LAND_REGEN_CMD: refused" 12 "$T/ge6"
set_conf 'LAND_TEST_CMD=true' 'LAND_GENERATED_LIST=gen/list.txt' 'LAND_GEN_CMD=echo always > gen/out.txt'
worker ge7; commit "$T/ge7" other.txt 1
lands "LAND_GEN_CMD runs on every rebased tree; its output lands as a commit of the lander" "$T/ge7"
check "the lander's own commit is on main with the generated file" bash -c "[ \"\$(git -C '$T/remote.git' show main:gen/out.txt)\" = always ] && git -C '$T/remote.git' log -1 --format=%s main | grep -q '^chore: regenerate generated files'"

echo "## hold and freeze"
set_conf 'LAND_TEST_CMD=true'
worker h1; commit "$T/h1" h.txt 1
( cd "$T/h1" && "$L" --hold "maintenance window" ) >/dev/null
refused "a hold stops a landing" 14 "$T/h1"; out_has "maintenance window"
( cd "$T/h1" && "$L" --status ) >"$T/out" 2>&1; out_has "hold: maintenance window"
( cd "$T/h1" && "$L" --release ) >/dev/null
lands "released: lands" "$T/h1"
worker h2; commit "$T/h2" h2.txt 1
expect_exit "--freeze needs an owner and an expiry" 2 bash -c "cd '$T/h2' && '$L' --freeze 'broken' "
( cd "$T/h2" && "$L" --freeze "tier 2 broke" --owner alice --for 1h ) >"$T/out" 2>&1; out_has "FROZEN until"
refused "a frozen base refuses an ordinary change" 14 "$T/h2"; out_has "frozen"
set_conf 'LAND_TEST_CMD=true' 'LAND_FIX_PATHS=tests/* .github/*' 'LAND_PROTECTED=bin/* lib/*'
worker h3; commit "$T/h3" tests/t.sh 1 "fix(tests): repair"; ( cd "$T/h3" && "$L" --freeze "tier 2 broke" --owner alice --for 1h ) >/dev/null
lands "a fix touching only test paths lands on a frozen base" "$T/h3"; out_has "frozen; this change is a fix"
check "landing the fix lifted the freeze" test ! -e "$T/h3/.git/vbm-land/freeze"
worker h4; commit "$T/h4" h4.txt 1
( cd "$T/h4" && "$L" --freeze "again" --owner bob --for 1s ) >/dev/null; sleep 2
lands "an expired freeze is not in force" "$T/h4"
( cd "$T/h2" && "$L" --freeze "again" --owner bob --for 1h && "$L" --thaw ) >/dev/null 2>&1; check "--thaw clears it" test ! -e "$T/h2/.git/vbm-land/freeze"

echo "## red main"
gh_mode red
worker r1; commit "$T/r1" r1.txt 1
refused "red main refuses an ordinary change" 10 "$T/r1"; out_has "is red"
worker r2; commit "$T/r2" other/code.txt 1 "fix(tests): sneaky"
refused "a fix(tests) subject touching non-test paths is not a fix" 10 "$T/r2"
worker r3; commit "$T/r3" lib/x.sh 1 "fix(ci): touches the protected set"
refused "a fix touching the protected set is not a fix" 10 "$T/r3"
worker r4; commit "$T/r4" tests/new.sh 1 "fix(tests): real fix"
lands "a fix touching only test paths lands on a red main" "$T/r4"; out_has "this change is the fix"
worker r5; commit "$T/r5" r5.txt 1
lands "LAND_FIX_FOR_RED=1 is the operator's override" "$T/r5" LAND_FIX_FOR_RED=1
# a true revert: undoes one commit of main and says so
worker r6; sha=$(git -C "$T/r6" rev-parse HEAD)
( cd "$T/r6" && git revert --no-edit "$sha" >/dev/null 2>&1 && git commit -q --amend -m "Revert \"x\"" -m "This reverts commit $sha." -m "Task-ID: t" )
lands "a true revert (names a commit of main, touches only its files) lands on a red main" "$T/r6"
worker r7; commit "$T/r7" lib/y.sh 1 'Revert "feat: pretend"'
refused "a Revert subject that names no commit of main is not a revert" 10 "$T/r7"
gh_mode infra
worker r8; commit "$T/r8" r8.txt 1
lands "an infrastructure failure (billing, runner, network) is not red" "$T/r8"; out_has "infrastructure reason"
gh_mode fail
worker r9; commit "$T/r9" r9.txt 1
refused "gh failing means not knowable: refused" 10 "$T/r9"; out_has "cannot tell"
gh_mode running
worker r10; commit "$T/r10" r10.txt 1
lands "a Tier 1 still running is not a failure: the lander's own Tier 1 is the gate" "$T/r10"; out_has "no finished tier1 job"
gh_mode dispatch
set_conf 'LAND_TEST_CMD=true' 'LAND_RED_MODE=push'
worker r11; commit "$T/r11" r11.txt 1
lands "mode push ignores a red dispatch run" "$T/r11"
set_conf 'LAND_TEST_CMD=true' 'LAND_RED_MODE=push+dispatch'
worker r12; commit "$T/r12" r12.txt 1
refused "mode push+dispatch counts a red dispatch run" 10 "$T/r12"
set_conf 'LAND_TEST_CMD=true' 'LAND_RED_MODE=off'
worker r13; commit "$T/r13" r13.txt 1
gh_mode fail
lands "mode off asks nobody" "$T/r13"
gh_mode noworkflow
set_conf 'LAND_TEST_CMD=true'
worker r14; commit "$T/r14" r14.txt 1
lands "a CI workflow that is not on main yet cannot be red" "$T/r14"
gh_mode ok
set_conf 'LAND_TEST_CMD=true' 'LAND_CI_WORKFLOW=build.yml' 'LAND_TIER1_JOB=gate'
worker r15; commit "$T/r15" r15.txt 1; : > "$T/gh/calls.log"
lands "workflow and job names come from the config" "$T/r15"; check "it asked about build.yml" grep -q -- '--workflow build.yml' "$T/gh/calls.log"

echo "## hooks (taken from main, so a change cannot rewrite the rules it is judged by)"
gh_mode ok
set_conf 'LAND_TEST_CMD=true' 'LAND_PROTECTED=guarded/*'
seed_exec scripts/land.d/post-rebase '#!/usr/bin/env bash
[ -z "$LAND_PROTECTED_TOUCHED" ] || { echo "hook: protected file touched: $LAND_PROTECTED_TOUCHED"; exit 1; }
grep -q . "$LAND_TOUCHED_FILE" || exit 1'
seed_exec scripts/land.d/json-fields '#!/usr/bin/env bash
echo "extra_metric=42"; echo "label=ok-1"; echo "bad key=1"; echo "sha=evil"; echo "text=has spaces"'
worker o1; commit "$T/o1" guarded/g.txt 1
refused "a post-rebase hook refuses a protected-set change" 12 "$T/o1"; out_has "protected file touched: guarded/g.txt"; out_has "protected set: TOUCHED"
worker o2; commit "$T/o2" guarded/g.txt 1; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/o2/scripts/land.d/post-rebase"; git -C "$T/o2" add -A; git -C "$T/o2" commit -qm "feat: also neuter the hook" -m "Task-ID: t"
refused "a change that rewrites the hook is still judged by main's hook" 12 "$T/o2"
worker o3; commit "$T/o3" free.txt 1
lands "an unprotected change passes the hook" "$T/o3"
check "json-fields adds numeric and safe string keys" bash -c "tail -n1 '$T/out' | grep -q '\"extra_metric\":42,\"label\":\"ok-1\"'"
check "json-fields cannot override the contract keys or add junk" bash -c "tail -n1 '$T/out' | grep -vq 'evil' && tail -n1 '$T/out' | grep -q '\"text\":null'"
seed_exec scripts/land.d/pre-rebase '#!/usr/bin/env bash
test ! -e NOPE'
worker o4; commit "$T/o4" NOPE 1
refused "a pre-rebase hook can refuse (exit 12)" 12 "$T/o4"
seed_exec scripts/land.d/post-tier1 '#!/usr/bin/env bash
test ! -e NOPE2'
worker o5; commit "$T/o5" NOPE2 1
refused "a post-tier1 hook can refuse (exit 12)" 12 "$T/o5"
seed_exec scripts/land.d/on-run '#!/usr/bin/env bash
echo "$LAND_RESULT" >> "$LAND_STATE_DIR/on-run.log"'
worker o6; commit "$T/o6" o6.txt 1
lands "an on-run hook sees every run" "$T/o6"; check "on-run saw the result" grep -q landed "$T/o6/.git/vbm-land/on-run.log"

echo "## lock, lease, racing workers"
worker b1; commit "$T/b1" b.txt 1
mkdir -p "$T/b1/.git/vbm-land"; ( exec 8>"$T/b1/.git/vbm-land/lock"; flock 8; sleep 8 ) & holder=$!
sleep 0.3; refused "a busy lock refuses" 15 "$T/b1" LAND_LOCK_WAIT_SECONDS=1; kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
# a lease whose holder is alive but silent past the stale limit is broken: the holder (a process this test started) is terminated
worker l1; commit "$T/l1" l.txt 1; mkdir -p "$T/l1/.git/vbm-land"
sleep 120 & victim=$!; st=$(awk '{sub(/^.*\) /,""); print $20}' "/proc/$victim/stat")
printf 'pid=%s start=%s task=t at=1\n' "$victim" "$st" > "$T/l1/.git/vbm-land/lease"; touch -d '2 hours ago' "$T/l1/.git/vbm-land/lease"
( exec 8>"$T/l1/.git/vbm-land/lock"; flock 8; sleep 60 ) & lockholder=$!; sleep 0.3
lands "a stale lease is broken and the landing proceeds" "$T/l1" LAND_LEASE_STALE_SECONDS=60 LAND_LOCK_WAIT_SECONDS=30; out_has "LEASE BROKEN"
sleep 1; check "the stale holder was terminated" bash -c "! kill -0 $victim 2>/dev/null"
check "the break is logged" test -s "$T/l1/.git/vbm-land/lease.log"
kill "$victim" "$lockholder" 2>/dev/null || true; wait 2>/dev/null || true
worker p1; worker p2; commit "$T/p1" p1.txt 1; commit "$T/p2" p2.txt 2
set_conf 'LAND_TEST_CMD=sleep 1' 'LAND_LOCK_WAIT=30'
( cd "$T/p1" && "$L" >"$T/p1.out" 2>&1 ) & q1=$!; ( cd "$T/p2" && "$L" >"$T/p2.out" 2>&1 ) & q2=$!
rc1=0; rc2=0; wait $q1 || rc1=$?; wait $q2 || rc2=$?
check "two racing workers both land" bash -c "[ $rc1 = 0 ] && [ $rc2 = 0 ] && git -C '$T/remote.git' cat-file -e main:p1.txt && git -C '$T/remote.git' cat-file -e main:p2.txt"
check "history stays linear" test -z "$(git -C "$T/remote.git" rev-list --merges main)"
set_conf 'LAND_TEST_CMD=true'

echo "## group mode (a batch coordinator): --group and LAND_LOCK_HELD"
set_conf 'LAND_TEST_CMD=test -z "$LAND_LOCK_HELD"' 'LAND_PROD_PATHS=src' 'LAND_BUDGET_LINES=3'
worker gp1; mkdir -p "$T/gp1/src"; seq 1 40 > "$T/gp1/src/f"; git -C "$T/gp1" add src; git -C "$T/gp1" commit -qm "feat: big entry" -m "Task-ID: t"
refused "over the budget without --group is refused" 1 "$T/gp1"
before=$(remote_head); ( cd "$T/gp1" && "$L" --group >"$T/out" 2>&1 ) && rc=0 || rc=$?; [ "$rc" = 0 ] && pass "--group waives the size budget (the coordinator checked each entry)" || { fail "--group: exit $rc"; cat "$T/out" >&2; }
out_has "by --group"
worker gp2; commit "$T/gp2" gp2.txt 1
mkdir -p "$T/gp2/.git/vbm-land"; ( exec 8>"$T/gp2/.git/vbm-land/lock"; flock 8; sleep 6 ) & holder=$!; sleep 0.3
refused "another holder of the lock: busy" 15 "$T/gp2" LAND_LOCK_WAIT_SECONDS=1
lands "LAND_LOCK_HELD=1: the caller holds the lock, none is taken; Tier 1 does not inherit the variable" "$T/gp2" LAND_LOCK_HELD=1; out_has "the caller holds the lock"
kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
set_conf 'LAND_TEST_CMD=true'

echo "## known flaky: a listed failure is rerun once"
gh_mode ok
seed_push scripts/known-flaky.txt "# name owner expiry issue
test_flaky.sh alice 2099-01-01 123
test_other_flaky.sh alice 2099-01-01 124
test_old.sh bob 2000-01-01 5
test_bad.sh alice 2099-01-01"
set_conf 'LAND_TEST_CMD=true' 'LAND_KNOWN_FLAKY=scripts/known-flaky.txt' 'LAND_FLAKY_RERUN_WAIT=3'
kfcase() {   # kfcase LOGTEXT: a red main whose failed log is LOGTEXT; attempt 1, no refused rerun
  gh_mode red; rm -f "$T/gh/attempt" "$T/gh/rerun_refused" "$T/gh/rerun_conclusion"; printf '%s\n' "$1" > "$T/gh/failedlog"; : > "$T/gh/calls.log"
}
reran() { grep -c 'run rerun' "$T/gh/calls.log" || true; }
kfcase "FAIL scripts/test_flaky.sh: exit 1"; worker kf1; commit "$T/kf1" kf1.txt 1
lands "a failure naming only a listed test: rerun once, green: not red, lands" "$T/kf1"; out_has "rerunning the failed job once"; check "exactly one rerun was asked for" test "$(reran)" = 1
check "the rerun is logged" grep -q "known-flaky test_flaky.sh: rerun --failed: green" "$T/kf1/.git/vbm-land/known-flaky.log"
kfcase "FLAKY scripts/test_flaky.sh
FAIL scripts/test_other_flaky.sh"; echo failure > "$T/gh/rerun_conclusion"; worker kf2; commit "$T/kf2" kf2.txt 1
refused "listed, but the rerun is red: red main refuses" 10 "$T/kf2"; out_has "rerun of 100"; out_has ": red"
kfcase "FAIL scripts/test_unlisted.sh"; worker kf3; commit "$T/kf3" kf3.txt 1
refused "an unlisted failure is not rerun: red" 10 "$T/kf3"; out_has "not on the known-flaky list"; check "and no rerun was asked for" test "$(reran)" = 0
kfcase "FAIL scripts/test_flaky.sh
FAIL scripts/test_unlisted.sh"; worker kf4; commit "$T/kf4" kf4.txt 1
refused "listed AND unlisted failures: red" 10 "$T/kf4"; check "no rerun" test "$(reran)" = 0
kfcase "FAIL scripts/test_old.sh"; worker kf5; commit "$T/kf5" kf5.txt 1
refused "an expired entry is not listed: red" 10 "$T/kf5"; check "no rerun" test "$(reran)" = 0
kfcase "FAIL scripts/test_bad.sh"; worker kf6; commit "$T/kf6" kf6.txt 1
refused "a malformed entry (no issue) is not listed: red" 10 "$T/kf6"; check "no rerun" test "$(reran)" = 0
kfcase "FAIL scripts/test_flaky.sh"; echo 2 > "$T/gh/attempt"; echo failure > "$T/gh/rerun_conclusion"; worker kf7; commit "$T/kf7" kf7.txt 1
refused "a run that was already rerun is never rerun again: red" 10 "$T/kf7"; out_has "already rerun"; check "no rerun" test "$(reran)" = 0
kfcase "FAIL scripts/test_flaky.sh"; touch "$T/gh/rerun_refused"; worker kf8; commit "$T/kf8" kf8.txt 1
refused "a refused rerun is red" 10 "$T/kf8"; out_has "refused"
kfcase "FAIL scripts/test_unlisted_by_main.sh"; worker kf9; commit "$T/kf9" scripts/known-flaky.txt "test_unlisted_by_main.sh me 2099-01-01 1"
refused "a change cannot list its own flaky test: the list is main's" 10 "$T/kf9"; check "no rerun" test "$(reran)" = 0
kfcase "FAIL scripts/test_flaky.sh"; worker kf10; commit "$T/kf10" kf10.txt 1 "fix(tests): repair"
lands "a fix lands on a red main without a rerun being needed" "$T/kf10" LAND_FIX_FOR_RED=1

echo "## Tier 2 freeze, read from the CI runs"
rm -f "$T/gh/failedlog" "$T/gh/attempt" "$T/gh/rerun_refused" "$T/gh/rerun_conclusion"
set_conf 'LAND_TEST_CMD=true' 'LAND_TIER2_JOB=tier2' 'LAND_FIX_PATHS=tests/*'
gh_mode t2red; worker tf1; commit "$T/tf1" tf1.txt 1
refused "Tier 1 green but Tier 2 failed: landing is frozen (14)" 14 "$T/tf1"; out_has "FROZEN"; check "the marker names land-red as its owner and has an expiry" bash -c "grep -q '^owner=land-red' '$T/tf1/.git/vbm-land/freeze' && grep -q '^expires=[0-9]' '$T/tf1/.git/vbm-land/freeze'"
worker tf2; commit "$T/tf2" tests/tier2-fix.sh 1 "fix(tests): repair"
lands "a fix lands on the frozen main" "$T/tf2"; check "and lifted the freeze" test ! -e "$T/tf2/.git/vbm-land/freeze"
gh_mode t2red; printf 'fatal: unable to access https://x/: Could not resolve host\n' > "$T/gh/failedlog"; worker tf3; commit "$T/tf3" tf3.txt 1
lands "a Tier 2 failure that is the infrastructure's does not freeze" "$T/tf3"; out_has "not freezing"; rm -f "$T/gh/failedlog"
gh_mode t2red; worker tf4; commit "$T/tf4" tf4.txt 1; ( cd "$T/tf4" && "$L" >/dev/null 2>&1 ) || true
gh_mode ok; lands "a green Tier 2 lifts the freeze that land-red set" "$T/tf4"; out_has "freeze is lifted"
worker tf5; commit "$T/tf5" tf5.txt 1; ( cd "$T/tf5" && "$L" --freeze "person" --owner alice --for 1h >/dev/null )
refused "a green Tier 2 never lifts a freeze a person set" 14 "$T/tf5"
set_conf 'LAND_TEST_CMD=true'

echo "## never force, never prune"
check "no force push in the lander" bash -c "! grep -nE -- '--force|push +-f|push[^#]*\\+(refs|\\\$)' '$L' | grep -v 'no force\\|never'"
check "no worktree prune in the lander" bash -c "! grep -n 'worktree prune' '$L' '$ROOT/bin/land-red' | grep -v ':[0-9]*:[^#]*#'"
worker s1; git -C "$T/s1" worktree add -q "$T/s1-other" -b other; commit "$T/s1" s.txt 1
lands "lands in a clone that has another worktree" "$T/s1"; check "the other worktree is untouched" test -e "$T/s1-other/.git"
check "its registration is still there" bash -c "git -C '$T/s1' worktree list | grep -q s1-other"
# a plain (non-fast-forward) push is refused by the remote: no force exists to get around it
worker nf; commit "$T/nf" nf.txt 1
git -C "$T/remote.git" config receive.denyNonFastForwards true
check "the remote would refuse a non-fast-forward push (and the lander only ever pushes fast-forwards)" bash -c "cd '$T/nf' && git reset -q --hard HEAD~3 2>/dev/null; ! git push -q origin HEAD:main 2>/dev/null"

echo "## another base branch"
sandbox master
set_conf 'LAND_TEST_CMD=true' 'LAND_BASE=master'
worker ma; commit "$T/ma" ma.txt 1
lands "a repository whose base is master lands" "$T/ma"; check "it is on master" remote_has ma.txt
finish
