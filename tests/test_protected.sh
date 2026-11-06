#!/usr/bin/env bash
# Protected-set approvals (lib/approvals.sh ga_protected, docs/gate-edit-approvals.md, "Protected sets") through the real lander: with LAND_PROTECTED_LIST set, a landing whose net diff touches ANY path of the
# protected-paths list is refused (12) unless a one-time approval for exactly that file-set and exactly that net diff is already on the base branch. Every attack has a negative test and NOTHING reaches the remote when one is refused.
# Run twice: the approvals in a file of their own (a consumer with its own baseline approvals) and in the shared gate-edit approvals file (the default).
. "$(dirname "$0")/lib.sh"
L=$ROOT/bin/land-direct
export RED_SLEEP=true
today=$(date -u +%F); old=$(date -u -d '30 days ago' +%F)
LIST=scripts/protected-paths.txt
nothing_landed() { test "$(remote_head)" = "$before"; }
refused() { local d=$1 dir=$2; before=$(remote_head)
  ( cd "$dir" && "$L" ${3:-} >"$T/out" 2>&1 ) && rc=0 || rc=$?
  if [ "$rc" = 12 ]; then pass "$d (exit $rc)"; else fail "$d: wanted exit 12, got $rc"; sed 's/^/     | /' "$T/out" >&2; fi
  check "$d: nothing reached the remote" nothing_landed; }
