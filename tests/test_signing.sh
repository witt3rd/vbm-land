#!/usr/bin/env bash
# Signed releases: bin/land-release makes the signed tag (with the manifest hash in its message); install and land-update verify it against the consumer's
# the consumer's signers file (LAND_SIGNERS_FILE) BEFORE anything of the release runs or is written. Each refusal has a negative test, and a refused release leaves the consumer untouched.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null || { echo "ssh-keygen missing: signing tests skipped"; pass "skipped (no ssh-keygen)"; finish; exit; }
K=$T/keys; mkdir -p "$K"
ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$K/signers"; echo "rogue $(cut -d' ' -f1,2 "$K/rogue.pub")" > "$K/rogue-signers"
O=$T/origin.git; R=$T/rel
git init -q --bare -b main "$O"; mkdir -p "$R"; ( cd "$ROOT" && cp -r bin lib lean docs templates skills install VERSION CHANGELOG.md "$R/" )
( cd "$R" && git init -q -b main && git config commit.gpgsign false && git remote add origin "$O" && echo 3.0.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release 3.0.0" && git push -q origin main )
rel() { ( cd "$R" && LAND_SIGNING_KEY=$K/maint ./bin/land-release "$@" ); }
bump() { ( cd "$R" && echo "$1" > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release $1" && git push -q origin main ); }

echo "## land-release"
( cd "$R" && env -u LAND_SIGNING_KEY ./bin/land-release >"$T/out" 2>&1 ) && rc=0 || rc=$?; [ "$rc" != 0 ] && pass "no signing key: refused" || fail "land-release ran without a key"
echo dirty >> "$R/README-x"; git -C "$R" add README-x; expect_exit "a dirty tree is refused" 1 rel; git -C "$R" reset -q --hard
git -C "$R" commit -q --allow-empty -m "chore: unpushed"; expect_exit "HEAD that is not origin/main is refused (a release is what main is)" 1 rel; git -C "$R" reset -q --hard origin/main
echo "# stale" >> "$R/bin/run-probe"; git -C "$R" commit -qam "chore: payload edit without the manifest"; git -C "$R" push -q origin main; expect_exit "a stale manifest is refused" 1 rel; out_has stale
( cd "$R" && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: manifest" && git push -q origin main )
expect_exit "the release is made: a signed tag v3.0.0 recording the manifest hash" 0 rel --push
check "the tag is annotated and its message carries the manifest hash" bash -c "git -C '$O' cat-file -t refs/tags/v3.0.0 | grep -qx tag && git -C '$O' tag -l --format='%(contents)' v3.0.0 | grep -q '^manifest_sha256=[0-9a-f]\\{64\\}\$'"
check "and the tree hash (tree_sha256=) too, for land-pin vendor" bash -c "git -C '$O' tag -l --format='%(contents)' v3.0.0 | grep -qE '^tree_sha256=[0-9a-f]{64}\$'"
check "the signature verifies for the maintainer" git -C "$O" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$K/signers" verify-tag v3.0.0
expect_exit "a tag is never moved: releasing the same version again is refused" 1 rel; out_has "already exists"

echo "## install and update verify before they write"
consumer() { git clone -q "$T/remote.git" "$T/$1"; git -C "$T/$1" config commit.gpgsign false; }
consumer s1
consumer s0; expect_exit "a RELATIVE --signers path works (the verifier runs elsewhere; a relative path must not make a good signature look unknown)" 0 bash -c "cd '$K' && '$R/install' --source '$O' --target '$T/s0' --signers signers v3.0.0"; out_has "verified: tag v3.0.0"
expect_exit "a first install with the maintainer's signers file verifies the tag" 0 "$R/install" --source "$O" --target "$T/s1" --signers "$K/signers" v3.0.0; out_has "verified: tag v3.0.0"
check "the pin says verified, and the signers file is now the repository's own" bash -c "grep -q '^signature=verified\$' '$T/s1/$LAND_PIN' && cmp -s '$K/signers' '$T/s1/$LAND_SIGNERS_FILE'"
# bad releases, each refused with nothing written
bad() { consumer "$1"; cp "$K/signers" "$T/$1/scripts-signers.tmp"; mkdir -p "$T/$1/$(dirname "$LAND_SIGNERS_FILE")"; mv "$T/$1/scripts-signers.tmp" "$T/$1/$LAND_SIGNERS_FILE"; }
git -C "$R" commit -q --allow-empty -m "chore: for tag tests"
git -C "$R" tag -a v3.0.1 -m "unsigned annotated" -m "manifest_sha256=x"
git -C "$R" tag v3.0.2
git -C "$R" -c gpg.format=ssh -c user.signingkey="$K/rogue" tag -s v3.0.3 -m "signed by someone not allowed" -m "manifest_sha256=$(sha256sum < "$R/MANIFEST.sha256" | cut -d' ' -f1)"
git -C "$R" -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s v3.0.4 -m "signed, wrong tree hash" -m "tree_sha256=0000000000000000000000000000000000000000000000000000000000000000"
O2=$T/origin2.git; git clone -q --bare "$R" "$O2"
for spec in "v3.0.1:does not verify" "v3.0.2:lightweight" "v3.0.3:does not verify" "v3.0.4:records tree_sha256" "$(git -C "$R" rev-parse HEAD):not a release tag"; do
  t=${spec%%:*}; why=${spec#*:}; bad "b-${t:0:6}"
  expect_exit "install refuses $why (${t:0:8})" 1 "$R/install" --source "$O2" --target "$T/b-${t:0:6}" "$t"; out_has "$why"
  check "and wrote nothing (no $LAND_DIR)" test ! -e "$T/b-${t:0:6}/$LAND_DIR"
done
consumer u1; expect_exit "without a signers file the install goes ahead and says UNVERIFIED" 0 "$R/install" --source "$O2" --target "$T/u1" v3.0.1; out_has "UNVERIFIED"
check "the pin says unverified" grep -q '^signature=unverified$' "$T/u1/$LAND_PIN"

echo "## land-update: verify first, and nothing of a refused release runs"
bump 3.1.0; rel --push >/dev/null
cat >> "$R/install" <<SH
touch "$T/pwned"
SH
git -C "$R" add -A; git -C "$R" commit -qm "chore: a release whose installer is hostile"; echo 3.1.1 > "$R/VERSION"; ( cd "$R" && bin/land-manifest >/dev/null ); git -C "$R" commit -qam "chore: release 3.1.1"
git -C "$R" -c gpg.format=ssh -c user.signingkey="$K/rogue" tag -s v3.1.1 -m "hostile" -m "manifest_sha256=$(sha256sum < "$R/MANIFEST.sha256" | cut -d' ' -f1)"; git -C "$R" push -q origin main "refs/tags/v3.1.1"
pin_before=$(cat "$T/s1/$LAND_PIN")
expect_exit "a release signed by an unknown key is refused by the vendored land-update" 1 "$T/s1/$LAND_DIR/bin/land-update" v3.1.1 --root "$T/s1"
check "its installer never ran" test ! -e "$T/pwned"
check "the consumer's pin is unchanged" test "$(cat "$T/s1/$LAND_PIN")" = "$pin_before"
expect_exit "--diff shows what a good release would change and changes nothing" 0 "$T/s1/$LAND_DIR/bin/land-update" --diff v3.1.0 --root "$T/s1"; out_has "land-update --diff: v3.1.0"; out_has "CHANGELOG entries newer than 3.0.0"
check "--diff left the pin alone" test "$(cat "$T/s1/$LAND_PIN")" = "$pin_before"
expect_exit "a good signed release updates" 0 "$T/s1/$LAND_DIR/bin/land-update" v3.1.0 --root "$T/s1"; out_has "verified: tag v3.1.0"
check "the pin moved and is verified" bash -c "grep -q '^version=v3.1.0\$' '$T/s1/$LAND_PIN' && grep -q '^signature=verified\$' '$T/s1/$LAND_PIN'"
expect_exit "the updated copy passes the drift check" 0 "$T/s1/$LAND_DIR/bin/land-check" --root "$T/s1"

echo "## install verifies BEFORE it runs or trusts anything the release says"
# the release's own lib/paths.sh is sourced by install only AFTER the signature is checked, and it cannot say where the signers file is (that would let a hostile release downgrade the check)
evil() {   # evil TAG LINE: a release signed by an unknown key whose lib/paths.sh carries LINE
  git -C "$R" checkout -q v3.1.0 -- lib/paths.sh; printf '%s\n' "$2" >> "$R/lib/paths.sh"
  ( cd "$R" && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: $1" )
  git -C "$R" -c gpg.format=ssh -c user.signingkey="$K/rogue" tag -s "$1" -m "hostile paths" -m "manifest_sha256=$(sha256sum < "$R/MANIFEST.sha256" | cut -d' ' -f1)" -m "tree_sha256=$(tree_of "$R")"
}
evil v3.2.0 "touch \"$T/pwned-paths\""
evil v3.2.1 "LAND_SIGNERS_FILE=elsewhere/no-signers-here"
O3=$T/origin3.git; git clone -q --bare "$R" "$O3"
bad h1; expect_exit "a rogue-signed release whose paths.sh runs a command is refused" 1 "$R/install" --source "$O3" --target "$T/h1" v3.2.0; out_has "does not verify"
check "and the command in its paths.sh never ran" test ! -e "$T/pwned-paths"
check "and nothing was written" test ! -e "$T/h1/$LAND_DIR"
bad h2; expect_exit "a release whose paths.sh moves the signers file (a downgrade to unverified) is refused" 1 "$R/install" --source "$O3" --target "$T/h2" v3.2.1; out_has "does not verify"
check "and nothing was written" test ! -e "$T/h2/$LAND_DIR"
bad h3; expect_exit "the same with the signers file given explicitly (control: refused for the signature, as before)" 1 "$R/install" --source "$O3" --target "$T/h3" --signers "$K/signers" v3.2.1; out_has "does not verify"
finish
