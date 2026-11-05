#!/usr/bin/env bash
# Pinned vendoring: install, the drift check (offline and upstream), update, audit; and the lander refusing a change that edits its own vendored copy.
# Each refusal has a negative test. The "source repository" is a scratch git repository built from this working tree, so uncommitted work is what is tested.
. "$(dirname "$0")/lib.sh"
sandbox
S=$T/src
make_source() {   # make_source VERSION: a scratch source repository (this tree's files, VERSION set, manifest regenerated) with a commit and a tag v<VERSION>
  mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib templates skills install VERSION "$S/" )
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
check "the skills are vendored into .agents/skills/" bash -c "cd '$T/c1' && for n in new-repo land-a-change triage-red update-vbm-land hold-and-freeze adopt-in-existing-repo release; do grep -q \"^name: \$n\\\$\" .agents/skills/\$n/SKILL.md || exit 1; done"
check "the templates the skills point at are vendored under scripts/land/templates/" bash -c "cd '$T/c1/scripts/land/templates' && test -f AGENTS-block.md -a -f ci.yml.example -a -f ruleset-protect-main.json -a -f ruleset-protect-release-tags.json -a -f PUBLIC-REPO-SETTINGS.md"
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
             "entry script no longer runs the lander:echo 'exit 0' > scripts/land-direct:does not run the pinned lander" \
             "entry script removed:rm scripts/land-direct:does not run the pinned lander" \
             "manifest edited:sed -i '1s/^./0/' scripts/land/MANIFEST.sha256:does not hash to the pin" \
             "skill edited:echo x >> .agents/skills/release/SKILL.md:differs from the pinned release" \
             "skill deleted:rm .agents/skills/triage-red/SKILL.md:is missing" \
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
rm -rf "$T/d"; cp -a "$T/c1" "$T/d"; sed -i '1a # my repository: an extra variable before the exec\nexport MY_VAR=1' "$T/d/scripts/land-direct"
expect_exit "the entry script is the repository's own: extra lines before the exec are fine" 0 chk "$T/d"
cp -a "$T/c1" "$T/d4"; echo "# mine" >> "$T/d4/scripts/land-direct"; "$S/install" --source "$S" --target "$T/d4" v1.0.0 >/dev/null
check "re-installing never overwrites the repository's own entry script" grep -q '^# mine' "$T/d4/scripts/land-direct"
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

echo "## update check (read-only: pinned vs the source's release tags)"
upd() { "$1/scripts/land/bin/land-update" --check --root "$1"; }
rel_tag() { ( cd "$S" && echo "$1" > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "release $1" && git tag "v$1" ); }   # a real release: VERSION and manifest move
expect_exit "pinned at the latest release: up to date" 0 upd "$T/c1"; out_has "up to date"
rel_tag 1.1.1
expect_exit "one patch release behind" 1 upd "$T/c1"; out_has "pinned v1.1.0, latest v1.1.1: behind 1 release (patch)"
rel_tag 1.2.0
expect_exit "a patch and a minor behind: the class is the largest distance" 1 upd "$T/c1"; out_has "latest v1.2.0: behind 2 releases (minor)"
rel_tag 2.0.0
expect_exit "a major release behind" 1 upd "$T/c1"; out_has "latest v2.0.0: behind 3 releases (major)"
check "tags that are not plain releases (v1.0.1-broken, untagged...) are ignored" bash -c "grep -q 'v2.0.0' '$T/out' && ! grep -q 'broken' '$T/out'"
cp -a "$T/c1" "$T/d5"; sed -i 's/^version=.*/version=v1.1.0-dev/' "$T/d5/scripts/land/PIN"
expect_exit "a pre-release pin is behind its own release" 1 upd "$T/d5"; out_has "behind 4 releases"
before=$(git -C "$T/c1" status --porcelain | sort | md5sum); upd "$T/c1" >/dev/null 2>&1 || true
check "--check changes nothing in the repository" test "$(git -C "$T/c1" status --porcelain | sort | md5sum)" = "$before"
GITHUB_ACTIONS=true GITHUB_STEP_SUMMARY=$T/summary expect_exit "under Actions it annotates and writes the summary line" 1 upd "$T/c1"; out_has "::warning title=vbm-land update available::"
check "the summary line was written" grep -q "behind 3 releases (major)" "$T/summary"
expect_exit "an unreachable source is exit 3, never 'up to date'" 3 upd "$T/d2"; out_has "NOT verified up to date"
rm -rf "$T/d"; mkdir -p "$T/d"; expect_exit "a repository without a pin is exit 2" 2 "$T/c1/scripts/land/bin/land-update" --check --root "$T/d"
check "install wrote the scheduled workflow (weekly, dispatch, read-only, a separate file from the gate)" bash -c "f='$T/c1/.github/workflows/vbm-land-update.yml'; grep -q 'schedule:' \$f && grep -q 'workflow_dispatch' \$f && grep -q 'contents: read' \$f && grep -q 'land-update --auto' \$f && grep -q 'land-check --upstream' \$f"
echo '# mine' >> "$T/c1/.github/workflows/vbm-land-update.yml"; "$S/install" --source "$S" --target "$T/c1" v1.0.0 >/dev/null
check "re-installing never overwrites the repository's own workflow" grep -q '^# mine' "$T/c1/.github/workflows/vbm-land-update.yml"
rm "$T/c1/.github/workflows/vbm-land-update.yml"; "$S/install" --source "$S" --target "$T/c1" v1.0.0 >/dev/null
check "an update never brings back a workflow the repository deleted (the repository's own files are made by the first install only)" test ! -e "$T/c1/.github/workflows/vbm-land-update.yml"
"$S/install" --source "$S" --target "$T/c1" v1.1.0 >/dev/null

