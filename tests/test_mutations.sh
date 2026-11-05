#!/usr/bin/env bash
# Does the suite notice if a refusal is removed? For each guard of the lander, a scenario that must be REFUSED runs against the real lander
# (it must refuse with the expected code) and against a mutant with that one guard cut out (it must NOT refuse that way: the guard was
# what refused it). A guard that nothing depends on would show up here as a mutant that is still refused.
. "$(dirname "$0")/lib.sh"
sandbox
unset LAND_LOCK_WAIT_SECONDS
MUT=$T/mut
mutant() {   # mutant NAME SED_EXPR [FILE]: a copy of bin/ and lib/ with ONE line changed in FILE (default bin/land-direct); the sed expression must change the file
  local f=${3:-bin/land-direct}
  rm -rf "$MUT"; mkdir -p "$MUT"; cp -r "$ROOT/bin" "$ROOT/lib" "$MUT/"; cp "$ROOT/VERSION" "$MUT/"
  sed -i "$2" "$MUT/$f"; cmp -s "$MUT/$f" "$ROOT/$f" && { fail "mutation $1 changed nothing (the sed expression is stale)"; return 1; }; return 0
}
# a scenario builds a fresh sandbox, a worker with one change that must be refused, and prints the lander's exit code (L = the lander to run)
scn_prelude() { sandbox "${1:-main}"; }
sc_hold()      { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" --hold x >/dev/null; "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_red()       { scn_prelude; set_conf 'LAND_TEST_CMD=true'; gh_mode red; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_tier1()     { scn_prelude; set_conf 'LAND_TEST_CMD=false'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_gates()     { scn_prelude; set_conf 'LAND_GATES_CMD=false'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_conflict()  { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; worker v; commit "$T/w" a.txt 1; commit "$T/v" a.txt 2; ( cd "$T/v" && "$1" >/dev/null 2>&1 ); ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_budget()    { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_PROD_PATHS=src' 'LAND_BUDGET_LINES=3'; worker w; mkdir -p "$T/w/src"; seq 1 40 > "$T/w/src/f"; git -C "$T/w" add src; git -C "$T/w" commit -qm "feat: big" -m "Task-ID: t"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_subject()   { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; echo 1 > "$T/w/a"; git -C "$T/w" add a; git -C "$T/w" commit -qm "not conventional"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_conf_base() { scn_prelude; set_conf 'LAND_TEST_CMD=test ! -e BAD'; worker w; : > "$T/w/BAD"; echo 'LAND_TEST_CMD=true' > "$T/w/scripts/land.conf"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: loosen" -m "Task-ID: t"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
# (hooks are read from main twice over: from main's tree and from a scratch worktree that starts at main, so no single-line mutant removes that guard)
sc_hook_base() { scn_prelude; set_conf 'LAND_TEST_CMD=true'; seed_exec scripts/land.d/post-rebase $'#!/usr/bin/env bash\nexit 1'; worker w; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/w/scripts/land.d/post-rebase"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: neuter hook" -m "Task-ID: t"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_drift()     { scn_prelude; S=$T/src; mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib templates skills install VERSION "$S/" ); ( cd "$S" && git init -q -b main && git config commit.gpgsign false && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: r" && git tag v1 )
               git clone -q "$T/remote.git" "$T/w"; "$S/install" --source "$S" --target "$T/w" v1 >/dev/null; printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\n' > "$T/w/scripts/land.conf"
               echo '# patched' >> "$T/w/scripts/land/bin/land-red"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: patched copy" -m "Task-ID: t"
               ( cd "$T/w" && env -u X "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_flaky()     { scn_prelude; seed_push scripts/known-flaky.txt "test_flaky.sh alice 2099-01-01 1"; set_conf 'LAND_TEST_CMD=true' 'LAND_KNOWN_FLAKY=scripts/known-flaky.txt' 'LAND_FLAKY_RERUN_WAIT=2'; gh_mode red; echo "FAIL scripts/test_unlisted.sh" > "$T/gh/failedlog"; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && RED_SLEEP=true "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_tier2()     { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_TIER2_JOB=tier2'; gh_mode t2red; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_nothing_pushed_on_failure() { scn_prelude; set_conf 'LAND_TEST_CMD=false'; worker w; commit "$T/w" a.txt 1; b=$(remote_head); ( cd "$T/w" && "$1" >/dev/null 2>&1 ) || true; [ "$(remote_head)" = "$b" ] && echo 13 || echo 0; }

# NAME | expected exit with the real lander | scenario | sed that cuts the guard out
while IFS='|' read -r name want scn file expr; do
  [ -n "$name" ] || continue
  got=$($scn "$ROOT/bin/land-direct")
  [ "$got" = "$want" ] && pass "real lander: $name refuses ($want)" || fail "real lander: $name expected exit $want, got $got"
  if mutant "$name" "$expr" "$( [ "$file" = - ] && echo bin/land-direct || echo "$file")"; then
    got=$($scn "$MUT/bin/land-direct")
    [ "$got" != "$want" ] && pass "mutant without the $name guard is NOT refused (got $got): the suite depends on the guard" || fail "mutant without the $name guard still gives $want: nothing tests that guard"
  fi
done <<'LIST'
hold|14|sc_hold|-|s/^holdcheck() {.*$/holdcheck() { :; }/
red check|10|sc_red|-|s/^red_check() {$/red_check() { return 0;/
Tier 1 tests|13|sc_tier1|-|s/bounded "\$lt" "Tier 1 tests" bash -c "\$LAND_TEST_CMD"/true/
Tier 1 gates|13|sc_gates|-|s/bounded "\$lt" "Tier 1 gates" bash -c "\$LAND_GATES_CMD"/true/
conflict|11|sc_conflict|-|s/stop 11 conflict/echo conflict-ignored; stop 0 landed/
size budget|1|sc_budget|-|s/\[ "\$prod" -gt "\$LAND_BUDGET_LINES" \] \&\& \[ -z "\$budget" \]/false/
Conventional subject|1|sc_subject|-|s/\[ "\$LAND_CONVENTIONAL" = 1 \]/false/
config from main|13|sc_conf_base|-|s|elif git -C "\$top" cat-file -e "\$remote/\$base:\$confpath" 2>/dev/null;|elif false;|
drift check|12|sc_drift|-|s|scripts/land/bin/land-check) >\&2|true) >\&2|
known-flaky list membership|10|sc_flaky|bin/land-red|s/^kf_listed() {$/kf_listed() { return 0;/
Tier 2 freeze|14|sc_tier2|bin/land-red|s/elif \[ ! -e "\$state\/freeze" \]; then now=/elif false; then now=/
LIST
got=$(sc_nothing_pushed_on_failure "$ROOT/bin/land-direct"); [ "$got" = 13 ] && pass "a Tier 1 failure leaves the remote untouched" || fail "a Tier 1 failure moved the remote"
finish
