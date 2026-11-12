#!/usr/bin/env bash
# land-lean recheck (docs/lean-gates.md): replay every proof of the listed modules, and of everything they import, with Lean's own checker in a fresh process (leanchecker --fresh: the same kernel code, so it catches what BYPASSED the kernel, not a bug in it). The build's own kernel
# accepted these proofs once; a fresh replay is what catches a declaration that never went through it (the check skipped), or an olean that was not produced by an honest build. Run on a REAL toy Lean project: a clean
# module, and a module that builds but holds a FALSE theorem (added with the kernel check skipped, which is exactly what a bug in the build's kernel would let through). --selftest is the negative test of the
# gate itself; handed a checker that accepts everything, it must FAIL.
. "$(dirname "$0")/lib.sh"
sandbox
command -v mise >/dev/null || { fail "mise is needed to run Lean (this repository's mise.toml pins it)"; finish; exit; }
P=$T/toy; mkdir -p "$P/.land"
cat > "$P/lakefile.lean" <<'LAKE'
import Lake
open Lake DSL
package toy
lean_lib Good
lean_lib Good2
lean_lib Lie
lean_lib Uses
LAKE
printf 'theorem good_thm : 1 + 1 = 2 := rfl\n' > "$P/Good.lean"
cat > "$P/Lie.lean" <<'LIE'
import Lean
open Lean Elab Command
-- a false theorem the elaborator would refuse, added straight to the environment with the kernel check skipped: what an unsound kernel would accept
set_option debug.skipKernelTC true in
run_cmd liftCoreM <| addDecl (.thmDecl { name := `lie, levelParams := [], type := mkApp3 (mkConst ``Eq [1]) (mkConst ``Nat) (mkRawNatLit 1) (mkRawNatLit 2), value := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Nat) (mkRawNatLit 1) })
LIE
printf 'theorem good2_thm : 2 + 2 = 4 := rfl\n' > "$P/Good2.lean"
printf 'import Lie\ntheorem fine : 2 = 2 := rfl\n' > "$P/Uses.lean"
eval "$(mise env -C "$ROOT" -s bash)"
ml() { "$@"; }
( cd "$P" && ml lake build Good Good2 Lie Uses >"$T/build.out" 2>&1 ) && pass "the toy project builds (the false theorem builds too: the build's kernel check was skipped)" || { fail "the toy project does not build: $(tail -3 "$T/build.out")"; finish; exit; }
lg() { LAND_LEAN_ROOT=$P ml "$ROOT/bin/land-lean" "$@"; }
conf() { printf '%s\n' "$@" > "$P/.land/lean.conf"; }

echo "## the replay on real modules"
conf 'LAND_LEAN_RECHECK_MODULES="Uses"'
expect_exit "a module that only IMPORTS the false one fails (the closure is replayed, not just the root)" 1 lg recheck
conf 'LAND_LEAN_RECHECK_MODULES="Good Good2"'
expect_exit "clean modules pass, and two at once do (leanchecker --fresh takes ONE module per run: each is replayed on its own)" 0 lg recheck; out_has "recheck: Good ok"; out_has "recheck: Good2 ok"; out_has "recheck: ok"
conf 'LAND_LEAN_RECHECK_MODULES="Good Lie"'
expect_exit "a module holding a false theorem fails, and every listed module still gets its own verdict (the clean one does not hide it)" 1 lg recheck; out_has "recheck: Good ok"; out_has "recheck: Lie REJECTED"
conf 'LAND_LEAN_RECHECK_MODULES="Nope"'
expect_exit "a module that cannot be found is a failure, never a pass" 1 lg recheck

echo "## the gate's own negative test"
conf 'LAND_LEAN_RECHECK_MODULES="Good"'
expect_exit "--selftest: a true theorem is accepted and a false one is rejected" 0 lg recheck --selftest; out_has "recheck self-test ok"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/accept-all"; chmod +x "$T/accept-all"
lga() { LEANCHECKER="$T/accept-all" lg "$@"; }   # the same tool with a checker that accepts everything
expect_exit "--selftest FAILS with a checker that accepts everything (a gate that cannot reject proves nothing)" 1 lga recheck --selftest; out_has "accepted the false theorem"
expect_exit "a checker that accepts everything passes the replay itself (so the self-test is what guards it)" 0 lga recheck

echo "## the configuration"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good"'
expect_exit "no LAND_LEAN_RECHECK_MODULES: refused, and says what to set" 2 lg recheck; out_has "recheck needs LAND_LEAN_RECHECK_MODULES"
conf 'LAND_LEAN_RECHECK_MODULES="Good; rm -rf x"'
expect_exit "a value that is not module names is refused" 2 lg recheck; out_has "holds module names only"
conf 'LAND_LEAN_RECHECK_MODULE="Good"'
expect_exit "a misspelled key is refused, never ignored" 2 lg recheck
finish
