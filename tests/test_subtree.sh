#!/usr/bin/env bash
# land-pin vendor NAME URL TAG --path PATH (docs/family-repo.md section 4): a SUBTREE of a family repository pinned by its tree hash, with its in-repo dependency closure vendored flat from the same commit.
# No network: the family repository is a local git repository built here. Every negative case is WATCHED to fail: at the end each guard is cut out of a copy of the tool (a mutant) and the scenario that depends on it must go red.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null && command -v jq >/dev/null || { fail "ssh-keygen and jq are needed"; finish; exit; }
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
F=$T/family; C=$T/c; TS=$T/tool; PINBIN=$ROOT/bin/land-pin
pin() { LAND_PIN_ROOT=$C "$PINBIN" "$@"; }
gitq() { git -c commit.gpgsign=false "$@"; }
state() { { find "$C" -type d -not -path '*/.git/*' | LC_ALL=C sort; find "$C" -type f -not -path '*/.git/*' | LC_ALL=C sort | xargs -r sha256sum; } | sha256sum | cut -d' ' -f1; }
rc_of() { local rc=0; "$@" >"$T/mout" 2>&1 || rc=$?; echo "$rc"; }

# ---- the family repository: alpha (no deps), beta (alpha), gamma (beta, so alpha too), delta (none), epsilon (alpha) ----
subh() {   # subh REV NAME: the tree hash of lib/NAME at REV, from a git export (the tool's own hash function, on the files git hands out)
  local d h; d=$(mktemp -d); git -C "$F" archive --format=tar "$1" "lib/$2" | tar -x --strip-components=2 -C "$d"; h=$(tree_hash "$d"); rm -rf "$d"; echo "$h"
}
mklib() { local n=$1 c=$2; shift 2; mkdir -p "$F/lib/$n"; printf '%s\n' "$c" > "$F/lib/$n/a.txt"; echo 0.1.0 > "$F/lib/$n/VERSION"; if [ $# = 0 ]; then : > "$F/lib/$n/deps"; else printf '%s\n' "$@" > "$F/lib/$n/deps"; fi; }
git init -q -b main "$F"; git -C "$F" config commit.gpgsign false
mklib alpha "alpha one"; mklib beta "beta one" alpha; mklib gamma "gamma one" beta; mklib delta "delta one"; mklib epsilon "epsilon one" alpha
mkdir -p "$F/registry"; echo '{}' > "$F/registry/alpha.json"; echo readme > "$F/README.md"
git -C "$F" add -A; git -C "$F" commit -qm c1; C1=$(git -C "$F" rev-parse HEAD)
echo "delta two" > "$F/lib/delta/a.txt"; echo more >> "$F/README.md"; echo '{"v":1}' > "$F/registry/alpha.json"; git -C "$F" commit -qam c2; C2=$(git -C "$F" rev-parse HEAD)
echo "alpha two" > "$F/lib/alpha/a.txt"; git -C "$F" commit -qam c3; C3=$(git -C "$F" rev-parse HEAD)
good() {   # good REV NAME DEPS...: the message lines of a correct release of NAME at REV (the closure given by the caller, sorted)
  local rev=$1 n=$2 d; shift 2; echo "tree_sha256=$(subh "$rev" "$n")"; for d in "$@"; do echo "dep_tree_sha256=$d:$(subh "$rev" "$d")"; done
}
mk() {   # mk TAG REV KEY|none LINES...: an annotated tag on REV, signed by KEY (or not)
  local t=$1 rev=$2 k=$3; shift 3; local m=(-m "family $t") l
  for l in "$@"; do m+=(-m "$l"); done
  if [ "$k" = none ]; then git -C "$F" -c tag.gpgsign=false tag -a "$t" "$rev" "${m[@]}"; else git -C "$F" -c gpg.format=ssh -c "user.signingkey=$K/$k" tag -s "$t" "$rev" "${m[@]}"; fi
}
rel() { local t=$1 rev=$2 n=$3; shift 3; mapfile -t L < <(good "$rev" "$n" "$@"); mk "$t" "$rev" maint "${L[@]}"; }   # rel TAG REV NAME DEPS...: a correct signed release
rel gamma/v0.4.0 "$C1" gamma alpha beta; rel delta/v1.0.0 "$C1" delta; rel epsilon/v0.9.0 "$C2" epsilon alpha; rel gamma/v0.4.1 "$C2" gamma alpha beta; rel epsilon/v1.0.0 "$C3" epsilon alpha
# the wrong ones, all at C1 and all signed by the maintainer unless said
mapfile -t G < <(good "$C1" gamma alpha beta)
mk gamma/v0.4.2 "$C1" none "${G[@]}"                                                    # unsigned
mk gamma/v0.4.3 "$C1" rogue "${G[@]}"                                                   # signed by a key that is not listed
mk gamma/v0.4.4 "$C1" maint "dep_tree_sha256=alpha:$(subh "$C1" alpha)" "dep_tree_sha256=beta:$(subh "$C1" beta)"   # no tree_sha256=
mk gamma/v0.4.5 "$C1" maint "${G[@]}" "${G[0]}"                                         # two tree_sha256=
mk gamma/v0.4.6 "$C1" maint "${G[0]}" "${G[2]}"                                         # a dep_tree_sha256= line missing (alpha)
mk gamma/v0.4.7 "$C1" maint "${G[@]}" "dep_tree_sha256=delta:$(subh "$C1" delta)"       # an extra one (delta is not in the closure)
mk gamma/v0.4.8 "$C1" maint "${G[0]}" "${G[1]}" "dep_tree_sha256=beta:$(printf 'c%.0s' $(seq 64))"   # a hash that disagrees with the exported directory
mk gamma/v0.4.9 "$C1" maint "tree_sha256=$(printf 'c%.0s' $(seq 64))" "${G[1]}" "${G[2]}"            # the subtree hash disagrees
mk gamma/v0.4.11 "$C1" maint "${G[0]}" "dep_tree_sha256=beta:$(subh "$C1" beta)"         # the message lists only beta; the deps files at the commit say alpha too
git -C "$F" -c tag.gpgsign=false tag gamma/v0.4.10 "$C1"                               # a lightweight tag
# a tag of another library, vendored as gamma
rel beta/v0.1.0 "$C1" beta alpha
# a legacy tag: a commit with no deps file (the closure is empty, tree_sha256= only)
git -C "$F" checkout -q -b legacy "$C1"; mkdir -p "$F/lib/zed"; echo z > "$F/lib/zed/a.txt"; git -C "$F" add -A; git -C "$F" commit -qm legacy; CL=$(git -C "$F" rev-parse HEAD); git -C "$F" checkout -q main
mk zed/v0.1.0 "$CL" maint "tree_sha256=$(subh "$CL" zed)"
# c4: alpha and gamma change (closure_changed is alpha and gamma), a later tag of gamma, and tags of others
git -C "$F" checkout -q main; echo "gamma two" > "$F/lib/gamma/a.txt"; git -C "$F" commit -qam c4; C4=$(git -C "$F" rev-parse HEAD)
rel gamma/v0.5.0 "$C4" gamma alpha beta; rel alpha/v1.3.0 "$C4" alpha; rel delta/v1.0.1 "$C4" delta   # delta/v1.0.1: delta did not change, but it is a tag of delta
git -C "$F" tag -d delta/v1.0.1 >/dev/null     # it is not a tag after all: main moved in delta's neighbours, delta has no newer tag
# c5: gamma drops its dependency
echo -n > "$F/lib/gamma/deps"; echo "gamma three" > "$F/lib/gamma/a.txt"; git -C "$F" commit -qam c5; C5=$(git -C "$F" rev-parse HEAD)
rel gamma/v0.6.0 "$C5" gamma

fresh() { rm -rf "$C"; mkdir -p "$C/$LAND_HOME"; echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$C/$LAND_SIGNERS_FILE"; }
gv() { pin vendor "$1" "$F" "$2" --path "lib/$1"; }   # gv NAME TAG
line() { echo "$1 $F $2 $3 lib/$1 $(subh "$3" "$1") $4"; }   # line NAME TAG REV ROLE: the expected lock line
lockhas() { grep -qxF "$1" "$C/$LAND_PINS_FILE"; }
GOLD_A=$(d=$(mktemp -d); git -C "$F" archive --format=tar "$C1" lib/alpha | tar -x --strip-components=2 -C "$d"; for f in VERSION a.txt deps; do printf '%s %s\n' "$(sha256sum < "$d/$f" | cut -d' ' -f1)" "$f"; done | LC_ALL=C sort | sha256sum | cut -d' ' -f1; rm -rf "$d")

echo "## the tree hash of a subtree"
check "the hash of lib/alpha is the independent golden vector (three files: VERSION, a.txt, an empty deps)" test "$(subh "$C1" alpha)" = "$GOLD_A"
check "a change OUTSIDE the path (another library, the registry, the readme) does not change it" test "$(subh "$C1" alpha)" = "$(subh "$C2" alpha)" -a "$(subh "$C1" gamma)" = "$(subh "$C2" gamma)"
check "a change inside the path does" test "$(subh "$C2" alpha)" != "$(subh "$C3" alpha)"
check "  and only in that library" test "$(subh "$C2" beta)" = "$(subh "$C3" beta)"

echo "## vendoring a library with its closure: three libraries, flat, three lines"
fresh; expect_exit "gamma/v0.4.0 is vendored with its closure" 0 gv gamma gamma/v0.4.0; out_has "with its closure: alpha beta"
check "vendor/alpha, vendor/beta and vendor/gamma side by side, one copy of each" bash -c "cd '$C/vendor' && test \"\$(ls | tr '\n' ' ')\" = 'alpha beta gamma ' && test -f alpha/a.txt -a -f beta/deps -a -f gamma/a.txt && ! find . -mindepth 2 -type d -name vendor | grep -q ."
check "  the directory holds exactly the subtree (the files of lib/gamma, the prefix removed)" test "$(cd "$C/vendor/gamma"; find . -type f | LC_ALL=C sort | tr '\n' ' ')" = "./VERSION ./a.txt ./deps "
check "the lock has the seven-field line of each, gamma as root and the others as dep" bash -c "[ \$(grep -c . '$C/$LAND_PINS_FILE') = 3 ]"
check "  gamma" lockhas "$(line gamma gamma/v0.4.0 "$C1" root)"
check "  beta" lockhas "$(line beta gamma/v0.4.0 "$C1" dep)"
check "  alpha" lockhas "$(line alpha gamma/v0.4.0 "$C1" dep)"
expect_exit "and verify accepts the result" 0 pin verify
check "no scratch directory is left" test -z "$(ls -A "$TMPDIR")"
fresh; expect_exit "a library with no deps is vendored alone" 0 gv delta delta/v1.0.0; check "  one line, root" bash -c "[ \$(grep -c . '$C/$LAND_PINS_FILE') = 1 ] && grep -qF ' root' '$C/$LAND_PINS_FILE'"
fresh; expect_exit "a legacy release (no deps file at its commit, the closure is empty) is vendored as any tag" 0 gv zed zed/v0.1.0
echo "## the same library at a later commit: unrelated landings do not move the pin"
fresh; gv gamma gamma/v0.4.0 >/dev/null 2>&1; expect_exit "gamma/v0.4.1 (made after a change in delta, the registry and the readme only) replaces the first" 0 gv gamma gamma/v0.4.1
check "  the three tree hashes are what they were; the tag and the commit moved" bash -c "grep -qF '$(line gamma gamma/v0.4.1 "$C2" root)' '$C/$LAND_PINS_FILE' && grep -qF '$(line alpha gamma/v0.4.1 "$C2" dep)' '$C/$LAND_PINS_FILE'"
check "  and the hashes equal those of the first" test "$(subh "$C1" alpha)" = "$(subh "$C2" alpha)"

echo "## vendor refuses, and a refusal changes nothing"
fresh; gv gamma gamma/v0.4.0 >/dev/null 2>&1; S=$(state)
refused() { expect_exit "$1" 1 gv "${4:-gamma}" "$2"; out_has "$3"; check "  and nothing changed" test "$(state)" = "$S"; }
refused "an unsigned tag" gamma/v0.4.2 "does not verify"
refused "a tag signed by a key that is not listed" gamma/v0.4.3 "does not verify"
refused "a message with no tree_sha256=" gamma/v0.4.4 "exactly one tree_sha256="
refused "a message with two" gamma/v0.4.5 "exactly one tree_sha256="
refused "a dep_tree_sha256= line missing" gamma/v0.4.6 "not exactly one for each member"
refused "an extra dep_tree_sha256= line" gamma/v0.4.7 "not exactly one for each member"
refused "a dep_tree_sha256= that disagrees with the exported directory" gamma/v0.4.8 "records another tree hash for beta"
refused "a tree_sha256= that disagrees with the exported subtree" gamma/v0.4.9 "hashes to"
refused "a message whose list differs from the deps files at the commit" gamma/v0.4.11 "not exactly one for each member"
refused "a lightweight tag" gamma/v0.4.10 "lightweight tag"
refused "a tag that does not exist" gamma/v9.9.9 "cannot fetch"
expect_exit "a tag of another library (its prefix is not NAME) is a usage error" 2 gv gamma beta/v0.1.0; out_has "the tag must be gamma/vX.Y.Z"
expect_exit "a whole-repository tag form is a usage error with --path" 2 gv gamma v0.4.0
expect_exit "a path that is not lib/NAME is a usage error" 2 pin vendor gamma "$F" gamma/v0.4.0 --path lib/beta
expect_exit "a diamond: epsilon brings an alpha that is not the one gamma brought; the roots are named" 1 gv epsilon epsilon/v1.0.0; out_has "diamond"; out_has "alpha"; out_has "gamma"; out_has "epsilon"; check "  nothing changed" test "$(state)" = "$S"
expect_exit "ACCEPTED: a shared dependency with an equal hash from two roots at two commits (epsilon/v0.9.0 is at c2, gamma at c1)" 0 gv epsilon epsilon/v0.9.0
check "  the shared alpha is one copy, its line carries the first root by name (epsilon), and verify is happy" bash -c "grep -qF '$(line alpha epsilon/v0.9.0 "$C2" dep)' '$C/$LAND_PINS_FILE' && [ \$(grep -c '^alpha ' '$C/$LAND_PINS_FILE') = 1 ]"
expect_exit "  verify" 0 pin verify
rm "$C/$LAND_SIGNERS_FILE"; expect_exit "no signers file: refused" 1 gv gamma gamma/v0.4.0; out_has "no readable signers file"

echo "## verify: offline, each reason names the library"
vend() { fresh; gv gamma gamma/v0.4.0 >/dev/null 2>&1; }
vend; echo x >> "$C/vendor/alpha/a.txt"; expect_exit "an edited vendored file" 1 pin verify; out_has "alpha: the tree hash"
vend; echo x > "$C/vendor/beta/extra.txt"; expect_exit "an extra file" 1 pin verify; out_has "beta: the tree hash"
vend; rm "$C/vendor/gamma/a.txt"; expect_exit "a missing file" 1 pin verify; out_has "gamma: the tree hash"
vend; mkdir "$C/vendor/zz"; echo z > "$C/vendor/zz/f"; expect_exit "an unlocked directory" 1 pin verify; out_has "zz: vendor/zz is vendored but not in the lock"
vend; rm -rf "$C/vendor/alpha"; expect_exit "a lock line with no directory" 1 pin verify; out_has "alpha: vendor/alpha is missing"
vend; sed -i "s/^alpha \(.*\) $(subh "$C1" alpha) dep\$/alpha \1 $(printf 'd%.0s' $(seq 64)) dep/" "$C/$LAND_PINS_FILE"; expect_exit "a flipped hash" 1 pin verify; out_has "alpha: the tree hash"
vend; grep -v '^beta ' "$C/$LAND_PINS_FILE" > "$T/l"; cp "$T/l" "$C/$LAND_PINS_FILE"; rm -rf "$C/vendor/beta"; expect_exit "a name in a vendored deps file that is not locked (the closure is incomplete)" 1 pin verify; out_has "gamma: its deps file names beta"
vend; echo "omega $F gamma/v0.4.0 $C1 lib/omega $(printf 'e%.0s' $(seq 64)) dep" >> "$C/$LAND_PINS_FILE"; mkdir "$C/vendor/omega"; echo o > "$C/vendor/omega/f"; "$ROOT/bin/land-pin" tree "$C/vendor/omega" >/dev/null
sed -i "s/^omega \(.*\) $(printf 'e%.0s' $(seq 64)) dep\$/omega \1 $(LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" tree "$C/vendor/omega") dep/" "$C/$LAND_PINS_FILE"
expect_exit "a dep line that no vendored deps file names (a stale dependency)" 1 pin verify; out_has "omega: a dep line that no vendored library's deps file names"
vend; sed -i "s/^alpha $(printf '%s' "$F" | sed 's/[\/&]/\\&/g') gamma\/v0.4.0 /alpha $(printf '%s' "$F" | sed 's/[\/&]/\\&/g') gamma\/v0.4.1 /" "$C/$LAND_PINS_FILE"
expect_exit "a dep line whose TAG is not its first root's" 1 pin verify; out_has "alpha: its TAG and COMMIT are not those of its first root, gamma"
echo "## verify: an old whole-repository lock line is still read"
fresh; mkdir -p "$C/vendor/libx"; echo hi > "$C/vendor/libx/a.txt"; echo "libx https://e.invalid/x v1.2.3 $C1 $(LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" tree "$C/vendor/libx")" > "$C/$LAND_PINS_FILE"
expect_exit "a five-field line verifies" 0 pin verify
gv gamma gamma/v0.4.0 >/dev/null 2>&1
expect_exit "beside the subtree lines (a mixed lock)" 0 pin verify; check "  the old line is untouched by vendoring the new" lockhas "libx https://e.invalid/x v1.2.3 $C1 $(LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" tree "$C/vendor/libx")"
echo "## verify: a malformed seven-field line is exit 2"
badlock() { fresh; printf '%s\n' "$1" > "$C/$LAND_PINS_FILE"; expect_exit "malformed lock refused: $2" 2 pin verify; }
HH=$(printf 'a%.0s' $(seq 64))
badlock "gamma $F gamma/v0.4.0 $C1 lib/beta $HH root" "a PATH that is not lib/NAME"
badlock "gamma $F gamma/v0.4.0 $C1 lib/gamma $HH other" "a role that is neither root nor dep"
badlock "gamma $F gamma/v0.4.0 $C1 lib/gamma $HH root extra" "eight fields"
badlock "gamma $F gamma/v0.4.0 $C1 lib/gamma $HH" "six fields"
badlock "gamma $F gamma/v0.4.0 abc lib/gamma $HH root" "a short commit"
badlock "gamma $F gamma/v0.4.0 $C1 lib/gamma abc root" "a short hash"
badlock "gamma $F v0.4.0 $C1 lib/gamma $HH root" "a tag with no prefix"
badlock "gamma $F beta/v0.4.0 $C1 lib/gamma $HH root" "a tag whose prefix is not a name in the lock"
badlock "$(printf 'gamma %s gamma/v0.4.0 %s lib/gamma %s root\ngamma %s gamma/v0.4.0 %s lib/gamma %s root' "$F" "$C1" "$HH" "$F" "$C1" "$HH")" "a duplicate"
badlock "Gamma $F gamma/v0.4.0 $C1 lib/Gamma $HH root" "an uppercase name"

