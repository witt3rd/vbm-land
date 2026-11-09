#!/usr/bin/env bash
# The MIGRATION of a consumer that still has the OLD layout (before 0.8.0: the tool in $LAND_LEGACY_DIR with its PIN there, and no $LAND_PIN): install moves the repository's own files into
# $LAND_HOME and removes the old tool folder, in the same run that writes the new layout; a destination that already exists stops the whole migration and writes nothing; a repository already in
# the new layout is untouched; and land-update --land stages the old paths, so their deletions are part of the update commit.
# Every path comes from lib/paths.sh (tests/lib.sh sources it): never a literal.
. "$(dirname "$0")/lib.sh"
sandbox
S=$T/src
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$K/signers"; echo "rogue $(cut -d' ' -f1,2 "$K/rogue.pub")" > "$K/rogue-signers"
make_source() {   # make_source VERSION: a scratch source repository (this tree's files, VERSION set, manifest regenerated) with a SIGNED release tag v<VERSION> (a signers file makes signatures mandatory)
  mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib docs templates skills install VERSION "$S/" )
  ( cd "$S" && { [ -d .git ] || git init -q -b main; } && git config commit.gpgsign false && git config gpg.format ssh && git config user.signingkey "$K/maint" \
    && echo "$1" > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release $1" \
    && git tag -s "v$1" -m "release $1" -m "manifest_sha256=$(sha256sum < MANIFEST.sha256 | cut -d' ' -f1)" )
}
make_source 1.0.0
consumer() { git clone -q "$T/remote.git" "$T/$1"; git -C "$T/$1" config commit.gpgsign false; }
old_layout() {   # old_layout DIR: a consumer as a pre-0.8.0 install left it: the tool at the old paths with an old-layout PIN, the repository's own files beside it
  local d=$1
  mkdir -p "$d/$LAND_LEGACY_DIR"
  cp -a "$S/bin" "$S/lib" "$S/docs" "$S/templates" "$S/VERSION" "$S/MANIFEST.sha256" "$d/$LAND_LEGACY_DIR/"
  printf 'source=%s\nversion=v1.0.0\ncommit=%s\nmanifest_sha256=%s\nsignature=unverified\n' "$S" "$(git -C "$S" rev-parse v1.0.0)" "$(sha256sum < "$S/MANIFEST.sha256" | cut -d' ' -f1)" > "$d/$LAND_LEGACY_PIN"
  cat > "$d/$LAND_LEGACY_CONF_FILE" <<'CONF'
LAND_TEST_CMD=true
# the settings this repository wrote itself, carried over by the migration
CONF
  cp "$K/signers" "$d/$LAND_LEGACY_SIGNERS_FILE"   # the repository's own signers file (the old path: the migration must move it, and it is enforced before the migration)
  mkdir -p "$d/$LAND_LEGACY_HOOKS_DEFAULT"; printf '#!/bin/sh\nexit 0\n' > "$d/$LAND_LEGACY_HOOKS_DEFAULT/post-rebase"; chmod +x "$d/$LAND_LEGACY_HOOKS_DEFAULT/post-rebase"
  cat > "$d/$LAND_LEGACY_ENTRY" <<'ENTRY'
#!/usr/bin/env bash
# the repository's own entry script: a variable before the exec, as a consumer may add
export MY_REPO_SETTING=1
exec "$(cd "$(dirname "$0")" && pwd)/land/bin/land-direct" "$@"
ENTRY
  chmod +x "$d/$LAND_LEGACY_ENTRY"
  # a tracked symlink of the repository's OWN that points into the old tool folder (a relative target, resolved from the link's own directory: scripts/ + land/lib/no-crash-record.sh), and one that
  # points somewhere else (the repository's own file): the migration repoints the first and leaves the second alone
  printf '#!/bin/sh\nexit 0\n' > "$d/$LAND_LEGACY_HOME/repo-own.sh"; chmod +x "$d/$LAND_LEGACY_HOME/repo-own.sh"
  ln -s "${LAND_LEGACY_DIR#"$LAND_LEGACY_HOME"/}/lib/no-crash-record.sh" "$d/$LAND_LEGACY_HOME/lib-no-crash-record.sh"
  ln -s repo-own.sh "$d/$LAND_LEGACY_HOME/lib-repo-own.sh"
  git -C "$d" add -A; git -C "$d" commit -qm "chore(land): vbm-land v1.0.0 (the old layout)" -m "Task-ID: setup"
}
entry_ok() { bash -c "cd '$1' && './$LAND_ENTRY' --version | grep -q 'land-direct'"; }   # run as an agent does: from the repository root
moved_not_rewritten() {   # moved_not_rewritten DIR: the repository's own files came across byte for byte (compared with the old-layout commit)
  local d=$1 p
  for p in "$LAND_LEGACY_CONF_FILE:$LAND_CONF_FILE" "$LAND_LEGACY_SIGNERS_FILE:$LAND_SIGNERS_FILE" "$LAND_LEGACY_HOOKS_DEFAULT/post-rebase:$LAND_HOOKS_DEFAULT/post-rebase"; do
    git -C "$d" show "HEAD:${p%%:*}" | cmp -s - "$d/${p#*:}" || return 1
  done
}

