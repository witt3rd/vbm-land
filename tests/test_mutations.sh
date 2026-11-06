#!/usr/bin/env bash
# Does the suite notice if a refusal is removed? For each guard of the lander, a scenario that must be REFUSED runs against the real lander
# (it must refuse with the expected code) and against a mutant with that one guard cut out (it must NOT refuse that way: the guard was
# what refused it). A guard that nothing depends on would show up here as a mutant that is still refused.
. "$(dirname "$0")/lib.sh"
sandbox
MUT=$T/mut
mutant() {   # mutant NAME SED_EXPR [FILE]: a copy of bin/ and lib/ with ONE line changed in FILE (default bin/land-direct); the sed expression must change the file
  local f=${3:-bin/land-direct}
  rm -rf "$MUT"; mkdir -p "$MUT"; cp -r "$ROOT/bin" "$ROOT/lib" "$MUT/"; cp "$ROOT/VERSION" "$MUT/"
  sed -i "$2" "$MUT/$f"; cmp -s "$MUT/$f" "$ROOT/$f" && { fail "mutation $1 changed nothing (the sed expression is stale)"; return 1; }; return 0
}
# a scenario builds a fresh sandbox, a worker with one change that must be refused, and prints the lander's exit code (L = the lander to run)
scn_prelude() { sandbox "${1:-main}"; }
sc_hold()      { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" --hold x >/dev/null; "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_tier1()     { scn_prelude; set_conf 'LAND_TEST_CMD=false'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_gates()     { scn_prelude; set_conf 'LAND_GATES_CMD=false'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_conflict()  { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; worker v; commit "$T/w" a.txt 1; commit "$T/v" a.txt 2; ( cd "$T/v" && "$1" >/dev/null 2>&1 ); ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_subject()   { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; echo 1 > "$T/w/a"; git -C "$T/w" add a; git -C "$T/w" commit -qm "not conventional"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_conf_base() { scn_prelude; set_conf 'LAND_TEST_CMD=test ! -e BAD'; worker w; : > "$T/w/BAD"; echo 'LAND_TEST_CMD=true' > "$T/w/scripts/land.conf"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: loosen" -m "Task-ID: t"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
# (hooks are read from main twice over: from main's tree and from a scratch worktree that starts at main, so no single-line mutant removes that guard)
sc_hook_base() { scn_prelude; set_conf 'LAND_TEST_CMD=true'; seed_exec scripts/land.d/post-rebase $'#!/usr/bin/env bash\nexit 1'; worker w; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/w/scripts/land.d/post-rebase"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: neuter hook" -m "Task-ID: t"; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_drift()     { scn_prelude; S=$T/src; mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib docs templates skills install VERSION "$S/" ); ( cd "$S" && git init -q -b main && git config commit.gpgsign false && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: r" && git tag v1 )
               git clone -q "$T/remote.git" "$T/w"; "$S/install" --source "$S" --target "$T/w" v1 >/dev/null; printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\n' > "$T/w/scripts/land.conf"
               echo '# patched' >> "$T/w/scripts/land/bin/run-probe"; git -C "$T/w" add -A; git -C "$T/w" commit -qm "feat: patched copy" -m "Task-ID: t"
               ( cd "$T/w" && env -u X "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_push_refused() { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_ATTEMPTS=3'; printf '#!/bin/sh\necho refused >&2\nexit 1\n' > "$T/remote.git/hooks/pre-receive"; chmod +x "$T/remote.git/hooks/pre-receive"; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_freeze()    { scn_prelude; set_conf 'LAND_TEST_CMD=true'; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" --freeze x --owner o --for 1h >/dev/null; "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
# a red main: main already fails OLD; the landing is unrelated (inherited: lands) or adds NEW (refused) or fails without a failure line (refused)
ih_world() { scn_prelude; set_conf 'LAND_TEST_CMD=rc=0; [ ! -e OLD ] || { echo "FAIL old"; rc=1; }; [ ! -e NEW ] || { echo "FAIL new"; rc=1; }; [ ! -e SILENT ] || rc=1; exit $rc'; seed_push OLD 1; worker w; }
sc_ih_new()    { ih_world; commit "$T/w" NEW 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_ih_silent() { scn_prelude; set_conf 'LAND_TEST_CMD=[ ! -e SILENT ]'; worker w; commit "$T/w" SILENT 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_moved_attempts() { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_ATTEMPTS=3'; race_hook 5; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_moved_deadline() { scn_prelude; set_conf 'LAND_TEST_CMD=sleep 2' 'LAND_DEADLINE=1'; race_hook 3; worker w; commit "$T/w" a.txt 1; ( cd "$T/w" && "$1" >/dev/null 2>&1 ) && echo 0 || echo $?; }
# land-revert (the watchdog): $1 is a land-direct path; the watchdog beside it is the one under test
rv_world() { scn_prelude; set_conf 'LAND_TEST_CMD=test ! -e BAD' 'LAND_REQUIRE_TRAILERS=Task-ID'; good=$(remote_head); }
rv_go() { worker w; ( cd "$T/w" && "$(dirname "$1")/land-revert" --bad "$bad" --good "$good" >/dev/null 2>&1 ) && echo 0 || echo $?; }
sc_rv_green()   { rv_world; seed_push a.txt 1; seed_push b.txt 2; seed_push c.txt 3; bad=$(remote_head); b=$bad; r=$(rv_go "$1"); [ "$r" = 0 ] && [ "$(remote_head)" = "$b" ] && echo 0 || echo 1; }
sc_rv_five()    { rv_world; ( cd "$T/seed" && git pull -q origin main && echo 1 > f.txt && : > BAD && git add -A && git commit -qm "feat: breaks" -m "Task-ID: s" && git push -q origin main ); for i in 2 3 4 5 6 7; do seed_push f.txt $i "feat: edit $i"; done; bad=$(remote_head); rv_go "$1"; }
sc_rv_refused() { rv_world; seed_push BAD x "feat: breaks"; bad=$(remote_head); worker w; ( cd "$T/w" && "$ROOT/bin/land-direct" --hold h >/dev/null ); rv_go "$1"; }
# gate-edit approvals (lib/approvals.sh): AP = the approvals file; ga_h = the diff hash of dropping line b of gate.sh, computed by the real lander
AP=scripts/gate-edit-approvals.txt; ga_today=$(date -u +%F); ga_old=$(date -u -d '30 days ago' +%F); ga_hz=$(printf '%064x' 7)
ga_prelude() { scn_prelude; set_conf 'LAND_TEST_CMD=true' 'LAND_GATE_APPEND_ONLY=gate.sh'; seed_push gate.sh $'a\nb\nc'; }
gacm() { git -C "$1" add -A; git -C "$1" commit -qm "${2:-chore: x}" -m "Task-ID: t"; }
ga_drop() { sed -i 2d "$1/${2:-gate.sh}"; gacm "$1" "feat: drop line b"; }
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
ps_prelude() { scn_prelude; set_conf 'LAND_TEST_CMD=true' "LAND_PROTECTED_LIST=$PL" "$@"; seed_push keys.signers $'a\nb\nc'; seed_push scripts/land.d/x $'1\n2'; seed_push "$PL" $'keys.signers\nscripts/land.d/'; }
ps_h() { worker h; ga_drop "$T/h" keys.signers; ( cd "$T/h" && "$ROOT/bin/land-direct" --print-gate-diff-hash "${1:-keys.signers}" 2>/dev/null ); }
sc_ps_none()    { ps_prelude; worker w; ga_drop "$T/w" keys.signers; ga_go "$1"; }
sc_ps_set()     { ps_prelude; h=$(ps_h); seed_push $AP "keys.signers,scripts/land.d/x | $h | r | $ga_today"; worker w; ga_drop "$T/w" keys.signers; : > "$T/w/$AP"; gacm "$T/w" "chore: consume"; ga_go "$1"; }
sc_ps_empty()   { ps_prelude; seed_push $PL "# no entries"; worker w; commit "$T/w" z.txt 1; ga_go "$1"; }
sc_ps_union()   { ps_prelude; worker h; echo 'new/' >> "$T/h/$PL"; gacm "$T/h" "feat: entry"; hl=$( cd "$T/h" && "$ROOT/bin/land-direct" --print-gate-diff-hash "$PL" 2>/dev/null ); seed_push $AP "$PL | $hl | r | $ga_today"
                  worker w; echo 'new/' >> "$T/w/$PL"; mkdir "$T/w/new"; echo n > "$T/w/new/f"; : > "$T/w/$AP"; gacm "$T/w" "feat: entry and a file under it"; ga_go "$1"; }
sc_ps_list()    { ps_prelude; worker w; sed -i '/^keys.signers$/d' "$T/w/$PL"; gacm "$T/w" "feat: loosen the list"; ga_go "$1"; }
sc_ps_rename()  { ps_prelude; worker w; git -C "$T/w" mv keys.signers moved.sh; gacm "$T/w" "feat: move the gate out"; ga_go "$1"; }
sc_ps_onetime() { ps_prelude; h=$(ps_h); seed_push $AP "keys.signers | $h | r | $ga_today"; worker w; ga_drop "$T/w" keys.signers; ga_go "$1"; }
sc_ps_sep()     { ps_prelude "LAND_PROTECTED_APPROVALS=$PP"; h=$(ps_h); seed_push $AP "keys.signers | $h | r | $ga_today"; worker w; ga_drop "$T/w" keys.signers; : > "$T/w/$AP"; gacm "$T/w" "chore: consume"; ga_go "$1"; }
sc_ps_early()   { ps_prelude "LAND_PROTECTED_APPROVALS=$PP"; worker w; echo "keys.signers | $ga_hz | r | $ga_today" > "$T/w/$PP"; echo n > "$T/w/n.txt"; gacm "$T/w" "chore: approval and n"; git -C "$T/w" rm -q n.txt; gacm "$T/w" "chore: no n"; ga_go "$1"; }
sc_ps_key()     { ps_prelude; worker w; echo "scripts/land.d/x,keys.signers | $ga_hz | r | $ga_today" > "$T/w/$AP"; gacm "$T/w" "chore: approval"; ga_go "$1"; }
sc_ps_conf()    { ps_prelude; worker w; echo '# x' >> "$T/w/scripts/land.conf"; gacm "$T/w" "feat: touch the configuration"; ga_go "$1"; }
sc_ps_regen()   { scn_prelude; set_conf 'LAND_TEST_CMD=echo regenerated > gen.txt' 'LAND_GENERATED_LIST=scripts/generated.txt' "LAND_PROTECTED_LIST=$PL"; seed_push scripts/generated.txt gen.txt; seed_push gen.txt stale; seed_push $PL $'keys.signers\ngen.txt'; worker w; commit "$T/w" z.txt 1; ga_go "$1"; }
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
Tier 1 tests|13|sc_tier1|-|s/^t1cmd() { case \$1 in gates) echo "\$LAND_GATES_CMD";; \*) echo "\$LAND_TEST_CMD";; esac; }/t1cmd() { case $1 in gates) echo "$LAND_GATES_CMD";; *) echo true;; esac; }/
Tier 1 gates|13|sc_gates|-|s/^t1cmd() { case \$1 in gates) echo "\$LAND_GATES_CMD";; \*) echo "\$LAND_TEST_CMD";; esac; }/t1cmd() { case $1 in gates) echo true;; *) echo "$LAND_TEST_CMD";; esac; }/
conflict|11|sc_conflict|-|s/stop 11 conflict/echo conflict-ignored; stop 0 landed/
Conventional subject|1|sc_subject|-|s/\[ "\$LAND_CONVENTIONAL" = 1 \]/false/
config from main|13|sc_conf_base|-|s|elif git -C "\$top" cat-file -e "\$remote/\$base:\$confpath" 2>/dev/null;|elif false;|
drift check|12|sc_drift|-|s|scripts/land/bin/land-check) >\&2|true) >\&2|
push arbiter: a refused push lands nothing|1|sc_push_refused|-|s/^  if bounded "\$gt" "git push"/  if true || bounded "$gt" "git push"/
freeze|14|sc_freeze|-|s/^freezecheck() { freeze_active/freezecheck() { return 0; freeze_active/
inherited red: a new failure is refused|13|sc_ih_new|-|s/^  \[ -z "\$newfail" \]; }/  true; }/
inherited red: no failure line, no inheritance|13|sc_ih_silent|-|s/\[ -n "\$mine" \] || return 1/:/
retry bound: attempts|16|sc_moved_attempts|-|s/\[ "\$attempt" -lt "\$LAND_ATTEMPTS" \] \&\& //
retry bound: deadline|16|sc_moved_deadline|-|s/ \&\& \[ "\$(date +%s)" -lt "\$deadline" \]//
push refused while the base has not moved is final|1|sc_push_refused|-|s/^  ! g merge-base --is-ancestor "\$remote\/\$base" "\$sha" || die .*$/  :/
land-revert: a failure that does not reproduce is not reverted|0|sc_rv_green|bin/land-revert|s/^if tier1 "\$run\/bis"; then stop 0 green/if false; then stop 0 green/
land-revert: more than five dependents alert|3|sc_rv_five|bin/land-revert|s/^  \[ \${#later\[@\]} -le 5 \] || stop 3 alert .*$/  :/
land-revert: a refused landing is an alert|3|sc_rv_refused|bin/land-revert|s/^\[ "\$rc" = 0 \] || stop 3 alert "the revert of/: || stop 3 alert "the revert of/
LIST
got=$(sc_nothing_pushed_on_failure "$ROOT/bin/land-direct"); [ "$got" = 13 ] && pass "a Tier 1 failure leaves the remote untouched" || fail "a Tier 1 failure moved the remote"
finish