lands() { local d=$1 dir=$2; ( cd "$dir" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?; if [ "$rc" = 0 ]; then pass "$d (exit 0)"; else fail "$d: exit $rc"; sed 's/^/     | /' "$T/out" >&2; fi; }
hash_of() { ( cd "$1" && "$L" --print-gate-diff-hash "$2" 2>/dev/null ); }
cm() { git -C "$1" add -A; git -C "$1" commit -qm "${2:-chore(approvals): approval}" -m "Task-ID: t"; }
cmi() { git -C "$1" commit -qm "$2" -m "Task-ID: t"; }                                               # commit the index as it is
record() { printf '%s | %s | %s | %s\n' "$2" "$3" "$4" "$5" >> "$1/$PAP"; }                  # record DIR SET HASH REASON DATE
drop_line() { sed -i "\\#$2#d" "$1/$PAP"; }
seed_pap() { seed_push "$PAP" "$(printf '%s\n' "$@")" "chore(approvals): seed"; }
list_body() { printf '%s\n' '# the protected set' 'gate.sh' 'spec/' 'scripts/*Gate.lean' '?later/' '.github/workflows/'; }
base_files() { seed_push gate.sh $'a\nb\nc'; seed_push spec/x $'1\n2'; seed_push other.txt $'x\ny'; seed_push scripts/AxGate.lean g; seed_push .github/workflows/ci.yml w; seed_push "$LIST" "$(list_body)" "chore: list"; }
conf() { set_conf 'LAND_TEST_CMD=true' 'LAND_REQUIRE_TRAILERS=Task-ID' "LAND_PROTECTED_LIST=$LIST" ${SEP:+"LAND_PROTECTED_APPROVALS=$PAP"} "$@"; }
fresh() { sandbox; conf "$@"; base_files; }
edit_gate() { sed -i 2d "$1/gate.sh"; cm "$1" "feat: drop line b of the gate"; }               # touches gate.sh
edit_spec() { echo 3 >> "$1/spec/x"; cm "$1" "feat: add to spec"; }

suite() {   # suite NAME SEP: SEP=1 -> the protected approvals live in their own file
  echo "######## $1"
  SEP=$2; if [ -n "$SEP" ]; then PAP=scripts/protected-approvals.txt; else PAP=scripts/gate-edit-approvals.txt; fi

  echo "## the set key and the hash"
  fresh; worker a0; edit_gate "$T/a0"; edit_spec "$T/a0"
  H=$(hash_of "$T/a0" gate.sh,spec/x); check "--print-gate-diff-hash takes a file set: a sha256" bash -c "[[ '$H' =~ ^[0-9a-f]{64}\$ ]]"
  check "the set is canonical: the order of the paths does not matter" test "$(hash_of "$T/a0" spec/x,gate.sh)" = "$H"
  check "@protected is the touched protected set" test "$(hash_of "$T/a0" @protected)" = "$H"
  check "the hash binds the set: one file alone has another hash" test "$(hash_of "$T/a0" gate.sh)" != "$H"
  ( cd "$T/a0" && "$L" --print-gate-diff @protected ) >"$T/out" 2>&1; out_has '^-b$'; out_has '^+3$'
  ( cd "$T/a0" && "$L" --print-gate-diff-hash other.txt ) >"$T/out" 2>&1 && fail "an unchanged file has nothing to approve" || pass "an unchanged file has nothing to approve"
  ( cd "$T/a0" && "$L" --print-gate-diff-hash 'gate.sh,../x' ) >"$T/out" 2>&1 && fail "a bad path in the set is refused" || pass "a bad path in the set is refused"

  echo "## nothing protected touched: lands with no approval"
  fresh; worker n1; commit "$T/n1" other.txt $'x\ny\nz'; lands "an unprotected file" "$T/n1"; out_has "none touched"
  worker n2; echo more >> "$T/n2/later-file"; cm "$T/n2" "feat: later file"; lands "a path of a '?' entry that does not exist yet is not touched" "$T/n2"

  echo "## without an approval: the misread-message case"
  fresh; worker p1; edit_gate "$T/p1"
  refused "a protected file changed with no approval line on base is refused" "$T/p1"; out_has "no approval for exactly that set"; out_has "Set: gate.sh"; out_has "Hash: $(hash_of "$T/p1" gate.sh)"
  refused "--dry-run is refused the same" "$T/p1" --dry-run
  worker p2; echo 4 >> "$T/p2/spec/x"; mkdir -p "$T/p2/spec/deep"; echo d > "$T/p2/spec/deep/y"; cm "$T/p2" "feat: spec"; refused "a directory entry covers every path under it" "$T/p2"
  worker p3; echo n > "$T/p3/scripts/NewGate.lean"; cm "$T/p3" "feat: a new gate"; refused "a name pattern covers a NEW path" "$T/p3"
  worker p4; echo w >> "$T/p4/.github/workflows/ci.yml"; cm "$T/p4" "feat: ci"; refused "a dot-directory entry covers its files" "$T/p4"
  worker p5; edit_gate "$T/p5"; echo o > "$T/p5/other2.txt"; cm "$T/p5" "feat: protected and unprotected"; refused "unprotected files alongside a protected one do not help" "$T/p5"
  worker p6; commit "$T/p6" other.txt $'q'; git -C "$T/p6" commit -q --amend -m "feat: other" -m "Task-ID: t"; edit_gate "$T/p6"; refused "a protected edit in the second commit of a landing is refused" "$T/p6"
  worker p7; edit_gate "$T/p7"; sed -i '1i b' "$T/p7/gate.sh"; sed -i '1,2d' "$T/p7/gate.sh"; cm "$T/p7" "feat: more"; refused "a different net diff of the same file: refused (no approval at all)" "$T/p7"
  worker p8; sed -i 2d "$T/p8/gate.sh"; cm "$T/p8" "feat: drop"; git -C "$T/p8" revert --no-edit HEAD >/dev/null; git -C "$T/p8" commit -q --amend -m "revert: drop" -m "Task-ID: t"; lands "(control) a change and its revert in one landing is no net change: nothing protected is touched" "$T/p8"

  echo "## the approval flow: the approval lands alone, first; the change lands after it and consumes it"
  fresh; worker f0; edit_gate "$T/f0"; H=$(hash_of "$T/f0" gate.sh)
  worker f1; record "$T/f1" gate.sh "$H" "drop line b of the gate: dead" "$today"; cm "$T/f1"
  lands "the approval commit lands alone (the approvals file needs no approval of its own)" "$T/f1"; out_has "APPROVAL COMMIT: announce to the judge"
  worker f2; edit_gate "$T/f2"
  refused "the change WITHOUT removing the approval line is refused: it must be consumed" "$T/f2"; out_has "its line is still in"
  drop_line "$T/f2" "^gate.sh | $H"; cm "$T/f2" "chore(approvals): consume"
  seed_exec scripts/land.d/post-rebase $'#!/usr/bin/env bash\ncp "$LAND_GATE_APPROVED_FILE" "$APPROVED_COPY"'
  export APPROVED_COPY=$T/approved.copy
  lands "the change lands with the approval removed in the same landing" "$T/f2"; out_has "protected set APPROVED: gate.sh"
  check "the change is on main" bash -c "! git -C '$T/remote.git' show main:gate.sh | grep -qx b"
  check "the approval line is gone from main" bash -c "! git -C '$T/remote.git' show main:$PAP | grep -q '^gate.sh'"
  check "the hooks were told which approval was used" grep -qx "gate.sh $H" "$APPROVED_COPY"
  echo "## reuse"
  worker f3; sed -i '1a b' "$T/f3/gate.sh"; cm "$T/f3" "feat: restore b"; refused "(a pure addition to a protected file needs an approval too)" "$T/f3"
  worker f4; edit_gate "$T/f4"; git -C "$T/f4" fetch -q; refused "the same change a second time: its approval was consumed" "$T/f4"
  worker f5; record "$T/f5" gate.sh "$H" "again" "$today"; edit_gate "$T/f5"; refused "the line re-added in the same commit as the change (self-approval)" "$T/f5"; out_has "lands ALONE"

  echo "## forged and wrong approvals"
  fresh; worker w0; edit_gate "$T/w0"; H=$(hash_of "$T/w0" gate.sh); worker w0b; edit_spec "$T/w0b"; edit_gate "$T/w0b"; HB=$(hash_of "$T/w0b" gate.sh,spec/x)
  seed_pap "gate.sh | $(printf '%064x' 5) | forged hash | $today"
  worker w1; edit_gate "$T/w1"; drop_line "$T/w1" "forged hash"; cm "$T/w1" "chore(approvals): consume"
  refused "a forged line (a hash that is not the diff's) approves nothing" "$T/w1"
  fresh; seed_pap "gate.sh | $HB | wrong set: the hash is of a bigger set | $today"
  worker w2; edit_gate "$T/w2"; drop_line "$T/w2" "wrong set"; cm "$T/w2" "chore(approvals): consume"
  refused "the hash of another set (gate.sh,spec/x) under the key gate.sh does not approve gate.sh" "$T/w2"
  fresh; seed_pap "gate.sh | $H | only gate.sh | $today"
  worker w3; edit_gate "$T/w3"; edit_spec "$T/w3"; drop_line "$T/w3" "only gate.sh"; cm "$T/w3" "chore(approvals): consume"
  refused "an approval for a SUBSET of the touched paths (gate.sh) does not approve gate.sh and spec/x" "$T/w3"; out_has "Set: gate.sh,spec/x"
  fresh; seed_pap "gate.sh,spec/x | $HB | the bigger set | $today"
  worker w4; edit_gate "$T/w4"; drop_line "$T/w4" "the bigger set"; cm "$T/w4" "chore(approvals): consume"
  refused "an approval for a SUPERSET (gate.sh,spec/x) does not approve a change to gate.sh alone" "$T/w4"
  fresh; seed_pap "gate.sh,spec/x | $H | the superset key with the diff hash of gate.sh alone | $today"
  worker w4b; edit_gate "$T/w4b"; drop_line "$T/w4b" "superset key"; cm "$T/w4b" "chore(approvals): consume"
  refused "a record whose key is a superset but whose hash IS this diff's (spec/x unchanged) does not approve: the set must be exactly the touched paths" "$T/w4b"
  fresh; seed_pap "gate.sh,spec/x | $HB | the bigger set | $today"
  worker w5; edit_gate "$T/w5"; edit_spec "$T/w5"; drop_line "$T/w5" "the bigger set"; cm "$T/w5" "chore(approvals): consume"
  lands "(control) the exact set, the exact diff, consumed in the landing, lands" "$T/w5"
  check "both files changed on main" bash -c "git -C '$T/remote.git' show main:spec/x | grep -qx 3 && ! git -C '$T/remote.git' show main:gate.sh | grep -qx b"
  fresh; worker w6; edit_gate "$T/w6"; HD=$(hash_of "$T/w6" gate.sh); seed_pap "gate.sh | $HD | drop b | $today"
  worker w7; sed -i 3d "$T/w7/gate.sh"; cm "$T/w7" "feat: drop c instead"; drop_line "$T/w7" "drop b"; cm "$T/w7" "chore(approvals): consume"
  refused "an approval of a different diff of the same file (drops b) does not approve this one (drops c)" "$T/w7"
  worker w8; sed -i 2d "$T/w8/gate.sh"; echo e >> "$T/w8/gate.sh"; cm "$T/w8" "feat: drop b add e"; drop_line "$T/w8" "drop b"; cm "$T/w8" "chore(approvals): consume"
  refused "one more added line is a different diff: refused" "$T/w8"
  worker w9; edit_gate "$T/w9"; drop_line "$T/w9" "drop b"; cm "$T/w9" "chore(approvals): consume"; lands "(control) the exact approved diff lands" "$T/w9"

  echo "## stale, future-dated, malformed and non-canonical records"
  fresh; worker s0; edit_gate "$T/s0"; H=$(hash_of "$T/s0" gate.sh); seed_pap "gate.sh | $H | old | $old"
  worker s1; edit_gate "$T/s1"; drop_line "$T/s1" "| old |"; cm "$T/s1" "chore(approvals): consume"; refused "an approval older than 7 days approves nothing" "$T/s1"; out_has "is stale"
  worker s2; record "$T/s2" gate.sh "$H" late "$old"; cm "$T/s2"; refused "adding an already stale approval is refused" "$T/s2"
  for bad in "spec/x,gate.sh" "gate.sh,gate.sh" "gate.sh,,spec/x" "gate.sh, spec/x" ",gate.sh" "gate.sh," "gate.sh,../x" "gate.sh,/etc/x"; do
    nk=$((${nk:-0} + 1)); wd=$T/bk$nk; worker "bk$nk"; record "$wd" "$bad" "$H" "bad key" "$today"; cm "$wd"; refused "a record with the key '$bad' (not canonical) is refused" "$wd"
  done
  worker s3; record "$T/s3" "$PAP" "$H" self "$today"; cm "$T/s3"; refused "an approval that names the approvals file is refused" "$T/s3"; out_has "may not name the approvals file"
  worker s4; record "$T/s4" "gate.sh,$PAP" "$H" self "$today"; cm "$T/s4"; refused "a set that includes the approvals file is refused" "$T/s4"

  echo "## the approvals file edited with the change"
  fresh; worker c0; edit_gate "$T/c0"; H=$(hash_of "$T/c0" gate.sh)
  worker c1; record "$T/c1" gate.sh "$H" self "$today"; edit_gate "$T/c1"; refused "approval and change in ONE commit" "$T/c1"; out_has "lands ALONE"
  worker c2; record "$T/c2" gate.sh "$H" self "$today"; cm "$T/c2"; edit_gate "$T/c2"; drop_line "$T/c2" "^gate.sh | $H"; cm "$T/c2" "chore(approvals): consume"
  refused "approval commit, change commit and consumption in ONE landing (approvals are read from main)" "$T/c2"
  worker c3; record "$T/c3" gate.sh "$H" self "$today"; echo n > "$T/c3/spec/new"; cm "$T/c3"; refused "an approval riding along with a protected file" "$T/c3"
  seed_pap "gate.sh | $H | ok | $today"
  worker c4; drop_line "$T/c4" "^gate.sh | $H"; cm "$T/c4" "chore(approvals): quietly remove it"; refused "an approval removed without being consumed is flagged" "$T/c4"; out_has "removed without being consumed"
  worker c5; rm "$T/c5/$PAP"; cm "$T/c5" "chore(approvals): delete the file"; refused "deleting the approvals file" "$T/c5"
  worker c6; drop_line "$T/c6" "^gate.sh | $H"; git -C "$T/c6" add -A; git -C "$T/c6" commit -qm "chore(approvals): withdraw" -m "Approval-Withdrawn: gate.sh ${H:0:12}" -m "Task-ID: t"
  lands "a withdrawal by trailer still works for a set record" "$T/c6"; out_has "APPROVAL WITHDRAWN"

  echo "## the protected list: loosening it is itself protected"
  fresh; worker l0; sed -i '/^gate.sh$/d' "$T/l0/$LIST"; cm "$T/l0" "feat: drop gate.sh from the protected list"
  refused "removing an entry from the list needs an approval" "$T/l0"; out_has "Set: $LIST"
  worker l1; sed -i '/^gate.sh$/d' "$T/l1/$LIST"; edit_gate "$T/l1"; refused "loosening the list and editing the freed file in one landing is refused (the base list still covers it)" "$T/l1"; out_has "Set: gate.sh,$LIST"
  worker l2; sed -i '/^gate.sh$/d' "$T/l2/$LIST"; cm "$T/l2" "feat: loosen"; HL=$(hash_of "$T/l2" "$LIST")
  fresh; seed_pap "$LIST | $HL | the judge read the diff: gate.sh leaves the list | $today"
  worker l3; sed -i '/^gate.sh$/d' "$T/l3/$LIST"; drop_line "$T/l3" "^$LIST"; cm "$T/l3" "feat: loosen, approved"; lands "(control) the exact approved loosening lands" "$T/l3"
  worker l4; echo 'new/' >> "$T/l4/$LIST"; mkdir -p "$T/l4/new"; echo n > "$T/l4/new/f"; cm "$T/l4" "feat: new entry and a file under it"
  refused "adding an entry and a file under it in one landing needs both (the change's own list counts)" "$T/l4"; out_has "Set: new/f,$LIST"
  worker l5; sed -i 's#^spec/$#spec/x#' "$T/l5/$LIST"; cm "$T/l5" "feat: narrow spec/ to one file"; refused "narrowing a directory entry is a loosening: refused" "$T/l5"
  worker l6; rm "$T/l6/$LIST"; cm "$T/l6" "feat: delete the list"; refused "deleting the list is refused" "$T/l6"
  worker l7; printf '# nothing\n' > "$T/l7/$LIST"; cm "$T/l7" "feat: empty the list"; refused "emptying the list is refused" "$T/l7"
  worker l8; ln -sf gate.sh "$T/l8/$LIST"; cm "$T/l8" "feat: the list as a symlink"; refused "the list replaced by a symlink is refused" "$T/l8"
  echo "## the configuration and the hooks are protected under the list"
  worker k1; echo '# c' >> "$T/k1/scripts/land.conf"; cm "$T/k1" "feat: touch the configuration"; refused "scripts/land.conf is protected when the list is on" "$T/k1"; out_has "scripts/land.conf"
  worker k2; mkdir -p "$T/k2/scripts/land.d"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/k2/scripts/land.d/pre-rebase"; chmod +x "$T/k2/scripts/land.d/pre-rebase"; cm "$T/k2" "feat: a hook"; refused "the hooks directory is protected when the list is on" "$T/k2"

  echo "## renames, modes, symlinks, submodules"
  fresh
  worker r1; git -C "$T/r1" mv gate.sh moved.sh; cm "$T/r1" "feat: move the gate out of the protected set"; refused "a protected file renamed to an unprotected name (the old path is touched)" "$T/r1"; out_has "Set: gate.sh"
  worker r2; git -C "$T/r2" mv other.txt spec/other.txt; cm "$T/r2" "feat: move a file into the protected directory"; refused "an unprotected file renamed INTO the protected directory" "$T/r2"
  worker r3; chmod +x "$T/r3/gate.sh"; cm "$T/r3" "feat: mode change"; refused "a mode change of a protected file" "$T/r3"
  worker r4; rm "$T/r4/gate.sh"; ln -s other.txt "$T/r4/gate.sh"; cm "$T/r4" "feat: the gate becomes a symlink"; refused "a protected file replaced by a symlink" "$T/r4"
  worker r5; git -C "$T/r5" rm -q -r spec; ln -s other.txt "$T/r5/spec"; cm "$T/r5" "feat: the protected directory becomes a symlink"; refused "a protected directory replaced by a symlink to an unprotected file" "$T/r5"
  worker r6; git -C "$T/r6" update-index --add --cacheinfo 160000,"$(git -C "$T/r6" rev-parse HEAD)",spec/sub; cmi "$T/r6" "feat: a submodule under the protected directory"; refused "a submodule (gitlink) under a protected directory" "$T/r6"
  worker r7; git -C "$T/r7" update-index --add --cacheinfo 160000,"$(git -C "$T/r7" rev-parse HEAD)",scripts/ZGate.lean; cmi "$T/r7" "feat: a gitlink with a protected name"; refused "a gitlink at a protected name" "$T/r7"
  worker r8; git -C "$T/r8" rm -q gate.sh; cm "$T/r8" "feat: delete the gate"; refused "deleting a protected file" "$T/r8"
  worker r9; mkdir -p "$T/r9/x"; echo y > "$T/r9/x/y"; git -C "$T/r9" mv gate.sh "x/gate.sh"; cm "$T/r9" "feat: nest the gate"; refused "a protected file moved under another directory" "$T/r9"
  H=$(hash_of "$T/r1" gate.sh,moved.sh 2>/dev/null) || true; check "the approval for a rename names both paths (the diff has no rename detection)" bash -c "( cd '$T/r1' && '$L' --print-gate-diff-hash @protected 2>/dev/null ) | grep -qE '^[0-9a-f]{64}\$'"
  ( cd "$T/r1" && "$L" --print-gate-diff @protected | sed -n 1p ) >"$T/out" 2>&1; out_has 'a/gate.sh'

  echo "## the list fails closed"
  fresh; seed_push "$LIST" $'# no entries at all\n' "chore: empty list"; worker e1; commit "$T/e1" other.txt z; refused "an EMPTY list on base refuses every landing, even an unprotected file" "$T/e1"; out_has "no entries"
  fresh; seed_push "$LIST" $'gate.sh\nnot an entry!' "chore: bad line"; worker e2; commit "$T/e2" other.txt z; refused "a malformed line in the list on base refuses every landing" "$T/e2"; out_has "not an entry"
  fresh; ( cd "$T/seed" && git pull -q origin main && git rm -q "$LIST" && git commit -qm "chore: remove the list" && git push -q origin main ); worker e3; commit "$T/e3" other.txt z; refused "no list on base at all refuses every landing" "$T/e3"; out_has "is not on"
  fresh; seed_push "$LIST" $'../x\ngate.sh' "chore: bad entry"; worker e4; commit "$T/e4" other.txt z; refused "an entry with .. refuses every landing" "$T/e4"
  fresh; worker e5; commit "$T/e5" other.txt z; printf '# emptied in the change\n' > "$T/e5/$LIST"; cm "$T/e5" "feat: empty the list too"; refused "the change's own emptied list does not matter: base's list governs (and the list is touched)" "$T/e5"
  fresh 'LAND_PROTECTED_LIST=scripts/other-list.txt'; worker e6; commit "$T/e6" other.txt z; refused "a LAND_PROTECTED_LIST naming a file that is not on base: fail closed" "$T/e6"

  echo "## a protected generated file that Tier 1 regenerates is judged too"
  sandbox; set_conf 'LAND_TEST_CMD=echo regenerated > gen.txt' 'LAND_GENERATED_LIST=scripts/generated.txt' 'LAND_REQUIRE_TRAILERS=Task-ID' "LAND_PROTECTED_LIST=$LIST" ${SEP:+"LAND_PROTECTED_APPROVALS=$PAP"}
  seed_push scripts/generated.txt gen.txt; seed_push gen.txt stale; seed_push "$LIST" $'gate.sh\ngen.txt'
  worker g1; commit "$T/g1" other.txt z; refused "Tier 1 rewrites a protected generated file after the verdict: refused" "$T/g1"; out_has "regenerated files"
  sandbox; set_conf 'LAND_TEST_CMD=echo regenerated > gen.txt' 'LAND_GENERATED_LIST=scripts/generated.txt' 'LAND_REQUIRE_TRAILERS=Task-ID' "LAND_PROTECTED_LIST=$LIST" ${SEP:+"LAND_PROTECTED_APPROVALS=$PAP"}
  seed_push scripts/generated.txt gen.txt; seed_push gen.txt regenerated; seed_push "$LIST" $'gate.sh\ngen.txt'
  worker g2; commit "$T/g2" other.txt z; lands "(control) a generated file that is already current: nothing to regenerate, lands" "$T/g2"

  echo "## the rules come from main, and the old behaviour is untouched when the list is not set"
  fresh; worker m1; edit_gate "$T/m1"; sed -i '/PROTECTED_LIST/d' "$T/m1/scripts/land.conf"; cm "$T/m1" "feat: drop the list key and edit the gate"; refused "removing LAND_PROTECTED_LIST in the change does not loosen the rule that judges it" "$T/m1"
  sandbox; set_conf 'LAND_TEST_CMD=true' 'LAND_REQUIRE_TRAILERS=Task-ID' 'LAND_PROTECTED=gate.sh'; base_files; worker m2; edit_gate "$T/m2"; lands "without LAND_PROTECTED_LIST the lander behaves as before" "$T/m2"
  sandbox; set_conf 'LAND_TEST_CMD=true' "LAND_PROTECTED_APPROVALS=$PAP"; worker m3; commit "$T/m3" z 1; ( cd "$T/m3" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
  [ "$rc" = 2 ] && pass "LAND_PROTECTED_APPROVALS without LAND_PROTECTED_LIST is a bad configuration (exit 2)" || fail "exit $rc"
  sandbox; set_conf 'LAND_TEST_CMD=true' "LAND_PROTECTED_LIST=scripts/gate-edit-approvals.txt"; worker m4; commit "$T/m4" z 1; ( cd "$T/m4" && "$L" >"$T/out" 2>&1 ) && rc=0 || rc=$?
  [ "$rc" = 2 ] && pass "the list may not be an approvals file (exit 2)" || fail "exit $rc"
}
suite "approvals in a file of their own (LAND_PROTECTED_APPROVALS)" 1
suite "approvals in the shared gate-edit file (the default)" ""

echo "######## the two approval files do not substitute for each other"
PAP=scripts/protected-approvals.txt; SEP=1; fresh 'LAND_GATE_APPEND_ONLY=other.txt'
worker x0; edit_gate "$T/x0"; H=$(hash_of "$T/x0" gate.sh)
seed_push scripts/gate-edit-approvals.txt "gate.sh | $H | in the wrong file | $today" "chore(approvals): wrong file"
worker x1; edit_gate "$T/x1"; sed -i '/wrong file/d' "$T/x1/scripts/gate-edit-approvals.txt"; cm "$T/x1" "chore(approvals): consume"
refused "a record in the gate-edit approvals file does not approve a protected change when the protected approvals have their own file" "$T/x1"
worker x2; edit_gate "$T/x2"; echo extra >> "$T/x2/scripts/protected-approvals.txt"; cm "$T/x2" "feat: also touch the protected approvals file"; refused "a change plus junk in the protected approvals file (malformed)" "$T/x2"
echo "######## the protected-set judge fails closed"
PAP=scripts/gate-edit-approvals.txt; SEP=; fresh; mkdir -p "$T/mut"; cp -r "$ROOT/bin" "$ROOT/lib" "$ROOT/VERSION" "$T/mut/"
sed -i 's/^  ga_ptfail=$/  ga_ptfail=; false/' "$T/mut/lib/approvals.sh"; check "(the crash is in the copy)" grep -q 'ga_ptfail=; false' "$T/mut/lib/approvals.sh"
worker k1; commit "$T/k1" other.txt z; before=$(remote_head)
( cd "$T/k1" && "$T/mut/bin/land-direct" >"$T/out" 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 12 ] && pass "a protected-set judge that crashes part-way refuses the landing (exit 12)" || fail "a crashing judge gave exit $rc"; out_has "failed unexpectedly"; check "nothing reached the remote" nothing_landed
finish
