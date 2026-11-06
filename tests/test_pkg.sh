#!/usr/bin/env bash
# Pinned packages (land-update --pkg NAME): a second signed source vendored into scripts/NAME/ like this tool is vendored into scripts/land/. Every test builds its OWN world: a scratch package
# source with throwaway ssh keys and signed tags, and scratch consumers. Each refusal has a negative test, and a refused release leaves the consumer untouched.
. "$(dirname "$0")/lib.sh"
sandbox
K=$T/keys; mkdir -p "$K"
ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
echo "pkg-release $(cut -d' ' -f1,2 "$K/maint.pub")" > "$K/signers"; echo "other $(cut -d' ' -f1,2 "$K/rogue.pub")" > "$K/other-signers"
S=$T/gsrc; U=$ROOT/bin/land-update
git init -q -b main "$S"; git -C "$S" config commit.gpgsign false
mkfile() { mkdir -p "$S/$(dirname "$1")"; printf '%s\n' "$2" > "$S/$1"; }
manifest() { ( cd "$S" && git ls-files --others --cached --exclude-standard | grep -v '^MANIFEST.sha256$' | LC_ALL=C sort | xargs sha256sum | LC_ALL=C sort -k2 > MANIFEST.sha256 ); }
msha() { sha256sum < "$S/MANIFEST.sha256" | cut -d' ' -f1; }
release() {   # release VERSION [KEY]: VERSION file, manifest, commit, a signed annotated tag v<VERSION> recording the manifest hash
  echo "$1" > "$S/VERSION"; manifest; git -C "$S" add -A; git -C "$S" commit -qm "chore: release $1"
  git -C "$S" -c gpg.format=ssh -c user.signingkey="$K/${2:-maint}" tag -s "v$1" -m "gates v$1" -m "manifest_sha256=$(msha)"
}
mkfile core/run.sh $'#!/usr/bin/env bash\necho run'; mkfile core/lib.sh 'x=1'; mkfile docs/README.md 'docs'
release 1.0.0
consumer() { git clone -q "$T/remote.git" "$T/$1"; git -C "$T/$1" config commit.gpgsign false; }
upd() { local c=$1; shift; "$U" --pkg gates --root "$T/$c" "$@"; }
pinv() { sed -n "s/^$2=//p" "$T/$1/scripts/gates/PIN"; }

echo "## first install"
consumer c1
expect_exit "a first install names the source and the trusted signers, and verifies the signed tag" 0 upd c1 --source "$S" --signers "$K/signers" v1.0.0; out_has "verified: tag v1.0.0"
check "scripts/gates/ has exactly the manifest's files, the MANIFEST and the PIN" bash -c "cd '$T/c1/scripts/gates' && test \"\$(find . -type f | LC_ALL=C sort | tr '\n' ' ')\" = './MANIFEST.sha256 ./PIN ./VERSION ./core/lib.sh ./core/run.sh ./docs/README.md '"
check "a file with a shebang is executable, the others are not (the mode follows the content)" bash -c "cd '$T/c1/scripts/gates' && test -x core/run.sh -a ! -x core/lib.sh -a ! -x docs/README.md"
check "PIN records the source, the version, the 40-hex commit of the tag, the manifest hash and signature=verified" bash -c "cd '$T/c1/scripts/gates' && grep -q '^source=$S\$' PIN && grep -q '^version=v1.0.0\$' PIN && grep -q \"^commit=\$(git -C '$S' rev-parse v1.0.0^{commit})\$\" PIN && grep -q '^manifest_sha256=$(msha)\$' PIN && grep -q '^signature=verified\$' PIN"
check "the signers file is the repository's own: scripts/gates.signers" cmp -s "$K/signers" "$T/c1/scripts/gates.signers"
check "nothing else was touched, and nothing was committed" bash -c "cd '$T/c1' && test \"\$(git status --porcelain)\" = '?? scripts/' && test \$(git rev-list --count HEAD) = 1 && test ! -e scripts/land"
check "the manifest in the copy is the source's" cmp -s "$S/MANIFEST.sha256" "$T/c1/scripts/gates/MANIFEST.sha256"
expect_exit "a second --source that is not the pin's is refused" 2 upd c1 --source "$T/elsewhere" v1.0.0; out_has "first install only"
expect_exit "--signers that differs from the repository's file is refused (a key change is a reviewed edit)" 2 upd c1 --signers "$K/other-signers" v1.0.0; out_has "differs from --signers"

