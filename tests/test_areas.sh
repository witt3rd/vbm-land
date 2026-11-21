#!/usr/bin/env bash
# Areas (docs/areas.md): every case of vectors/areas/areas.json through bin/land-areas (tests/areas_vectors.py), then the lander and land-check on real repositories, then NEGATIVE cases: an implementation with one
# rule swapped for its plausible wrong version (the `wrong_implementation` of the vectors) must FAIL the runner. A runner that cannot fail proves nothing; each mutant is checked to differ from the original.
. "$(dirname "$0")/lib.sh"
sandbox
A=$ROOT/bin/land-areas; V=$ROOT/vectors/areas/areas.json; RUN=$ROOT/tests/areas_vectors.py; L=$ROOT/bin/land-direct; C=$ROOT/bin/land-check

echo "## every vector, through bin/land-areas"
vec() { python3 "$RUN" "$1" "$V" > "$T/vec.out" 2>&1; }   # vec BIN
if vec "$A"; then pass "all $(sed -n 's/^\([0-9]*\) cases.*/\1/p' "$T/vec.out") cases pass"; else fail "a vector fails"; sed 's/^/     | /' "$T/vec.out" | head -20 >&2; fi
check "78 or more cases ran (a runner that read none would pass)" bash -c "[ \"\$(sed -n 's/^\\([0-9]*\\) cases.*/\\1/p' '$T/vec.out')\" -ge 78 ]"

echo "## the refusals name the reason (exit 2)"
bad() { printf '%s' "$2" > "$T/a.json"; expect_exit "$1" 2 "$A" validate --file "$T/a.json"; out_has "$3"; }
bad "malformed JSON" '{"version": 1,' "not valid JSON"
bad "a duplicate key" '{"version":1,"version":1,"areas":[]}' "duplicate key"
bad "a duplicate name" '{"version":1,"areas":[{"name":"a","paths":["a/*"],"steps":[]},{"name":"a","paths":["b/*"],"steps":[]}]}' "duplicate name"
bad "an area with no paths" '{"version":1,"areas":[{"name":"a","paths":[],"steps":[]}]}' "area 'a': paths must be a non-empty"
bad "a glob outside the language" '{"version":1,"areas":[{"name":"a","paths":["a/{b,c}"],"steps":[]}]}' "contains '{'"
bad "a missing file" '' "not valid JSON"
expect_exit "an unreadable file" 2 "$A" validate --file "$T/none.json"; out_has "cannot read"

echo "## the lander runs the steps of the touched areas, in file order, and stops at the first red"
set_conf 'LAND_BASE=main'
cat > "$T/areas.json" <<'J'
{"version":1,"areas":[
 {"name":"lib","paths":["lib/*"],"steps":[{"run":"echo lib-1"},{"run":"echo lib-2"}]},
 {"name":"app","paths":["app/*","lib/*"],"steps":[{"run":"echo app-1"},{"run":"test ! -e app/BAD"},{"run":"echo after > $LAND_STATE_DIR/after-red"}]},
 {"name":"docs","paths":["docs/*"],"steps":[]},
 {"name":"web","paths":["web/*"],"steps":[{"run":"pwd","cwd":"web"}]}]}
