#!/usr/bin/env bash
# bootstrap-land against a scratch repo with a bare remote: lands; refuses (red, hold, conflict, Tier 1 failure, busy); main moving
# during Tier 1; two racing workers; never force-pushes; never prunes a shared clone's worktrees.
. "$(dirname "$0")/lib.sh"
sandbox
L=$ROOT/scripts/bootstrap-land
export LAND_TIER1_CMD='true' LAND_LOCK_WAIT_SECONDS=5

worker w1; worker w3; commit "$T/w1" one.txt 1
( cd "$T/w1" && expect_exit "lands one commit" 0 "$L" ); out_has '"result":"landed"'
check "main has the commit" remote_has one.txt
check "the last line is JSON with the exit code" bash -c "tail -n1 '$T/out' | grep -q '\"exit\":0}'"

# a Tier 1 failure lands nothing
worker w2; commit "$T/w2" two.txt 2; before=$(remote_head)
( cd "$T/w2" && LAND_TIER1_CMD='echo boom; exit 3' expect_exit "Tier 1 failure refuses" 13 "$L" ); out_has boom
check "nothing landed after a Tier 1 failure" test "$(remote_head)" = "$before"

# a conflict aborts and names the file
commit "$T/w3" one.txt "other"; before=$(remote_head)
( cd "$T/w3" && expect_exit "conflict refuses" 11 "$L" ); out_has one.txt
check "nothing landed after a conflict" test "$(remote_head)" = "$before"

# hold stops a landing at once
mkdir -p "$T/w2/.git/vbm-land"; echo "maintenance" > "$T/w2/.git/vbm-land/hold"
( cd "$T/w2" && expect_exit "hold refuses" 14 "$L" ); out_has maintenance
rm -f "$T/w2/.git/vbm-land/hold"

# a red main refuses (and a gh that fails is red: not knowing is not green)
gh_mode red;  ( cd "$T/w2" && expect_exit "red main refuses" 10 "$L" )
gh_mode fail; ( cd "$T/w2" && expect_exit "unknowable main refuses" 10 "$L" )
gh_mode noworkflow; ( cd "$T/w2" && expect_exit "no CI workflow on main yet is not red" 0 "$L" )
worker w2b; commit "$T/w2b" twob.txt 2
gh_mode none; ( cd "$T/w2b" && LAND_RED_CHECK=off expect_exit "red check off lands without gh" 0 "$L" )

# main moves during Tier 1: the lander rebases and tests again
worker w4; worker w5; commit "$T/w4" four.txt 4; commit "$T/w5" five.txt 5
mv_cmd="[ -e $T/moved ] || { touch $T/moved; git -C $T/w5 pull -q --rebase origin main && git -C $T/w5 push -q origin HEAD:main; }"
( cd "$T/w4" && LAND_TIER1_CMD="$mv_cmd" expect_exit "main moving during Tier 1 still lands" 0 "$L" ); out_has "moved during Tier 1"
check "both commits are on main" bash -c "git -C '$T/remote.git' cat-file -e main:four.txt && git -C '$T/remote.git' cat-file -e main:five.txt"

# two racing workers: one waits for the lock, both land, history stays linear
worker r1; worker r2; commit "$T/r1" r1.txt 1; commit "$T/r2" r2.txt 2
( cd "$T/r1" && LAND_TIER1_CMD='sleep 1' LAND_LOCK_WAIT_SECONDS=30 "$L" >"$T/r1.out" 2>&1 ) & p1=$!
( cd "$T/r2" && LAND_TIER1_CMD='sleep 1' LAND_LOCK_WAIT_SECONDS=30 "$L" >"$T/r2.out" 2>&1 ) & p2=$!
rc1=0; rc2=0; wait $p1 || rc1=$?; wait $p2 || rc2=$?
# the two clones have separate lock files, so they may not exclude each other: either order is fine, a refused push retries
check "both racing workers landed" bash -c "[ $rc1 = 0 ] && [ $rc2 = 0 ] && git -C '$T/remote.git' cat-file -e main:r1.txt && git -C '$T/remote.git' cat-file -e main:r2.txt"
check "history is linear" test -z "$(git -C "$T/remote.git" rev-list --merges main)"

# busy: the same clone's lock held elsewhere
worker b1; commit "$T/b1" b.txt 1
mkdir -p "$T/b1/.git/vbm-land"; ( exec 8>"$T/b1/.git/vbm-land/lock"; flock 8; sleep 8 ) & holder=$!
sleep 0.3; ( cd "$T/b1" && LAND_LOCK_WAIT_SECONDS=1 expect_exit "busy lock refuses" 15 "$L" ); kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true

# no force push anywhere in the lander; no `worktree prune` (it would drop other lanes' worktree records in a shared clone)
check "no force push in the source" bash -c "! grep -nE -- '--force|push +-f|push.*\\+(refs|\\\$)' '$L' | grep -v 'never\\|no force'"
check "no worktree prune in the source" bash -c "! grep -n 'worktree prune' '$L' | grep -v '^[0-9]*:.*#'"
worker s1; git -C "$T/s1" worktree add -q "$T/s1-other" -b other; commit "$T/s1" s.txt 1
( cd "$T/s1" && expect_exit "lands in a clone that has another worktree" 0 "$L" )
check "the other worktree is untouched" test -e "$T/s1-other/.git"
check "no stale worktree registered by the lander left behind" bash -c "git -C '$T/s1' worktree list | grep -c . | grep -q '^3$'"
finish
