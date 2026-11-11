#!/usr/bin/env bash
# land-release for ANY repository (docs/pin.md section 2): a library that vendors the tool releases the same way vbm-land does. The signed tag records tree_sha256= (the tree hash of the exported
# HEAD), and a repository with no manifest of its own is not asked for one. The end-to-end check: land-pin vendor accepts exactly the tag land-release made.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null || { fail "ssh-keygen is needed for the signing tests"; finish; exit; }
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint
echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$K/signers"
O=$T/lib.git; L=$T/lib
git init -q --bare -b main "$O"; mkdir -p "$L/$LAND_DIR/bin" "$L/$LAND_DIR/lib" "$L/src"
( cd "$ROOT" && cp bin/land-release bin/land-pin "$L/$LAND_DIR/bin/" && cp lib/treehash.sh lib/paths.sh "$L/$LAND_DIR/lib/" )   # the tool as a library vendors it
echo 0.1.0 > "$L/VERSION"; printf 'hello\n' > "$L/src/a.txt"
( cd "$L" && git init -q -b main && git config commit.gpgsign false && git remote add origin "$O" && git add -A && git commit -qm "libx" && git push -q origin main )
rel() { ( cd "$L" && LAND_SIGNING_KEY=$K/maint "./$LAND_DIR/bin/land-release" "$@" ); }

echo "## a library (no manifest of its own) releases"
( cd "$L" && env -u LAND_SIGNING_KEY "./$LAND_DIR/bin/land-release" >"$T/out" 2>&1 ) && rc=0 || rc=$?; [ "$rc" != 0 ] && pass "no signing key: refused" || fail "released without a key"
echo dirty >> "$L/src/a.txt"; expect_exit "a dirty tree is refused" 1 rel; git -C "$L" checkout -q -- src/a.txt
git -C "$L" commit -q --allow-empty -m unpushed; expect_exit "HEAD that is not origin/main is refused" 1 rel; git -C "$L" reset -q --hard origin/main
echo bad > "$L/VERSION"; git -C "$L" commit -qam "bad version"; git -C "$L" push -q origin main; expect_exit "a VERSION that is not X.Y.Z is refused" 2 rel; echo 0.1.0 > "$L/VERSION"; git -C "$L" commit -qam "version"; git -C "$L" push -q origin main
expect_exit "the release is made without a manifest" 0 rel --push
check "the tag is annotated" bash -c "git -C '$O' cat-file -t refs/tags/v0.1.0 | grep -qx tag"
check "its signature verifies for the maintainer" git -C "$O" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$K/signers" verify-tag v0.1.0
check "its message records exactly one tree_sha256=" bash -c "test \"\$(git -C '$O' tag -l --format='%(contents)' v0.1.0 | grep -cE '^tree_sha256=[0-9a-f]{64}\$')\" = 1"
check "and no manifest_sha256= (this repository ships no manifest)" bash -c "! git -C '$O' tag -l --format='%(contents)' v0.1.0 | grep -q manifest_sha256"
expect_exit "a tag is never moved: releasing the same version again is refused" 1 rel; out_has "already exists"

echo "## the end to end: land-pin vendor accepts exactly that tag"
C=$T/c; mkdir -p "$C/$LAND_HOME"; cp "$K/signers" "$C/$LAND_SIGNERS_FILE"
expect_exit "vendoring the released tag succeeds" 0 env LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" vendor libx "$O" v0.1.0
check "the vendored copy is the released tree (src/a.txt)" test "$(cat "$C/vendor/libx/src/a.txt")" = hello
expect_exit "and verify accepts it" 0 env LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" verify
finish