echo "## an old-layout consumer is migrated by the install that writes the new layout"
consumer m1; old_layout "$T/m1"
expect_exit "install migrates it (same run: the new layout is written)" 0 "$S/install" --source "$S" --target "$T/m1" v1.0.0
out_has "migrated the old layout"
check "the new layout is there: the tool, the manifest, the PIN beside it, the repository's own files" bash -c "cd '$T/m1' && test -x '$LAND_DIR/bin/land-direct' -a -f '$LAND_MANIFEST_FILE' -a -f '$LAND_PIN' -a -f '$LAND_CONF_FILE' -a -f '$LAND_SIGNERS_FILE' -a -x '$LAND_ENTRY' -a -d '$LAND_HOOKS_DEFAULT'"
check "the repository's own settings, signers and hooks are the old content, moved not rewritten" moved_not_rewritten "$T/m1"
check "the old files are gone, and the old tool folder with them" bash -c "cd '$T/m1' && test ! -e '$LAND_LEGACY_DIR' -a ! -e '$LAND_LEGACY_CONF_FILE' -a ! -e '$LAND_LEGACY_SIGNERS_FILE' -a ! -e '$LAND_LEGACY_ENTRY' -a ! -e '$LAND_LEGACY_HOOKS_DEFAULT'"
check "the entry script keeps its own content, but its exec line runs ./tool/bin/land-direct" bash -c "grep -q 'MY_REPO_SETTING=1' '$T/m1/$LAND_ENTRY' && grep -q '/tool/bin/land-direct' '$T/m1/$LAND_ENTRY' && ! grep -q '/land/bin/land-direct' '$T/m1/$LAND_ENTRY'"
check "and the migrated entry script really runs the vendored lander" entry_ok "$T/m1"
check "a tracked symlink into the old tool folder is repointed into the new one, relative to its own directory" bash -c "cd '$T/m1' && [ \"\$(readlink '$LAND_LEGACY_HOME/lib-no-crash-record.sh')\" = '../$LAND_DIR/lib/no-crash-record.sh' ]"
check "and it resolves to the vendored file, which is there" bash -c "cd '$T/m1' && test -f '$LAND_LEGACY_HOME/lib-no-crash-record.sh'"
check "a symlink that points somewhere else is left alone, and still resolves" bash -c "cd '$T/m1' && [ \"\$(readlink '$LAND_LEGACY_HOME/lib-repo-own.sh')\" = 'repo-own.sh' ] && test -f '$LAND_LEGACY_HOME/lib-repo-own.sh'"
check "the printed migration line names the repointed link" grep -qF "repointed $LAND_LEGACY_HOME/lib-no-crash-record.sh -> ../$LAND_DIR/lib/no-crash-record.sh" "$T/out"
check "the pin is the release's (the old PIN did not survive as the pin)" bash -c "grep -q '^version=v1.0.0\$' '$T/m1/$LAND_PIN' && grep -q \"^commit=\$(git -C '$S' rev-parse 'v1.0.0^{commit}')\$\" '$T/m1/$LAND_PIN' && grep -q '^signature=verified\$' '$T/m1/$LAND_PIN'"
expect_exit "the migrated copy passes the drift check" 0 "$T/m1/$LAND_DIR/bin/land-check" --root "$T/m1"
check "in git it is one change: the new files tracked, the old ones and the old tool folder gone" bash -c "cd '$T/m1' && git add -A && git ls-files --error-unmatch '$LAND_CONF_FILE' '$LAND_ENTRY' '$LAND_PIN' '$LAND_SIGNERS_FILE' >/dev/null && ! git ls-files --error-unmatch '$LAND_LEGACY_CONF_FILE' '$LAND_LEGACY_ENTRY' '$LAND_LEGACY_DIR/PIN' >/dev/null 2>&1"

