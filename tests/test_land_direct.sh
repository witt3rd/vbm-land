#!/usr/bin/env bash
# bin/land-direct against scratch repositories with a bare remote. Every refusal has a negative test: what must be refused is refused (with
# its exit code and a message naming the cause), and NOTHING reaches the remote when it is refused.
. "$(dirname "$0")/lib.sh"
sandbox
L=$ROOT/bin/land-direct
export RED_SLEEP=true
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
# a key this tool has retired is not a key: an old config naming one is refused as unknown, by file and line, and nothing lands
for key in LAND_LOCK_WAIT LAND_CI_WORKFLOW LAND_TIER1_JOB LAND_RED_MODE LAND_RED_WAIT LAND_KNOWN_FLAKY LAND_FLAKY_RERUN_WAIT LAND_TIER2_JOB LAND_APPROVALS \
           LAND_APPROVAL_DAYS LAND_PROTECTED_LIST LAND_PROTECTED_APPROVALS LAND_GATE_APPEND_ONLY LAND_PROD_PATHS LAND_BUDGET_LINES; do
  set_conf 'LAND_TEST_CMD=true' "$key=x"
  worker "c3-$key"; commit "$T/c3-$key" c3.txt 1
  refused "the retired key $key is refused as unknown (not read and ignored)" 2 "$T/c3-$key"; out_has "unknown key $key"
  check "the refusal names the file it was read from and the line" grep -qF "origin/main:$LAND_CONF_FILE:2: unknown key $key" "$T/out"
done
set_conf 'LAND_TEST_CMD=true'
set_conf 'LAND_TEST_CMD=true' 'LAND_REGEN_CMD=$(touch /tmp/vbm-land-injected)'   # data, never evaluated at read time (and a regeneration command only runs after a conflict)
worker c4; commit "$T/c4" x.txt 1
( cd "$T/c4" && "$L" >"$T/out" 2>&1 ) || true; check "reading the config executes nothing" test ! -e /tmp/vbm-land-injected; rm -f /tmp/vbm-land-injected

echo "## first landing: the base has no config yet, the working tree's is used"
sandbox
worker f1; mkdir -p "$T/f1/$(dirname "$LAND_CONF_FILE")"; echo 'LAND_TEST_CMD=true' > "$T/f1/$LAND_CONF_FILE"; git -C "$T/f1" add "$LAND_CONF_FILE"; git -C "$T/f1" commit -qm "chore: add $LAND_CONF_FILE"
lands "the first landing (config only in the working tree) lands" "$T/f1"; out_has "has no $LAND_CONF_FILE yet"

echo "## landing"
sandbox
set_conf 'LAND_TEST_CMD=test ! -e BAD' 'LAND_REQUIRE_TRAILERS=Task-ID'
worker a; commit "$T/a" one.txt 1
lands "lands one commit" "$T/a"; out_has '"result":"landed"'
check "main has it" remote_has one.txt
check "JSON last line names sha, commits, tier1_seconds, result, exit" bash -c "tail -n1 '$T/out' | grep -qE '^\\{\"sha\":\"[0-9a-f]{40}\",\"commits\":1,\"tier1_seconds\":[0-9]+,\"result\":\"landed\",\"exit\":0\\}$'"
check "a metrics line is written" bash -c "grep -q '\"result\":\"landed\"' '$T/a/.git/vbm-land/metrics.jsonl'"
worker a2; commit "$T/a2" two.txt 2; before=$(remote_head)
( cd "$T/a2" && "$L" --validate >"$T/out" 2>&1 ) || true; out_has "validated"; check "--validate pushes nothing" nothing_landed
( cd "$T/a2" && "$L" --check >"$T/out" 2>&1 ) || true; out_has '"result":"checked"'; check "--check pushes nothing" nothing_landed
worker a3; git -C "$T/a3" commit -q --allow-empty -m "chore: nothing" -m "Task-ID: t"; git -C "$T/a3" reset -q --hard origin/main
refused "nothing to land refuses" 2 "$T/a3"
worker a4; commit "$T/a4" m1.txt 1; git -C "$T/a4" checkout -q -b side HEAD~1; commit "$T/a4" m2.txt 2; git -C "$T/a4" merge -q --no-ff --no-edit main 2>/dev/null || git -C "$T/a4" merge -q --no-ff -m "chore: merge" -m "Task-ID: m" main 2>/dev/null || true
git -C "$T/a4" checkout -q main 2>/dev/null; git -C "$T/a4" merge -q --no-ff -m "chore: merge" side 2>/dev/null || true
if [ -n "$(git -C "$T/a4" rev-list --merges origin/main..HEAD)" ]; then refused "merge commits are refused (history lands linear)" 2 "$T/a4"; else pass "merge-commit setup unavailable here (skipped)"; fi

