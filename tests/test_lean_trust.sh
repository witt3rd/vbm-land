#!/usr/bin/env bash
# land-lean trust (docs/lean-gates.md, "The trust ledger"): what cannot be proven is marked as trusted, and COMPLETENESS IS DERIVED FROM THE TREE, never from the ledger. The tool derives the required keys (the build pins, the Lean
# toolchain pieces, every extern symbol, the configured trusted files, every vendored library and what it carries, the tools the scripts run) and the checker requires every one to be named by an entry's Covers line, every Covers
# token to name something required, every entry to be complete, and every cited file to exist. Run on a toy repository; no Lean toolchain is needed (the derivation reads files).
. "$(dirname "$0")/lib.sh"
sandbox
command -v python3 >/dev/null || { fail "python3 is needed (the checker)"; finish; exit; }
P=$T/toy; mkdir -p "$P/.land" "$P/Toy" "$P/native" "$P/scripts" "$P/docs" "$P/vendor/libx/include"
git -C "$P" init -q -b main
echo "leanprover/lean4:v4.35.0" > "$P/lean-toolchain"; echo '[tools]' > "$P/mise.toml"; echo "import Lake" > "$P/lakefile.lean"
printf '@[extern "my_ext"]\nopaque myExt : Nat → Nat\n' > "$P/Toy/Ffi.lean"; echo "int my_ext(int x){return x;}" > "$P/native/x.c"
echo "int x(void);" > "$P/vendor/libx/include/x.h"; printf '@[extern "libx_fn"]\nopaque libxFn : Nat → Nat\n' > "$P/vendor/libx/Libx.lean"
mkdir -p "$P/vendor/libx/vendor/liby/include"; echo "int y(void);" > "$P/vendor/libx/vendor/liby/include/y.h"; printf '@[extern "liby_fn"]\nopaque libyFn : Nat → Nat\n' > "$P/vendor/libx/vendor/liby/Liby.lean"   # vendored INSIDE libx: its code runs in our artifacts all the same
mkdir -p "$P/vendor/libx/runtime/include"; echo "int z(void);" > "$P/vendor/libx/runtime/include/z.h"   # a header outside the library's own include/ is not its published surface: never required
echo "libx https://example.invalid/libx v1.0.0 $(printf 'a%.0s' $(seq 40)) $(printf 'b%.0s' $(seq 64))" > "$P/.land/pins.lock"
printf '#!/usr/bin/env bash\ngit status\n' > "$P/scripts/tier1.sh"
git -C "$P" add -A
cat > "$T/ledger.base" <<'LEDGER'
# Trust ledger

### T1. The Lean toolchain and the build pins
- **What:** the Lean compiler, runtime and bundled clang, pinned by lean-toolchain and mise.toml; lakefile.lean drives the build.
- **Enters:** `lean-toolchain`, `mise.toml`, `lakefile.lean`; every generated C file of this library.
- **Assumes:** the pinned release is what the Lean project published: no written contract beyond its documentation.
- **Test:** none beyond the pinned release's own.
- **Owner:** the owner
- **Plan:** accept because the compiler is outside this repository and every claim already assumes it.
- **Covers:** `file:lean-toolchain` `file:mise.toml` `file:lakefile.lean` `lean-compiler` `lean-runtime` `clang-lld`

### T2. The tools the scripts run
- **What:** python3 runs the ledger checker and git runs the scripts' repository operations.
- **Enters:** `scripts/tier1.sh`.
- **Assumes:** the tools behave as documented: no written contract beyond their manuals.
- **Test:** none beyond the tools' own.
- **Owner:** the owner
- **Plan:** accept because these are the host's own tools.
- **Covers:** `tool:python3` `tool:git`

### T3. The foreign function and its C
- **What:** the extern my_ext is implemented by the C file native/x.c, outside the proofs.
- **Enters:** `Toy/Ffi.lean`, `native/x.c`.
- **Assumes:** the C satisfies the declared type: no written contract, read by hand.
- **Test:** none yet; a conformance vector is planned.
- **Owner:** the owner
- **Plan:** verify by a conformance suite, then replace by a proved version.
- **Covers:** `extern:my_ext` `file:native/x.c`

### T4. The vendored library libx
- **What:** libx at a signed release, vendored and locked; its header and its extern run in our artifacts.
- **Enters:** `.land/pins.lock`, `vendor/libx/include/x.h`.
- **Assumes:** the release passed its own gates; its own ledger names its trusted parts (see docs/trust-ledger.md of that repository, not here): no written contract here.
- **Test:** `.land/pins.lock` is checked by land-pin verify, which fails on an edited copy.
- **Owner:** the owner
- **Plan:** verify at the source repository; accept here because we claim no better than it does.
- **Covers:** `pin:libx` `dep:libx/include/x.h` `extern:libx_fn` `dep:liby/include/y.h` `extern:liby_fn`
LEDGER
conf() { printf '%s\n' "$@" > "$P/.land/lean.conf"; }
ledger() { cp "$T/ledger.base" "$P/docs/trust-ledger.md"; }
lg() { LAND_LEAN_ROOT=$P "$ROOT/bin/land-lean" "$@"; }
TF='LAND_LEAN_TRUST_FILES="native/*.c"'; TD='LAND_LEAN_TRUST_EXTERN_DIRS="Toy"'; TT='LAND_LEAN_TRUST_TOOLS="git gh mise lake"'
ledger; conf "$TF" "$TD" "$TT"