echo "## the information line: what the repository's own files still call by the old names"
consumer m2; old_layout "$T/m2"
cat > "$T/m2/ci.sh" <<TIER1
#!/usr/bin/env bash
# this repository's own Tier 1, still naming the tool by its old path
$LAND_LEGACY_DIR/bin/land-check --root . >/dev/null
exit 0
TIER1
git -C "$T/m2" add -A; git -C "$T/m2" commit -qm "chore: our own Tier 1" -m "Task-ID: setup"
expect_exit "install migrates a repository whose own Tier 1 still names the old paths" 0 "$S/install" --source "$S" --target "$T/m2" v1.0.0
out_has "INFORMATION ONLY"
out_has "must be updated from the old names to the new ones"
out_has "reference(s) to the old paths are left in the repository's own tracked files"
out_has "ci.sh"
check "migration never edits the repository's own files (the old name is still in ci.sh)" grep -q "$LAND_LEGACY_DIR/bin/land-check" "$T/m2/ci.sh"
consumer m2b; old_layout "$T/m2b"
expect_exit "install migrates a repository that has no reference left" 0 "$S/install" --source "$S" --target "$T/m2b" v1.0.0
out_has "no reference to the old paths is left in the repository's own tracked files"
consumer m3; old_layout "$T/m3"
printf '#!/usr/bin/env bash\n# the repository own entry script, naming the tool from the repository root\nexec %s/bin/land-direct "$@"\n' "$LAND_LEGACY_DIR" > "$T/m3/$LAND_LEGACY_ENTRY"
git -C "$T/m3" commit -qam "chore: an entry script that names the tool from the root" -m "Task-ID: setup"
expect_exit "an entry script that names the old tool from the repository root is migrated too" 0 "$S/install" --source "$S" --target "$T/m3" v1.0.0
check "its exec line is the new path from the root" bash -c "grep -q 'exec $LAND_DIR/bin/land-direct' '$T/m3/$LAND_ENTRY' && ! grep -q '$LAND_LEGACY_DIR' '$T/m3/$LAND_ENTRY'"
check "and it runs the vendored lander" entry_ok "$T/m3"

echo "## a destination that already exists stops the migration, and changes nothing"
clash() {   # clash DIR DEST: an old-layout consumer that already has DEST, made by hand
  consumer "$1"; old_layout "$T/$1"; mkdir -p "$T/$1/$(dirname "$2")"; printf 'this-was-here-first\n' > "$T/$1/$2"
  git -C "$T/$1" add -A; git -C "$T/$1" commit -qm "chore: an early $2" -m "Task-ID: setup"
}
clash c1 "$LAND_CONF_FILE"
before=$(git -C "$T/c1" status --porcelain | sort | md5sum)
expect_exit "a pre-existing $LAND_CONF_FILE refuses the whole migration" 1 "$S/install" --source "$S" --target "$T/c1" v1.0.0
out_has "REFUSED"; out_has "$LAND_CONF_FILE"
check "nothing at all was written (no new tool, no pin, no skill)" bash -c "cd '$T/c1' && test ! -e '$LAND_DIR' -a ! -e '$LAND_PIN' -a ! -e '$LAND_SKILLS_DIR'"
check "the old layout is still whole and untouched" bash -c "cd '$T/c1' && test -x '$LAND_LEGACY_DIR/bin/land-direct' -a -e '$LAND_LEGACY_CONF_FILE' -a -e '$LAND_LEGACY_ENTRY'"
check "the pre-existing file kept its content, and the working tree is unchanged" bash -c "grep -qx 'this-was-here-first' '$T/c1/$LAND_CONF_FILE' && test \"\$(git -C '$T/c1' status --porcelain | sort | md5sum)\" = '$before'"
clash c2 "$LAND_HOOKS_DEFAULT/post-rebase"
expect_exit "a pre-existing hooks directory refuses it too" 1 "$S/install" --source "$S" --target "$T/c2" v1.0.0; out_has "$LAND_HOOKS_DEFAULT"
clash c3 "$LAND_ENTRY"
expect_exit "a pre-existing entry script refuses it too" 1 "$S/install" --source "$S" --target "$T/c3" v1.0.0; out_has "$LAND_ENTRY"
clash c5 "$LAND_SIGNERS_FILE"
expect_exit "a pre-existing signers file refuses it too (it would be silently replaced)" 1 "$S/install" --source "$S" --target "$T/c5" v1.0.0; out_has "$LAND_SIGNERS_FILE"
check "and none of them wrote a tool folder" bash -c "for d in '$T/c2' '$T/c3' '$T/c5'; do test ! -e \"\$d/$LAND_DIR\" || exit 1; done"
consumer c4; old_layout "$T/c4"; cp "$K/rogue-signers" "$T/c4/$LAND_LEGACY_SIGNERS_FILE"; git -C "$T/c4" commit -qam "chore: a signers file that does not know the maintainer" -m "Task-ID: setup"
expect_exit "the old-layout signers file is enforced before the migration: an unsigned release is refused" 1 "$S/install" --source "$S" --target "$T/c4" v1.0.0
out_has "does not verify"; check "and nothing was written" bash -c "cd '$T/c4' && test ! -e '$LAND_DIR' -a ! -e '$LAND_PIN' -a -e '$LAND_LEGACY_DIR/PIN'"

