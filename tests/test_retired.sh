#!/usr/bin/env bash
# The retired-path check (docs/payload.md 5): a file that moved into the payload must not come back as a repository's own copy. lib/retired-paths.txt ships with the tool (hash-checked like every payload
# file) and `land-check` fails a repository that holds any of its paths, as a file or a link, naming the replacement. Every retired path is shown to fail, and every replacement is a real payload file.
. "$(dirname "$0")/lib.sh"
sandbox
S=$T/src
mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib docs templates skills install VERSION "$S/" )
( cd "$S" && git init -q -b main && git config commit.gpgsign false && echo 1.0.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release 1.0.0" && git tag v1.0.0 )
git clone -q "$T/remote.git" "$T/c"; git -C "$T/c" config commit.gpgsign false
"$S/install" --source "$S" --target "$T/c" v1.0.0 >/dev/null 2>&1 || { fail "install into the scratch consumer"; finish; exit; }
chk() { "$T/c/$LAND_DIR/bin/land-check" --root "$T/c"; }
LIST=$T/c/$LAND_DIR/lib/retired-paths.txt
paths=$(sed -E 's/#.*//' "$LIST" | awk 'NF {print $1}')

echo "## the list"
check "it ships with the tool, inside the manifest" grep -q " $LAND_DIR/lib/retired-paths.txt\$\|  lib/retired-paths.txt\$" "$T/c/$LAND_MANIFEST_FILE"
check "it names the files that moved (at least the evidence pair, the runners and the pin script)" bash -c "for p in scripts/lib-ran.sh scripts/ran-evidence.sh scripts/run-tests-parallel.sh scripts/run-scoped.sh scripts/lib-reap.sh scripts/pinned-lib.py scripts/pinned-libs.lock; do echo '$paths' | grep -qx \$p || exit 1; done"
bad=0; for r in $(sed -E 's/#.*//' "$LIST" | awk 'NF {for (i = 2; i <= NF; i++) if ($i ~ /^(bin|lib)\//) print $i}'); do [ -f "$S/$r" ] || { echo "no payload file $r" >&2; bad=1; }; done
check "every replacement a retired path names is a real payload file" test "$bad" = 0

echo "## land-check"
expect_exit "a repository with none of them passes" 0 chk
mkdir -p "$T/c/scripts"; echo x > "$T/c/scripts/lib-ran.sh"; expect_exit "a retired file the tool ships names the replacement" 1 chk; out_has "scripts/lib-ran.sh is retired: the tool ships lib/ran.sh; delete the repository's copy"; rm -f "$T/c/scripts/lib-ran.sh"
echo x > "$T/c/scripts/test_reap.sh"; expect_exit "a retired TEST says the tool tests it, never that the tool ships it" 1 chk; out_has "scripts/test_reap.sh is retired: tested by the tool itself"; check "  and does not claim the tool ships a test" bash -c "! grep -q 'the tool ships it' '$T/out'"; rm -f "$T/c/scripts/test_reap.sh"
for p in $paths; do
  mkdir -p "$T/c/$(dirname "$p")"; echo x > "$T/c/$p"
  expect_exit "a copy of $p fails" 1 chk; out_has "$p is retired"
  rm -f "$T/c/$p"
done
mkdir -p "$T/c/scripts"; ln -s nowhere "$T/c/scripts/lib-ran.sh"; expect_exit "a dangling link at a retired path fails too (the old layout tracked links)" 1 chk; out_has "scripts/lib-ran.sh is retired"; rm -f "$T/c/scripts/lib-ran.sh"
ln -s "../$LAND_DIR/lib/verify.sh" "$T/c/scripts/lib-ran.sh"; expect_exit "a link that resolves INTO the vendored tool is allowed (it is the vendored file; the old layout tracked such links)" 0 chk; rm -f "$T/c/scripts/lib-ran.sh"
ln -s /etc/hostname "$T/c/scripts/lib-ran.sh"; expect_exit "a link to anything else fails" 1 chk; out_has "scripts/lib-ran.sh is retired"; rm -f "$T/c/scripts/lib-ran.sh"
expect_exit "removed again: passes" 0 chk
sed -i 's#^scripts/lib-ran.sh .*##' "$LIST"; echo x > "$T/c/scripts/lib-ran.sh"; expect_exit "an edited list is drift (the list is hash-checked like the tool)" 1 chk; out_has "DRIFT"
finish
