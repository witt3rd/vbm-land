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
sc_drift()     { scn_prelude; S=$T/src; mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib docs templates skills install VERSION "$S/" ); ( cd "$S" && git init -q -b main && git config commit.gpgsign false && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: r" && git tag v1 )
               git clone -q "$T/remote.git" "$T/w"; "$S/install" --source "$S" --target "$T/w" v1 >/dev/null; printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\n' > "$T/w/scripts/land.conf"
               echo '# patched' >> "$T/w/scripts/land/bin/land-red"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: patched copy" -m "Task-ID: t"
               ( cd "$T/w" && env -u X "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_flaky()     { scn_prelude; seed_push scripts/known-flaky.txt "test_flaky.sh alice 2099-01-01 1"; set_conf 'LAND_TEST_CMD=true' 'LAND_KNOWN_FLAKY=scripts/known-flaky.txt' 'LAND_FLAKY_RERUN_WAIT=2'; gh_mode red; echo "FAIL scripts/test_unlisted.sh" > "$T/gh/failedlog"; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && RED_SLEEP=true "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_tier2()     { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_TIER2_JOB=tier2'; gh_mode t2red; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
# gate-edit approvals (lib/approvals.sh): AP = the approvals file; ga_h = the diff hash of dropping line b of gate.sh, computed by the real lander
AP=scripts/gate-edit-approvals.txt; ga_today=$(date -u +%F); ga_old=$(date -u -d '30 days ago' +%F); ga_hz=$(printf '%064x' 7)
ga_prelude() { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_GATE_APPEND_ONLY=gate.sh'; seed_push gate.sh $'a\nb\nc'; }
gacm() { git -C "$1" add -A; git -C "$1" commit -qm "${2:-chore: x}" -m "Task-ID: t"; }
ga_drop() { sed -i 2d "$1/gate.sh"; gacm "$1" "feat: drop line b"; }
ga_h() { worker h; ga_drop "$T/h"; ( cd "$T/h" && "$ROOT/bin/land-direct" --print-gate-diff-hash gate.sh 2>/dev/null ); }
ga_go() { ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_ga_append()    { ga_prelude; worker w; ga_drop "$T/w"; ga_go "$1"; }
sc_ga_onetime()   { ga_prelude; h=$(ga_h); seed_push $AP "gate.sh | $h | r | $ga_today"; worker w; ga_drop "$T/w"; ga_go "$1"; }
sc_ga_stale()     { ga_prelude; h=$(ga_h); seed_push $AP "gate.sh | $h | r | $ga_old"; worker w; ga_drop "$T/w"; : > "$T/w/$AP"; gacm "$T/w" "chore: consume"; ga_go "$1"; }
sc_ga_removed()   { ga_prelude; h=$(ga_h); seed_push $AP "gate.sh | $h | r | $ga_today"; worker w; : > "$T/w/$AP"; gacm "$T/w" "chore: quietly remove it"; ga_go "$1"; }
sc_ga_net_alone() { ga_prelude; worker w; echo "gate.sh | $ga_hz | r | $ga_today" > "$T/w/$AP"; gacm "$T/w" "chore: approval"; echo n > "$T/w/n.txt"; gacm "$T/w" "feat: n"; ga_go "$1"; }
sc_ga_early()     { ga_prelude; worker w; echo "gate.sh | $ga_hz | r | $ga_today" > "$T/w/$AP"; echo n > "$T/w/n.txt"; gacm "$T/w" "chore: approval and n"; git -C "$T/w" rm -q n.txt; gacm "$T/w" "chore: no n"; ga_go "$1"; }
sc_ga_wd_alone() { ga_prelude; h=$(ga_h); seed_push $AP "gate.sh | $h | r | $ga_today"; worker w; : > "$T/w/$AP"; echo n > "$T/w/n.txt"; git -C "$T/w" add -A; git -C "$T/w" commit -qm 'chore: withdraw' -m "Approval-Withdrawn: gate.sh ${h:0:12}"; ga_go "$1"; }
sc_ga_one_early() { ga_prelude; worker w; { echo "gate.sh | $ga_hz | r | $ga_today"; echo "gate.sh | $(printf '%064x' 8) | r2 | $ga_today"; } > "$T/w/$AP"; gacm "$T/w" "chore: two approvals"; sed -i 2d "$T/w/$AP"; gacm "$T/w" "chore: one is enough"; ga_go "$1"; }
sc_ga_one_net()   { ga_prelude; worker w; echo "gate.sh | $ga_hz | r | $ga_today" > "$T/w/$AP"; gacm "$T/w" "chore: approval 1"; echo "gate.sh | $(printf '%064x' 8) | r2 | $ga_today" >> "$T/w/$AP"; gacm "$T/w" "chore: approval 2"; ga_go "$1"; }
sc_ga_window()    { ga_prelude; worker w; echo "gate.sh | $ga_hz | r | $ga_old" > "$T/w/$AP"; gacm "$T/w" "chore: approval"; ga_go "$1"; }
sc_ga_self()      { ga_prelude; worker w; echo "$AP | $ga_hz | r | $ga_today" > "$T/w/$AP"; gacm "$T/w" "chore: approval"; ga_go "$1"; }
sc_ga_malformed() { ga_prelude; worker w; echo "gate.sh | nothash | r | $ga_today" > "$T/w/$AP"; gacm "$T/w" "chore: approval"; ga_go "$1"; }
# protected sets (lib/approvals.sh ga_protected): PL = the protected-paths list, PP = the approvals file of their own; the lander computes the hash
PL=scripts/protected-paths.txt; PP=scripts/protected-approvals.txt
ps_prelude() { scn_prelude; set_conf 'LAND_TEST_CMD=true' "LAND_PROTECTED_LIST=$PL" "$@"; seed_push gate.sh $'a\nb\nc'; seed_push spec/x $'1\n2'; seed_push "$PL" $'gate.sh\nspec/'; }
ps_h() { worker h; ga_drop "$T/h"; ( cd "$T/h" && "$ROOT/bin/land-direct" --print-gate-diff-hash "${1:-gate.sh}" 2>/dev/null ); }
sc_ps_none()    { ps_prelude; worker w; ga_drop "$T/w"; ga_go "$1"; }
sc_ps_set()     { ps_prelude; h=$(ps_h); seed_push $AP "gate.sh,spec/x | $h | r | $ga_today"; worker w; ga_drop "$T/w"; : > "$T/w/$AP"; gacm "$T/w" "chore: consume"; ga_go "$1"; }
sc_ps_empty()   { ps_prelude; seed_push $PL "# no entries"; worker w; commit "$T/w" z.txt 1; ga_go "$1"; }
sc_ps_union()   { ps_prelude; worker h; echo 'new/' >> "$T/h/$PL"; gacm "$T/h" "feat: entry"; hl=$( cd "$T/h" && "$ROOT/bin/land-direct" --print-gate-diff-hash "$PL" 2>/dev/null ); seed_push $AP "$PL | $hl | r | $ga_today"
                  worker w; echo 'new/' >> "$T/w/$PL"; mkdir "$T/w/new"; echo n > "$T/w/new/f"; : > "$T/w/$AP"; gacm "$T/w" "feat: entry and a file under it"; ga_go "$1"; }
sc_ps_list()    { ps_prelude; worker w; sed -i '/^gate.sh$/d' "$T/w/$PL"; gacm "$T/w" "feat: loosen the list"; ga_go "$1"; }
sc_ps_rename()  { ps_prelude; worker w; git -C "$T/w" mv gate.sh moved.sh; gacm "$T/w" "feat: move the gate out"; ga_go "$1"; }
sc_ps_onetime() { ps_prelude; h=$(ps_h); seed_push $AP "gate.sh | $h | r | $ga_today"; worker w; ga_drop "$T/w"; ga_go "$1"; }
sc_ps_sep()     { ps_prelude "LAND_PROTECTED_APPROVALS=$PP"; h=$(ps_h); seed_push $AP "gate.sh | $h | r | $ga_today"; worker w; ga_drop "$T/w"; : > "$T/w/$AP"; gacm "$T/w" "chore: consume"; ga_go "$1"; }
sc_ps_early()   { ps_prelude "LAND_PROTECTED_APPROVALS=$PP"; worker w; echo "gate.sh | $ga_hz | r | $ga_today" > "$T/w/$PP"; echo n > "$T/w/n.txt"; gacm "$T/w" "chore: approval and n"; git -C "$T/w" rm -q n.txt; gacm "$T/w" "chore: no n"; ga_go "$1"; }
sc_ps_key()     { ps_prelude; worker w; echo "spec/x,gate.sh | $ga_hz | r | $ga_today" > "$T/w/$AP"; gacm "$T/w" "chore: approval"; ga_go "$1"; }
sc_ps_conf()    { ps_prelude; worker w; echo '# x' >> "$T/w/scripts/land.conf"; gacm "$T/w" "feat: touch the configuration"; ga_go "$1"; }
sc_ps_regen()   { scn_prelude; set_conf 'LAND_TEST_CMD=echo regenerated > gen.txt' 'LAND_GENERATED_LIST=scripts/generated.txt' "LAND_PROTECTED_LIST=$PL"; seed_push scripts/generated.txt gen.txt; seed_push gen.txt stale; seed_push $PL $'gate.sh\ngen.txt'; worker w; commit "$T/w" z.txt 1; ga_go "$1"; }
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
gate edit: append-only|12|sc_ga_append|lib/approvals.sh|s/ga_refuse "\$f is a gate-defining file/: "\$f is a gate-defining file/
gate edit: one-time consumption|12|sc_ga_onetime|lib/approvals.sh|s/"\$REM" || ga_refuse "the approval for/"\$REM" || : "the approval for/
gate edit: stale approval|12|sc_ga_stale|lib/approvals.sh|s/^    if ga_fresh "\$d" "\$days"; then$/    if true; then/
gate edit: removed without consumption|12|sc_ga_removed|lib/approvals.sh|s/ga_refuse "the approval for \$f (\${h:0:12}) was removed/: "the approval for/
gate edit: approval alone in its landing|12|sc_ga_net_alone|lib/approvals.sh|s/\[ -z "\$others" \] || ga_refuse "this landing adds/: "this landing adds/
gate edit: approval alone in its commit|12|sc_ga_early|-|s/^ga_early "\$top" "\$commits" "\$LAND_APPROVALS" \&\&/true \&\&/
gate edit: a withdrawal lands alone|12|sc_ga_wd_alone|lib/approvals.sh|s/\[ -z "\$others" \] || ga_refuse "the approval for/: "the approval for/
gate edit: one line per approval commit|12|sc_ga_one_early|lib/approvals.sh|s/^    if \[ "\$ns" != "1"\$'\\t'"0" \]; then$/    if false; then/
gate edit: one approval per landing|12|sc_ga_one_net|lib/approvals.sh|s/^    \[ "\$ns" = "1"\$'\\t'"0" \] || ga_refuse/    : || ga_refuse/
gate edit: approval window on add|12|sc_ga_window|lib/approvals.sh|s/ga_fresh "\$d" "\$days" || ga_refuse "an approval dated/true || : "an approval dated/
gate edit: no approval of the approvals file|12|sc_ga_self|lib/approvals.sh|s/\[ "\$p" != "\$x" \] || ga_refuse/true || :/
gate edit: malformed record|12|sc_ga_malformed|lib/approvals.sh|s/ga_refuse "\$ap: a line that is not an approval record/: "\$ap: a line that is not an approval record/
protected set: approval required|12|sc_ps_none|lib/approvals.sh|s/^  ga_refuse "this landing touches the protected set/  : "this landing touches the protected set/
protected set: the approval's set is exactly the touched set|12|sc_ps_set|lib/approvals.sh|s/grep -qxF -- "\$key \$h" "\$used"/grep -qF -- " $h" "$used"/
protected set: an empty list fails closed|12|sc_ps_empty|lib/approvals.sh|s/if \[ ! -s "\$st\/ga-pe-base" \]; then ga_ptfail=/if false; then ga_ptfail=/
protected set: the change's own list counts too|12|sc_ps_union|lib/approvals.sh|s/\[ \${#X\[@\]} -eq 0 \] || E+=("\${X\[@\]}")/:/
protected set: the list itself is protected|12|sc_ps_list|-|s/^prot_extra=\$LAND_PROTECTED_LIST;/prot_extra=;/
protected set: the configuration is protected|12|sc_ps_conf|-|s/prot_extra="\$prot_extra \$confpath"/:/
protected set: no rename detection|12|sc_ps_rename|lib/approvals.sh|s/--name-only -z --no-renames/--name-only -z/
protected set: one-time consumption|12|sc_ps_onetime|lib/approvals.sh|s/"\$REM" || ga_refuse "the approval for/"\$REM" || : "the approval for/
protected set: its own approvals file|12|sc_ps_sep|lib/approvals.sh|s/pused=\$UP; fi/pused=$U; fi/
protected set: approval alone in its commit (own file)|12|sc_ps_early|-|s/ga_early "\$top" "\$commits" "\$pap"/true/
protected set: a set key is canonical|12|sc_ps_key|lib/approvals.sh|s/\[ -z "\$prev" \] || \[\[ "\$prev" < "\$p" \]\] || return 1;/:;/
protected set: judged again after Tier 1 regenerates files|12|sc_ps_regen|-|s/^    \[ -z "\$LAND_PROTECTED_LIST" \] || ga_judge_run/    true || ga_judge_run/
LIST
got=$(sc_nothing_pushed_on_failure "$ROOT/bin/land-direct"); [ "$got" = 13 ] && pass "a Tier 1 failure leaves the remote untouched" || fail "a Tier 1 failure moved the remote"
finish