echo "## a repository already in the new layout is untouched by a re-install"
consumer n1; "$S/install" --source "$S" --target "$T/n1" v1.0.0 >/dev/null
cat > "$T/n1/$LAND_CONF_FILE" <<'CONF'
LAND_TEST_CMD=true
# the settings this repository wrote itself, kept across an update
CONF
mkdir -p "$T/n1/$LAND_HOOKS_DEFAULT"; printf '#!/bin/sh\nexit 0\n' > "$T/n1/$LAND_HOOKS_DEFAULT/post-rebase"; chmod +x "$T/n1/$LAND_HOOKS_DEFAULT/post-rebase"
printf '\nexport MY_REPO_SETTING=1\n' >> "$T/n1/$LAND_ENTRY"
git -C "$T/n1" add -A; git -C "$T/n1" commit -qm "chore(land): vbm-land v1.0.0" -m "Task-ID: setup"
snap() { ( cd "$1" && find "$LAND_CONF_FILE" "$LAND_ENTRY" "$LAND_HOOKS_DEFAULT" -type f | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "$(sha256sum < "$f" | cut -d' ' -f1)" "$f"; done ); }
before=$(snap "$T/n1")
expect_exit "re-installing a new-layout repository works, and says nothing of a migration" 0 "$S/install" --source "$S" --target "$T/n1" v1.0.0
check "its own settings, entry script and hooks are byte for byte what they were" test "$(snap "$T/n1")" = "$before"
check "no old path appeared, and the new layout is still intact" bash -c "cd '$T/n1' && test ! -e '$LAND_LEGACY_DIR' -a ! -e '$LAND_LEGACY_CONF_FILE' && '$LAND_DIR/bin/land-check' --root . >/dev/null"
check "the re-install printed no migration" bash -c "! grep -q 'migrated the old layout' '$T/out'"
cp -a "$T/n1" "$T/n2"; sed -i 's|/tool/bin/land-direct|/land/bin/land-direct|' "$T/n2/$LAND_ENTRY"; git -C "$T/n2" commit -qam "chore: a stale entry script" -m "Task-ID: setup"
expect_exit "a repository in the new layout whose entry script still names the old tool is never rewritten (its PIN is the new one: no migration)" 1 "$S/install" --source "$S" --target "$T/n2" v1.0.0
out_has "does not run the pinned lander"
check "its entry script is the repository's own: not rewritten" grep -q '/land/bin/land-direct' "$T/n2/$LAND_ENTRY"
check "and no old tool folder came back" bash -c "cd '$T/n2' && test ! -e '$LAND_LEGACY_DIR'"

