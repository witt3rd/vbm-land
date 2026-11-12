#!/usr/bin/env bash
# land-lean axiom (docs/lean-gates.md, docs/payload.md 4a): the axiom gate the tool ships. Run on a REAL toy Lean project (one clean module, two that depend on a custom axiom), configured by .land/lean.conf.
# The gate passes the clean module, names the offender of a bad one, audits only the roots the repository lists, refuses to pass a root that matches no constant (a gate that audited nothing proves nothing), and
# --selftest runs its differential test (the shared walk equals Lean's own, and it catches planted axioms and broken walks). The config is read by the tool's one parser: an unknown key is refused.
. "$(dirname "$0")/lib.sh"
sandbox
command -v mise >/dev/null || { fail "mise is needed to run Lean (this repository's mise.toml pins it)"; finish; exit; }
P=$T/toy; mkdir -p "$P/.land"
cat > "$P/lakefile.lean" <<'LAKE'
import Lake
open Lake DSL
package toy
lean_lib Good
lean_lib Bad
lean_lib Other
LAKE
printf 'theorem good_thm : 1 + 1 = 2 := rfl\ndef goodDef : Nat := 5\n' > "$P/Good.lean"
printf 'axiom myAx : False\ntheorem badThm : 1 = 2 := myAx.elim\n' > "$P/Bad.lean"
printf 'axiom otherAx : False\ntheorem otherThm : 3 = 4 := otherAx.elim\n' > "$P/Other.lean"
eval "$(mise env -C "$ROOT" -s bash)"   # the toolchain this repository pins (mise.toml), on PATH wherever a step runs
ml() { "$@"; }
( cd "$P" && ml lake build Good Bad Other >"$T/build.out" 2>&1 ) && pass "the toy project builds" || { fail "the toy project does not build: $(tail -3 "$T/build.out")"; finish; exit; }
lg() { LAND_LEAN_ROOT=$P ml "$ROOT/bin/land-lean" "$@"; }
conf() { printf '%s\n' "$@" > "$P/.land/lean.conf"; }

echo "## the gate on real constants"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good"' 'LAND_LEAN_AXIOM_ROOTS="Good"'
expect_exit "a clean module passes" 0 lg axiom; out_has "axiom gate: [0-9]* constants checked, 0 offending"
conf 'LAND_LEAN_AXIOM_IMPORTS="Bad"' 'LAND_LEAN_AXIOM_ROOTS="Bad"'
expect_exit "a module that depends on a custom axiom fails" 1 lg axiom; out_has "badThm depends on non-standard axiom myAx"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good Bad"' 'LAND_LEAN_AXIOM_ROOTS="Good"'
expect_exit "a bad module that is imported but not in the audited roots is not audited" 0 lg axiom
conf 'LAND_LEAN_AXIOM_IMPORTS="Good Bad Other"' 'LAND_LEAN_AXIOM_ROOTS="Good Other"'
expect_exit "every listed root is audited (the second bad one)" 1 lg axiom; out_has "otherThm depends on non-standard axiom otherAx"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good"' 'LAND_LEAN_AXIOM_ROOTS="Nothing"'
expect_exit "a root that matches no constant is refused (a gate that audited nothing proves nothing)" 1 lg axiom; out_has "no constants"
conf 'LAND_LEAN_AXIOM_IMPORTS="Nope"' 'LAND_LEAN_AXIOM_ROOTS="Nope"'
expect_exit "a module that cannot be imported is a failure, never a pass" 1 lg axiom

echo "## the differential self-test"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good"' 'LAND_LEAN_AXIOM_ROOTS="Good"'
expect_exit "--selftest: the shared walk equals Lean's own, and planted axioms and broken walks are caught" 0 lg axiom --selftest; out_has "differential test ok"; out_has "negative self-test ok"

echo "## the configuration: .land/lean.conf, read by the tool's one parser"
rm "$P/.land/lean.conf"; expect_exit "no .land/lean.conf: the Lean gates are off, and say so" 2 lg axiom; out_has "no .land/lean.conf"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good"' 'LAND_LEAN_AXIOM_ROOTS="Good"' 'LAND_LEAN_AXIOM_TYPO="x"'
expect_exit "an unknown key is refused (a typo must not silently turn a gate off)" 2 lg axiom; out_has "unknown key LAND_LEAN_AXIOM_TYPO"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good"' 'LAND_LEAN_AXIOM_ROOTS="Good"' 'LAND_BASE=main'
expect_exit "a land.conf key does not belong here (one file per tool, its own keys)" 2 lg axiom; out_has "unknown key LAND_BASE"
conf 'LAND_LEAN_AXIOM_ROOTS="Good"'
expect_exit "imports are required" 2 lg axiom; out_has "LAND_LEAN_AXIOM_IMPORTS"
conf 'LAND_LEAN_AXIOM_IMPORTS="Good; rm -rf /"' 'LAND_LEAN_AXIOM_ROOTS="Good"'
expect_exit "a module list is module names only (nothing is executed or expanded)" 2 lg axiom; out_has "module names"
conf '# a comment' '' 'LAND_LEAN_AXIOM_IMPORTS=Good   ' "LAND_LEAN_AXIOM_ROOTS='Good'"
expect_exit "comments, blank lines, unquoted and single-quoted values are accepted (land.conf's grammar)" 0 lg axiom
expect_exit "an unknown subcommand is a usage error" 2 lg nothing

finish
