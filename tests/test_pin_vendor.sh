#!/usr/bin/env bash
# land-pin vendor (docs/pin.md section 4): the ONLY way to add or move a pin. It trusts nothing it fetched: the tag must be signed by a key in the signers file, its message must record exactly one
# tree_sha256=, and the exported tree must hash to it. Every refusal has a negative case and a refused vendoring leaves the repository exactly as it was.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null || { echo "ssh-keygen missing"; fail "ssh-keygen is needed for the signing tests"; finish; exit; }
GOLD=f3e9efef2e6b617c7effdee61b5e52eaf808d542e2acdd8879c6f260574148b4   # the tree hash of the two files below, computed independently of the tool (tests/test_pin.sh)
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
C=$T/c; O=$T/lib.git; W=$T/libw
pin() { LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" "$@"; }
git init -q --bare -b main "$O"; git init -q -b main "$W"; git -C "$W" remote add origin "$O"; git -C "$W" config commit.gpgsign false
mkdir -p "$W/d"; printf 'hello\n' > "$W/a.txt"; printf 'world\n' > "$W/d/b.txt"; git -C "$W" add -A; git -C "$W" commit -qm "libx"; git -C "$W" push -q origin main
tag() {   # tag NAME KEY|none [MESSAGE LINE...]: an annotated tag on the work clone's HEAD, signed by KEY (or not signed), pushed
  local n=$1 k=$2; shift 2; local m=(-m "libx $n"); for l in "$@"; do m+=(-m "$l"); done
  if [ "$k" = none ]; then git -C "$W" -c tag.gpgsign=false tag -a "$n" "${m[@]}"; else git -C "$W" -c gpg.format=ssh -c "user.signingkey=$K/$k" tag -s "$n" "${m[@]}"; fi
  git -C "$W" push -q origin "$n"
}
fresh() { rm -rf "$C"; mkdir -p "$C/$LAND_HOME"; echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$C/$LAND_SIGNERS_FILE"; }
state() { find "$C" -type f -not -path '*/.git/*' | LC_ALL=C sort | xargs -r sha256sum | sha256sum | cut -d' ' -f1; }
REV=$(git -C "$W" rev-parse HEAD)
tag v1.0.0 maint "tree_sha256=$GOLD"
tag v1.0.1 none "tree_sha256=$GOLD"
tag v1.0.2 rogue "tree_sha256=$GOLD"
tag v1.0.3 maint "no hash recorded here"
tag v1.0.4 maint "tree_sha256=$(printf 'c%.0s' $(seq 64))"
tag v1.0.5 maint "tree_sha256=$GOLD" "tree_sha256=$GOLD"
git -C "$W" tag v1.0.6 && git -C "$W" push -q origin v1.0.6   # a lightweight tag

echo "## vendoring a good release"
fresh
expect_exit "a signed tag that records the tree hash is vendored" 0 pin vendor libx "$O" v1.0.0
check "the files are in vendor/libx" test "$(cat "$C/vendor/libx/d/b.txt")" = world
check "the lock line records url, tag, commit and tree hash" grep -qx "libx $O v1.0.0 $REV $GOLD" "$C/$LAND_PINS_FILE"
expect_exit "and verify accepts the result" 0 pin verify
check "no export scratch is left in the repository" test -z "$(find "$C" -name '.git' | head -n1)"
echo "libx-new" > "$W/new.txt"; git -C "$W" add -A; git -C "$W" commit -qm bump; git -C "$W" push -q origin main; REV2=$(git -C "$W" rev-parse HEAD)
tag v1.1.0 maint "tree_sha256=$(git -C "$W" archive HEAD | { d=$(mktemp -d); tar -x -C "$d"; "$ROOT/bin/land-pin" tree "$d"; rm -rf "$d"; })"
expect_exit "a later tag replaces the vendored copy and the lock line (a bump)" 0 pin vendor libx "$O" v1.1.0
check "the new file is there" test -f "$C/vendor/libx/new.txt"
check "the lock has one line for libx, at the new tag" test "$(grep -c '^libx ' "$C/$LAND_PINS_FILE")" = 1 -a "$(grep -c ' v1.1.0 ' "$C/$LAND_PINS_FILE")" = 1

echo "## refusals leave the repository exactly as it was"
fresh; pin vendor libx "$O" v1.0.0 >/dev/null 2>&1; S=$(state)
refused() { expect_exit "$1" 1 pin vendor libx "$O" "$2"; out_has "$3"; check "  and nothing changed" test "$(state)" = "$S"; }
refused "an annotated tag that is not signed is refused" v1.0.1 "does not verify"
refused "a tag signed by a key that is not in the signers file is refused" v1.0.2 "does not verify"
refused "a signed tag whose message records no tree_sha256= is refused" v1.0.3 "exactly one tree_sha256="
refused "a signed tag whose recorded hash disagrees with the exported tree is refused" v1.0.4 "hashes to"
refused "a message recording two tree_sha256= lines is refused" v1.0.5 "exactly one tree_sha256="
refused "a lightweight tag is refused" v1.0.6 "lightweight tag"
refused "a tag that does not exist is refused" v9.9.9 "cannot fetch"
rm "$C/$LAND_SIGNERS_FILE"; S=$(state); expect_exit "no signers file: refused (a signature cannot be checked)" 1 pin vendor libx "$O" v1.0.0; out_has "no readable signers file"; check "  and nothing changed" test "$(state)" = "$S"
fresh
expect_exit "a bad library name is a usage error" 2 pin vendor Libx "$O" v1.0.0
expect_exit "a tag that is not vX.Y.Z is a usage error" 2 pin vendor libx "$O" 1.0.0
expect_exit "missing arguments are a usage error" 2 pin vendor libx
finish
