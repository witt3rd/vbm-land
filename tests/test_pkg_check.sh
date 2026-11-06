#!/usr/bin/env bash
# The drift check for pinned packages (land-check, land-check --pkg NAME, --upstream) and scripts/NAME.conf (known keys only), and the lander refusing a landing that edits a vendored package.
# Every test builds its OWN world: a scratch vbm-land source (this tree's tool), a scratch package source with a signed tag, and scratch consumers. Each failure mode has a negative test.
. "$(dirname "$0")/lib.sh"
sandbox
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; echo "pkg-release $(cut -d' ' -f1,2 "$K/maint.pub")" > "$K/signers"
L=$T/lsrc; G=$T/gsrc
mkdir -p "$L"; ( cd "$ROOT" && cp -r bin lib docs templates skills install VERSION "$L/" )
( cd "$L" && git init -q -b main && git config commit.gpgsign false && echo 1.0.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release" && git tag v1.0.0 )
mkdir -p "$G/core"; git init -q -b main "$G"; git -C "$G" config commit.gpgsign false
printf '#!/usr/bin/env bash\necho run\n' > "$G/core/run.sh"; echo 'x=1' > "$G/core/lib.sh"; printf '# keys\nGATES_BUDGET\nGATES_MODE   # a comment\n' > "$G/KEYS"; echo 1.0.0 > "$G/VERSION"
( cd "$G" && git ls-files --others --exclude-standard | grep -v "^MANIFEST.sha256$" | LC_ALL=C sort | xargs sha256sum > MANIFEST.sha256 && git add -A && git commit -qm "chore: release 1.0.0" \
  && git -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s v1.0.0 -m "gates v1.0.0" -m "manifest_sha256=$(sha256sum < MANIFEST.sha256 | cut -d' ' -f1)" )
consumer() {   # consumer NAME: vbm-land and the package gates installed (staged, not committed)
  git clone -q "$T/remote.git" "$T/$1"; git -C "$T/$1" config commit.gpgsign false
  "$L/install" --source "$L" --target "$T/$1" v1.0.0 >/dev/null; "$T/$1/scripts/land/bin/land-update" --pkg gates --root "$T/$1" --source "$G" --signers "$K/signers" v1.0.0 >/dev/null
}
chk() { local c=$1; shift; "$T/c1/scripts/land/bin/land-check" --root "$T/$c" "$@"; }   # always judged by the pristine checker of c1
consumer c1

echo "## offline"
expect_exit "intact land and package pass" 0 chk c1; out_has "ok: vbm-land v1.0.0"; out_has "ok: gates v1.0.0"
expect_exit "--pkg checks only that package" 0 chk c1 --pkg gates; out_has "ok: gates v1.0.0"; check "and does not mention vbm-land" bash -c "! grep -q vbm-land '$T/out'"
for case_ in "edit:echo '# local patch' >> scripts/gates/core/lib.sh:scripts/gates/core/lib.sh differs from the pinned release" \
             "delete:rm scripts/gates/core/lib.sh:scripts/gates/core/lib.sh is missing" \
             "extra file:echo x > scripts/gates/core/local.sh:is not part of the pinned release" \
             "executable bit lost:chmod -x scripts/gates/core/run.sh:is not executable" \
             "executable bit added:chmod +x scripts/gates/core/lib.sh:is executable (it does not start with #!)" \
             "manifest edited:sed -i '1s/^./0/' scripts/gates/MANIFEST.sha256:does not hash to the pin" \
             "unknown conf key:echo GATES_TYPO=1 > scripts/gates.conf:unknown key GATES_TYPO" \
             "conf line that is not a key:echo 'no-equals' > scripts/gates.conf:not a GATES_KEY=value line" \
             "a key of another package:echo OTHER_BUDGET=1 > scripts/gates.conf:not a GATES_KEY=value line" \
             "PIN deleted:rm scripts/gates/PIN:has a manifest but no PIN"; do
  name=${case_%%:*}; rest=${case_#*:}; cmd=${rest%:*}; want=${rest##*:}
  rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; ( cd "$T/d" && bash -c "$cmd" )
  expect_exit "drift ($name) fails" 1 chk d; out_has "$want"
done
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; ( cd "$T/d" && echo 'echo hi' >> scripts/gates/core/lib.sh )
expect_exit "a drifted package is named, with the way back (restore, not edit)" 1 chk d; out_has "Edit the source of gates, not the copy"; out_has "land-update --pkg gates v1.0.0"
expect_exit "--pkg land does not see the package's drift" 0 chk d --pkg land
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; printf '# mine\nGATES_BUDGET=5\nGATES_MODE="strict"  \n\n' > "$T/d/scripts/gates.conf"
expect_exit "known keys, comments, quotes and blank lines are fine" 0 chk d
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; echo GATES_BUDGET=5 > "$T/d/scripts/gates.conf"; rm "$T/d/scripts/gates/KEYS"
expect_exit "a package that ships no KEYS file accepts no key at all" 1 chk d
rm -rf "$T/d"; mkdir -p "$T/d/scripts/land"; cp -a "$T/c1/scripts/land/." "$T/d/scripts/land/"; cp "$T/c1/scripts/land-direct" "$T/d/scripts/"; cp -a "$T/c1/.agents" "$T/d/"
expect_exit "a repository with only vbm-land installed is checked as before" 0 chk d
expect_exit "--pkg for a package that is not installed is refused (exit 2)" 2 chk d --pkg gates; out_has "not installed"
expect_exit "a bad package name is refused" 2 chk d --pkg ../x
check "pkgconf_load sets the variables (the reader a package uses)" bash -c ". '$ROOT/lib/pkg.sh'; printf 'GATES_BUDGET=7\nGATES_MODE=\"a b\"\n' > '$T/g.conf'; pkgconf_load gates '$T/g.conf' '$G/KEYS' && [ \"\$GATES_BUDGET\" = 7 ] && [ \"\$GATES_MODE\" = 'a b' ]"

echo "## upstream"
expect_exit "the source confirms the manifest at the pinned commit, for both" 0 chk c1 --upstream; check "once each" test "$(grep -c 'the source confirms' "$T/out")" = 2
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"
( cd "$T/d/scripts/gates" && echo '# evil' >> core/lib.sh && h=$(sha256sum core/lib.sh | cut -d' ' -f1) && sed -i "s|^[0-9a-f]*  core/lib.sh\$|$h  core/lib.sh|" MANIFEST.sha256 \
  && m=$(sha256sum < MANIFEST.sha256 | cut -d' ' -f1) && sed -i "s|^manifest_sha256=.*|manifest_sha256=$m|" PIN )
expect_exit "a consistent forgery of the package passes offline" 0 chk d
expect_exit "and fails upstream" 1 chk d --upstream; out_has "forged"
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; sed -i "s|^source=.*|source=$T/nowhere|" "$T/d/scripts/gates/PIN"
expect_exit "an unreachable package source is exit 3 (vbm-land still verified)" 3 chk d --upstream; out_has "cannot reach the source"; out_has "the source confirms"
( cd "$G" && echo 1.1.0 > VERSION && git add -A && git commit -qm "chore: release 1.1.0" && git tag -a v1.1.0 -m x )
expect_exit "a newer release is advice, with the command to take it" 0 chk c1 --upstream; out_has "newer release exists: v1.1.0 (pinned: v1.0.0). scripts/land/bin/land-update --pkg gates v1.1.0"

echo "## the lander refuses a landing that edits a vendored package"
printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\n' > "$T/c1/scripts/land.conf"; git -C "$T/c1" add -A; git -C "$T/c1" commit -qm "chore(land): vbm-land and gates" -m "Task-ID: t"
expect_exit "the first landing of land and the package passes" 0 bash -c "cd '$T/c1' && scripts/land-direct"
git -C "$T/c1" fetch -q origin; git -C "$T/c1" checkout -q -B main origin/main; before=$(remote_head)
echo '# patched in the consumer' >> "$T/c1/scripts/gates/core/lib.sh"; git -C "$T/c1" commit -qam "fix(gates): patch the vendored copy" -m "Task-ID: t"
expect_exit "a change that edits the vendored package is refused (exit 12)" 12 bash -c "cd '$T/c1' && scripts/land-direct"; out_has "differs from the pinned release"
check "nothing reached the remote" test "$(remote_head)" = "$before"
git -C "$T/c1" reset -q --hard origin/main; echo GATES_TYPO=1 > "$T/c1/scripts/gates.conf"; git -C "$T/c1" add -A; git -C "$T/c1" commit -qm "chore(gates): a typo in the conf" -m "Task-ID: t"
expect_exit "a landing with an unknown key in scripts/gates.conf is refused (exit 12)" 12 bash -c "cd '$T/c1' && scripts/land-direct"; out_has "unknown key GATES_TYPO"
git -C "$T/c1" reset -q --hard origin/main; echo GATES_BUDGET=3 > "$T/c1/scripts/gates.conf"; git -C "$T/c1" add -A; git -C "$T/c1" commit -qm "chore(gates): a known key" -m "Task-ID: t"
expect_exit "a landing with a known key lands" 0 bash -c "cd '$T/c1' && scripts/land-direct"
finish