echo "## a complete ledger passes; completeness comes from the tree"
expect_exit "a complete ledger passes" 0 lg trust; out_has "trust ledger: 4 entries"
expect_exit "--count prints the number of entries and needs nothing else" 0 lg trust --count; check "  it is 4" test "$(cat "$T/out")" = 4
sed -i 's/^- \*\*Covers:\*\* `extern:my_ext` `file:native\/x.c`/- **Covers:** `extern:my_ext`/' "$P/docs/trust-ledger.md"; expect_exit "a trusted C file the ledger does not name fails" 1 lg trust; out_has "not in the trust ledger: file:native/x.c"; ledger
sed -i 's/ `extern:my_ext`//' "$P/docs/trust-ledger.md"; expect_exit "an extern symbol the ledger does not name fails" 1 lg trust; out_has "not in the trust ledger: extern:my_ext"; ledger
sed -i 's/ `pin:libx`//' "$P/docs/trust-ledger.md"; expect_exit "a vendored library with no pin: entry fails (a vendored library is a ledger line)" 1 lg trust; out_has "not in the trust ledger: pin:libx"; ledger
sed -i 's/ `dep:libx\/include\/x.h`//' "$P/docs/trust-ledger.md"; expect_exit "a header a vendored library carries fails" 1 lg trust; out_has "not in the trust ledger: dep:libx/include/x.h"; ledger
sed -i 's/ `extern:libx_fn`//' "$P/docs/trust-ledger.md"; expect_exit "an extern a vendored library declares fails" 1 lg trust; out_has "not in the trust ledger: extern:libx_fn"; ledger
sed -i 's/ `dep:liby\/include\/y.h`//' "$P/docs/trust-ledger.md"; expect_exit "a header of a library vendored INSIDE a vendored library fails (transitive trusted code)" 1 lg trust; out_has "not in the trust ledger: dep:liby/include/y.h"; ledger
sed -i 's/ `extern:liby_fn`//' "$P/docs/trust-ledger.md"; expect_exit "an extern of a library vendored INSIDE a vendored library fails" 1 lg trust; out_has "not in the trust ledger: extern:liby_fn"; ledger
sed -i 's/ `clang-lld`//' "$P/docs/trust-ledger.md"; expect_exit "the Lean toolchain pieces are required whenever there is a lean-toolchain" 1 lg trust; out_has "not in the trust ledger: clang-lld"; ledger
sed -i 's/ `tool:git`//' "$P/docs/trust-ledger.md"; expect_exit "a tool the scripts run fails when unnamed" 1 lg trust; out_has "not in the trust ledger: tool:git"; ledger
sed -i 's/ `tool:python3`//' "$P/docs/trust-ledger.md"; expect_exit "python3 runs the checker, so it is always a trusted tool" 1 lg trust; out_has "not in the trust ledger: tool:python3"; ledger

expect_exit "a header under a vendored library's runtime/include (not its own include/) is not required" 0 lg trust
echo "## the ledger itself is held to account"
sed -i 's/`tool:git`/`tool:git` `tool:nothing`/' "$P/docs/trust-ledger.md"; expect_exit "a Covers token that names nothing required is stale and fails" 1 lg trust; out_has "Covers \`tool:nothing\` names nothing"; ledger
sed -i '/^- \*\*Owner:\*\*/d' "$P/docs/trust-ledger.md"; expect_exit "an entry missing a field fails" 1 lg trust; out_has "field Owner is missing"; ledger
sed -i 's/^- \*\*Plan:\*\* accept because.*/- **Plan:** accept/' "$P/docs/trust-ledger.md"; expect_exit "an accepted risk needs a stated reason" 1 lg trust; out_has "needs a stated reason"; ledger
sed -i 's/`Toy\/Ffi.lean`, //' "$P/docs/trust-ledger.md"; sed -i 's/`native\/x.c`\./`native\/gone.c`./' "$P/docs/trust-ledger.md"; expect_exit "a cited file that does not exist fails" 1 lg trust; out_has "native/gone.c, which does not exist"; ledger
sed -i 's/^- \*\*Plan:\*\* verify by a conformance suite, then replace by a proved version\./- **Plan:** maybe later./' "$P/docs/trust-ledger.md"; expect_exit "a plan must be one of verify, replace, sandbox, accept" 1 lg trust; out_has "Plan must start with"; ledger
rm "$P/docs/trust-ledger.md"; expect_exit "no ledger is a failure that says where it should be" 1 lg trust; out_has "docs/trust-ledger.md"; ledger

echo "## the configuration decides WHERE to look, the tool decides WHAT is required"
conf "$TD" "$TT"; expect_exit "a file glob that is not configured is not required (and its Covers token is then stale)" 1 lg trust; out_has "names nothing the tree"
conf "$TF" "$TT"; expect_exit "externs are scanned only where configured (the vendored ones are always scanned)" 1 lg trust; out_has "names nothing the tree"
conf "$TF" "$TD" 'LAND_LEAN_TRUST_TOOLS="gh"'; expect_exit "the tool watch-list is configured" 1 lg trust; out_has "names nothing the tree"
conf "$TF" "$TD" "$TT" 'LAND_LEAN_TRUST_KEYS_CMD="echo module:Extra.Mod"'; expect_exit "a command may add keys the tool cannot derive (the closure modules)" 1 lg trust; out_has "not in the trust ledger: module:Extra.Mod"
conf "$TF" "$TD" "$TT" 'LAND_LEAN_TRUST_TYPO="x"'; expect_exit "an unknown key is refused" 2 lg trust; out_has "unknown key LAND_LEAN_TRUST_TYPO"
conf 'LAND_LEAN_TRUST_FILES="native/*.c; rm -rf /"'; expect_exit "a file list holds path patterns only (nothing is executed)" 2 lg trust; out_has "path patterns only"

echo "## the checker negative-tests itself on every run"
conf "$TF" "$TD" "$TT"; lg trust >"$T/out" 2>&1 || true; check "it reports its own negative self-tests (remove any entry and it must fail)" grep -q "negative self-tests ok" "$T/out"
finish