echo "## refusals: nothing is written"
refuse() {   # refuse NAME TAG-OR-COMMIT WHY [land-update args]: a fresh consumer; the install is refused (1) with WHY, and scripts/gates is not there
  local n=$1 t=$2 why=$3; shift 3; consumer "r-$n"
  expect_exit "refused: $n" 1 upd "r-$n" --source "$S" --signers "$K/signers" "$t"; out_has "$why"
  check "and nothing was written ($n)" bash -c "test ! -e '$T/r-$n/scripts/gates' -a ! -e '$T/r-$n/scripts/gates.signers'"
}
git -C "$S" commit -q --allow-empty -m "chore: for tag tests"
git -C "$S" tag -a v1.0.1 -m "unsigned annotated" -m "manifest_sha256=$(msha)"; git -C "$S" tag v1.0.2
git -C "$S" -c gpg.format=ssh -c user.signingkey="$K/rogue" tag -s v1.0.3 -m "signed by a key the signers file does not list" -m "manifest_sha256=$(msha)"
git -C "$S" -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s v1.0.4 -m "wrong manifest hash" -m "manifest_sha256=$(printf 0%.0s {1..64})"
refuse unsigned v1.0.1 "does not verify"; refuse lightweight v1.0.2 lightweight; refuse rogue v1.0.3 "does not verify"; refuse wronghash v1.0.4 "records manifest_sha256"
refuse commit "$(git -C "$S" rev-parse HEAD)" "not a release tag"; refuse noref v9.9.9 "no such tag or commit"
consumer r-nosigners; expect_exit "a package without a signers file is refused, never UNVERIFIED" 1 upd r-nosigners --source "$S" v1.0.0; out_has "requires signed releases"
check "and nothing was written (no signers)" test ! -e "$T/r-nosigners/scripts/gates"
consumer r-nosource; expect_exit "a first install without --source is a plain refusal" 2 upd r-nosource --signers "$K/signers" v1.0.0; out_has "install first"
expect_exit "a package name is a plain lower-case word" 2 "$U" --pkg ../x --root "$T/c1" --check; out_has "bad package name"
expect_exit "land is not a package name (it has its own installer)" 2 "$U" --pkg land --root "$T/c1" --check
expect_exit "--source without --pkg is refused" 2 "$U" --source "$S" --root "$T/c1" v1.0.0
# a signed release whose file differs from its manifest entry, one whose manifest names a path outside the package, and one that lists the PIN
tampered() {   # tampered NAME VERSION: release VERSION with one file changed AFTER the manifest was made, signed
  echo "$2" > "$S/VERSION"; manifest; echo '# tampered after the manifest' >> "$S/core/lib.sh"; git -C "$S" add -A; git -C "$S" commit -qm "chore: $1"
  git -C "$S" -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s "v$2" -m "$1" -m "manifest_sha256=$(msha)"; git -C "$S" reset -q --hard HEAD~1
}
tampered mismatch 1.0.5; refuse mismatch v1.0.5 "does not match its manifest entry"
mkfile ../outside 'x' 2>/dev/null || true; echo "$(printf 0%.0s {1..64})  ../outside" >> "$S/MANIFEST.sha256"; git -C "$S" add -A; git -C "$S" commit -qm "chore: path escape"; git -C "$S" -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s v1.0.6 -m x -m "manifest_sha256=$(msha)"
refuse escape v1.0.6 "not a plain relative path"; git -C "$S" reset -q --hard v1.0.0