echo "## config comes from the base branch, never from the change"
worker g1; mkdir -p "$T/g1"; : > "$T/g1/BAD"; printf 'LAND_TEST_CMD=true\n' > "$T/g1/$LAND_CONF_FILE"
git -C "$T/g1" add -A; git -C "$T/g1" commit -qm "feat: bad file and a loosened config" -m "Task-ID: t"
refused "a change that loosens $(basename "$LAND_CONF_FILE") is still judged by main's" 13 "$T/g1"

echo "## land-time checks"
worker k; echo 1 > "$T/k/x.txt"; git -C "$T/k" add x.txt; git -C "$T/k" commit -qm "not conventional" -m "Task-ID: t"
refused "a non-Conventional subject refuses" 1 "$T/k"; out_has "not a Conventional Commit"
worker k2; echo 1 > "$T/k2/x.txt"; git -C "$T/k2" add x.txt; git -C "$T/k2" commit -qm "feat: no trailer"
refused "a missing required trailer refuses" 1 "$T/k2"; out_has "no 'Task-ID:' trailer"
worker k3; commit "$T/k3" r.txt 1 'Revert "feat: something"'
lands "git's own Revert \"...\" subject is accepted (no divergence between the subject check and the red rule)" "$T/k3"
echo "## a signing keys file that exists changes only by its owner"
set_conf 'LAND_TEST_CMD=true'; seed_push scripts/x.signers "k1"
worker sg1; echo k2 > "$T/sg1/scripts/x.signers"; git -C "$T/sg1" add -A; git -C "$T/sg1" commit -qm "feat: swap the signing key" -m "Task-ID: t"
refused "an existing signing keys file changed by an agent is refused" 12 "$T/sg1"
worker sg2; echo k > "$T/sg2/scripts/new.signers"; git -C "$T/sg2" add -A; git -C "$T/sg2" commit -qm "feat: a first signers file" -m "Task-ID: t"
lands "a first signing keys file (an install) lands" "$T/sg2"
worker k5; mkdir -p "$T/k5/src"; seq 1 200 > "$T/k5/src/big.txt"; git -C "$T/k5" add src; git -C "$T/k5" commit -qm "feat: big" -m "Task-ID: t"
lands "there is no size budget to be over (its keys are retired): a change of 200 lines lands" "$T/k5"

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

echo "## the retry loop: lost races are retried within bounds; a crash after an accepted push is a rerun that lands nothing twice"
sandbox
set_conf 'LAND_TEST_CMD=echo "$LAND_ATTEMPT:$LAND_PREV_BASE:$(git rev-parse HEAD~1)" >> '"$T/att.txt"
worker rl1; commit "$T/rl1" rl1.txt 1; race_hook 3
lands "a push lost to three competitors is retried and lands on the fourth attempt" "$T/rl1"
check "main has the competitors' three commits and then ours, linear" bash -c "[ \$(git -C '$T/remote.git' rev-list --count main) = \$((\$(git -C '$T/remote.git' rev-list --count main~4) + 4)) ] && git -C '$T/remote.git' cat-file -e main:rl1.txt && [ -z \"\$(git -C '$T/remote.git' rev-list --merges main)\" ]"
attempts_ok() { [ "$(wc -l < "$T/att.txt")" = 4 ] && [ "$(sed -n 1p "$T/att.txt" | cut -d: -f1,2)" = "1:" ] && [ "$(sed -n 4p "$T/att.txt" | cut -d: -f1)" = 4 ] \
  && [ "$(sed -n 2p "$T/att.txt" | cut -d: -f2)" = "$(sed -n 1p "$T/att.txt" | cut -d: -f3)" ] && [ "$(sed -n 4p "$T/att.txt" | cut -d: -f2)" = "$(sed -n 3p "$T/att.txt" | cut -d: -f3)" ]; }