echo "## land-update --land: the whole update through the repository's own lander"
consumer lu1; "$S/install" --source "$S" --target "$T/lu1" v1.0.0 >/dev/null
printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\nLAND_REQUIRE_TRAILERS=Task-ID\n' > "$T/lu1/scripts/land.conf"
git -C "$T/lu1" add -A; git -C "$T/lu1" commit -qm "chore(land): vbm-land v1.0.0" -m "Task-ID: setup"; ( cd "$T/lu1" && scripts/land-direct >/dev/null 2>&1 )
check "setup: the consumer landed its first copy" bash -c "git -C '$T/remote.git' show main:scripts/land/PIN | grep -q '^version=v1.0.0\$'"
git -C "$T/lu1" fetch -q origin; git -C "$T/lu1" checkout -q -B main origin/main
echo dirty >> "$T/lu1/scripts/land.conf"; expect_exit "--land refuses a dirty worktree" 1 "$T/lu1/scripts/land/bin/land-update" --land v1.1.0 --root "$T/lu1"; out_has "clean worktree"; git -C "$T/lu1" checkout -q scripts/land.conf
( cd "$T/lu1" && scripts/land-direct --hold "not now" >/dev/null )
before=$(remote_head); expect_exit "a hold stops the landed update (exit 14); nothing reaches the remote" 14 "$T/lu1/scripts/land/bin/land-update" --land v1.1.0 --root "$T/lu1"; out_has "NOT landed"
check "main did not move" test "$(remote_head)" = "$before"
check "the update commit stays local to look at" bash -c "git -C '$T/lu1' log -1 --format=%s | grep -q '^chore(land): vbm-land v1.1.0\$'"
( cd "$T/lu1" && scripts/land-direct --release >/dev/null ); git -C "$T/lu1" reset -q --hard origin/main
expect_exit "--land verifies, commits, and lands through the repository's own lander" 0 "$T/lu1/scripts/land/bin/land-update" --land v1.1.0 --root "$T/lu1"; out_has "pristine clone"; out_has '"result":"landed"'
check "main pins v1.1.0, in one commit carrying the required trailer" bash -c "git -C '$T/remote.git' show main:scripts/land/PIN | grep -q '^version=v1.1.0\$' && git -C '$T/remote.git' log -1 --format=%B main | grep -q '^Task-ID: vbm-land-update-v1.1.0\$'"
check "no temporary clone is left behind" bash -c "! ls '${TMPDIR:-/tmp}'/land-update.* 2>/dev/null | grep -q ."

