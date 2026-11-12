#!/usr/bin/env bash
# land-lean ledger (docs/lean-gates.md): the obligation-ledger gate every Lean repository shares. Run on a REAL toy Lean project: code the entry point runs
# (`Toy.run`), a model it never runs (`Toy.model`), theorems about each, and several ledger modules (good, a missing theorem, a non-theorem, a claim proved
# only about the model). The tool ships the vocabulary (lean/LandLedger.lean) and the gate (lean/LedgerGate.lean); the repository holds its data and
# .land/lean.conf says which checks apply: REACH (an entries file), the RATCHET (a baseline), the CLAUSES (an index) and their COVERAGE. Each option turns on
# its own check, and --selftest proves the gate can fail.
. "$(dirname "$0")/lib.sh"
sandbox
command -v mise >/dev/null || { fail "mise is needed to run Lean (this repository's mise.toml pins it)"; finish; exit; }
P=$T/toy; mkdir -p "$P/.land" "$P/docs" "$P/scripts"
cat > "$P/lakefile.lean" <<LAKE
import Lake
open Lake DSL
package toy
lean_lib LandLedger where
  srcDir := "$ROOT/lean"
  roots := #[\`LandLedger, \`LandWalk]
lean_lib Toy
lean_lib ToyProofs
lean_lib LedgerGood
lean_lib LedgerMissing
lean_lib LedgerNonThm
lean_lib LedgerModelOnly
LAKE
printf 'namespace Toy\ndef run (n : Nat) : Nat := n + 1\ndef model (n : Nat) : Nat := n + 1\nend Toy\n' > "$P/Toy.lean"
cat > "$P/ToyProofs.lean" <<'LEAN'
import Toy
theorem run_ok : Toy.run 1 = 2 := rfl
theorem model_ok : Toy.model 1 = 2 := rfl
theorem model_is_run (n : Nat) : Toy.model n = Toy.run n := rfl
theorem unrelated : 1 + 1 = 2 := rfl
LEAN
ledger() { # name, claims...   a Ledger module with the claims given (one per argument)
  local m=$1; shift; { printf 'import ToyProofs\nimport LandLedger\nopen Land.Ledger\ndef ledger : List Obligation := [\n'; local first=1; for c in "$@"; do [ $first = 1 ] || printf ',\n'; first=0; printf '  %s' "$c"; done; printf ']\n'; } > "$P/$m.lean"; }
ledger LedgerGood 'O "runs" (.proved [``run_ok])' 'OC "a-clause" ["c:one"] (.proved [``unrelated])' 'O "later" (.open_ "not yet")' 'O "carried" (.limit "the owner")'
ledger LedgerMissing 'O "ghost" (.proved [`Toy.nope])'
ledger LedgerNonThm 'O "notathm" (.proved [`Nat.add])'
ledger LedgerModelOnly 'O "model-claim" (.proved [``model_ok])' 'O "runs" (.proved [``run_ok])'
eval "$(mise env -C "$ROOT" -s bash)"
ml() { "$@"; }
( cd "$P" && ml lake build LandLedger Toy ToyProofs LedgerGood LedgerMissing LedgerNonThm LedgerModelOnly >"$T/build.out" 2>&1 ) && pass "the toy project builds (the tool's vocabulary is a lean_lib of it)" || { fail "the toy project does not build: $(tail -4 "$T/build.out")"; finish; exit; }
lg() { LAND_LEAN_ROOT=$P ml "$ROOT/bin/land-lean" "$@"; }
conf() { printf '%s\n' "$@" > "$P/.land/lean.conf"; }
doc() { cat "$P/docs/proof-ledger.md"; }
printf 'Toy.run\n' > "$P/scripts/closure-entries.txt"

echo "## the plain gate: render, and every named theorem must exist and be a theorem"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"'
expect_exit "a good ledger passes" 0 lg ledger; out_has "ledger: 2 proved, 0 partial, 1 open, 1 limit, of 4"
grep -q '`runs`' "$P/docs/proof-ledger.md" && grep -q '\*\*proved\*\*' "$P/docs/proof-ledger.md" && pass "docs/proof-ledger.md is rendered, claim by claim" || fail "no rendered ledger"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerMissing"'; rm -f "$P/docs/proof-ledger.md"
expect_exit "a claim naming a theorem that does not exist fails" 1 lg ledger; out_has "ghost names Toy.nope, which is not a theorem"
[ ! -f "$P/docs/proof-ledger.md" ] && pass "a failing ledger renders nothing (no half-true document)" || fail "a failed gate wrote the ledger"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerNonThm"'
expect_exit "a claim naming a constant that is not a theorem fails" 1 lg ledger; out_has "notathm names Nat.add, which is not a theorem"

