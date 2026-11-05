#!/usr/bin/env bash
# Pinned vendoring: install, the drift check (offline and upstream), update, audit; and the lander refusing a change that edits its own vendored copy.
# Each refusal has a negative test. The "source repository" is a scratch git repository built from this working tree, so uncommitted work is what is tested.
. "$(dirname "$0")/lib.sh"
sandbox
S=$T/src
make_source() {   # make_source VERSION: a scratch source repository (this tree's files, VERSION set, manifest regenerated) with a commit and a tag v<VERSION>
  mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib templates install VERSION "$S/" )
  ( cd "$S" && { [ -d .git ] || git init -q -b main; } && git config commit.gpgsign false && echo "$1" > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release $1" && git tag "v$1" )
}
make_source 1.0.0
consumer() { git clone -q "$T/remote.git" "$T/$1"; git -C "$T/$1" config commit.gpgsign false; }
chk() { "$T/c1/scripts/land/bin/land-check" --root "$1" "${@:2}"; }   # always judged by the pristine checker of c1

echo "## install"
consumer c1
expect_exit "install vendors a pinned copy" 0 "$S/install" --source "$S" --target "$T/c1" v1.0.0
check "scripts/land/ has the tool, the manifest and the PIN" bash -c "cd '$T/c1/scripts/land' && test -x bin/land-direct -a -x bin/land-red -a -x bin/land-check -a -f lib/conf.sh -a -f MANIFEST.sha256 -a -f PIN"
check "the stub is executable and runs the vendored lander" bash -c "'$T/c1/scripts/land-direct' --version | grep -q 'land-direct 1.0.0'"
check "PIN records source, version, a 40-hex commit and the manifest hash" bash -c "cd '$T/c1/scripts/land' && grep -q '^source=$S\$' PIN && grep -q '^version=v1.0.0\$' PIN && grep -qE '^commit=[0-9a-f]{40}\$' PIN && grep -qE '^manifest_sha256=[0-9a-f]{64}\$' PIN"
check "the pinned commit is the source's tag" bash -c "grep -q \"^commit=\$(git -C '$S' rev-parse v1.0.0)\$\" '$T/c1/scripts/land/PIN'"
check "a starter scripts/land.conf was created" test -f "$T/c1/scripts/land.conf"
echo "LAND_TEST_CMD=my-own-tests" > "$T/c1/scripts/land.conf"
"$S/install" --source "$S" --target "$T/c1" v1.0.0 >/dev/null
check "an existing scripts/land.conf is never overwritten" grep -q my-own-tests "$T/c1/scripts/land.conf"
check "install commits nothing" test "$(git -C "$T/c1" rev-list --count HEAD)" = 1
expect_exit "install refuses a ref the source does not have" 1 "$S/install" --source "$S" --target "$T/c1" v9.9.9; out_has "no tag or commit"
expect_exit "install needs a source" 2 env -u VBM_LAND_SOURCE "$S/install" --target "$T/c1" v1.0.0
expect_exit "install needs a git repository as target" 2 "$S/install" --source "$S" --target "$T" v1.0.0

