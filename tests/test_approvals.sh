#!/usr/bin/env bash
# Gate-edit approvals (lib/approvals.sh, docs/gate-edit-approvals.md) through the real lander: a removed or changed line in a gate-defining file (LAND_GATE_APPEND_ONLY) is accepted
# ONLY on an exact diff-hash match against an approval already on the base branch; each attack on that rule has a negative test, and NOTHING reaches the remote when one is refused.
. "$(dirname "$0")/lib.sh"
sandbox
L=$ROOT/bin/land-direct
export LAND_LOCK_WAIT_SECONDS=5 RED_SLEEP=true
AP=scripts/gate-edit-approvals.txt; today=$(date -u +%F); yesterday=$(date -u -d yesterday +%F); old=$(date -u -d '30 days ago' +%F); future=$(date -u -d '10 days' +%F)
nothing_landed() { test "$(remote_head)" = "$before"; }
refused() {   # refused DESC DIR: land from DIR; it must exit 12 (the judge; the caller checks the message) and leave the remote untouched
  local d=$1 dir=$2; before=$(remote_head)
  ( cd "$dir" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
  if [ "$rc" = 12 ]; then pass "$d (exit $rc)"; else fail "$d: wanted exit 12, got $rc"; sed 's/^/     | /' "$T/out" >&2; fi
  check "$d: nothing reached the remote" nothing_landed
}
lands() { local d=$1 dir=$2; ( cd "$dir" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?; if [ "$rc" = 0 ]; then pass "$d (exit 0)"; else fail "$d: exit $rc"; sed 's/^/     | /' "$T/out" >&2; fi; }
hash_of() { ( cd "$1" && "$L" --print-gate-diff-hash "${2:-gate.sh}" 2>/dev/null ); }
record() { printf '%s | %s | %s | %s\n' "$2" "$3" "$4" "$5" >> "$1/$AP"; }                         # record DIR FILE HASH REASON DATE
cm() { git -C "$1" add -A; git -C "$1" commit -qm "${2:-chore(approvals): approval}" -m "Task-ID: t"; }   # commit everything in DIR
drop_line() { sed -i "\\#$2#d" "$1/$AP"; }                                                         # drop_line DIR PATTERN: delete the record(s) matching PATTERN
seed_gate() { seed_push gate.sh $'a\nb\nc'; seed_push other.txt $'x\ny\nz'; }
conf() { set_conf 'LAND_TEST_CMD=true' 'LAND_GATE_APPEND_ONLY=gate.sh' 'LAND_REQUIRE_TRAILERS=Task-ID' "$@"; }
seed_ap() { seed_push "$AP" "$(printf '%s\n' "$@")" "chore(approvals): seed"; }                   # records already on main (as if approval commits had landed)
drop_b() { sed -i '2d' "$1/gate.sh"; cm "$1" "feat: drop line b from the gate"; }                 # the gate edit: removes line 2

echo "## the canonical hash"
conf; seed_gate
worker e0; drop_b "$T/e0"
H=$(hash_of "$T/e0"); check "--print-gate-diff-hash prints a sha256" bash -c "[[ '$H' =~ ^[0-9a-f]{64}\$ ]]"
( cd "$T/e0" && "$L" --print-gate-diff gate.sh ) >"$T/out" 2>&1; out_has '^-b$'; out_has '^--- a/gate.sh$'
check "the hash is the sha256 of the canonical diff" bash -c "[ \"\$(cd '$T/e0' && '$L' --print-gate-diff gate.sh | sha256sum | cut -d' ' -f1)\" = '$H' ]"
check "the hash does not change with the user's diff configuration" bash -c "cd '$T/e0' && git config diff.noprefix true && git config diff.algorithm patience && git config core.abbrev 4 && [ \"\$('$L' --print-gate-diff-hash gate.sh 2>/dev/null)\" = '$H' ]"
( cd "$T/e0" && "$L" --print-gate-diff-hash other.txt ) >"$T/out" 2>&1 && fail "a file that did not change has nothing to approve" || pass "a file that did not change has nothing to approve"
worker e0b; sed -i '2d' "$T/e0b/other.txt"; cm "$T/e0b" "feat: drop line y of another file"
H2=$(hash_of "$T/e0b" other.txt); check "the hash binds the path: the same removed line of another file has another hash" test "$H2" != "$H"

echo "## without an approval"
worker g1; printf 'd\n' >> "$T/g1/gate.sh"; cm "$T/g1" "feat: add a line to the gate"
lands "an append-only gate file may GAIN lines with no approval" "$T/g1"
worker g2; drop_b "$T/g2"
refused "a removed line in a gate file with no approval is refused" "$T/g2"; out_has "may only GAIN lines"; out_has "$H"
worker g3; sed -i '1s/a/A/' "$T/g3/gate.sh"; cm "$T/g3" "feat: change line a"
refused "a CHANGED line is refused too" "$T/g3"
worker g4; rm "$T/g4/gate.sh"; cm "$T/g4" "feat: delete the gate"
refused "deleting the gate file is refused" "$T/g4"
worker g5; chmod +x "$T/g5/gate.sh"; cm "$T/g5" "feat: make the gate executable"
refused "a mode change of the gate file is refused" "$T/g5"
worker g6; sed -i '1d' "$T/g6/other.txt"; cm "$T/g6" "feat: edit a file that is not append-only"
lands "a file outside LAND_GATE_APPEND_ONLY is not judged for removed lines" "$T/g6"

echo "## the approval flow: the approval lands alone, first; the edit lands after it and consumes it"
worker p1; record "$T/p1" gate.sh "$H" "drop line b: it is dead" "$today"; cm "$T/p1"
lands "the approval commit lands alone" "$T/p1"; out_has "APPROVAL COMMIT: announce to the judge before landing the edit"; out_has "protected set: TOUCHED ($AP)"
check "the approval record is on main" remote_has "$AP"
worker e1; drop_b "$T/e1"
refused "the edit WITHOUT removing the approval line is refused: it must be consumed by its landing" "$T/e1"; out_has "its line is still in"
drop_line "$T/e1" "^gate.sh | $H"; cm "$T/e1" "chore(approvals): consume the approval"
seed_exec scripts/land.d/post-rebase $'#!/usr/bin/env bash\ncp "$LAND_GATE_APPROVED_FILE" "$APPROVED_COPY"'
export APPROVED_COPY=$T/approved.copy
lands "the edit lands with the approval removed in the same landing (consumed)" "$T/e1"; out_has "gate edit APPROVED"
check "the edit is on main" bash -c "! git -C '$T/remote.git' show main:gate.sh | grep -qx b"
check "the approval line is gone from main" bash -c "! git -C '$T/remote.git' show main:$AP | grep -q '^gate.sh'"
check "the hooks were told which approvals this landing used (LAND_GATE_APPROVED_FILE)" grep -qx "gate.sh $H" "$APPROVED_COPY"

echo "## reuse: an approval is one-time"
worker u1; sed -i '1a b' "$T/u1/gate.sh"; cm "$T/u1" "feat: restore line b"
lands "restoring the line (a pure gain) lands" "$T/u1"
worker u2; drop_b "$T/u2"
check "the same edit again has the SAME diff hash" test "$(hash_of "$T/u2")" = "$H"
refused "the same diff a second time is refused: its approval was consumed" "$T/u2"; out_has "may only GAIN lines"
worker u3; drop_b "$T/u3"; record "$T/u3" gate.sh "$H" "drop line b again" "$today"; cm "$T/u3" "chore(approvals): self-approve the second edit"
refused "re-adding the consumed record in the same LANDING as the edit is refused (a record the change brings is no approval)" "$T/u3"; out_has "lands ALONE"

echo "## a hash over a different diff"
worker d1; sed -i '3d' "$T/d1/gate.sh"; cm "$T/d1" "feat: drop line c"
HC=$(hash_of "$T/d1"); check "dropping line c is a different diff" test "$HC" != "$H"
worker d2; record "$T/d2" gate.sh "$HC" "drop line c" "$today"; cm "$T/d2"; lands "(an approval of the diff that drops c lands)" "$T/d2"
worker d3; drop_b "$T/d3"; drop_line "$T/d3" "^gate.sh | $HC"; cm "$T/d3" "chore(approvals): remove it anyway"
refused "an approval for a different diff (drops c) does not approve this edit (drops b)" "$T/d3"
worker d4; sed -i '2,3d' "$T/d4/gate.sh"; cm "$T/d4" "feat: drop b and c"; drop_line "$T/d4" "^gate.sh | $HC"; cm "$T/d4" "chore(approvals): consume"
refused "an approval covers its exact diff: a bigger edit (b and c) is refused" "$T/d4"
worker d5; sed -i '3d' "$T/d5/gate.sh"; printf 'e\n' >> "$T/d5/gate.sh"; cm "$T/d5" "feat: drop c and add e"; drop_line "$T/d5" "^gate.sh | $HC"; cm "$T/d5" "chore(approvals): consume"
refused "the same removal with one more added line is a different diff: refused" "$T/d5"
worker d6; sed -i '3d' "$T/d6/gate.sh"; sed -i '3d' "$T/d6/other.txt"; cm "$T/d6" "feat: drop c in the gate and edit another file"; drop_line "$T/d6" "^gate.sh | $HC"; cm "$T/d6" "chore(approvals): consume"
lands "(control) the exact diff, consumed in the same landing, lands; other files in the landing do not matter" "$T/d6"
check "and the consumed record is gone" bash -c "! git -C '$T/remote.git' show main:$AP | grep -q '^gate.sh'"

echo "## stale approvals"
sandbox; conf; seed_gate; worker s0; drop_b "$T/s0"; H=$(hash_of "$T/s0")
seed_ap "gate.sh | $H | drop line b | $old"
worker s1; drop_b "$T/s1"; drop_line "$T/s1" "^gate.sh | $H"; cm "$T/s1" "chore(approvals): consume"
refused "an approval older than 7 days approves nothing" "$T/s1"; out_has "is stale"
worker s2; record "$T/s2" gate.sh "$H" "late" "$old"; cm "$T/s2"
refused "adding an approval that is already stale is refused" "$T/s2"; out_has "outside the window"
worker s3; record "$T/s3" gate.sh "$H" "forever" "$future"; cm "$T/s3"
refused "a future-dated approval (eternal freshness) is refused" "$T/s3"; out_has "outside the window"
worker s4; drop_line "$T/s4" "^gate.sh | $H"; cm "$T/s4" "chore(approvals): tidy a stale approval"
lands "a stale record may be tidied away (it approves nothing)" "$T/s4"

echo "## forged approvals"
sandbox; conf; seed_gate; worker f0; drop_b "$T/f0"; H=$(hash_of "$T/f0")
seed_ap "gate.sh | $(printf '%064x' 12345) | forged hash | $today"
worker f1; drop_b "$T/f1"; drop_line "$T/f1" "forged hash"; cm "$T/f1" "chore(approvals): consume"
refused "an approval whose hash is not the diff's approves nothing" "$T/f1"
worker f2; echo 'gate.sh | not-a-hash | reason | 2026-01-01' >> "$T/f2/$AP"; cm "$T/f2"
refused "a malformed record is refused (it must not pass for an approval)" "$T/f2"; out_has "not an approval record"
worker f3; record "$T/f3" "$AP" "$(printf '%064x' 1)" "approve the approvals file" "$today"; cm "$T/f3"
refused "an approval that names the approvals file itself is refused" "$T/f3"; out_has "may not name the approvals file"
worker f4; record "$T/f4" gate.sh "$H" "ok" "$today"; drop_b "$T/f4"
refused "a forged approval: the line and the edit in one commit (self-approval)" "$T/f4"; out_has "lands ALONE"

echo "## an approval line removed afterward"
sandbox; conf; seed_gate; worker r0; drop_b "$T/r0"; H=$(hash_of "$T/r0")
seed_ap "gate.sh | $H | drop line b | $today"
worker r1; drop_line "$T/r1" "^gate.sh | $H"; cm "$T/r1" "chore(approvals): quietly remove it"
refused "removing a fresh, unconsumed approval is flagged and refused" "$T/r1"; out_has "removed without being consumed"
worker r2; sed -i "s/$today/$yesterday/" "$T/r2/$AP"; cm "$T/r2" "chore(approvals): re-date it"
refused "editing (re-dating) an approval removes the old line: refused" "$T/r2"
worker r3; rm "$T/r3/$AP"; cm "$T/r3" "chore(approvals): delete the whole file"
refused "deleting the approvals file takes every approval with it: refused" "$T/r3"
wd_commit() { git -C "$1" add -A; git -C "$1" commit -qm "chore(approvals): withdraw" -m "Approval-Withdrawn: $2" -m "Task-ID: t"; }
worker w1; drop_line "$T/w1" "^gate.sh | $H"; wd_commit "$T/w1" "gate.sh ${H:0:12}"
lands "a withdrawal: the trailer names the record and the commit changes nothing else" "$T/w1"; out_has "APPROVAL WITHDRAWN: announce to the judge"
check "the withdrawn record is gone from main" bash -c "! git -C '$T/remote.git' show main:$AP | grep -q '^gate.sh'"
seed_ap "gate.sh | $H | drop line b | $today"
worker w2; drop_line "$T/w2" "^gate.sh | $H"; wd_commit "$T/w2" "gate.sh ${H:0:11}"
refused "a trailer with a hash prefix shorter than 12 digits withdraws nothing" "$T/w2"
worker w3; drop_line "$T/w3" "^gate.sh | $H"; wd_commit "$T/w3" "other.txt ${H:0:12}"
refused "a trailer naming another file withdraws nothing" "$T/w3"
worker w4; drop_line "$T/w4" "^gate.sh | $H"; wd_commit "$T/w4" "gate.sh $(printf '%012x' 99)"
refused "a trailer with another hash withdraws nothing" "$T/w4"
worker w5; drop_line "$T/w5" "^gate.sh | $H"; echo n > "$T/w5/n.txt"; wd_commit "$T/w5" "gate.sh ${H:0:12}"
refused "a withdrawal riding along with other files is refused (it lands ALONE)" "$T/w5"; out_has "withdrawal lands ALONE"
worker r5; drop_b "$T/r5"; drop_line "$T/r5" "^gate.sh | $H"; cm "$T/r5" "chore(approvals): consume"
lands "(control) the exact edit with its consumption lands" "$T/r5"

echo "## the approvals file edited in the same commit or landing as the edit"
sandbox; conf; seed_gate; worker c0; drop_b "$T/c0"; H=$(hash_of "$T/c0")
worker c1; record "$T/c1" gate.sh "$H" "self" "$today"; drop_b "$T/c1"
refused "approval and edit in ONE commit" "$T/c1"; out_has "lands ALONE"
worker c2; record "$T/c2" gate.sh "$H" "self" "$today"; cm "$T/c2"; drop_b "$T/c2"; drop_line "$T/c2" "^gate.sh | $H"; cm "$T/c2" "chore(approvals): consume"
refused "approval commit, edit commit and consumption in ONE landing (approvals are read from main, not from the change)" "$T/c2"
worker c3; record "$T/c3" gate.sh "$H" "self" "$today"; cm "$T/c3"; drop_b "$T/c3"
refused "approval commit then edit commit in ONE landing, approval line kept" "$T/c3"; out_has "lands ALONE"
worker c4; record "$T/c4" gate.sh "$H" "tuck it into a bigger change" "$today"; printf 'new\n' > "$T/c4/other-file.txt"; cm "$T/c4" "feat: a feature and an approval"
refused "an approval riding along with unrelated files is refused" "$T/c4"; out_has "lands ALONE"

echo "## an approval commit adds exactly ONE line"
sandbox; conf; seed_gate; worker o0; drop_b "$T/o0"; H=$(hash_of "$T/o0"); HC=$(printf '%064x' 3)
worker o1; record "$T/o1" gate.sh "$H" "one" "$today"; record "$T/o1" other.txt "$HC" "two" "$today"; cm "$T/o1"
refused "two approvals in one commit are refused" "$T/o1"; out_has "exactly ONE line"
worker o2; record "$T/o2" gate.sh "$H" "one" "$today"; echo "# a comment line too" >> "$T/o2/$AP"; cm "$T/o2"
refused "an approval plus a comment line (two lines) is refused" "$T/o2"; out_has "exactly ONE line"
seed_ap "gate.sh | $(printf '%064x' 9) | an old one | $old"
worker o3; record "$T/o3" gate.sh "$H" "one" "$today"; drop_line "$T/o3" "an old one"; cm "$T/o3"
refused "an approval that also removes a line (even a stale one) is refused" "$T/o3"; out_has "exactly ONE line"
worker o4; record "$T/o4" gate.sh "$H" "one" "$today"; cm "$T/o4"; record "$T/o4" other.txt "$HC" "two" "$today"; cm "$T/o4"
refused "two approval commits in one landing (two approvals) are refused" "$T/o4"; out_has "one approval only"
worker o5; record "$T/o5" gate.sh "$H" "one" "$today"; cm "$T/o5"
lands "(control) one commit, one line, only the approvals file: lands" "$T/o5"; out_has "FULL edit diff"

echo "## the judge fails closed"
sandbox; conf; seed_gate; mkdir -p "$T/mut"; cp -r "$ROOT/bin" "$ROOT/lib" "$ROOT/VERSION" "$T/mut/"
sed -i 's/^  : > "\$state\/approved-gate-edits.txt"; : > "\$USED"$/  : > "$state\/approved-gate-edits.txt"; : > "$USED"; false/' "$T/mut/lib/approvals.sh"
check "(the crash is in the copy)" grep -q '"\$USED"; false' "$T/mut/lib/approvals.sh"
worker k1; commit "$T/k1" z.txt 1
( cd "$T/k1" && "$T/mut/bin/land-direct" >"$T/out" 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 12 ] && pass "a judge that crashes part-way refuses the landing (exit 12)" || fail "a crashing judge gave exit $rc"; out_has "failed unexpectedly"

echo "## the config comes from main"
sandbox; conf; seed_gate
worker m1; drop_b "$T/m1"; sed -i '/GATE_APPEND_ONLY/d' "$T/m1/scripts/land.conf"; cm "$T/m1" "feat: loosen the config and drop the line"
refused "removing LAND_GATE_APPEND_ONLY in the change does not loosen the rule that judges it" "$T/m1"
conf 'LAND_APPROVALS='; worker m2; commit "$T/m2" z.txt 1; ( cd "$T/m2" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass "an empty LAND_APPROVALS (approvals off) is a bad configuration (exit 2)" || fail "an empty LAND_APPROVALS gave exit $rc"
finish
