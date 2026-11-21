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
( cd "$ROOT" && cp bin/land-release bin/land-pin "$L/$LAND_DIR/bin/" && cp lib/verify.sh lib/paths.sh lib/areas.sh lib/areas.py "$L/$LAND_DIR/lib/" )   # the tool as a library vendors it
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

echo "## the release candidate (LAND_RC_CMD): the full suite runs on the exact HEAD before any tag"
echo 0.2.0 > "$L/VERSION"
mkdir -p "$L/$LAND_DIR"; printf 'LAND_TEST_CMD=true\nLAND_RC_CMD=echo "$LAND_RC" > "$PWD/.rc-env"; git rev-parse HEAD > "$PWD/.rc-head"; exit 7\n' > "$L/$LAND_CONF_FILE"
git -C "$L" add -A; git -C "$L" commit -qm "chore: a red release candidate"; git -C "$L" push -q origin main
expect_exit "a red release candidate makes no tag (exit 1)" 1 rel --push; out_has "release candidate is RED"
check "no tag was made for it" bash -c "! git -C '$O' rev-parse -q --verify refs/tags/v0.2.0 >/dev/null"
check "the suite ran with LAND_RC=1 (nothing may be cached, selected or skipped)" test "$(cat "$L/.rc-env")" = 1
check "and on the exact HEAD that would be released" test "$(cat "$L/.rc-head")" = "$(git -C "$L" rev-parse HEAD)"
printf 'LAND_TEST_CMD=true\nLAND_RC_CMD=true\n' > "$L/$LAND_CONF_FILE"; git -C "$L" add -A; git -C "$L" commit -qm "chore: a green release candidate"; git -C "$L" push -q origin main
expect_exit "--rc runs the suite alone and needs no signing key (green: exit 0)" 0 bash -c "cd '$L' && env -u LAND_SIGNING_KEY ./$LAND_DIR/bin/land-release --rc"; out_has "release candidate is green"
check "--rc made no tag" bash -c "! git -C '$O' rev-parse -q --verify refs/tags/v0.2.0 >/dev/null"
expect_exit "a green release candidate is released (exit 0)" 0 rel --push
check "the tag exists" git -C "$O" rev-parse -q --verify refs/tags/v0.2.0
echo 0.3.0 > "$L/VERSION"; printf 'LAND_TEST_CMD=true\n' > "$L/$LAND_CONF_FILE"; git -C "$L" add -A; git -C "$L" commit -qm "chore: no release candidate command"; git -C "$L" push -q origin main
expect_exit "no LAND_RC_CMD: the release proceeds (exit 0)" 0 rel --push; out_has "NOT verified by a full suite"
check "and its tag exists" git -C "$O" rev-parse -q --verify refs/tags/v0.3.0

echo "## a declared candidate: main keeps landing, fixes land on the branch AND on main, the release is made from the branch"
echo 0.4.0 > "$L/VERSION"; printf 'LAND_TEST_CMD=true\nLAND_RC_CMD=test -f "$PWD/src/fixed"\n' > "$L/$LAND_CONF_FILE"; git -C "$L" add -A; git -C "$L" commit -qm "chore: version 0.4.0 and a suite that needs src/fixed"; git -C "$L" push -q origin main
expect_exit "--declare cuts rc/v0.4.0 from main (exit 0)" 0 rel --declare; out_has "declared the candidate rc/v0.4.0"
check "the branch is at main's head" test "$(git -C "$O" rev-parse refs/heads/rc/v0.4.0)" = "$(git -C "$O" rev-parse refs/heads/main)"
expect_exit "declaring it again is refused" 1 rel --declare; out_has "already declared"
echo more > "$L/src/b.txt"; git -C "$L" add -A; git -C "$L" commit -qm "feat: development goes on, on main"; git -C "$L" push -q origin main
expect_exit "a release from main runs the same full suite: red here, since main has not the fix (exit 1)" 1 rel; out_has "RED"
git -C "$L" fetch -q origin; git -C "$L" checkout -q -B cand origin/rc/v0.4.0
expect_exit "the candidate branch is red (the suite needs src/fixed): no tag (exit 1)" 1 rel --push; out_has "Fix it on rc/v0.4.0 and on main"
touch "$L/src/fixed"; git -C "$L" add -A; git -C "$L" commit -qm "fix: src/fixed"; fix=$(git -C "$L" rev-parse HEAD); git -C "$L" push -q origin cand:rc/v0.4.0
expect_exit "green on the branch but the fix is not on main: refused (exit 1)" 1 rel --push; out_has "not on main"
check "and no tag was made" bash -c "! git -C '$O' rev-parse -q --verify refs/tags/v0.4.0 >/dev/null"
git -C "$L" checkout -q main; git -C "$L" reset -q --hard origin/main; git -C "$L" cherry-pick -x "$fix" >/dev/null; git -C "$L" push -q origin main
git -C "$L" checkout -q cand
expect_exit "the same fix forward-ported to main: the release is made from the branch (exit 0)" 0 rel --push; out_has "the release candidate is green"
check "the tag is on the candidate's head" test "$(git -C "$O" rev-parse 'v0.4.0^{commit}')" = "$(git -C "$O" rev-parse refs/heads/rc/v0.4.0)"
git -C "$L" checkout -q main; git -C "$L" reset -q --hard origin/main
expect_exit "HEAD that is neither main nor a declared candidate is still refused" 1 bash -c "cd '$L' && git commit -q --allow-empty -m stray && LAND_SIGNING_KEY=$K/maint ./$LAND_DIR/bin/land-release"; git -C "$L" reset -q --hard origin/main

echo "## the end to end: land-pin vendor accepts exactly that tag"
C=$T/c; mkdir -p "$C/$LAND_HOME"; cp "$K/signers" "$C/$LAND_SIGNERS_FILE"
expect_exit "vendoring the released tag succeeds" 0 env LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" vendor libx "$O" v0.1.0
check "the vendored copy is the released tree (src/a.txt)" test "$(cat "$C/vendor/libx/src/a.txt")" = hello
expect_exit "and verify accepts it" 0 env LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" verify
finish