echo "## land-update --auto: LAND_AUTO_UPDATE decides what may update itself"
mk_auto() {   # mk_auto NAME POLICY FROM-TAG: a consumer (with a remote of its own) that landed FROM-TAG with LAND_AUTO_UPDATE=POLICY
  local n=$1; rm -rf "$T/$n" "$T/$n.git"; git init -q --bare -b main "$T/$n.git"; git clone -q "$T/$n.git" "$T/$n" 2>/dev/null; git -C "$T/$n" config commit.gpgsign false
  git -C "$T/$n" commit -q --allow-empty -m "chore: init"; git -C "$T/$n" push -q origin main; "$S/install" --source "$S" --target "$T/$n" "$3" >/dev/null
  printf 'LAND_TEST_CMD=true\nLAND_RED_MODE=off\nLAND_AUTO_UPDATE=%s\n' "$2" > "$T/$n/scripts/land.conf"
  git -C "$T/$n" add -A; git -C "$T/$n" commit -qm "chore(land): vbm-land $3"; ( cd "$T/$n" && scripts/land-direct >/dev/null 2>&1 ) || true; git -C "$T/$n" fetch -q origin; git -C "$T/$n" checkout -q -B main origin/main
}
auto() { "$T/$1/scripts/land/bin/land-update" --auto --root "$T/$1"; }
pinof() { git -C "$T/$1.git" show main:scripts/land/PIN | sed -n 's/^version=//p'; }
mk_auto au0 none v1.1.0; before=$(git -C "$T/au0.git" rev-parse main)
expect_exit "policy none only reports" 1 auto au0; out_has "reporting only"; check "and lands nothing" test "$(git -C "$T/au0.git" rev-parse main)" = "$before"
mk_auto au1 patch v1.1.0
expect_exit "policy patch takes the newest patch release (v1.1.1), not the minor or the major" 0 auto au1; out_has "updating to v1.1.1"
check "main pins v1.1.1" test "$(pinof au1)" = v1.1.1
mk_auto au2 minor v1.1.1
expect_exit "policy minor takes the newest release of the same major (v1.2.0), never the major" 0 auto au2; out_has "updating to v1.2.0"
check "main pins v1.2.0" test "$(pinof au2)" = v1.2.0
mk_auto au3 minor v1.2.0; before=$(git -C "$T/au3.git" rev-parse main)
expect_exit "a major release is never automatic: only reported" 1 auto au3; out_has "a major waits for a person"
check "and lands nothing" test "$(git -C "$T/au3.git" rev-parse main)" = "$before"
mk_auto au4 minor v2.0.0
expect_exit "up to date: nothing to do" 0 auto au4; out_has "up to date"
mk_auto au5 sometimes v1.1.0; check "the lander itself refuses a config with a bad LAND_AUTO_UPDATE (nothing was landed)" test ! -e "$T/au5/scripts/land"
mk_auto au5 none v1.1.0; sed -i 's/^LAND_AUTO_UPDATE=.*/LAND_AUTO_UPDATE=sometimes/' "$T/au5/scripts/land.conf"; git -C "$T/au5" commit -qam "chore: bad policy"; ( cd "$T/au5" && scripts/land-direct >/dev/null 2>&1 ) || true; before=$(git -C "$T/au5.git" rev-parse main)
expect_exit "a bad LAND_AUTO_UPDATE value that reached main never updates" 1 auto au5; check "and lands nothing" test "$(git -C "$T/au5.git" rev-parse main)" = "$before"
mk_auto au6 patch v1.1.0; ( cd "$T/au6" && scripts/land-direct --hold "freeze for the test" >/dev/null ); before=$(git -C "$T/au6.git" rev-parse main)
expect_exit "an auto update stops on a refusal (a hold) with the lander's exit code and lands nothing" 14 auto au6; check "main did not move" test "$(git -C "$T/au6.git" rev-parse main)" = "$before"

echo "## audit"
consumer c3; "$S/install" --source "$S" --target "$T/c3" v1.0.0 >/dev/null; mkdir -p "$T/plain"
expect_exit "audit fails when a repository has drift or no copy" 1 "$S/bin/land-audit" "$T/c1" "$T/c3" "$T/plain"; out_has "none"; out_has "ok"
cp -a "$T/c3" "$T/c3x"; echo '# x' >> "$T/c3x/scripts/land/bin/land-red"
expect_exit "audit shows drift" 1 "$S/bin/land-audit" "$T/c3x"; out_has DRIFT
expect_exit "audit passes when every repository is intact" 0 "$S/bin/land-audit" "$T/c1" "$T/c3"

echo "## audit: warns when the default branch is not protected"
cat > "$T/ghprot" <<'SH'
#!/usr/bin/env bash
case "$2" in
  repos/o/prot/rules/branches/main) printf 'deletion\nnon_fast_forward\n';;
  repos/o/half/rules/branches/main) printf 'deletion\n';;
  repos/o/none/rules/branches/main) ;;
  *) exit 1;;
esac
SH
chmod +x "$T/ghprot"
for n in prot half none down; do consumer "pr-$n"; "$S/install" --source "$S" --target "$T/pr-$n" v1.0.0 >/dev/null; git -C "$T/pr-$n" remote set-url origin "git@github.com:o/$n.git"; done
GH=$T/ghprot expect_exit "audit marks a protected default branch and warns about none, and about one without non-fast-forward (a warning, not a failure)" 0 "$S/bin/land-audit" "$T/pr-prot" "$T/pr-half" "$T/pr-none"
out_has "WARNING"; out_has "protected"; check "exactly the protected one says yes" bash -c "grep -c ' yes ' '$T/out' | grep -qx 1 && grep -c ' NO ' '$T/out' | grep -qx 2"
GH=$T/ghprot expect_exit "audit says unknown when GitHub cannot be asked (offline, error), without a warning" 0 "$S/bin/land-audit" "$T/pr-down"; out_has unknown; check "no warning for unknown" bash -c "! grep -q WARNING '$T/out'"
expect_exit "a remote that is not on GitHub is unknown" 0 "$S/bin/land-audit" "$T/c1"; out_has unknown
check "the ruleset templates are valid and refuse deletion and force-push / tag update" python3 - "$ROOT" <<'PY'
import json, sys
r = sys.argv[1]
m = json.load(open(r + "/templates/ruleset-protect-main.json")); t = json.load(open(r + "/templates/ruleset-protect-release-tags.json"))
assert m["target"] == "branch" and {x["type"] for x in m["rules"]} == {"deletion", "non_fast_forward"} and m["bypass_actors"] == [] and m["enforcement"] == "active"
assert t["target"] == "tag" and {x["type"] for x in t["rules"]} == {"deletion", "update"} and t["bypass_actors"] == []
PY

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