echo "## after the migration: the migrated layout is what the next update works from"
( cd "$S" && echo 1.1.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "feat: 1.1.0" && git tag -s v1.1.0 -m "release 1.1.0" -m "manifest_sha256=$(sha256sum < MANIFEST.sha256 | cut -d' ' -f1)" )
consumer lu1; old_layout "$T/lu1"
git -C "$T/lu1" push -q origin main   # main carries the old layout, as a real pre-0.8.0 consumer's does
git -C "$T/lu1" fetch -q origin; git -C "$T/lu1" checkout -q -B main origin/main
expect_exit "the new release's install migrates it" 0 "$S/install" --source "$S" --target "$T/lu1" v1.0.0
git -C "$T/lu1" add -A; git -C "$T/lu1" commit -qm "chore(land): vbm-land v1.0.0 in the new layout" -m "Task-ID: setup"
( cd "$T/lu1" && expect_exit "the migration commit lands through the migrated entry script" 0 "$LAND_ENTRY" )
check "main is in the new layout and carries none of the old paths" bash -c "git -C '$T/remote.git' cat-file -e main:$LAND_PIN && ! git -C '$T/remote.git' cat-file -e main:$LAND_LEGACY_DIR/PIN 2>/dev/null && ! git -C '$T/remote.git' cat-file -e main:$LAND_LEGACY_CONF_FILE 2>/dev/null && ! git -C '$T/remote.git' cat-file -e main:$LAND_LEGACY_ENTRY 2>/dev/null"
check "the landed entry script runs the tool beside it, and the repository's own settings moved" bash -c "git -C '$T/remote.git' show main:$LAND_ENTRY | grep -q '/tool/bin/land-direct' && git -C '$T/remote.git' show main:$LAND_CONF_FILE | grep -q 'carried over by the migration'"
git -C "$T/lu1" fetch -q origin; git -C "$T/lu1" checkout -q -B main origin/main
expect_exit "the next update (land-update --land, its path list carrying the old paths too) commits and lands" 0 "$T/lu1/$LAND_DIR/bin/land-update" --land v1.1.0 --root "$T/lu1"
check "the update commit is one change, and no old path is in it" bash -c "git -C '$T/lu1' log -1 --format=%s | grep -qx 'chore(land): vbm-land v1.1.0' && ! git -C '$T/lu1' log -1 --format= --name-only --no-renames | grep -q '^$LAND_LEGACY_HOME/land'"
check "main pins v1.1.0" bash -c "git -C '$T/remote.git' show main:$LAND_PIN | grep -q '^version=v1.1.0\$'"

echo "## an old-layout consumer updates with install, not with the new land-update (which needs the new PIN)"
git init -q --bare -b main "$T/ld1.git"; git clone -q "$T/ld1.git" "$T/ld1" 2>/dev/null; git -C "$T/ld1" config commit.gpgsign false   # a remote of its own: this consumer is in the old layout and nothing else
old_layout "$T/ld1"
expect_exit "the new land-update says install first: the migration of an old layout is install's job" 2 "$S/bin/land-update" --land v1.1.0 --root "$T/ld1"
out_has "install first"; check "and it changed nothing" bash -c "cd '$T/ld1' && test ! -e '$LAND_DIR' -a -e '$LAND_LEGACY_DIR/PIN'"

echo "## the --land path list names the old paths, not only the new ones"
# The list of paths --land stages must carry the OLD ones too: an update that migrates a repository (install's migration) MOVES the repository's own files out of $LAND_LEGACY_HOME and
# removes $LAND_LEGACY_DIR, and those deletions belong in the update commit. Every path is named by its variable, from lib/paths.sh, exactly as the new ones are.
list=$(sed -n 's/^[[:space:]]*paths=(//p' "$S/bin/land-update")
stages_old() {   # stages_old: does the --land path list name every old path, and the new ones beside them?
  local v
  for v in $(sed -n 's/^\(LAND_LEGACY_[A-Z_]*\)=.*/\1/p' "$ROOT/lib/paths.sh" | LC_ALL=C sort -u); do
    case $v in LAND_LEGACY_HOME) continue;; LAND_LEGACY_PIN) continue;; esac   # the old PIN sits inside $LAND_LEGACY_DIR, which is staged whole
    grep -qF "\$$v" <<<"$list" || { echo "missing: $v" >&2; return 1; }
  done
  for v in LAND_DIR LAND_PIN LAND_CONF_FILE LAND_SIGNERS_FILE LAND_ENTRY LAND_SKILLS_DIR; do grep -qF "\$$v" <<<"$list" || { echo "missing: $v" >&2; return 1; }; done
}
check "the --land commit's path list names every old path of lib/paths.sh, as it names the new ones" stages_old
check "and the old paths are there for their deletions, not instead of the new ones" bash -c "grep -qF '\$LAND_LEGACY_DIR' <<<'$list' && grep -qF '\$LAND_DIR' <<<'$list'"
finish
