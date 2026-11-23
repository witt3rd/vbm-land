#!/usr/bin/env bash
# land-release --area NAME --declare (docs/family-repo.md section 5): the candidate branch carries the LIBRARY's name, rc/NAME/vX.Y.Z, so two libraries released at the same version cannot collide, a candidate is never declared twice, and a release without --area keeps the plain rc/vX.Y.Z. No signing key and no network: declaring needs neither.
. "$(dirname "$0")/lib.sh"
sandbox
O=$T/family.git; F=$T/family
git init -q --bare -b main "$O"; mkdir -p "$F/$LAND_DIR/bin" "$F/$LAND_DIR/lib" "$F/lib/alpha" "$F/lib/beta" "$F/registry"
( cd "$ROOT" && cp bin/land-release "$F/$LAND_DIR/bin/" && cp lib/verify.sh lib/paths.sh lib/areas.sh lib/areas.py lib/subtree.sh "$F/$LAND_DIR/lib/" )   # the tool as the family repository vendors it
for n in alpha beta; do echo "$n" > "$F/lib/$n/a.txt"; echo 0.3.0 > "$F/lib/$n/VERSION"; printf '## 0.3.0\n\nfirst\n' > "$F/lib/$n/CHANGELOG.md"; printf '{"version":"0.3.0"}\n' > "$F/registry/$n.json"; done
echo '{"version":1,"areas":[{"name":"alpha","paths":["lib/alpha/*"],"steps":[]},{"name":"beta","paths":["lib/beta/*"],"steps":[]},{"name":"registry","paths":["registry/*"],"steps":[]}]}' > "$F/$LAND_AREAS_FILE"
( cd "$F" && git init -q -b main && git config commit.gpgsign false && git remote add origin "$O" && git add -A && git commit -qm "family" && git push -q origin main )
rel() { ( cd "$F" && "./$LAND_DIR/bin/land-release" "$@" ); }
has_branch() { git -C "$O" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
expect_exit "--declare for alpha cuts rc/alpha/v0.3.0 (exit 0)" 0 rel --area alpha --declare; out_has "declared the candidate rc/alpha/v0.3.0"
expect_exit "--declare for beta at the SAME version cuts its own rc/beta/v0.3.0 (exit 0): no collision" 0 rel --area beta --declare; out_has "declared the candidate rc/beta/v0.3.0"
check "both candidate branches exist" bash -c "git -C '$O' rev-parse -q --verify refs/heads/rc/alpha/v0.3.0 >/dev/null && git -C '$O' rev-parse -q --verify refs/heads/rc/beta/v0.3.0 >/dev/null"
check "and no plain rc/v0.3.0 was made for a library" bash -c "! git -C '$O' rev-parse -q --verify refs/heads/rc/v0.3.0 >/dev/null"
expect_exit "declaring alpha again is refused (exit 1)" 1 rel --area alpha --declare; out_has "already declared"
echo 0.3.0 > "$F/VERSION"; rm -rf "$F/registry"; ( cd "$F" && git add -A && git commit -qm "a repository with no registry" && git push -q origin main )
expect_exit "a release with no --area keeps the plain name rc/v0.3.0 (exit 0)" 0 rel --declare; out_has "declared the candidate rc/v0.3.0"
finish