echo "## reach: proved means proved about code the entry points run"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerModelOnly"' 'LAND_LEAN_LEDGER_IMPORTS="Toy"' 'LAND_LEAN_LEDGER_SUBJECT="Toy"' 'LAND_LEAN_LEDGER_ENTRIES="scripts/closure-entries.txt"'
expect_exit "reach on: a claim proved only about a model the entry points never run is demoted" 0 lg ledger; out_has "1 demoted"; out_has "ledger: 1 proved, 1 partial"
grep -q 'demoted from proved by the reach rule' "$P/docs/proof-ledger.md" && pass "the demotion is stated in the rendered ledger" || fail "the demotion is not stated"
printf 'Toy.model model_is_run Toy.run\n' > "$P/scripts/ledger-bridges.txt"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerModelOnly"' 'LAND_LEAN_LEDGER_IMPORTS="Toy"' 'LAND_LEAN_LEDGER_SUBJECT="Toy"' 'LAND_LEAN_LEDGER_ENTRIES="scripts/closure-entries.txt"' 'LAND_LEAN_LEDGER_BRIDGES="scripts/ledger-bridges.txt"'
expect_exit "a bridge (a refinement theorem naming both) makes the model count as reached" 0 lg ledger; out_has "ledger: 2 proved, 0 partial"; out_has "0 demoted"
printf 'Toy.model unrelated Toy.run\n' > "$P/scripts/ledger-bridges.txt"
expect_exit "a bridge whose theorem does not mention both names is refused" 1 lg ledger; out_has "bridge Toy.model is not backed"
rm "$P/scripts/ledger-bridges.txt"
printf 'Toy.nothing\n' > "$P/scripts/closure-entries.txt"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_IMPORTS="Toy"' 'LAND_LEAN_LEDGER_SUBJECT="Toy"' 'LAND_LEAN_LEDGER_ENTRIES="scripts/closure-entries.txt"'
expect_exit "an entry point that is not in the environment fails (a walk from nothing proves nothing)" 1 lg ledger; out_has "entry point Toy.nothing is not in the environment"
printf 'Toy.run\n' > "$P/scripts/closure-entries.txt"

echo "## the ratchet: proved may only rise, open may only rise by claims newly written down"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_BASELINE="scripts/ledger-baseline.txt"'
expect_exit "--write records the baseline" 0 lg ledger --write; grep -q '^proved 2' "$P/scripts/ledger-baseline.txt" && pass "the baseline holds proved 2" || fail "baseline: $(cat "$P/scripts/ledger-baseline.txt")"
expect_exit "at the baseline it passes" 0 lg ledger
printf 'proved 3\nopen 1\ntotal 4\n' > "$P/scripts/ledger-baseline.txt"
expect_exit "proved below the baseline fails" 1 lg ledger; out_has "proved fell from 3 to 2"
printf 'proved 2\nopen 0\ntotal 4\n' > "$P/scripts/ledger-baseline.txt"
expect_exit "open above the baseline with no new claim fails" 1 lg ledger; out_has "open rose from 0 to 1 with 0 new claim"
printf 'proved 2\nopen 0\ntotal 3\n' > "$P/scripts/ledger-baseline.txt"
expect_exit "open may rise by the claims newly written down" 0 lg ledger
printf '# a documented re-base\nproved 2\nopen 1\ntotal 4\n' > "$P/scripts/ledger-baseline.txt"; lg ledger --write >/dev/null 2>&1
grep -q '^# a documented re-base' "$P/scripts/ledger-baseline.txt" && pass "--write keeps the comment lines (the documented re-bases)" || fail "comments lost: $(cat "$P/scripts/ledger-baseline.txt")"

echo "## clauses: the tags a claim cites, and their coverage"
printf 'c:one read first clause\nc:two policy second clause\nc:three ignored third\n' > "$P/docs/clauses.txt"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_CLAUSES="docs/clauses.txt"'
expect_exit "a tag in the index, and a proved claim that cites one, pass for tagged claims; an untagged proved claim fails" 1 lg ledger; out_has "claim runs cites no clause"
ledger LedgerGood 'OC "runs" ["c:one"] (.proved [``run_ok])' 'OC "a-clause" ["c:two"] (.proved [``unrelated])' 'O "later" (.open_ "not yet")'
( cd "$P" && ml lake build LedgerGood >/dev/null 2>&1 )
expect_exit "every proved claim tagged with a listed clause passes" 0 lg ledger
ledger LedgerGood 'OC "runs" ["c:nope"] (.proved [``run_ok])'
( cd "$P" && ml lake build LedgerGood >/dev/null 2>&1 )
expect_exit "a tag the index does not list fails" 1 lg ledger; out_has "cites the clause c:nope, which the clause index does not list"
ledger LedgerGood 'OC "runs" ["c:one"] (.proved [``run_ok])' 'O "later" (.open_ "not yet")'
( cd "$P" && ml lake build LedgerGood >/dev/null 2>&1 )
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_CLAUSES="docs/clauses.txt"' 'LAND_LEAN_LEDGER_COVERAGE="read policy"'
expect_exit "coverage counts the clauses of the named dispositions that a proved or partial claim tags" 0 lg ledger; out_has "clause coverage 1 of 2"
grep -q 'c:two' "$P/docs/proof-ledger.md" && pass "the clause with no covering claim is listed" || fail "uncovered clause not listed"

echo "## the gate's own negative test"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_BASELINE="scripts/ledger-baseline.txt"' 'LAND_LEAN_LEDGER_CLAUSES="docs/clauses.txt"'
lg ledger --write >/dev/null 2>&1
expect_exit "--selftest: a non-theorem, a missing theorem, a falling baseline, a rising open, an unknown tag and an untagged proved claim are all rejected" 0 lg ledger --selftest; out_has "negative self-tests ok"

echo "## the configuration"
rm "$P/.land/lean.conf"; conf 'LAND_LEAN_AXIOM_IMPORTS="Toy"'
expect_exit "no LAND_LEAN_LEDGER_MODULE: refused, and says what to set" 2 lg ledger; out_has "ledger needs LAND_LEAN_LEDGER_MODULE"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_ENTRIES="scripts/closure-entries.txt"'
expect_exit "reach (entries) without a subject is refused" 2 lg ledger; out_has "needs LAND_LEAN_LEDGER_SUBJECT"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood; rm -rf x"'
expect_exit "a module that is not a module name is refused" 2 lg ledger; out_has "holds module names only"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_BASELINE="a b"'
expect_exit "a path value that is not one file path is refused" 2 lg ledger; out_has "holds one file path"
conf 'LAND_LEAN_LEDGER_MODULE="LedgerGood"' 'LAND_LEAN_LEDGER_BASELIN="x"'
expect_exit "a misspelled key is refused, never ignored" 2 lg ledger
finish
