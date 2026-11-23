#!/usr/bin/env bash
# land-release --area NAME in a family repository that keeps NO registry/NAME.json (it describes its libraries with cards and derives the version from lib/NAME/VERSION): the release is made. A mirror that EXISTS and disagrees is still refused (the guarantee is kept, not dropped). No network.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null && command -v python3 >/dev/null || { fail "ssh-keygen and python3 are needed"; finish; exit; }
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint
O=$T/family.git; F=$T/family
git init -q --bare -b main "$O"; mkdir -p "$F/$LAND_DIR/bin" "$F/$LAND_DIR/lib" "$F/lib/alpha"
( cd "$ROOT" && cp bin/land-release "$F/$LAND_DIR/bin/" && cp lib/verify.sh lib/paths.sh lib/areas.sh lib/areas.py lib/subtree.sh "$F/$LAND_DIR/lib/" )
echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$F/$LAND_SIGNERS_FILE"; echo "LAND_RC_CMD=true" > "$F/$LAND_CONF_FILE"
echo '{"version":1,"areas":[{"name":"alpha","paths":["lib/alpha/*"],"steps":[]}]}' > "$F/$LAND_AREAS_FILE"
echo "alpha one" > "$F/lib/alpha/a.txt"; echo 0.1.0 > "$F/lib/alpha/VERSION"; printf '## 0.1.0\n\nfirst\n' > "$F/lib/alpha/CHANGELOG.md"
( cd "$F" && git init -q -b main && git config commit.gpgsign false && git remote add origin "$O" && git add -A && git commit -qm "family" && git push -q origin main )
rel() { ( cd "$F" && LAND_SIGNING_KEY=$K/maint "./$LAND_DIR/bin/land-release" "$@" ); }
tagof() { git -C "$O" rev-parse -q --verify "refs/tags/$1" >/dev/null; }
check "the repository keeps no registry mirror" bash -c "[ ! -e '$F/registry' ]"
expect_exit "a library of a repository with no mirror is released (exit 0)" 0 rel --area alpha --push
check "the signed tag alpha/v0.1.0 exists" tagof alpha/v0.1.0
check "and it verifies against the signers file" git -C "$O" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$F/$LAND_SIGNERS_FILE" verify-tag alpha/v0.1.0
echo 0.2.0 > "$F/lib/alpha/VERSION"; printf '## 0.2.0\n\nchange\n\n' | cat - "$F/lib/alpha/CHANGELOG.md" > "$T/cl"; mv "$T/cl" "$F/lib/alpha/CHANGELOG.md"
mkdir -p "$F/registry"; echo '{"version":"0.0.9"}' > "$F/registry/alpha.json"
( cd "$F" && git add -A && git commit -qm "0.2.0 with a stale mirror" && git push -q origin main )
expect_exit "a mirror that EXISTS and disagrees is still refused (exit 1)" 1 rel --area alpha --push; out_has "registry/alpha.json says version"
check "and no tag was made" bash -c "! git -C '$O' rev-parse -q --verify refs/tags/alpha/v0.2.0 >/dev/null"
finish