J
seed_push .land/areas.json "$(cat "$T/areas.json")" "chore: areas"; seed_push web/.keep 1; seed_push lib/seed.c 1
worker w1; commit "$T/w1" app/x.c 1
( cd "$T/w1" && "$L" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "an app change lands (exit 0)" test "$rc" = 0
out_has '"areas":\["app"\],"skipped_areas":\["docs","lib","web"\]'
check "the summary line carries no validation key when steps ran" bash -c "! tail -n1 '$T/out' | grep -q '\"validation\"'"
out_has "area app: step 1"
check "every step of app ran, in file order, and none of lib's or web's" bash -c "[ \"\$(grep -c 'area: run' '$T/out')\" = 1 ] && [ \"\$(grep -c ': step ' '$T/out')\" = 3 ] && ! grep -q 'area lib\\|area web' '$T/out'"
check "app's steps are numbered in order" bash -c "grep ': step ' '$T/out' | sed 's/.*step \\([0-9]*\\):.*/\\1/' | paste -sd, | grep -qx '1,2,3'"
out_has "area: skip lib"
out_has "area: skip docs"
worker w2; commit "$T/w2" lib/y.c 1; commit "$T/w2" app/BAD 1 "feat: bad"
( cd "$T/w2" && "$L" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "a red step stops the landing (exit 13)" test "$rc" = 13
out_has "area app, step 'test ! -e app/BAD"
check "the step after the red one did not run" test ! -e "$T/w2/.git/vbm-land/after-red"
check "nothing reached the remote" bash -c "! git -C '$T/remote.git' cat-file -e main:app/BAD"
worker w3; commit "$T/w3" docs/g.md 1
( cd "$T/w3" && "$L" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "a documents-only change (an area with no steps) lands" test "$rc" = 0
out_has '"validation":"inert"'; out_has '"areas":\["docs"\]'
worker w4; commit "$T/w4" scripts/x.sh 1
( cd "$T/w4" && "$L" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "an unmapped path lands only after the FULL suite" test "$rc" = 0
out_has '"areas":\["app","docs","lib","web"\],"skipped_areas":\[\]'; out_has "unmapped scripts/x.sh"
worker w5; commit "$T/w5" web/w.js 1
( cd "$T/w5" && "$L" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "a step runs in its cwd" bash -c "test $rc = 0 && grep -q 'area web: step 1: pwd (in web)' '$T/out'"

echo "## area-level reuse: a lost race that moved nothing of mine re-validates nothing"
set_conf 'LAND_BASE=main' 'LAND_REUSE=1'
race_hook 1; worker w10; commit "$T/w10" lib/r.c 1
( cd "$T/w10" && "$L" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "the landing lands after the race" test "$rc" = 0
out_has "reused: every touched area with steps passed"
out_has '"validation":"reused"'; out_has '"reused_areas":\["app","lib"\]'
rm -f "$T/remote.git/hooks/pre-receive"
echo "## the areas file is the only source of commands; a malformed one and a second source are refused"
set_conf 'LAND_BASE=main' 'LAND_TEST_CMD=true'
worker w6; commit "$T/w6" docs/h.md 1
expect_exit "LAND_TEST_CMD beside an areas file" 2 bash -c "cd '$T/w6' && '$L'"; out_has "refused beside .land/areas.json"
set_conf 'LAND_BASE=main' 'LAND_REUSE=1' 'LAND_AFFECTS_CMD=cat'
expect_exit "LAND_AFFECTS_CMD beside an areas file" 2 bash -c "cd '$T/w6' && '$L'"; out_has "LAND_AFFECTS_CMD is refused"
set_conf 'LAND_BASE=main'
seed_push .land/areas.json '{"version":1,"areas":[]}' "chore: broken areas"
worker w7; commit "$T/w7" docs/i.md 1
expect_exit "a malformed areas file on the base" 2 bash -c "cd '$T/w7' && '$L'"; out_has "areas must be a non-empty list"
check "and land-check refuses it offline" bash -c "cd '$T/w7' && ! '$C' --areas >/dev/null 2>&1"
seed_push .land/areas.json "$(cat "$T/areas.json")" "chore: areas again"

echo "## land-check --areas reports overlap, unmapped paths and areas with no steps"
worker w9
( cd "$T/w9" && "$C" --areas --json > "$T/rep.json" 2>"$T/err" ) && rc=0 || rc=$?
check "exit 0 on a well-formed file" test "$rc" = 0
check "lib/ is in the overlap of app and lib" bash -c "jq -e '.overlap[0].areas == [\"app\",\"lib\"] and (.overlap[0].paths | index(\"lib/seed.c\"))' '$T/rep.json' >/dev/null"
check "the no-step area is listed" bash -c "jq -e '.no_steps == [\"docs\"]' '$T/rep.json' >/dev/null"
check "an unmapped path is listed with no enclosing area" bash -c "jq -e '[.unowned[] | select(.path == \"scripts/x.sh\")][0].enclosed_by == []' '$T/rep.json' >/dev/null"
( cd "$T/w9" && "$C" --areas > "$T/out" 2>&1 ); out_has "areas in overlap: 2"; out_has "unmapped paths: "

echo "## NEGATIVE cases: a wrong implementation must fail the runner (watched to fail)"
mk=$T/mk; mkdir -p "$mk/bin" "$mk/lib"; cp "$ROOT"/lib/areas.py "$ROOT"/lib/areas.sh "$ROOT"/lib/paths.sh "$mk/lib/"; cp "$A" "$mk/bin/"
mutant() {   # mutant DESCRIPTION OLD NEW: areas.py with OLD replaced by NEW; the runner must fail, and the mutant must differ
  cp "$ROOT/lib/areas.py" "$mk/lib/areas.py"
  python3 - "$mk/lib/areas.py" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]; t = open(p).read()
if t.count(old) != 1: sys.exit("mutation site not found exactly once: " + old)
open(p, "w").write(t.replace(old, new))
PY
  cmp -s "$mk/lib/areas.py" "$ROOT/lib/areas.py" && { fail "$1: the mutant is the original"; return; }
  if vec "$mk/bin/land-areas"; then fail "$1: the runner did NOT fail"; else pass "$1: the runner fails ($(sed -n 's/^FAIL \(.*\)/\1/p' "$T/vec.out" | head -2 | tr '\n' ' '))"; fi
}
mutant "selects by import graph (the facts add the areas that read the path)" '                    unmapped.add(p)
                    full = True' '                    unmapped.add(p)
                    full = True
            import os as _o
            for n in json.loads(_o.environ.get("CASE_FACTS", "{}")).get("read_by", {}).get(p, []):
                touched.setdefault(n, p)'
mutant "skips an unmapped path" '                    unmapped.add(p)
                    full = True' '                    pass'
mutant "ignores exclude when owning" 'return s.hit(s.paths, p) and not s.hit(s.excl, p)' 'return s.hit(s.paths, p)'
mutant "ignores exclude when enclosing" '        if s.hit(s.excl, p):
            return None
        ds =' '        ds ='
mutant "treats overlap as an error" '    return out

def build' '    for i, x in enumerate(out):
        for y in out[i + 1:]:
            if set(g.pattern for g in x.paths) & set(g.pattern for g in y.paths):
                raise Refuse("overlap")
    return out

def build'
mutant "first match wins" '            for n in owners:
                touched.setdefault(n, p)' '            for n in owners[:1]:
                touched.setdefault(n, p)'
mutant "a deleted path matches nothing" '        if st == "D" and s.nodel:' '        if st == "D":'
mutant "the release candidate narrows" 'full, touched, unmapped, gate = rc, {}, set(), set()' 'full, touched, unmapped, gate = False, {}, set(), set()'
mutant "a moved gate-defining path is ignored by reuse" 'not d["full"] and not moved["full"] and' 'not d["full"] and'
echo "## the lander with the decision cut out is caught"
cp "$ROOT/lib/areas.sh" "$mk/lib/areas.sh"; cp "$ROOT/lib/areas.py" "$mk/lib/areas.py"; cp "$L" "$mk/bin/land-direct"; cp "$ROOT"/lib/conf.sh "$ROOT"/lib/freeze.sh "$mk/lib/"; cp "$ROOT/bin/no-build-guard" "$mk/bin/"; cp "$ROOT/VERSION" "$mk/"
sed -i 's|areas_steps "\$wt" "\$run" "\$lt";|:;|' "$mk/lib/areas.sh"; cmp -s "$mk/lib/areas.sh" "$ROOT/lib/areas.sh" && fail "the step-skipping mutant is the original"
worker w8; commit "$T/w8" app/z.c 1; commit "$T/w8" app/BAD 1 "feat: bad2"
( cd "$T/w8" && "$mk/bin/land-direct" > "$T/out" 2>&1 ) && rc=0 || rc=$?
check "a lander that runs no step lands a red change (so the real one's exit 13 above is the gate)" test "$rc" = 0
finish
