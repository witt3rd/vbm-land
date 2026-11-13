#!/usr/bin/env bash
# bin/land-direct in two steps: `--validate` (rebase, every check on the rebased tree, no push; it PINS the commit it validated) and `--push SHA` (a fast-forward of
# exactly that commit, no check run again). A caller that decides what to do next (an orchestrator) reads the typed JSON summary, never the text: the result, the exit,
# the sha, and, for a failure, the reason, the path of the failing stage's whole log, the conflicted files. Every refusal is typed and nothing reaches the remote.
. "$(dirname "$0")/lib.sh"
sandbox
L=$ROOT/bin/land-direct
export RED_SLEEP=true
field() { tail -n1 "$T/out" | jq -r "$1"; }
set_conf "LAND_TEST_CMD=echo ran >> $T/count" 'LAND_REQUIRE_TRAILERS=Task-ID'
rm -f "$T/count"

echo "## validate: everything but the push, and the commit it validated is pinned"
worker a; commit "$T/a" one.txt 1; before=$(remote_head)
( cd "$T/a" && "$L" --validate >"$T/out" 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 0 ] && pass "--validate exits 0" || { fail "--validate exited $rc"; sed 's/^/     | /' "$T/out" >&2; }
check "the typed result is validated" test "$(field .result)" = validated
sha=$(field .sha); check "the summary names the validated commit (a full sha)" bash -c "[[ '$sha' =~ ^[0-9a-f]{40}\$ ]]"
check "nothing reached the remote" test "$(remote_head)" = "$before"
check "Tier 1 ran once, on the rebased tree" test "$(wc -l < "$T/count")" = 1
check "the commit is pinned (refs/vbm-land/validated/<sha>)" test "$(git -C "$T/a" rev-parse "refs/vbm-land/validated/$sha")" = "$sha"

echo "## push: exactly that commit, no check run again"
( cd "$T/a" && "$L" --push "$sha" >"$T/out" 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 0 ] && pass "--push exits 0" || { fail "--push exited $rc"; sed 's/^/     | /' "$T/out" >&2; }
check "the typed result is landed" test "$(field .result)" = landed
check "the remote's head IS the validated commit" test "$(remote_head)" = "$sha"
check "no check ran again: Tier 1 still ran once" test "$(wc -l < "$T/count")" = 1
check "the pin is gone once it has landed" bash -c "! git -C '$T/a' rev-parse -q --verify 'refs/vbm-land/validated/$sha' >/dev/null"
( cd "$T/a" && "$L" --push "$sha" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a second push of the same commit is refused: it is not pinned any more (exit 2, unvalidated)" bash -c "[ $rc = 2 ] && [ \"\$(tail -n1 '$T/out' | jq -r .result)\" = unvalidated ]"

echo "## push refuses what validate did not return"
worker b; commit "$T/b" two.txt 2; before=$(remote_head); real=$(git -C "$T/b" rev-parse HEAD)
( cd "$T/b" && "$L" --push "$real" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a commit that was never validated is refused (exit 2, unvalidated)" bash -c "[ $rc = 2 ] && [ \"\$(tail -n1 '$T/out' | jq -r .result)\" = unvalidated ]"
check "...and nothing reached the remote" test "$(remote_head)" = "$before"
( cd "$T/b" && "$L" --push not-a-sha >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "an argument that is not a full sha is refused before anything is read (exit 2)" test "$rc" = 2
check "--push does not combine with --validate" bash -c "cd '$T/b' && ! '$L' --push $real --validate >/dev/null 2>&1"

echo "## a moved base: typed, nothing pushed, and validating again lands"
worker c1; commit "$T/c1" three.txt 3
( cd "$T/c1" && "$L" --validate >"$T/out" 2>&1 ); sha1=$(field .sha)
worker c2; commit "$T/c2" four.txt 4
( cd "$T/c2" && "$L" >"$T/out" 2>&1 ) && pass "another lander lands in between" || fail "the other landing failed"
before=$(remote_head)
( cd "$T/c1" && "$L" --push "$sha1" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "the base moved since validation: exit 16, result moved" bash -c "[ $rc = 16 ] && [ \"\$(tail -n1 '$T/out' | jq -r .result)\" = moved ]"
check "...nothing was pushed" test "$(remote_head)" = "$before"
( cd "$T/c1" && "$L" --validate >"$T/out" 2>&1 ); sha2=$(field .sha)
check "validating again rebases onto the new base: a different commit" test "$sha2" != "$sha1"
( cd "$T/c1" && "$L" --push "$sha2" >"$T/out" 2>&1 ) && pass "pushing the new validated commit lands" || fail "the second push failed"
check "main has it" test "$(remote_head)" = "$sha2"

echo "## a hold stops the push too"
worker d; commit "$T/d" five.txt 5
( cd "$T/d" && "$L" --validate >"$T/out" 2>&1 ); shad=$(field .sha); before=$(remote_head)
( cd "$T/d" && "$L" --hold "stop for now" >/dev/null 2>&1 )
( cd "$T/d" && "$L" --push "$shad" >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a hold refuses the push (exit 14, result held)" bash -c "[ $rc = 14 ] && [ \"\$(tail -n1 '$T/out' | jq -r .result)\" = held ]"
check "...nothing reached the remote" test "$(remote_head)" = "$before"
( cd "$T/d" && "$L" --release >/dev/null 2>&1 )

echo "## the summary carries what a caller needs to decide, typed"
set_conf "LAND_TEST_CMD='echo details-of-the-red >&2; test ! -e BAD'"
worker e; commit "$T/e" BAD 6
( cd "$T/e" && "$L" --validate >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "red Tier 1: exit 13, result tier1" bash -c "[ $rc = 13 ] && [ \"\$(tail -n1 '$T/out' | jq -r .result)\" = tier1 ]"
check "the summary has a reason" bash -c "[ -n \"\$(tail -n1 '$T/out' | jq -r '.reason // empty')\" ]"
logf=$(field '.log // empty'); check "the summary names the failing stage's whole log, and it exists" bash -c "[ -f '$logf' ]"
check "...and that log holds the whole output (carried as text, never parsed by the lander for this)" grep -q "details-of-the-red" "$logf"
set_conf "LAND_TEST_CMD=true"
worker g1; commit "$T/g1" same.txt A; worker g2; commit "$T/g2" same.txt B
( cd "$T/g2" && "$L" >/dev/null 2>&1 )
( cd "$T/g1" && "$L" --validate >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "a conflict: exit 11, result conflict" bash -c "[ $rc = 11 ] && [ \"\$(tail -n1 '$T/out' | jq -r .result)\" = conflict ]"
check "the conflicted files are a typed list" bash -c "[ \"\$(tail -n1 '$T/out' | jq -r '.files | join(\" \")')\" = same.txt ]"

echo "## --dry-run is gone: it is --validate"
worker h; commit "$T/h" seven.txt 7
( cd "$T/h" && "$L" --dry-run >"$T/out" 2>&1 ) && rc=0 || rc=$?
check "--dry-run is refused (exit 2) and says what replaces it" bash -c "[ $rc = 2 ] && grep -q -- '--validate' '$T/out'"
finish