check "Tier 1 saw LAND_ATTEMPT 1..4 and LAND_PREV_BASE = the base the previous attempt validated against (empty at first)" attempts_ok
check "the metrics line has the attempts (4) and the commit id handed over" bash -c "tail -n1 '$T/rl1/.git/vbm-land/metrics.jsonl' | grep -q '\"attempts\":4' && tail -n1 '$T/rl1/.git/vbm-land/metrics.jsonl' | grep -q '\"commit\":\"'\$(git -C '$T/rl1' rev-parse HEAD)'\"'"
before=$(git -C "$T/remote.git" rev-list --count main)
( cd "$T/rl1" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "run again after that landing (a crash after the accepted push looks the same): exit 0, 'already landed', nothing pushed" bash -c "[ $rc = 0 ] && grep -q 'already landed' '$T/out' && [ \$(git -C '$T/remote.git' rev-list --count main) = $before ]"
rm -f "$T/remote.git/hooks/pre-receive"; set_conf 'LAND_TEST_CMD=true' 'LAND_ATTEMPTS=3'
worker rl2; commit "$T/rl2" rl2.txt 1; race_hook 99
( cd "$T/rl2" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "main moving at every push: exit 16 after the attempts, nothing of ours on main" bash -c "[ $rc = 16 ] && ! git -C '$T/remote.git' cat-file -e main:rl2.txt"
out_has "moved faster than I could validate: 3 attempt(s)"; check "the JSON says moved" bash -c "tail -n1 '$T/out' | grep -q '\"result\":\"moved\",\"exit\":16'"
rm -f "$T/remote.git/hooks/pre-receive"; set_conf 'LAND_TEST_CMD=sleep 2' 'LAND_DEADLINE=1'
worker rl3; commit "$T/rl3" rl3.txt 1; race_hook 99
( cd "$T/rl3" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a Tier 1 that outlasts LAND_DEADLINE is not run again: exit 16 after one attempt" bash -c "[ $rc = 16 ] && grep -q 'moved faster than I could validate: 1 attempt(s)' '$T/out'"
rm -f "$T/remote.git/hooks/pre-receive"; set_conf 'LAND_TEST_CMD=true'
worker rl4; commit "$T/rl4" rl4.txt 1; printf '#!/bin/sh\necho x >> "%s/rej.count"\necho "remote: refused by policy" >&2\nexit 1\n' "$T" > "$T/remote.git/hooks/pre-receive"; chmod +x "$T/remote.git/hooks/pre-receive"
( cd "$T/rl4" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a push refused while main has not moved is final: exit 1, tried once, the remote's reason shown" bash -c "[ $rc = 1 ] && [ \$(wc -l < '$T/rej.count') = 1 ] && grep -q 'has not moved: not retrying' '$T/out' && grep -q 'refused by policy' '$T/out'"
rm -f "$T/remote.git/hooks/pre-receive"
# a push that the remote accepted but whose report is lost (a timeout): the lander asks the remote and finds its commit in the base
mkdir -p "$T/shim2"; printf '#!/usr/bin/env bash\ncase " $* " in *" push "*) %s "$@"; exit 124;; esac\nexec %s "$@"\n' "$(command -v git)" "$(command -v git)" > "$T/shim2/git"; chmod +x "$T/shim2/git"
worker rl5; commit "$T/rl5" rl5.txt 1
lands "a push that timed out after the remote accepted it is found in the base: landed" "$T/rl5" PATH="$T/shim2:$PATH"; out_has "is in main: landed"; check "and it is on main once" bash -c "[ \$(git -C '$T/remote.git' log --format=%s main | grep -c 'change rl5.txt') = 1 ]"
set_conf 'LAND_TEST_CMD=true' 'LAND_ATTEMPTS=0'
worker rl6; commit "$T/rl6" rl6.txt 1
refused "LAND_ATTEMPTS=0 is a bad configuration" 2 "$T/rl6"; out_has "LAND_ATTEMPTS"
# the base of an attempt is pinned when it starts: another lander of the clone moves the shared origin/main ref (here a pre-rebase hook does, once, between the fetch and the rebase);
# this attempt must still be built on the base it fetched, and notice at the end that the ref moved: a second attempt
sandbox
set_conf 'LAND_TEST_CMD=echo "$LAND_ATTEMPT:$LAND_PREV_BASE:$(git rev-parse HEAD~1)" >> '"$T/pin.txt"
seed_exec "$LAND_HOOKS_DEFAULT/pre-rebase" "#!/usr/bin/env bash
[ ! -e '$T/pin.flag' ] || exit 0
: > '$T/pin.flag'
( cd '$T/seed' && git pull -q origin main && echo c > competitor.txt && git add competitor.txt && git commit -qm 'chore: competitor' -m 'Task-ID: c' && git push -q origin main )
git -C \"\$LAND_TOP\" fetch -q origin main"
worker pn1; commit "$T/pn1" pn1.txt 1
lands "the shared origin/main ref moving under a run does not change the base of its attempt: it lands after a second attempt" "$T/pn1"; out_has "moved during Tier 1"
pinned_ok() { [ "$(wc -l < "$T/pin.txt")" = 2 ] && [ "$(sed -n 2p "$T/pin.txt" | cut -d: -f2)" = "$(sed -n 1p "$T/pin.txt" | cut -d: -f3)" ] && [ "$(sed -n 1p "$T/pin.txt" | cut -d: -f3)" != "$(sed -n 2p "$T/pin.txt" | cut -d: -f3)" ]; }
check "attempt 1 ran on the base it had fetched (not the moved ref); attempt 2 on the new one, its LAND_PREV_BASE the first" pinned_ok
sandbox   # a clean world again for what follows

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
set_conf 'LAND_TEST_CMD=true' 'LAND_PROTECTED=bin/* lib/*'
worker h3; commit "$T/h3" tests/t.sh 1 "fix(tests): repair"; ( cd "$T/h3" && "$L" --freeze "tier 2 broke" --owner alice --for 1h ) >/dev/null
lands "a fix lands on a frozen base" "$T/h3"; out_has "frozen; this change is a fix"
check "landing the fix does not lift a person's freeze" test -e "$T/h3/.git/vbm-land/freeze"
worker h4; commit "$T/h4" h4.txt 1
( cd "$T/h4" && "$L" --freeze "again" --owner bob --for 1s ) >/dev/null; sleep 2
lands "an expired freeze is not in force" "$T/h4"
( cd "$T/h2" && "$L" --freeze "again" --owner bob --for 1h && "$L" --thaw ) >/dev/null 2>&1; check "--thaw clears it" test ! -e "$T/h2/.git/vbm-land/freeze"

echo "## a red main does not stop landing; a freeze does, but for a fix or a revert (recognised by the commit subject alone)"
gh_mode red; : > "$T/gh/calls.log"
worker r1; commit "$T/r1" r1.txt 1
lands "a red main (CI says its Tier 1 failed) does not refuse an ordinary change" "$T/r1"
check "and the lander asked nobody (no gh call per landing)" test ! -s "$T/gh/calls.log"
gh_mode fail; worker r2; commit "$T/r2" r2.txt 1
lands "a CI that cannot be read changes nothing either" "$T/r2"
freeze_in() { ( cd "$T/$1" && "$L" --freeze "operator's freeze" --owner operator --for 1h ) >/dev/null; }   # each worker is a clone of its own, with its own markers
worker r3; commit "$T/r3" other/code.txt 1 "fix(unrelated): the subject alone decides, no scope list"; freeze_in r3
lands "a fix(<scope>) subject lands whatever paths it touches (a fix is recognised by its subject, not its paths)" "$T/r3"; out_has "frozen; this change is a fix"
worker r4; commit "$T/r4" lib/x.sh 1 "fix(ci): a scope list is not required"; freeze_in r4
lands "any scope counts (fix(ci):), not just ci and tests" "$T/r4"; out_has "frozen; this change is a fix"
worker r9; commit "$T/r9" tests/plain.sh 1 "fix: no scope at all"; freeze_in r9
lands "a bare fix: subject (no scope) lands on a frozen main" "$T/r9"; out_has "frozen; this change is a fix"
worker r5; commit "$T/r5" tests/new.sh 1 "fix(tests): real fix"; freeze_in r5
lands "a fix lands on a frozen main" "$T/r5"; out_has "frozen; this change is a fix"
worker r3b; commit "$T/r3b" tests/x.sh 1 "feat(tests): not a fix, whatever it touches"; freeze_in r3b
refused "a change touching only test paths is not a fix without a fix subject: the freeze refuses it" 14 "$T/r3b"
worker r6; commit "$T/r6" r6.txt 1; freeze_in r6
lands "LAND_FIX_FOR_RED=1 is the operator's override of a freeze" "$T/r6" LAND_FIX_FOR_RED=1
worker r7; freeze_in r7
( cd "$T/r7" && git revert --no-edit HEAD >/dev/null 2>&1 && git commit -q --amend -m "Revert \"x\"" -m "This reverts commit sha." -m "Task-ID: t" )
lands "a Revert subject lands on a frozen main" "$T/r7"
worker r7b; freeze_in r7b
( cd "$T/r7b" && git commit -q --allow-empty -m "revert: lower case" -m "Task-ID: t" )
lands "a subject starting revert (lower case) lands too" "$T/r7b"
worker r8; commit "$T/r8" lib/y.sh 1 'test: a conventional subject that is not a fix'; freeze_in r8
refused "a conventional subject that is not fix:/Revert/revert is not a fix" 14 "$T/r8"
worker r8b; commit "$T/r8b" lib/z.sh 1 'chore(land): a scoped non-fix'; freeze_in r8b
refused "a scope alone does not make a fix (chore(<scope>): is refused)" 14 "$T/r8b"
set_conf 'LAND_TEST_CMD=true'

echo "## inherited red: a landing must not ADD a failure; one already on main is not its fault"
sandbox
set_conf 'LAND_GATES_CMD=[ ! -e OLDGATE ] || { echo "FAIL gate-old: broken on main"; exit 1; }' 'LAND_TEST_CMD=rc=0; [ ! -e OLD ] || { echo "FAIL old: broken on main"; rc=1; }; [ ! -e NEW ] || { echo "FAIL new: mine"; rc=1; }; [ ! -e SILENT ] || rc=1; exit $rc'
seed_push OLD 1; seed_push OLDGATE 1
worker ih1; commit "$T/ih1" ih1.txt 1
lands "main is red in tests and the change is unrelated: Tier 1 fails only with main's own failures: it lands" "$T/ih1"; out_has "inherited red"
flagged() { tail -n1 "$1/.git/vbm-land/metrics.jsonl" | grep -q "\"inherited_red\":$2"; }
both_stages() { [ "$(grep -c 'inherited red' "$T/out")" = 2 ]; }
check "the metrics line flags it" flagged "$T/ih1" true
check "the gates stage failed with main's failure and the tests stage still ran, also with main's failure" both_stages
worker ih2; commit "$T/ih2" NEW 1
refused "a change that adds its own failure to a red main is refused, and the new failure is named" 13 "$T/ih2"; out_has "a failure main does not have: FAIL new"
worker ih4; git -C "$T/ih4" rm -q OLD OLDGATE; git -C "$T/ih4" commit -qm "fix: repair main" -m "Task-ID: t1"
lands "the change that repairs main passes green, nothing inherited" "$T/ih4"; check "and did not flag inheritance" flagged "$T/ih4" false
worker ih3; commit "$T/ih3" SILENT 1
refused "a failure with no recognisable failure line (main is green here) is never inherited" 13 "$T/ih3"
sandbox

echo "## hooks (taken from main, so a change cannot rewrite the rules it is judged by)"
gh_mode ok
set_conf 'LAND_TEST_CMD=true' 'LAND_PROTECTED=guarded/*'
seed_exec "$LAND_HOOKS_DEFAULT/post-rebase" '#!/usr/bin/env bash
[ -z "$LAND_PROTECTED_TOUCHED" ] || { echo "hook: protected file touched: $LAND_PROTECTED_TOUCHED"; exit 1; }
grep -q . "$LAND_TOUCHED_FILE" || exit 1'
seed_exec "$LAND_HOOKS_DEFAULT/json-fields" '#!/usr/bin/env bash
echo "extra_metric=42"; echo "label=ok-1"; echo "bad key=1"; echo "sha=evil"; echo "text=has spaces"'
worker o1; commit "$T/o1" guarded/g.txt 1
refused "a post-rebase hook refuses a protected-set change" 12 "$T/o1"; out_has "protected file touched: guarded/g.txt"; out_has "protected set: TOUCHED"
worker o2; commit "$T/o2" guarded/g.txt 1; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/o2/$LAND_HOOKS_DEFAULT/post-rebase"; git -C "$T/o2" add -A; git -C "$T/o2" commit -qm "feat: also neuter the hook" -m "Task-ID: t"
refused "a change that rewrites the hook is still judged by main's hook" 12 "$T/o2"
worker o3; commit "$T/o3" free.txt 1
lands "an unprotected change passes the hook" "$T/o3"
check "json-fields adds numeric and safe string keys" bash -c "tail -n1 '$T/out' | grep -q '\"extra_metric\":42,\"label\":\"ok-1\"'"
check "json-fields cannot override the contract keys or add junk" bash -c "tail -n1 '$T/out' | grep -vq 'evil' && tail -n1 '$T/out' | grep -q '\"text\":null'"
seed_exec "$LAND_HOOKS_DEFAULT/pre-rebase" '#!/usr/bin/env bash
test ! -e NOPE'
worker o4; commit "$T/o4" NOPE 1
refused "a pre-rebase hook can refuse (exit 12)" 12 "$T/o4"
seed_exec "$LAND_HOOKS_DEFAULT/post-tier1" '#!/usr/bin/env bash
test ! -e NOPE2'
worker o5; commit "$T/o5" NOPE2 1
refused "a post-tier1 hook can refuse (exit 12)" 12 "$T/o5"
seed_exec "$LAND_HOOKS_DEFAULT/on-run" '#!/usr/bin/env bash
echo "$LAND_RESULT" >> "$LAND_STATE_DIR/on-run.log"'
worker o6; commit "$T/o6" o6.txt 1
lands "an on-run hook sees every run" "$T/o6"; check "on-run saw the result" grep -q landed "$T/o6/.git/vbm-land/on-run.log"

echo "## per-run directory: every run writes only in its own"
sandbox
set_conf 'LAND_TEST_CMD=echo "$LAND_RUN_DIR" >> '"$T/runs.txt"'; [ "$(pwd -P)" = "$(cd "$LAND_RUN_DIR/wt" && pwd -P)" ]; test ! -e "$LAND_STATE_DIR/wt"'
worker u1; commit "$T/u1" u1.txt 1
lands "Tier 1 runs inside this run's own scratch worktree" "$T/u1"
git -C "$T/u1" fetch -q origin; git -C "$T/u1" reset -q --hard origin/main; commit "$T/u1" u2.txt 2
lands "and so does the next run in the same clone" "$T/u1"
v=$T/u1/.git/vbm-land
distinct_run_dirs() { [ "$(sort -u "$T/runs.txt" | wc -l)" = 2 ] && ! grep -vE "^$v/run\\.[0-9]+\\.[A-Za-z0-9]+\$" "$T/runs.txt"; }
nothing_left() { [ -z "$(ls "$1/.git/vbm-land" | grep '^run\.' || true)" ] && [ "$(git -C "$1" worktree list | wc -l)" = 1 ]; }
check "two runs got two different run directories, both inside the clone's vbm-land/" distinct_run_dirs
check "after a landing no run directory and no worktree registration is left" nothing_left "$T/u1"
set_conf 'LAND_TEST_CMD=echo tier1-evidence; false'
worker u3; commit "$T/u3" u3.txt 1; v=$T/u3/.git/vbm-land
( cd "$T/u3" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
only_the_log() { [ "$rc" = 13 ] && grep -q tier1-evidence "$v"/run.*/tier1.tests.log && [ "$(ls "$v"/run.*/ | wc -l)" = 1 ] && [ "$(git -C "$T/u3" worktree list | wc -l)" = 1 ]; }
check "a failed run leaves its log and nothing else (no worktree), for diagnosis" only_the_log
# leftovers: a dead pid's old directory is swept by the next run; a young one, a live pid's and a name without a pid are kept; a symlink is never followed
sleep 300 & alive=$!; true & gone=$!; wait "$gone"
mkdir "$v/run.$gone.old" "$v/run.$gone.new" "$v/run.$alive.old" "$v/run.junk.old" "$T/precious"; echo keep > "$T/precious/f"; ln -s "$T/precious" "$v/run.$gone.link"
touch -d '2 days ago' "$v/run.$gone.old" "$v/run.$alive.old" "$v/run.junk.old"; touch -h -d '2 days ago' "$v/run.$gone.link"
( cd "$T/u3" && "$L" --validate >/dev/null 2>&1 ) || true
kill "$alive" 2>/dev/null || true; wait "$alive" 2>/dev/null || true
check "the next run sweeps a dead run's old directory" test ! -e "$v/run.$gone.old"
check "it keeps a young directory, a live pid's and a name without a pid" bash -c "[ -d '$v/run.$gone.new' ] && [ -d '$v/run.$alive.old' ] && [ -d '$v/run.junk.old' ]"
check "it never follows a symlink out of the clone" bash -c "[ -L '$v/run.$gone.link' ] && [ -e '$T/precious/f' ]"
set_conf 'LAND_TEST_CMD=true'
echo "## no lock: a stale lock file means nothing, runs in one clone race and both land, the retired lock settings are refused as an unknown key"
worker b1; commit "$T/b1" b.txt 1; v=$T/b1/.git/vbm-land; mkdir -p "$v"
( exec 8>"$v/lock"; flock 8; sleep 20 ) & holder=$!   # a lock file somebody holds, and a lease that looks like a live, silent holder: the lander must not look at either
printf 'pid=%s start=1 task=t at=1\n' "$holder" > "$v/lease"; touch -d '2 hours ago' "$v/lease"; sleep 0.3
lands "a held lock file and a lease that looks live change nothing: it lands" "$T/b1"; check "nothing waited for a lock" bash -c "! grep -qi 'lock' '$T/out'"
check "and nothing terminated the holder" kill -0 "$holder"
kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
worker b2; commit "$T/b2" b2.txt 1
lands "the retired lock environment names are not policy: set, they change nothing (a policy key is never read from the environment)" "$T/b2" LAND_LOCK_WAIT_SECONDS=1 LAND_LEASE_STALE_SECONDS=1
check "and nothing was named as ignored (there is no shim left to name it)" bash -c "! grep -qi 'ignored' '$T/out'"
set_conf 'LAND_TEST_CMD=true' 'LAND_LOCK_WAIT=30'
worker b3; commit "$T/b3" b3.txt 1
refused "a $(basename "$LAND_CONF_FILE") that still has LAND_LOCK_WAIT is refused as an unknown key" 2 "$T/b3"; out_has "unknown key LAND_LOCK_WAIT"
set_conf 'LAND_TEST_CMD=true'
worker p1; git -C "$T/p1" worktree add -q "$T/p2" -b p2 origin/main; git -C "$T/p2" config commit.gpgsign false; commit "$T/p1" p1.txt 1; commit "$T/p2" p2.txt 2   # two worktrees of ONE clone share its .git
set_conf 'LAND_TEST_CMD=echo "$LAND_RUN_DIR" >> '"$T/race-runs.txt"'; sleep 1'
( cd "$T/p1" && "$L" >"$T/p1.out" 2>&1 ) & q1=$!; ( cd "$T/p2" && "$L" >"$T/p2.out" 2>&1 ) & q2=$!
rc1=0; rc2=0; wait $q1 || rc1=$?; wait $q2 || rc2=$?
check "two racing runs of one clone both land" bash -c "[ $rc1 = 0 ] && [ $rc2 = 0 ] && git -C '$T/remote.git' cat-file -e main:p1.txt && git -C '$T/remote.git' cat-file -e main:p2.txt"
check "history stays linear" test -z "$(git -C "$T/remote.git" rev-list --merges main)"
check "the two racing runs used two different run directories" bash -c "[ \$(sort -u '$T/race-runs.txt' | wc -l) = 2 ]"
# landers of one clone fetch into the same remote-tracking ref and git refuses the loser: a shim `git` refuses fetches with a message of the test's choosing; the lander must retry that refusal and no other
mkdir -p "$T/shim"; cat > "$T/shim/git" <<SHIM
#!/usr/bin/env bash
case " \$* " in *" fetch "*) echo x >> "\$SHIM_LOG"; if [ -n "\${SHIM_ALWAYS:-}" ] || [ ! -e "\$SHIM_LOG.done" ]; then : > "\$SHIM_LOG.done"; echo "\$SHIM_MSG" >&2; exit 1; fi;; esac
exec $(command -v git) "\$@"
SHIM
chmod +x "$T/shim/git"
worker fr1; commit "$T/fr1" fr1.txt 1
lands "a fetch refused with 'cannot lock ref' is retried and the landing goes through" "$T/fr1" PATH="$T/shim:$PATH" SHIM_LOG="$T/shim/log1" SHIM_MSG="error: cannot lock ref 'refs/remotes/origin/main': is at 1 but expected 2"
check "the shim really refused a fetch" test -e "$T/shim/log1.done"
worker fr2; commit "$T/fr2" fr2.txt 1
refused "a fetch that fails for any other reason stops the landing" 1 "$T/fr2" PATH="$T/shim:$PATH" SHIM_LOG="$T/shim/log2" SHIM_ALWAYS=1 SHIM_MSG="fatal: unable to access 'x'"
check "and it was not retried (one fetch, not eight)" test "$(wc -l < "$T/shim/log2")" = 1
set_conf 'LAND_TEST_CMD=true'

echo "## --group (a batch coordinator's entries)"
worker gp1; mkdir -p "$T/gp1/src"; seq 1 40 > "$T/gp1/src/f"; git -C "$T/gp1" add src; git -C "$T/gp1" commit -qm "feat: big entry" -m "Task-ID: t"
lands "a big entry lands, with --group the same as without it (no budget to waive)" "$T/gp1"

echo "## never force, never prune"
check "no force push in the lander" bash -c "! grep -nE -- '--force|push +-f|push[^#]*\\+(refs|\\\$)' '$L' | grep -v 'no force\\|never'"
check "no worktree prune in the lander" bash -c "! grep -Hn 'worktree prune' '$L' | grep -v ':[0-9]*:[^#]*#'"
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
