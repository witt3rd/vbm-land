#!/usr/bin/env bash
# SOAK of the lock-free lander (docs/gate-mechanism-acceptance.md). Run by hand, on a machine with room, never from Tier 1: tests/soak.sh [N] (default 20).
# In a scratch world (a bare remote, ONE clone with many worktrees: the way agents share a clone) N worktrees each land one commit through the REAL bin/land-direct, all at the same
# instant, with a stub Tier 1 of 10-20 s (a repeat attempt re-checks for 1 s: what a repository's delta selection does with LAND_ATTEMPT), plus 4 landing the same hot file and one lander
# that is killed (kill -9) in the middle of its validation. PASS = N exit 0, none "busy", the remote's history is base + N + 1 linear, every
# file present (no lost update), exactly one of the hot four landed and the others got exit 11, the killed lander disturbed nobody and no lock file exists anywhere. Knobs: SOAK_T1_MIN, SOAK_T1_MAX (seconds), SOAK_FULL_RERUN=1 (every attempt pays the full stub Tier 1), SOAK_ATTEMPTS (LAND_ATTEMPTS of the world; default: the tool's).
. "$(dirname "$0")/lib.sh"
N=${1:-20}; T1MIN=${SOAK_T1_MIN:-10}; T1MAX=${SOAK_T1_MAX:-20}; L=$ROOT/bin/land-direct; HOT=4
sandbox
v() { echo "soak: $*"; }
rc_of() { RC=0; wait "$1" || RC=$?; }   # not in a $( ): only this shell can wait for its children
stub="if [ \"\${LAND_ATTEMPT:-1}\" = 1 ] || [ -n \"\${SOAK_FULL_RERUN:-}\" ]; then sleep \$(( $T1MIN + RANDOM % ($T1MAX - $T1MIN + 1) )); else sleep 1; fi"
set_conf "LAND_TEST_CMD=$stub" ${SOAK_ATTEMPTS:+"LAND_ATTEMPTS=$SOAK_ATTEMPTS"}
git clone -q "$T/remote.git" "$T/clone"; git -C "$T/clone" config commit.gpgsign false
wt() { git -C "$T/clone" worktree add -q "$T/$1" -b "$1" origin/main; git -C "$T/$1" config commit.gpgsign false; }
for i in $(seq 1 "$N"); do wt "w$i"; commit "$T/w$i" "f$i.txt" "file $i"; done
for k in $(seq 1 $HOT); do wt "hot$k"; commit "$T/hot$k" hot.txt "hot $k" "feat: hot $k"; done
wt victim; commit "$T/victim" victim.txt 1
base=$(git -C "$T/remote.git" rev-list --count main); t0=$(date +%s)
declare -A pid
go() { ( cd "$T/$1" && exec env SOAK_FULL_RERUN="${SOAK_FULL_RERUN:-}" "$L" >"$T/$1.out" 2>&1 ) & pid[$1]=$!; }
for i in $(seq 1 "$N"); do go "w$i"; done; for k in $(seq 1 $HOT); do go "hot$k"; done; go victim
sleep $(( T1MIN / 2 > 0 ? T1MIN / 2 : 1 )); kill -9 "${pid[victim]}"; wait "${pid[victim]}" 2>/dev/null || true; v "killed one lander (kill -9) mid-validation; $((N + HOT)) others running"
ok=0; busy=0; bad=0
for i in $(seq 1 "$N"); do rc_of "${pid[w$i]}"; r=$RC; if [ "$r" = 0 ]; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "w$i exit $r" >&2; tail -4 "$T/w$i.out" >&2; fi; grep -qi busy "$T/w$i.out" && busy=$((busy + 1)) || true; done
hot0=0; hot11=0; hotwin=; for k in $(seq 1 $HOT); do rc_of "${pid[hot$k]}"; r=$RC; [ "$r" != 0 ] || { hot0=$((hot0 + 1)); hotwin=$k; }; [ "$r" != 11 ] || hot11=$((hot11 + 1)); done
wall=$(( $(date +%s) - t0 ))
v "$N landers: $ok exit 0, $bad not; hot file: $hot0 landed, $hot11 conflicted (11); wall ${wall}s"
check "all $N landers exit 0" test "$ok" = "$N"
check "none of them was told 'busy'" test "$busy" = 0
files_ok() { local i; for i in $(seq 1 "$N"); do remote_has "f$i.txt" || return 1; done; }
check "every one of the $N files is on main (no lost update)" files_ok
check "the remote history is base + $N + 1 (the one hot winner), linear, no merge commit" bash -c "[ \$(git -C '$T/remote.git' rev-list --count main) = $((base + N + 1)) ] && [ -z \"\$(git -C '$T/remote.git' rev-list --merges main)\" ]"
check "exactly one of the four on the hot file landed and the other three got exit 11" bash -c "[ $hot0 = 1 ] && [ $hot11 = $((HOT - 1)) ]"
check "the hot file on main is the winner's, nothing of the losers" bash -c "[ \"\$(git -C '$T/remote.git' show main:hot.txt)\" = 'hot $hotwin' ]"
check "the killed lander's change is not on main and it disturbed nobody" bash -c "! git -C '$T/remote.git' cat-file -e main:victim.txt"
check "no lock or lease file anywhere in the clone" bash -c "[ -z \"\$(find '$T/clone/.git' \\( -name 'lock' -o -name 'lease*' \\) 2>/dev/null)\" ]"
if command -v jq >/dev/null; then v "attempts per landing (metrics): $(jq -s -c '[.[] | select(.result=="landed") | .attempts] | {n: length, max: max, mean: (add / length)}' "$T/clone/.git/vbm-land/metrics.jsonl")"; fi
finish