echo "## outdated and update --all compare per library"
mkdir -p "$TS"; git init -q -b main "$TS"; git -C "$TS" config commit.gpgsign false; git -C "$TS" commit -q --allow-empty -m t; git -C "$TS" tag v1.0.0
world() {   # a repository whose pins are real: gamma (with alpha, beta) at gamma/v0.4.0 and delta at delta/v1.0.0, the tool current; the family has moved on (c4, c5, tags of gamma and of other libraries)
  fresh; rm -rf "$C/.git"; git init -q -b main "$C"; git -C "$C" config commit.gpgsign false
  printf 'source=%s\nversion=v1.0.0\ncommit=%s\nmanifest_sha256=%s\n' "$TS" "$(printf 'a%.0s' $(seq 40))" "$(printf 'b%.0s' $(seq 64))" > "$C/$LAND_PIN"
  gv gamma gamma/v0.4.0 >/dev/null 2>&1 && gv delta delta/v1.0.0 >/dev/null 2>&1 && gitq -C "$C" add -A && gitq -C "$C" commit -qm world -m x
}
s_outdated() {
  world; pin outdated --json > "$T/j" 2>/dev/null; local rc=$?
  jq -e '.behind == 1 and ([.pins[].name] | sort == ["delta","gamma","vbm-land"])' "$T/j" >/dev/null &&
  jq -e '[.pins[] | select(.name == "gamma")][0] | .status == "behind" and .newer == "gamma/v0.6.0" and .closure_changed == ["alpha","gamma"]' "$T/j" >/dev/null || return 1
  jq -e '[.pins[] | select(.name == "delta" or .name == "vbm-land")] | all(.status == "current" and .closure_changed == null)' "$T/j" >/dev/null &&
  [ "$(rc_of pin outdated)" = 1 ] && grep -q 'library gamma gamma/v0.4.0 -> gamma/v0.6.0' "$T/mout"
}
check "outdated reports gamma behind (its newest tag, by number, is gamma/v0.6.0) and nothing else: delta, whose neighbours moved, is current; a newer alpha tag is not a candidate for the dep line" s_outdated
check "  closure_changed names exactly the members whose hash differs (beta did not change, though the new closure dropped it; alpha and gamma did)" bash -c "jq -e '[.pins[] | select(.name==\"gamma\")][0].closure_changed == [\"alpha\",\"gamma\"]' '$T/j'"
echo "## a newer tag where only gamma's own files changed"
git -C "$F" tag -d gamma/v0.6.0 >/dev/null; world; pin outdated --json > "$T/j" 2>/dev/null || true
check "  closure_changed is [alpha, gamma] at gamma/v0.5.0 too (alpha moved at c3, gamma at c4, beta did not)" bash -c "jq -e '[.pins[] | select(.name==\"gamma\")][0] | .newer == \"gamma/v0.5.0\" and .closure_changed == [\"alpha\",\"gamma\"]' '$T/j'"
rel gamma/v0.6.0 "$C5" gamma
echo "## update --all re-vendors the whole closure of a library that is behind, and leaves the others"
s_update() {
  world; local h; h=$(sha256sum "$C/vendor/delta"/* | sha256sum); [ "$(rc_of pin update --all)" = 0 ] || return 1
  lockhas "$(line gamma gamma/v0.6.0 "$C5" root)" && [ ! -e "$C/vendor/alpha" ] && [ ! -e "$C/vendor/beta" ] &&   # the new closure is empty: the members it dropped go, with their lines
  [ "$(grep -c . "$C/$LAND_PINS_FILE")" = 2 ] && lockhas "$(line delta delta/v1.0.0 "$C1" root)" && [ "$h" = "$(sha256sum "$C/vendor/delta"/* | sha256sum)" ] &&
  [ "$(rc_of pin verify)" = 0 ] && [ -z "$(git -C "$C" log --format=%H -n2 | sed -n 2p)" ]
}
check "update --all takes gamma to gamma/v0.6.0, removes the dropped alpha and beta with their lines, keeps delta, never commits" s_update
git -C "$F" tag -d gamma/v0.6.0 >/dev/null
s_update_dry() { world; local S; S=$(state); [ "$(rc_of pin update --dry-run)" = 1 ] && [ "$(state)" = "$S" ] && jq -e '[.pins[] | select(.name == "gamma")][0].would.to == "gamma/v0.5.0"' "$T/mout" >/dev/null; }
check "  a dry run changes nothing and names the target tag of that library" s_update_dry
rel gamma/v0.6.0 "$C5" gamma

# ---- every negative WATCHED to fail ----------------------------------------------------------------------------------------------------------------------------------------------------
echo "## the negatives are watched to fail (a mutant with one guard removed)"
MUT=$T/mut; REAL=$ROOT/bin/land-pin
mutant() { rm -rf "$MUT"; mkdir -p "$MUT"; cp -r "$ROOT/bin" "$ROOT/lib" "$MUT/"; sed -i "$3" "$MUT/$2"; if cmp -s "$MUT/$2" "$ROOT/$2"; then fail "the mutation of $2 changed nothing (stale sed): $3"; return 1; fi; }
watch() {   # watch DESCRIPTION FILE SED SCENARIO
  local d=$1 f=$2 e=$3 s=$4
  PINBIN=$REAL; if "$s" >/dev/null 2>&1; then :; else fail "the scenario for '$d' is red with the real tool"; return; fi
  mutant "$d" "$f" "$e" || return
  PINBIN=$MUT/bin/land-pin; if "$s" >/dev/null 2>&1; then fail "MUTANT SURVIVED: $d (the scenario is still green with the guard cut out)"; else pass "mutant caught: $d"; fi
  PINBIN=$REAL
}
s_closure() { fresh; gv gamma gamma/v0.4.0 >/dev/null 2>&1 && [ "$(grep -c . "$C/$LAND_PINS_FILE")" = 3 ] && [ -f "$C/vendor/alpha/a.txt" ] && [ -f "$C/vendor/beta/a.txt" ]; }
s_hash_path() { fresh; gv gamma gamma/v0.4.1 >/dev/null 2>&1 && lockhas "$(line gamma gamma/v0.4.1 "$C2" root)"; }
s_unsigned() { fresh; [ "$(rc_of gv gamma gamma/v0.4.2)" = 1 ] && [ ! -e "$C/vendor/gamma" ]; }
s_rogue() { fresh; [ "$(rc_of gv gamma gamma/v0.4.3)" = 1 ] && [ ! -e "$C/vendor/gamma" ]; }
s_two() { fresh; [ "$(rc_of gv gamma gamma/v0.4.5)" = 1 ] && [ ! -e "$C/vendor/gamma" ]; }
s_extra() { fresh; [ "$(rc_of gv gamma gamma/v0.4.7)" = 1 ] && [ ! -e "$C/vendor/gamma" ]; }
s_depdis() { fresh; [ "$(rc_of gv gamma gamma/v0.4.8)" = 1 ] && [ ! -e "$C/vendor/gamma" ]; }
s_treedis() { fresh; [ "$(rc_of gv gamma gamma/v0.4.9)" = 1 ] && [ ! -e "$C/vendor/gamma" ]; }
s_prefix() { fresh; [ "$(rc_of gv gamma beta/v0.1.0)" = 2 ] && [ ! -e "$C/vendor/gamma" ]; }
s_diamond() { fresh; gv gamma gamma/v0.4.0 >/dev/null 2>&1; [ "$(rc_of gv epsilon epsilon/v1.0.0)" = 1 ] && [ ! -e "$C/vendor/epsilon" ] && [ "$(rc_of gv epsilon epsilon/v0.9.0)" = 0 ]; }
s_tamper() { fresh; gv gamma gamma/v0.4.0 >/dev/null 2>&1; echo x >> "$C/vendor/alpha/a.txt"; [ "$(rc_of pin verify)" = 1 ]; }
s_legacy() { fresh; mkdir -p "$C/vendor/libx"; echo hi > "$C/vendor/libx/a.txt"; echo "libx https://e.invalid/x v1.2.3 $C1 $(LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" tree "$C/vendor/libx")" > "$C/$LAND_PINS_FILE"; [ "$(rc_of pin verify)" = 0 ]; }
s_incomplete() { vend; grep -v '^beta ' "$C/$LAND_PINS_FILE" > "$T/l"; cp "$T/l" "$C/$LAND_PINS_FILE"; rm -rf "$C/vendor/beta"; [ "$(rc_of pin verify)" = 1 ] && grep -q 'gamma: its deps file names beta' "$T/mout"; }
s_stale() { vend; echo "omega $F gamma/v0.4.0 $C1 lib/omega $(printf 'e%.0s' $(seq 64)) dep" >> "$C/$LAND_PINS_FILE"; mkdir "$C/vendor/omega"; echo o > "$C/vendor/omega/f"
  sed -i "s/^omega \(.*\) $(printf 'e%.0s' $(seq 64)) dep\$/omega \1 $(LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" tree "$C/vendor/omega") dep/" "$C/$LAND_PINS_FILE"; [ "$(rc_of pin verify)" = 1 ] && grep -q "omega: a dep line that no vendored" "$T/mout"; }
s_firstroot() { vend; sed -i "s/ gamma\/v0.4.0 \($C1 lib\/alpha\)/ gamma\/v0.4.1 \1/" "$C/$LAND_PINS_FILE"; [ "$(rc_of pin verify)" = 1 ]; }
s_badpath() { fresh; echo "gamma $F gamma/v0.4.0 $C1 lib/beta $HH root" > "$C/$LAND_PINS_FILE"; [ "$(rc_of pin verify)" = 2 ]; }
s_otherlib() { world; pin outdated --json > "$T/j" 2>/dev/null; jq -e '[.pins[] | select(.name == "gamma")][0].newer == "gamma/v0.6.0"' "$T/j" >/dev/null; }
s_cc() { world; pin outdated --json > "$T/j" 2>/dev/null; jq -e '[.pins[] | select(.name == "gamma")][0].closure_changed == ["alpha","gamma"]' "$T/j" >/dev/null; }
s_dropped() { world; [ "$(rc_of pin update --all)" = 0 ] && [ ! -e "$C/vendor/alpha" ] && [ "$(grep -c . "$C/$LAND_PINS_FILE")" = 2 ]; }
s_leave() { world; pin outdated --json > "$T/j" 2>/dev/null; jq -e '[.pins[] | select(.name == "delta")][0] | .status == "current" and .newer == null' "$T/j" >/dev/null && [ "$(rc_of pin update --all)" = 0 ] && ! grep -q 'library delta' "$T/mout"; }
watch "the closure not vendored" lib/subtree.sh 's/^  members=\$(st_closure_at "\$r" "\$rev" "\$name") || exit 1$/  members=/' s_closure
watch "a hash of the whole export instead of the path" lib/subtree.sh 's/archive --format=tar "\$2" "\$3" | tar -x --strip-components="\$strip"/archive --format=tar "$2" | tar -x/' s_hash_path
watch "an unsigned or unlisted tag accepted" lib/subtree.sh 's/^  src_tag_signed "\$r" "\$tag" "\$signers" || exit 1$/  true/' s_unsigned
watch "  (the same, for a tag signed by an unlisted key)" lib/subtree.sh 's/^  src_tag_signed "\$r" "\$tag" "\$signers" || exit 1$/  true/' s_rogue
watch "two tree_sha256= accepted" lib/subtree.sh 's/^  \[ "\$(printf .%s\\n. "\$want" | grep -c .)" = 1 \] || refuse "the message of \$tag does not record exactly one tree_sha256="$/  want=$(sed -n 1p <<<"$want")/' s_two
watch "an extra dep_tree_sha256= accepted" lib/subtree.sh 's/^  \[ "\$(printf .%s\\n. "\$rows" | cut -d. . -f1 | LC_ALL=C sort)" = "\$members" \] || refuse/  true || refuse/' s_extra
watch "a dep hash that disagrees with the exported directory accepted" lib/subtree.sh 's/^    \[ "\$h" = "\$(awk -v n="\$m" .\$1 == n { print \$2 }. <<<"\$rows")" \] || refuse/    true || refuse/' s_depdis
watch "a subtree hash that disagrees with the message accepted" lib/subtree.sh 's/^  \[ "\$h" = "\$want" \] || refuse "tag/  true || refuse "tag/' s_treedis
watch "a tag of another library accepted" lib/subtree.sh 's|\[\[ \$tag =~ ^\$name/v\[0-9\]+|[[ $tag =~ ^[a-z]+/v[0-9]+|' s_prefix
watch "a diamond accepted" lib/subtree.sh 's/^    \[ -z "\$holder" \] || refuse/    true || refuse/' s_diamond
watch "verify that does not compare the hash of a subtree" bin/land-pin 's/if \[ "\$got" = "\${L_HASH\[\$i\]}" \]; then echo "pin/if true; then echo "pin/' s_tamper
watch "a reader that refuses the five-field line" bin/land-pin 's/^      5) name=/      5) die "gone";; 55) name=/' s_legacy
watch "an incomplete closure accepted" lib/subtree.sh 's/|| note "\$n: its deps file names/|| : "$n: its deps file names/' s_incomplete
watch "a stale dep line accepted" lib/subtree.sh 's/\] || note "\$n: a dep line that no vendored library.s deps file names/] || : "$n: a dep line that no vendored library/' s_stale
watch "a dep line with another root's tag accepted" lib/subtree.sh 's/|| note "\$n: its TAG and COMMIT/|| : "$n: its TAG and COMMIT/' s_firstroot
watch "a PATH that is not lib/NAME accepted" bin/land-pin 's/\[ "\$p" = "lib\/\$name" \] || die/true || die/' s_badpath
watch "a newer tag of ANOTHER library taken as a candidate" lib/outdated.sh 's/if (index(\$2, p) == 1) print/if (1) print/' s_otherlib
watch "a closure_changed that names the wrong members" lib/subtree.sh 's/ || echo "\$n"$/ || echo "$name"/' s_cc
watch "an update that leaves a dropped member behind" lib/subtree.sh 's/^    if \[ -z "\$j" \]; then echo "-\$d" >> "\$rows"; stale+=("\$d"); continue; fi$/    if [ -z "$j" ]; then continue; fi/' s_dropped
watch "a library that is not behind reported as behind" lib/outdated.sh 's/if \[ -n "\$new" \] \&\& tag_gt "\${new#"\$pre"}" "\${tag#"\$pre"}"; then/if [ -n "$new" ]; then/' s_leave
watch "a dep line reported as a library of its own" lib/outdated.sh 's/^  \[ "\${L_ROLE\[\$1\]}" != dep \] || return 0$/  true/' s_outdated
rm -rf "$MUT"
finish