echo "## update, check, diff"
git -C "$S" tag -l 'v1.0.[1-9]' | xargs git -C "$S" tag -d >/dev/null   # the refusal fixtures are not releases
mkfile core/new.sh $'#!/usr/bin/env bash\necho new'; echo 'x=2' > "$S/core/lib.sh"; git -C "$S" rm -q docs/README.md; release 1.1.0
pin_before=$(cat "$T/c1/scripts/gates/PIN")
expect_exit "--check: behind one release" 1 upd c1 --check; out_has "gates: pinned v1.0.0, latest v1.1.0: behind 1 release (minor)"
expect_exit "--diff verifies the release and shows what would change, in scripts/gates/" 0 upd c1 --diff v1.1.0; out_has "2 changed, 1 added, 1 removed"; out_has "ADDED   scripts/gates/core/new.sh"; out_has "CHANGED scripts/gates/core/lib.sh"; out_has "REMOVED scripts/gates/docs/README.md"
check "--diff changed nothing" test "$(cat "$T/c1/scripts/gates/PIN")" = "$pin_before"
expect_exit "update moves the pin: new files in, dropped files out" 0 upd c1 v1.1.0; out_has "verified: tag v1.1.0"
check "the pin names v1.1.0, and the dropped file is gone, the new one is executable" bash -c "test \$(sed -n 's/^version=//p' '$T/c1/scripts/gates/PIN') = v1.1.0 && test ! -e '$T/c1/scripts/gates/docs/README.md' -a -x '$T/c1/scripts/gates/core/new.sh'"
expect_exit "--check: up to date" 0 upd c1 --check; out_has "gates: pinned v1.1.0 is the latest release (v1.1.0): up to date"
cp -a "$T/c1" "$T/c1u"; sed -i "s|^source=.*|source=$T/nowhere|" "$T/c1u/scripts/gates/PIN"; expect_exit "an unreachable source is exit 3, never up to date" 3 upd c1u --check; out_has "NOT verified up to date"
expect_exit "a repository without the package is exit 2" 2 upd r-nosource --check

echo "## land-update --land: the package update goes through the repository's own lander"
consumer l1
printf '#!/usr/bin/env bash\nexec %s/bin/land-direct "$@"\n' "$ROOT" > "$T/l1/scripts-stub"; mkdir -p "$T/l1/scripts"; mv "$T/l1/scripts-stub" "$T/l1/scripts/land-direct"; chmod +x "$T/l1/scripts/land-direct"
printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\nLAND_REQUIRE_TRAILERS=Task-ID\n' > "$T/l1/scripts/land.conf"
git -C "$T/l1" add -A; git -C "$T/l1" commit -qm "chore: the repository's own lander" -m "Task-ID: setup"; ( cd "$T/l1" && scripts/land-direct >/dev/null 2>&1 )
git -C "$T/l1" fetch -q origin; git -C "$T/l1" checkout -q -B main origin/main
expect_exit "--land installs a package for the first time and lands it" 0 upd l1 --land --source "$S" --signers "$K/signers" v1.0.0; out_has '"result":"landed"'
check "main has the pin, the signers file and one commit carrying the required trailer" bash -c "git -C '$T/remote.git' show main:scripts/gates/PIN | grep -q '^version=v1.0.0\$' && git -C '$T/remote.git' cat-file -e main:scripts/gates.signers && git -C '$T/remote.git' log -1 --format=%B main | grep -q '^Task-ID: vbm-land-update-gates-v1.0.0\$' && git -C '$T/remote.git' log -1 --format=%s main | grep -qx 'chore(land): gates v1.0.0'"
expect_exit "a later --land moves the pin" 0 upd l1 --land v1.1.0; out_has '"result":"landed"'
check "main pins v1.1.0 and the dropped file is gone from main" bash -c "git -C '$T/remote.git' show main:scripts/gates/PIN | grep -q '^version=v1.1.0\$' && ! git -C '$T/remote.git' cat-file -e main:scripts/gates/docs/README.md"
echo dirty >> "$T/l1/scripts/land.conf"; expect_exit "--land refuses a dirty worktree" 1 upd l1 --land v1.1.0; out_has "clean worktree"; git -C "$T/l1" checkout -q scripts/land.conf

echo "## --auto: the repository's own policy decides"
release 1.1.1; release 1.2.0
printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\nLAND_REQUIRE_TRAILERS=Task-ID\nLAND_AUTO_UPDATE=patch\n' > "$T/l1/scripts/land.conf"; git -C "$T/l1" commit -qam "chore: auto patch" -m "Task-ID: s"; ( cd "$T/l1" && scripts/land-direct >/dev/null 2>&1 )
git -C "$T/l1" fetch -q origin; git -C "$T/l1" checkout -q -B main origin/main
expect_exit "policy patch takes the newest patch release of the pin's minor (v1.1.1), not v1.2.0" 0 upd l1 --auto; out_has "updating to v1.1.1"
check "main pins v1.1.1" bash -c "git -C '$T/remote.git' show main:scripts/gates/PIN | grep -q '^version=v1.1.1\$'"
finish
