#!/usr/bin/env bash
# bin/land-revert (the watchdog) against scratch repositories with a bare remote: it finds the first failing commit by BISECTING with the repository's own Tier 1, reverts it as a true revert that
# lands through land-direct (on a red main too), widens to later commits that touch the same files (at most 5), alerts instead of guessing, and never reverts what it cannot reproduce.
. "$(dirname "$0")/lib.sh"
R=$ROOT/bin/land-revert; export RED_SLEEP=true
world() {   # world: a fresh sandbox whose Tier 1 fails while a file BAD exists; counts its own runs; an on-revert hook that logs its environment
  sandbox; rm -f "$T/t1.count"
  set_conf "LAND_TEST_CMD=echo x >> $T/t1.count; test ! -e BAD" 'LAND_REQUIRE_TRAILERS=Task-ID'
  seed_exec scripts/land.d/on-revert "#!/usr/bin/env bash
echo \"\$LAND_REVERT_RESULT culprit=\$LAND_REVERT_CULPRIT task=\$LAND_REVERT_TASK author=\$LAND_REVERT_AUTHOR shas=\$LAND_REVERT_SHAS\" >> '$T/hook.log'"
  good=$(remote_head)
}
wr() { local f=$1; shift; seed_push "$f" "$@"; }   # a commit on the remote's main
run_rv() { ( cd "$T/r" && "$R" "$@" >"$T/out" 2>&1 ) && rc=0 || rc=$?; }
tip_files() { git -C "$T/remote.git" ls-tree -r --name-only main | tr '\n' ' '; }

echo "## bisect: the first failing of sixteen commits is found with few Tier 1 runs, reverted and landed on a red main"
world; gh_mode red
for i in $(seq 1 10); do wr "f$i.txt" "$i" "feat: c$i"; done; wr BAD x "feat: c11 breaks it"; culprit=$(remote_head)
for i in $(seq 12 16); do wr "f$i.txt" "$i" "feat: c$i"; done; bad=$(remote_head); before=$(git -C "$T/remote.git" rev-list --count main)
worker r; : > "$T/t1.count"; run_rv --bad "$bad" --good "$good"
[ "$rc" = 0 ] && pass "land-revert exits 0 (exit $rc)" || { fail "land-revert: exit $rc"; sed 's/^/     | /' "$T/out" >&2; }
out_has "the first failing commit of 16 is ${culprit:0:12}"; check "the JSON says reverted, one commit" bash -c "tail -n1 '$T/out' | grep -q '\"result\":\"reverted\",\"culprit\":\"$culprit\",\"reverted\":1,\"exit\":0'"
only_c11_gone() { ! git -C "$T/remote.git" cat-file -e main:BAD && for i in $(seq 1 10) $(seq 12 16); do remote_has "f$i.txt" || return 1; done; }
check "main has no BAD file and keeps every other commit's file" only_c11_gone
check "one revert commit on top, a true revert naming the culprit, carrying its Task-ID, linear" bash -c "[ \$(git -C '$T/remote.git' rev-list --count main) = $((before + 1)) ] && git -C '$T/remote.git' log -1 --format=%B main | grep -q '^This reverts commit $culprit' && git -C '$T/remote.git' log -1 --format=%B main | grep -q '^Task-ID: seed' && [ -z \"\$(git -C '$T/remote.git' rev-list --merges main)\" ]"
check "it bisected: 1 run on the bad commit, at most 4 steps, 1 for landing the revert (not sixteen)" bash -c "[ \$(wc -l < '$T/t1.count') -le 7 ]"
check "the on-revert hook was told: result, culprit, task, author, shas" grep -q "reverted culprit=$culprit task=seed author=t@example.invalid shas=$culprit" "$T/hook.log"
h1=$(remote_head); run_rv --bad "$bad" --good "$good"
check "run again for the same red: already reverted, exit 0, nothing more pushed" test "$rc" = 0 -a "$(remote_head)" = "$h1"; out_has "already reverted"

echo "## it never reverts what it cannot reproduce, nor guesses"
world; for i in 1 2 3; do wr "f$i.txt" "$i" "feat: c$i"; done; bad=$(remote_head); worker r; before=$(remote_head)
run_rv --bad "$bad" --good "$good"; out_has "does not reproduce"; check "a Tier 1 that is green on the bad commit: exit 0, nothing reverted or pushed" test "$rc" = 0 -a "$(remote_head)" = "$before"
run_rv --bad "$good" --good "$bad"; check "--good that is not an ancestor of --bad: refused (2)" test "$rc" = 2
run_rv --bad "$bad"; check "--good is required (2)" test "$rc" = 2
echo "## --dry-run names the culprit and pushes nothing"
world; wr a.txt 1 "feat: ok"; wr BAD x "feat: breaks"; culprit=$(remote_head); wr b.txt 2 "feat: after"; bad=$(remote_head); worker r; before=$(remote_head)
run_rv --dry-run --bad "$bad" --good "$good"; out_has "the first failing commit of 3 is ${culprit:0:12}"; check "dry run: exit 0, nothing pushed" test "$rc" = 0 -a "$(remote_head)" = "$before"

echo "## the revert conflicts with a later commit: the later commits on the same files go first, newest first"
world; ( cd "$T/seed" && git pull -q origin main && echo 1 > f.txt && : > BAD && git add -A && git commit -qm "feat: c1 breaks it and writes f" -m "Task-ID: seed" && git push -q origin main ); culprit=$(remote_head)
wr f.txt 2 "feat: c2 edits f"; wr other.txt o "feat: c3 elsewhere"; bad=$(remote_head); worker r; run_rv --bad "$bad" --good "$good"
[ "$rc" = 0 ] && pass "a conflicting revert widens to the dependents and lands (exit $rc)" || { fail "exit $rc"; sed 's/^/     | /' "$T/out" >&2; }
check "the culprit and the later commit on f.txt are reverted, the unrelated commit stays" bash -c "! git -C '$T/remote.git' cat-file -e main:BAD && ! git -C '$T/remote.git' cat-file -e main:f.txt && git -C '$T/remote.git' cat-file -e main:other.txt && tail -n1 '$T/out' | grep -q '\"reverted\":2'"

echo "## more than five dependents: an alert, nothing reverted"
world; ( cd "$T/seed" && git pull -q origin main && echo 1 > f.txt && : > BAD && git add -A && git commit -qm "feat: c1 breaks it and writes f" -m "Task-ID: seed" && git push -q origin main ); culprit=$(remote_head)
for i in 2 3 4 5 6 7; do wr f.txt "$i" "feat: c$i edits f"; done; bad=$(remote_head); worker r; before=$(remote_head)
run_rv --bad "$bad" --good "$good"; out_has "more than 5"; check "exit 3 (alert), nothing pushed" test "$rc" = 3 -a "$(remote_head)" = "$before"
check "the on-revert hook got the alert" grep -q "^alert culprit=$culprit" "$T/hook.log"

echo "## a landing refused for any reason is an alert, not a guess"
world; wr BAD x "feat: breaks"; bad=$(remote_head); worker r; ( cd "$T/r" && "$ROOT/bin/land-direct" --hold "operator hold" ) >/dev/null; before=$(remote_head)
run_rv --bad "$bad" --good "$good"; check "a hold stops the revert too: exit 3, nothing pushed" test "$rc" = 3 -a "$(remote_head)" = "$before"; out_has "was not landed"
echo "## it never pushes by itself and never forces"
check "no git push in land-revert: the revert lands through land-direct" bash -c "! grep -nE 'git[^#]* push' '$R'"
finish