echo "## drift check, offline"
expect_exit "an untouched copy passes" 0 chk "$T/c1"; out_has "is intact"
for case_ in "edit:echo '# local patch' >> scripts/land/bin/land-red:differs from the pinned release" \
             "delete:rm scripts/land/lib/infra-re.sh:is missing" \
             "extra file:echo x > scripts/land/lib/local.sh:not part of the pinned release" \
             "not executable:chmod -x scripts/land/bin/land-direct:not executable" \
             "stub edited:echo '# x' >> scripts/land-direct:differs from the pinned release" \
             "manifest edited:sed -i '1s/^./0/' scripts/land/MANIFEST.sha256:does not hash to the pin" \
             "bad conf key:echo LAND_TYPO=1 >> scripts/land.conf:unknown key"; do
  name=${case_%%:*}; rest=${case_#*:}; cmd=${rest%:*}; want=${rest##*:}
  rm -rf "$T/d"; cp -a "$T/c1" "$T/d"
  ( cd "$T/d" && bash -c "$cmd" )
  expect_exit "drift ($name) fails" 1 chk "$T/d"; out_has "$want"; out_has "Edit vbm-land, not the copy"
done
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; mkdir -p "$T/d/scripts/land.d"; printf '#!/bin/sh\n' > "$T/d/scripts/land.d/post-rebase"
expect_exit "a hook that is not executable fails (it would silently never run)" 1 chk "$T/d"; out_has "not executable"
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; mkdir -p "$T/d/scripts/land.d"; printf '#!/bin/sh\n' > "$T/d/scripts/land.d/post-rebasee"; chmod +x "$T/d/scripts/land.d/post-rebasee"
expect_exit "a misspelled hook name fails (it would silently never run)" 1 chk "$T/d"; out_has "not a hook name"
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; mkdir -p "$T/d/scripts/land.d"; echo ': helper' > "$T/d/scripts/land.d/judge.sh"; printf '#!/bin/sh\n' > "$T/d/scripts/land.d/post-rebase"; chmod +x "$T/d/scripts/land.d/post-rebase"
expect_exit "a *.sh helper next to executable hooks is fine" 0 chk "$T/d"
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; echo garbage > "$T/d/scripts/land/PIN"
expect_exit "an unreadable PIN is refused" 2 chk "$T/d"
rm -rf "$T/d"; mkdir -p "$T/d"
expect_exit "a repository without a pinned copy is refused" 2 chk "$T/d"; out_has "not installed"
echo "## a forged copy: tree, manifest and PIN edited together pass offline and fail upstream"
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"
( cd "$T/d/scripts/land" && echo '# evil' >> bin/land-red && h=$(sha256sum bin/land-red | cut -d' ' -f1) && sed -i "s|^[0-9a-f]*  bin/land-red\$|$h  bin/land-red|" MANIFEST.sha256 \
  && m=$(sha256sum < MANIFEST.sha256 | cut -d' ' -f1) && sed -i "s|^manifest_sha256=.*|manifest_sha256=$m|" PIN )
expect_exit "consistent forgery passes the offline check" 0 chk "$T/d"
expect_exit "but the upstream check fails it" 1 chk "$T/d" --upstream; out_has "forged"
expect_exit "upstream check of the genuine copy passes" 0 chk "$T/c1" --upstream; out_has "source confirms"
cp -a "$T/c1" "$T/d2"; sed -i "s|^source=.*|source=$T/nowhere|" "$T/d2/scripts/land/PIN"
expect_exit "an unreachable source is exit 3" 3 chk "$T/d2" --upstream; out_has "cannot reach the source"

echo "## refusals at install"
git -C "$S" commit -q --allow-empty -m "chore: x"; git -C "$S" tag untagged-no-change
cp "$S/bin/land-red" "$T/red.bak"; echo "# tampered after the manifest" >> "$S/bin/land-red"; git -C "$S" commit -qam "fix: tamper without regenerating the manifest"; git -C "$S" tag v1.0.1-broken
consumer c2
expect_exit "a release whose files do not match its manifest is refused" 1 "$S/install" --source "$S" --target "$T/c2" v1.0.1-broken; out_has "does not match its manifest entry"
check "and nothing was written into the target" test ! -e "$T/c2/scripts/land"
git -C "$S" rm -q --cached MANIFEST.sha256; git -C "$S" commit -qm "chore: drop manifest"; git -C "$S" tag v1.0.2-nomanifest
expect_exit "a commit without a manifest is not a release" 1 "$S/install" --source "$S" --target "$T/c2" v1.0.2-nomanifest; out_has "no MANIFEST.sha256"
cp "$T/red.bak" "$S/bin/land-red"; ( cd "$S" && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: restore" && git add -f MANIFEST.sha256 )

echo "## update"
( cd "$S" && echo 1.1.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "feat: 1.1.0" && git tag v1.1.0 )
expect_exit "update moves the pin to another release" 0 "$T/c1/scripts/land/bin/land-update" v1.1.0 --root "$T/c1"; out_has "v1.1.0"
check "the pin names v1.1.0 and its commit" bash -c "grep -q '^version=v1.1.0\$' '$T/c1/scripts/land/PIN' && grep -q \"^commit=\$(git -C '$S' rev-parse v1.1.0)\$\" '$T/c1/scripts/land/PIN'"
expect_exit "the updated copy passes the drift check" 0 chk "$T/c1"
expect_exit "update refuses an unknown ref" 1 "$T/c1/scripts/land/bin/land-update" v7.7.7 --root "$T/c1"
expect_exit "update without a ref is a usage error" 2 "$T/c1/scripts/land/bin/land-update" --root "$T/c1"
cp -a "$T/c1" "$T/d3"; sed -i "s|^version=.*|version=v1.0.0|; s|^commit=.*|commit=$(git -C "$S" rev-parse v1.0.0)|" "$T/d3/scripts/land/PIN"
( cd "$T/d3" && "$S/install" --source "$S" --target "$T/d3" v1.0.0 >/dev/null )
expect_exit "re-pinning an older release works and verifies" 0 chk "$T/d3" --upstream; out_has "newer release exists: v1.1.0"

echo "## audit"
consumer c3; "$S/install" --source "$S" --target "$T/c3" v1.0.0 >/dev/null; mkdir -p "$T/plain"
expect_exit "audit fails when a repository has drift or no copy" 1 "$S/bin/land-audit" "$T/c1" "$T/c3" "$T/plain"; out_has "none"; out_has "ok"
cp -a "$T/c3" "$T/c3x"; echo '# x' >> "$T/c3x/scripts/land/bin/land-red"
expect_exit "audit shows drift" 1 "$S/bin/land-audit" "$T/c3x"; out_has DRIFT
expect_exit "audit passes when every repository is intact" 0 "$S/bin/land-audit" "$T/c1" "$T/c3"

echo "## the lander and its own vendored copy"
consumer l1; "$S/install" --source "$S" --target "$T/l1" v1.0.0 >/dev/null
printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\n' > "$T/l1/scripts/land.conf"
git -C "$T/l1" add -A; git -C "$T/l1" commit -qm "chore(land): vbm-land v1.0.0" -m "Task-ID: t"
expect_exit "a vendor commit lands through the stub" 0 bash -c "cd '$T/l1' && scripts/land-direct"
check "the vendored lander landed it" remote_has scripts/land/PIN
consumer l2; before=$(remote_head)
echo '# patched locally' >> "$T/l2/scripts/land/bin/land-red"; git -C "$T/l2" commit -qam "fix(land): patch the vendored copy" -m "Task-ID: t"
expect_exit "a change that edits the vendored copy is refused (exit 12)" 12 bash -c "cd '$T/l2' && scripts/land-direct"; out_has "differs from its pin"
check "nothing reached the remote" test "$(remote_head)" = "$before"
consumer l3; mkdir -p "$T/l3/scripts/land.d"; echo "$ROOT" > /dev/null
echo '# stray' > "$T/l3/scripts/land/lib/stray.sh"; git -C "$T/l3" add -A; git -C "$T/l3" commit -qm "chore: add a stray file in the vendored tree" -m "Task-ID: t"
expect_exit "a stray file in the vendored tree is refused" 12 bash -c "cd '$T/l3' && scripts/land-direct"
consumer l4; ( cd "$T/l4" && "$T/l4/scripts/land/bin/land-update" v1.1.0 >/dev/null && git add -A && git commit -qm "chore(land): vbm-land v1.1.0" -m "Task-ID: t" )
expect_exit "an update commit (new tree, new pin) lands" 0 bash -c "cd '$T/l4' && scripts/land-direct"
check "main now pins v1.1.0" bash -c "git -C '$T/remote.git' show main:scripts/land/PIN | grep -q '^version=v1.1.0\$'"

echo "## this repository's own manifest"
expect_exit "MANIFEST.sha256 is fresh for the working tree" 0 "$ROOT/bin/land-manifest" --check
rm -rf "$T/m"; cp -a "$ROOT" "$T/m"; echo "# edit" >> "$T/m/bin/land-red"
expect_exit "a stale manifest is detected" 1 "$T/m/bin/land-manifest" --check
finish
