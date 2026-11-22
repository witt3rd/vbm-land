#!/usr/bin/env bash
# land-release --area NAME (docs/family-repo.md sections 3 and 5): ONE library of a family repository is released as the signed tag NAME/vX.Y.Z, after the steps of its area AND of every area that depends on it pass.
# A local family repository with three libraries: alpha (no deps), beta (depends on alpha) and delta (independent, its area RED on purpose). No network. Every refusal is WATCHED to fail: at the end each guard is cut out of
# a copy of the tool (a mutant) and the scenario that depends on it must then be accepted, so the refusal above is proved to come from that guard.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null && command -v python3 >/dev/null || { fail "ssh-keygen and python3 are needed"; finish; exit; }
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
O=$T/family.git; F=$T/family; LOG=$T/steps.log; : > "$LOG"
git init -q --bare -b main "$O"; mkdir -p "$F/$LAND_DIR/bin" "$F/$LAND_DIR/lib" "$F/lib/alpha" "$F/lib/beta" "$F/lib/delta" "$F/registry"
( cd "$ROOT" && cp bin/land-release "$F/$LAND_DIR/bin/" && cp lib/verify.sh lib/paths.sh lib/areas.sh lib/areas.py lib/subtree.sh "$F/$LAND_DIR/lib/" )   # the tool as the family repository vendors it
echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$F/$LAND_SIGNERS_FILE"
echo "LAND_RC_CMD=touch $T/rc-cmd-ran" > "$F/$LAND_CONF_FILE"
cat > "$F/$LAND_AREAS_FILE" <<JSON
{"version":1,"areas":[
 {"name":"alpha","paths":["lib/alpha/*"],"steps":[{"run":"echo alpha >> $LOG; test \"\$(cat lib/alpha/a.txt)\" != planted-red-in-alpha"}]},
 {"name":"beta","paths":["lib/alpha/*","lib/beta/*"],"steps":[{"run":"echo beta >> $LOG; test \"\$(cat lib/alpha/a.txt)\" != breaks-beta"}]},
 {"name":"delta","paths":["lib/delta/*"],"steps":[{"run":"echo delta >> $LOG; false"}]},
 {"name":"registry","paths":["registry/*"],"steps":[]}
]}
JSON
mklib() { local n=$1; shift; echo "$n one" > "$F/lib/$n/a.txt"; echo 0.1.0 > "$F/lib/$n/VERSION"; printf '## 0.1.0\n\nfirst\n' > "$F/lib/$n/CHANGELOG.md"; printf '{"version":"0.1.0"}\n' > "$F/registry/$n.json"; : > "$F/lib/$n/deps"; [ $# = 0 ] || printf '%s\n' "$@" > "$F/lib/$n/deps"; }
mklib alpha; mklib beta alpha; mklib delta
( cd "$F" && git init -q -b main && git config commit.gpgsign false && git remote add origin "$O" && git add -A && git commit -qm "family" && git push -q origin main )
land() { ( cd "$F" && git add -A && git commit -qm "$1" && git push -q origin main ); }
bump() {   # bump NAME VERSION: the version, the changelog heading and the registry version, in one landing
  local n=$1 v=$2; echo "$v" > "$F/lib/$n/VERSION"; printf '## %s\n\nchange\n\n' "$v" | cat - "$F/lib/$n/CHANGELOG.md" > "$T/cl"; mv "$T/cl" "$F/lib/$n/CHANGELOG.md"; printf '{"version":"%s"}\n' "$v" > "$F/registry/$n.json"; land "release $n $v"
}
rel() { ( cd "$F" && LAND_SIGNING_KEY=$K/maint "./$LAND_DIR/bin/land-release" "$@" ); }
tagof() { git -C "$O" rev-parse -q --verify "refs/tags/$1" >/dev/null; }
verified() { git -C "$O" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$F/$LAND_SIGNERS_FILE" verify-tag "$1"; }
subh() { local d h; d=$(mktemp -d); git -C "$F" archive --format=tar HEAD "lib/$1" | tar -x --strip-components=2 -C "$d"; h=$(tree_hash "$d"); rm -rf "$d"; echo "$h"; }
msg() { git -C "$O" tag -l --format='%(contents)' "$1"; }

echo "## the leaf area is released; the others are left alone"
expect_exit "a repository with registry/ refuses to tag without --area" 2 rel --push; out_has "release one library with --area"
check "and made no tag" bash -c "! git -C '$O' tag -l | grep -q ."
expect_exit "--area beta: signed tag beta/v0.1.0, although the area delta (not a dependent) is red" 0 rel --area beta --push; out_has "area beta and the areas that depend on it run"
check "the tag beta/v0.1.0 exists on the remote" tagof beta/v0.1.0
check "its signature verifies against the signers file" verified beta/v0.1.0
check "it is on the commit that landed" test "$(git -C "$O" rev-parse 'beta/v0.1.0^{commit}')" = "$(git -C "$O" rev-parse main)"
check "the message holds tree_sha256= of lib/beta/" bash -c "[ \"\$(git -C '$O' tag -l --format='%(contents)' beta/v0.1.0 | grep -c '^tree_sha256=')\" = 1 ] && git -C '$O' tag -l --format='%(contents)' beta/v0.1.0 | grep -qx 'tree_sha256=$(subh beta)'"
check "and exactly one dep_tree_sha256= line, for alpha, with the hash of lib/alpha/" bash -c "[ \"\$(git -C '$O' tag -l --format='%(contents)' beta/v0.1.0 | grep -c '^dep_tree_sha256=')\" = 1 ] && git -C '$O' tag -l --format='%(contents)' beta/v0.1.0 | grep -qx 'dep_tree_sha256=alpha:$(subh alpha)'"
check "the other libraries have no tag" bash -c "! git -C '$O' tag -l | grep -qv '^beta/'"
check "the steps of beta ran, and not those of alpha or of delta (they are not dependents of beta)" bash -c "grep -qx beta '$LOG' && ! grep -qx alpha '$LOG' && ! grep -qx delta '$LOG'"
out_has "not run: alpha delta registry"
check "LAND_RC_CMD was not run (it is the repository-wide candidate)" test ! -e "$T/rc-cmd-ran"
C=$T/consumer; mkdir -p "$C/$LAND_HOME"; cp "$F/$LAND_SIGNERS_FILE" "$C/$LAND_SIGNERS_FILE"
expect_exit "land-pin vendor accepts exactly that tag, with its closure" 0 env LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" vendor beta "$O" beta/v0.1.0 --path lib/beta
check "vendor/alpha and vendor/beta are there" test -f "$C/vendor/alpha/a.txt" -a -f "$C/vendor/beta/a.txt"

echo "## a version that did not change, or is not greater, is refused"
expect_exit "the same version again: the tag exists (tags are never moved)" 1 rel --area beta; out_has "already exists"
bump beta 0.9.0; expect_exit "beta 0.9.0 is released" 0 rel --area beta --push
bump beta 0.10.0; expect_exit "0.10.0 after 0.9.0 is greater BY NUMBER and is released" 0 rel --area beta --push
check "beta/v0.10.0 exists" tagof beta/v0.10.0
bump beta 0.2.0; expect_exit "0.2.0 is lower than the existing beta/v0.10.0: refused" 1 rel --area beta; out_has "is not greater"
check "and no tag beta/v0.2.0" bash -c "! git -C '$O' rev-parse -q --verify refs/tags/beta/v0.2.0 >/dev/null"
VER_STATE=$(git -C "$F" rev-parse HEAD)
bump beta 0.11.0; expect_exit "the next greater version is released" 0 rel --area beta --push
echo 0.12.0 > "$F/lib/beta/VERSION"; printf '{"version":"0.12.0"}\n' > "$F/registry/beta.json"; land "version without a changelog heading"
expect_exit "no '## 0.12.0' heading in lib/beta/CHANGELOG.md: refused" 1 rel --area beta; out_has "no heading line"
printf '## 0.12.0\n\n' | cat - "$F/lib/beta/CHANGELOG.md" > "$T/cl"; cp "$T/cl" "$F/lib/beta/CHANGELOG.md"; printf '{"version":"0.0.1"}\n' > "$F/registry/beta.json"; land "registry says another version"
expect_exit "registry/beta.json with another version: refused" 1 rel --area beta; out_has "registry/beta.json says version"
printf '{"version":"0.12.0"}\n' > "$F/registry/beta.json"; land "registry fixed"
expect_exit "a library that has no area is refused (exit 2)" 2 bash -c "cd '$F' && mkdir lib/nonesuch && echo 0.1.0 > lib/nonesuch/VERSION && printf '## 0.1.0\n' > lib/nonesuch/CHANGELOG.md && printf '{\"version\":\"0.1.0\"}\n' > registry/nonesuch.json && git add -A && git commit -qm x && git push -q origin main && LAND_SIGNING_KEY=$K/maint ./$LAND_DIR/bin/land-release --area nonesuch"
git -C "$F" reset -q --hard HEAD~1; git -C "$F" push -q -f origin HEAD:main

echo "## the release of a dependency runs the steps of its dependents"
: > "$LOG"; bump alpha 0.2.0
expect_exit "alpha 0.2.0 with the steps of its dependents green: signed tag alpha/v0.2.0" 0 rel --area alpha --push
check "alpha/v0.2.0 verifies" verified alpha/v0.2.0
check "the steps of alpha AND of beta ran (beta lists lib/alpha/*), not delta's" bash -c "grep -qx alpha '$LOG' && grep -qx beta '$LOG' && ! grep -qx delta '$LOG'"
check "its message has tree_sha256= and no dep_tree_sha256= (alpha has no dependency)" bash -c "msgs=\$(git -C '$O' tag -l --format='%(contents)' alpha/v0.2.0); echo \"\$msgs\" | grep -qx 'tree_sha256=$(subh alpha)' && ! echo \"\$msgs\" | grep -q dep_tree"
check "beta was not released by it (no newer beta tag than beta/v0.11.0)" bash -c "! git -C '$O' tag -l 'beta/v0.12*' | grep -q ."
echo "breaks-beta" > "$F/lib/alpha/a.txt"; bump alpha 0.3.0
expect_exit "a change in alpha that is red in the dependent beta: refused (exit 1)" 1 rel --area alpha --push; out_has "area beta: step"; out_has "RED in an area"
check "and no tag alpha/v0.3.0" bash -c "! git -C '$O' rev-parse -q --verify refs/tags/alpha/v0.3.0 >/dev/null && ! git -C '$F' rev-parse -q --verify refs/tags/alpha/v0.3.0 >/dev/null"
DEP_STATE=$(git -C "$F" rev-parse HEAD)
echo "planted-red-in-alpha" > "$F/lib/alpha/a.txt"; land "alpha itself red"
expect_exit "a red step of the area itself: refused (exit 1)" 1 rel --area alpha --push; out_has "area alpha: step"
echo "fine" > "$F/lib/alpha/a.txt"; land "alpha fixed"
expect_exit "fixed: alpha 0.3.0 is released" 0 rel --area alpha --push

echo "## an unsigned or wrongly signed tag is refused"
bump alpha 0.4.0
expect_exit "no signing key: refused" 1 bash -c "cd '$F' && env -u LAND_SIGNING_KEY ./$LAND_DIR/bin/land-release --area alpha"
expect_exit "an unreadable key: refused" 2 bash -c "cd '$F' && LAND_SIGNING_KEY=$K/none ./$LAND_DIR/bin/land-release --area alpha"
expect_exit "a tag signed by a key the signers file does not list: refused" 1 bash -c "cd '$F' && LAND_SIGNING_KEY=$K/rogue ./$LAND_DIR/bin/land-release --area alpha --push"; out_has "is not signed by a key of"
check "the wrong tag is gone, locally and on the remote" bash -c "! git -C '$F' rev-parse -q --verify refs/tags/alpha/v0.4.0 >/dev/null && ! git -C '$O' rev-parse -q --verify refs/tags/alpha/v0.4.0 >/dev/null"
SIG_STATE=$(git -C "$F" rev-parse HEAD)
expect_exit "and the maintainer's key still releases it" 0 rel --area alpha --push

echo "## each refusal WATCHED to fail: with its guard cut out of a copy of the tool, the same scenario is accepted"
# mutant NAME STATE KEEPTAGS EDIT: a clone of the family repository at STATE (its own origin, its own tags: those not matching KEEPTAGS are dropped), the tool in it edited by the shell command EDIT (run in its tool directory) and committed
# as the head of that origin, so that HEAD is origin/main. The release attempt of the scenario is then made with that copy of the tool.
mutant() {
  local n=$1 st=$2 keep=$3 edit=$4 O2 t; O2=$T/mut-$n.git; MUT=$T/mut-$n
  git clone -q --bare "$O" "$O2"; git -C "$O2" branch -f main "$st"; for t in $(git -C "$O2" tag -l); do case $t in $keep) ;; *) git -C "$O2" tag -d "$t" >/dev/null;; esac; done
  git clone -q "$O2" "$MUT"; git -C "$MUT" config commit.gpgsign false
  ( cd "$MUT/$LAND_DIR" && eval "$edit" ); [ -n "$(git -C "$MUT" status --porcelain)" ] || fail "mutant $n changed nothing"
  ( cd "$MUT" && git add -A && git commit -qm "mutant $n" && git push -q origin main )
}
mrel() { local k=$1; shift; ( cd "$MUT" && LAND_SIGNING_KEY=$K/$k "./$LAND_DIR/bin/land-release" "$@" ); }
mutant version "$VER_STATE" 'beta/*' "sed -i '/\\[guard:version\\]/d' bin/land-release"
expect_exit "the version guard cut out: beta 0.2.0, lower than beta/v0.10.0, is TAGGED (the refusal above came from that guard)" 0 mrel maint --area beta
cat > "$T/only.py" <<'PY'
import sys
d = sys.stdin.buffer.read().split(b"\0")[:-1]
sys.stdout.buffer.write(b"".join(x + b"\0" for i in range(0, len(d), 3) if d[i].decode() == sys.argv[1] for x in d[i:i + 3]))
PY
mutant dependents "$DEP_STATE" 'beta/*' "sed -i 's|done < \"\$tmp/steps0\"|done < <(python3 $T/only.py \"\$4\" < \"\$tmp/steps0\")|' lib/areas.sh"
expect_exit "the dependents not run: the alpha release that is red in beta is TAGGED (the refusal above came from running them)" 0 mrel maint --area alpha
mutant signed "$SIG_STATE" 'beta/*' "sed -i '/\\[guard:signed\\]/d' bin/land-release"
expect_exit "the signature check cut out: the rogue-signed tag is made (the refusal above came from the check)" 0 mrel rogue --area alpha
mutant registry "$(git -C "$F" rev-parse HEAD)" 'none' "sed -i '/\\[guard:registry\\]/d' bin/land-release; echo 1.0.0 > ../../VERSION; sed -i '/\"name\":\"delta\"/d' ../areas.json"
expect_exit "the registry guard cut out: no --area in a repository with registry/ tags the whole repository (v1.0.0)" 0 mrel maint
check "the whole-repository tag v1.0.0 exists in the mutant (and in the real tool the same state is refused: exit 2 above)" git -C "$MUT" rev-parse -q --verify refs/tags/v1.0.0
finish
