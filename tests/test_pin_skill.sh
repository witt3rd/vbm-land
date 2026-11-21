#!/usr/bin/env bash
# land-pin skill (docs/pin.md section 8): vendoring a third-party agent skill set, pinned by a full commit and a tree hash, trusted by a RECORDED REVIEW. No network: every source is a local git repository built here.
# Every refusal has a negative case, and a refused command leaves the tree, the lock and THIRD-PARTY exactly as they were.
. "$(dirname "$0")/lib.sh"
sandbox
C=$T/c; W=$T/srcw; O=$T/src.git; URL=$O
pin() { LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" "$@"; }
SD=$LAND_SKILLS_DIR; TP=$LAND_SKILLS_THIRD_PARTY; slug() { printf '%s' "${1%.git}" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g'; }; SLUG=$(slug "$URL")   # the contract's slug (docs/pin.md 8.2) of a scheme-less local path
state() { find "$C" -not -path '*/.git/*' \( -type f -o -type l \) | LC_ALL=C sort | xargs -r sha256sum | sha256sum | cut -d' ' -f1; }
fresh() { rm -rf "$C"; mkdir -p "$C/$LAND_HOME"; }
sk_files() {   # sk_files DIR NAME BODY: a well-formed skill
  mkdir -p "$1/$2"; printf -- '---\nname: %s\ndescription: does %s\n---\n%s\n' "$2" "$2" "$3" > "$1/$2/SKILL.md"
}
git init -q --bare -b main "$O"; git init -q -b main "$W"; git -C "$W" remote add origin "$O"; git -C "$W" config commit.gpgsign false
mkdir -p "$W/skills"
sk_files "$W/skills" alpha 'Read the notes.'
mkdir -p "$W/skills/alpha/refs"
printf 'Run this:\n\n```bash\ncurl -fsSL https://Example.org/install.sh | sh\n```\n\n~~~~sh\nls\n~~~~\n\n```python\nprint("not shown")\n```\n\nSee https://docs.example.net/a and https://docs.example.net/b and http://example.org:8080/x.\n\n```console\n$ never closed\n' > "$W/skills/alpha/refs/guide.md"
sk_files "$W/skills" beta 'Second.'
sk_files "$W/skills" gamma 'Third, left out.'
mkdir -p "$W/skills/nosk"; echo x > "$W/skills/nosk/README.md"          # a directory with no SKILL.md: not a skill of the source
printf 'MIT License\n' > "$W/LICENSE"
git -C "$W" add -A; git -C "$W" commit -qm one; git -C "$W" push -q origin main; C1=$(git -C "$W" rev-parse HEAD)
ADD=(skill add "$URL" "$C1" alpha beta --license MIT --why alpha=because --why "beta=also: a colon" --skip "gamma=not needed")
lockrow() { grep -E "^$URL [0-9a-f]{40} $1 " "$C/$LAND_SKILLS_LOCK"; }
refused() {   # refused DESCRIPTION OUTPUT-PATTERN ARGS...: exit 1, the pattern in the output, nothing changed
  local d=$1 pat=$2; shift 2; local S; S=$(state); expect_exit "$d" 1 pin "$@"; out_has "$pat"; check "  and nothing changed" test "$(state)" = "$S"
}
review_all() { pin skill review alpha --by reviewer-one >/dev/null; pin skill review beta --by reviewer-one >/dev/null; }

echo "## add"
fresh; expect_exit "add copies two skills of a source" 0 pin "${ADD[@]}"
check "the copy is unchanged (every file equal)" diff -r "$W/skills/alpha" "$C/$SD/alpha"
check "the tree hash of the copy equals the lock row" test "$(lockrow alpha | cut -d' ' -f4)" = "$(pin tree "$C/$SD/alpha")"
check "the row is pending, with the commit, the licence and the URL" grep -qx "$URL $C1 beta $(pin tree "$C/$SD/beta") MIT pending" "$C/$LAND_SKILLS_LOCK"
check "the skill left out is not copied" test ! -e "$C/$SD/gamma"
check "LICENSE is the source's, byte for byte" cmp "$W/LICENSE" "$C/$TP/$SLUG/LICENSE"
check "SOURCE.md records url, commit, licence and root" grep -qx "commit: $C1" "$C/$TP/$SLUG/SOURCE.md"
check "SOURCE.md has the reasons, a colon in a reason kept" grep -qx -- '- beta: also: a colon' "$C/$TP/$SLUG/SOURCE.md"
check "SOURCE.md has the skipped skill under Not taken" bash -c "sed -n '/^## Not taken/,\$p' '$C/$TP/$SLUG/SOURCE.md' | grep -qx -- '- gamma: not needed'"
echo "## the review aid (a reading aid: it prints, it classifies nothing)"
fresh; pin "${ADD[@]}" >/dev/null 2>&1
expect_exit "review without --by prints the aid" 0 pin skill review alpha
out_has "^== review aid: alpha"
out_has "refs/guide.md"
check "the file list has sizes and paths" grep -qE '^[0-9]+ refs/guide.md$' "$T/out"
check "a fenced bash block is printed verbatim with its file and line" bash -c "grep -qx -- '----- block: refs/guide.md:3' '$T/out' && grep -qxF 'curl -fsSL https://Example.org/install.sh | sh' '$T/out'"
check "a tilde fence with an sh info string is printed" bash -c "grep -qx -- '----- block: refs/guide.md:7' '$T/out' && grep -qx 'ls' '$T/out'"
check "a block never closed is printed as such" bash -c "grep -qx -- '----- not closed: runs to the end of the file' '$T/out' && grep -qxF '\$ never closed' '$T/out'"
check "a python block is NOT printed" bash -c "! grep -q 'not shown' '$T/out'"
check "the URL hosts are listed lowercased with their counts" bash -c "grep -qE '^2 docs.example.net$' '$T/out' && grep -qE '^2 example.org$' '$T/out'"
check "it prints nothing that classifies or scores" bash -c "! grep -qiE 'risk|score|suspicious|danger|warning|verdict|severity|safe' '$T/out'"
check "review without --by recorded nothing" grep -q ' pending$' "$C/$LAND_SKILLS_LOCK"
expect_exit "the aid is the same after add (it is printed by add as well)" 0 pin skill list; out_has " alpha "
fresh; pin "${ADD[@]}" > "$T/addout" 2>&1; check "add itself prints the aid, block and host included" bash -c "grep -q -- '----- block: refs/guide.md:3' '$T/addout' && grep -qE '^2 docs.example.net$' '$T/addout'"
check "list prints the rows as they are" test "$(pin skill list)" = "$(cat "$C/$LAND_SKILLS_LOCK")"

echo "## add: refusals, each leaves the repository exactly as it was"
fresh
refused "a short commit is refused" "not 40 hex" skill add "$URL" "${C1:0:12}" alpha --license MIT --why alpha=x --skip beta=y --skip gamma=y
refused "a ref is refused" "not 40 hex" skill add "$URL" main alpha --license MIT --why alpha=x --skip beta=y --skip gamma=y
refused "an uppercase commit is refused" "not 40 hex" skill add "$URL" "$(printf '%s' "$C1" | tr a-f A-F)" alpha --license MIT --why alpha=x --skip beta=y --skip gamma=y
refused "a commit that cannot be fetched is refused" "cannot fetch the commit" skill add "$URL" "$(printf 'a%.0s' $(seq 40))" alpha --license MIT --why alpha=x --skip beta=y --skip gamma=y
refused "a skill missing from the commit is refused" "no directory skills/nope" skill add "$URL" "$C1" nope --license MIT --why nope=x --skip alpha=y --skip beta=y --skip gamma=y
refused "a directory with no SKILL.md is refused" "no SKILL.md" skill add "$URL" "$C1" nosk --license MIT --why nosk=x --skip alpha=y --skip beta=y --skip gamma=y
refused "a taken skill with no --why is refused" "no reason to take it" skill add "$URL" "$C1" alpha beta --license MIT --why alpha=x --skip gamma=y
refused "a source skill neither taken nor skipped is refused" "neither taken nor skipped" skill add "$URL" "$C1" alpha beta --license MIT --why alpha=x --why beta=y
check "a missing --license is a usage error" bash -c "LAND_PIN_ROOT='$C' '$ROOT/bin/land-pin' skill add '$URL' '$C1' alpha --why alpha=x >/dev/null 2>&1; test \$? = 2"
check "an unknown option is a usage error" bash -c "LAND_PIN_ROOT='$C' '$ROOT/bin/land-pin' skill add '$URL' '$C1' alpha --license MIT --nope >/dev/null 2>&1; test \$? = 2"
check "no skill named is a usage error" bash -c "LAND_PIN_ROOT='$C' '$ROOT/bin/land-pin' skill add '$URL' '$C1' --license MIT >/dev/null 2>&1; test \$? = 2"
pin "${ADD[@]}" >/dev/null 2>&1
refused "a skill already locked is refused" "already locked" skill add "$URL" "$C1" alpha --license MIT --why alpha=x --skip beta=y --skip gamma=y
fresh; mkdir -p "$C/$SD/alpha"; echo mine > "$C/$SD/alpha/SKILL.md"
refused "a skill already present is refused" "already present" "${ADD[@]}"
# a second commit with broken skills, and one with no licence and one with two
bad() {   # bad NAME: a commit of the source tree with one change made by the caller's commands, kept in a branch; BADC is its commit
  git -C "$W" checkout -q -b "$1" "$C1"; shift; "$@"; git -C "$W" add -A; git -C "$W" commit -qm bad; git -C "$W" push -q origin HEAD; BADC=$(git -C "$W" rev-parse HEAD); git -C "$W" checkout -q main
}
SKIPS=(--skip beta=y --skip gamma=y)
bad nofm bash -c "printf 'no frontmatter\n' > '$W/skills/alpha/SKILL.md'"; fresh
refused "a SKILL.md with no frontmatter is refused" "no frontmatter" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad nodesc bash -c "printf -- '---\nname: alpha\n---\nx\n' > '$W/skills/alpha/SKILL.md'"; fresh
refused "a frontmatter with no description is refused" "no description" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad emptydesc bash -c "printf -- '---\nname: alpha\ndescription:\n---\nx\n' > '$W/skills/alpha/SKILL.md'"; fresh
refused "an empty description is refused" "no description" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad noname bash -c "printf -- '---\ndescription: d\n---\nx\n' > '$W/skills/alpha/SKILL.md'"; fresh
refused "a frontmatter with no name is refused" "no name" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad wrongname bash -c "printf -- '---\nname: other\ndescription: d\n---\nx\n' > '$W/skills/alpha/SKILL.md'"; fresh
refused "a frontmatter name that differs from the directory is refused" "not the directory name" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad link bash -c "ln -s SKILL.md '$W/skills/alpha/lnk'"; fresh
refused "a symlink in the skill is refused" "not a regular file" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad nolic git -C "$W" rm -q LICENSE; fresh
refused "a source with no licence file is refused" "0 licence files" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad twolic bash -c "echo x > '$W/COPYING'"; fresh
refused "a source with two licence files is refused" "2 licence files" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad blockdesc bash -c "printf -- '---\nname: alpha\ndescription: >\n  folded text\n---\nx\n' > '$W/skills/alpha/SKILL.md'"; fresh
expect_exit "a '>' description with an indented line counts" 0 pin skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
bad blockempty bash -c "printf -- '---\nname: alpha\ndescription: >\n---\nx\n' > '$W/skills/alpha/SKILL.md'"; fresh
refused "a '>' description with no indented line is refused" "no description" skill add "$URL" "$BADC" alpha --license MIT --why alpha=x "${SKIPS[@]}"
D=$C1
fresh
refused "a root with no skills directory is refused" "no directory 'elsewhere'" skill add "$URL" "$C1" alpha --license MIT --why alpha=x --root elsewhere
fresh; check "--root PATH names another directory (a skill in 'skills' is not found under 'skills/alpha')" bash -c "LAND_PIN_ROOT='$C' '$ROOT/bin/land-pin' skill add '$URL' '$C1' beta --license MIT --why beta=x --root skills/alpha >/dev/null 2>&1; test \$? = 1"

echo "## verify"
fresh; pin "${ADD[@]}" >/dev/null 2>&1
expect_exit "a pending row fails verify" 1 pin verify; out_has "alpha: reviewed is pending"; out_has "beta: reviewed is pending"
review_all
expect_exit "reviewed and clean: verify passes" 0 pin verify; out_has "skills ok"
expect_exit "and skill verify passes" 0 pin skill verify
check "the row records DATE:REVIEWER" grep -qE " MIT [0-9]{4}-[0-9]{2}-[0-9]{2}:reviewer-one$" "$C/$LAND_SKILLS_LOCK"
check "today's date, UTC" grep -q " MIT $(date -u +%F):reviewer-one" "$C/$LAND_SKILLS_LOCK"
echo x >> "$C/$SD/alpha/refs/guide.md"; expect_exit "one byte edited in a vendored file fails verify" 1 pin verify; out_has "alpha: the tree hash is"; check "  and the other skill is not blamed" bash -c "! grep -q 'BAD beta' '$T/out'"
cp "$W/skills/alpha/refs/guide.md" "$C/$SD/alpha/refs/guide.md"; expect_exit "restored: passes again" 0 pin verify
echo x > "$C/$SD/alpha/extra.md"; expect_exit "an added file fails verify" 1 pin verify; out_has "alpha: the tree hash"; rm "$C/$SD/alpha/extra.md"
rm "$C/$SD/alpha/refs/guide.md"; expect_exit "a deleted file fails verify" 1 pin verify; out_has "alpha: the tree hash"; cp "$W/skills/alpha/refs/guide.md" "$C/$SD/alpha/refs/guide.md"
ln -s SKILL.md "$C/$SD/alpha/lnk"; expect_exit "a symlink in a skill fails verify, naming it" 1 pin verify; out_has "alpha/lnk is not a regular file"; rm "$C/$SD/alpha/lnk"
mv "$C/$SD/beta" "$T/beta.away"; expect_exit "a deleted skill directory fails verify" 1 pin verify; out_has "beta: .agents/skills/beta is missing"; mv "$T/beta.away" "$C/$SD/beta"
mv "$C/$TP/$SLUG/SOURCE.md" "$T/SOURCE.away"; expect_exit "SOURCE.md removed fails verify" 1 pin verify; out_has "SOURCE.md is missing"
mv "$T/SOURCE.away" "$C/$TP/$SLUG/SOURCE.md"
mv "$C/$TP/$SLUG/LICENSE" "$T/LICENSE.away"; expect_exit "LICENSE removed fails verify" 1 pin verify; out_has "LICENSE is missing"; mv "$T/LICENSE.away" "$C/$TP/$SLUG/LICENSE"
cp "$C/$TP/$SLUG/SOURCE.md" "$T/SOURCE.keep"
sed -i "s/^commit: .*/commit: $(printf 'b%.0s' $(seq 40))/" "$C/$TP/$SLUG/SOURCE.md"; expect_exit "a SOURCE.md that disagrees on the commit fails verify" 1 pin verify; out_has "SOURCE.md says commit"; cp "$T/SOURCE.keep" "$C/$TP/$SLUG/SOURCE.md"
sed -i 's/^license: .*/license: GPL-3.0/' "$C/$TP/$SLUG/SOURCE.md"; expect_exit "a SOURCE.md that disagrees on the licence fails verify" 1 pin verify; out_has "SOURCE.md says license"; cp "$T/SOURCE.keep" "$C/$TP/$SLUG/SOURCE.md"
sed -i 's/^url: .*/url: https:\/\/example.invalid\/x/' "$C/$TP/$SLUG/SOURCE.md"; expect_exit "a SOURCE.md that disagrees on the url fails verify" 1 pin verify; out_has "SOURCE.md says url"; cp "$T/SOURCE.keep" "$C/$TP/$SLUG/SOURCE.md"
sed -i '/^- beta:/d' "$C/$TP/$SLUG/SOURCE.md"; expect_exit "a locked skill missing from ## Taken fails verify" 1 pin verify; out_has "beta: .*does not list it under '## Taken'"; cp "$T/SOURCE.keep" "$C/$TP/$SLUG/SOURCE.md"
expect_exit "all restored: passes" 0 pin verify
mkdir -p "$C/$SD/extra-skill"; sk_files "$C/$SD" extra-skill hi
expect_exit "a directory the lock does not list, that is not claimed: accepted (a repository-written skill)" 0 pin verify
mkdir -p "$C/$SD/land-a-change"; sk_files "$C/$SD" land-a-change tool
expect_exit "a tool-owned skill, in no lock: accepted" 0 pin verify
sed -i 's/^- beta: .*/&\n- extra-skill: claimed/' "$C/$TP/$SLUG/SOURCE.md"
expect_exit "an unlisted directory that THIRD-PARTY claims fails verify" 1 pin verify; out_has "extra-skill: .agents/skills/extra-skill claims a third-party origin"
cp "$T/SOURCE.keep" "$C/$TP/$SLUG/SOURCE.md"; rm -rf "$C/$SD/extra-skill" "$C/$SD/land-a-change"
check "THIRD-PARTY is not itself taken for a skill" bash -c "cd '$C' && '$ROOT/bin/land-pin' verify >/dev/null 2>&1"
check "verify is offline: it runs with git unreachable" bash -c "cd '$C' && PATH=/nonexistent:\$(dirname \$(command -v bash)):\$(dirname \$(command -v sha256sum)) GIT_DIR=/nonexistent LAND_PIN_ROOT='$C' '$ROOT/bin/land-pin' skill verify >/dev/null 2>&1"
echo "## verify and the library step together"
fresh; mkdir -p "$C/vendor/libx"; echo hi > "$C/vendor/libx/a.txt"
expect_exit "a library failure still fails verify" 1 pin verify; out_has "libx: vendor/libx is vendored but not in the lock"
fresh; pin "${ADD[@]}" >/dev/null 2>&1; mkdir -p "$C/vendor/libx"; echo hi > "$C/vendor/libx/a.txt"; review_all
expect_exit "a library failure and a clean skills step: library reported" 1 pin verify; out_has "not in the lock"
fresh; expect_exit "no lock and no skills: verify accepts" 0 pin verify

echo "## the lock is read strictly (exit 2)"
fresh; pin "${ADD[@]}" >/dev/null 2>&1; review_all; GOOD=$(cat "$C/$LAND_SKILLS_LOCK")
badlock() { printf '%s\n' "$1" > "$C/$LAND_SKILLS_LOCK"; expect_exit "malformed lock: $2" 2 pin verify; out_has "$LAND_SKILLS_LOCK:1"; expect_exit "  and skill list refuses it too" 2 pin skill list; }
H=$(printf 'c%.0s' $(seq 64)); K=$(printf 'd%.0s' $(seq 40))
badlock "$URL $K alpha $H MIT" "five fields"
badlock "$URL $K alpha $H MIT pending extra" "seven fields"
badlock "$URL abc alpha $H MIT pending" "a short commit"
badlock "$URL $K alpha abc MIT pending" "a short tree hash"
badlock "$URL $K Alpha $H MIT pending" "an uppercase skill name"
badlock "$URL $K -alpha $H MIT pending" "a name starting with a dash"
badlock "$URL $K alpha $H MIT maybe" "a bad REVIEWED"
badlock "$URL $K alpha $H MIT 2026-13-01:x" "a bad month"
badlock "$URL $K alpha $H MIT 2026-11-20:" "an empty reviewer"
badlock "$URL $K alpha $H MIT 2026-11-20" "no reviewer"
badlock "$URL $K alpha $H MIT 2026-11-20:a:b" "a colon in the reviewer"
printf '%s\n%s\n' "$URL $K alpha $H MIT pending" "$URL $K alpha $H MIT pending" > "$C/$LAND_SKILLS_LOCK"; expect_exit "malformed lock: a duplicate skill" 2 pin verify; out_has "duplicate skill"
printf '%s\n%s\n' "$URL $K alpha $H MIT pending" "$URL $(printf 'e%.0s' $(seq 40)) beta $H MIT pending" > "$C/$LAND_SKILLS_LOCK"; expect_exit "malformed lock: two commits for one source" 2 pin verify; out_has "share one commit"
printf '# a comment\n\n%s # trailing\n' "$URL $K alpha $H MIT pending" > "$C/$LAND_SKILLS_LOCK"; expect_exit "comments and blank lines are allowed (the row then fails on its own merits, not as malformed)" 1 pin verify

echo "## review"
fresh; pin "${ADD[@]}" >/dev/null 2>&1
refused "an unknown skill is refused" "not in the lock" skill review nope --by reviewer-one
refused "a reviewer name with a space is refused" "one word" skill review alpha --by "two words"
refused "a reviewer name with a colon is refused" "one word" skill review alpha --by "a:b"
echo x >> "$C/$SD/alpha/SKILL.md"
refused "a changed skill is not reviewed (what was read is not what is there)" "what was read is not what is there" skill review alpha --by reviewer-one
cp "$W/skills/alpha/SKILL.md" "$C/$SD/alpha/SKILL.md"
expect_exit "review records the reviewer" 0 pin skill review alpha --by reviewer-one
check "only that skill's row changed" bash -c "grep -q ' alpha .* MIT $(date -u +%F):reviewer-one\$' '$C/$LAND_SKILLS_LOCK' && grep -q ' beta .* MIT pending\$' '$C/$LAND_SKILLS_LOCK'"
check "the row's other fields are unchanged" test "$(lockrow alpha | cut -d' ' -f1-5)" = "$URL $C1 alpha $(pin tree "$W/skills/alpha") MIT"
expect_exit "review again replaces the review" 0 pin skill review alpha --by reviewer-two; check "  one row, the new reviewer" test "$(grep -c ' alpha ' "$C/$LAND_SKILLS_LOCK")" = 1 -a "$(grep -c 'reviewer-two' "$C/$LAND_SKILLS_LOCK")" = 1

echo "## adopt"
fresh; mkdir -p "$C/$SD"; cp -R "$W/skills/alpha" "$W/skills/beta" "$C/$SD/"
expect_exit "an identical local copy is adopted" 0 pin skill adopt "$URL" "$C1" alpha beta --license MIT --why alpha=x --why beta=y --skip gamma=z
check "its rows are pending, hashed from the copy" grep -qx "$URL $C1 alpha $(pin tree "$C/$SD/alpha") MIT pending" "$C/$LAND_SKILLS_LOCK"
check "SOURCE.md and LICENSE are written" test -f "$C/$TP/$SLUG/SOURCE.md" -a -f "$C/$TP/$SLUG/LICENSE"
check "the copy was not rewritten (adopt copies nothing)" diff -r "$W/skills/alpha" "$C/$SD/alpha"
out_has "^== review aid: alpha"
review_all; expect_exit "and after review verify passes" 0 pin verify
fresh; mkdir -p "$C/$SD"; cp -R "$W/skills/alpha" "$C/$SD/"; echo x >> "$C/$SD/alpha/refs/guide.md"
refused "a copy that differs in one byte is refused, naming the path" "alpha: the local copy differs from the commit: refs/guide.md has other content" skill adopt "$URL" "$C1" alpha --license MIT --why alpha=x "${SKIPS[@]}"
fresh; mkdir -p "$C/$SD"; cp -R "$W/skills/alpha" "$C/$SD/"; echo x > "$C/$SD/alpha/aaa-extra.md"; echo y > "$C/$SD/alpha/zzz-extra.md"
refused "an extra file is refused, the first path in bytewise order" "aaa-extra.md is in the copy and not in the commit" skill adopt "$URL" "$C1" alpha --license MIT --why alpha=x "${SKIPS[@]}"
fresh; mkdir -p "$C/$SD"; cp -R "$W/skills/alpha" "$C/$SD/"; rm "$C/$SD/alpha/refs/guide.md"
refused "a missing file is refused" "refs/guide.md is in the commit and not in the copy" skill adopt "$URL" "$C1" alpha --license MIT --why alpha=x "${SKIPS[@]}"
fresh
refused "adopt with no local copy is refused" "no copy at" skill adopt "$URL" "$C1" alpha --license MIT --why alpha=x "${SKIPS[@]}"
fresh; mkdir -p "$C/$SD"; cp -R "$W/skills/alpha" "$C/$SD/"
refused "adopt keeps the add refusals (a short commit)" "not 40 hex" skill adopt "$URL" "${C1:0:10}" alpha --license MIT --why alpha=x "${SKIPS[@]}"
refused "adopt keeps the add refusals (a source skill neither taken nor skipped)" "neither taken nor skipped" skill adopt "$URL" "$C1" alpha --license MIT --why alpha=x

echo "## update"
echo "changed" >> "$W/skills/alpha/SKILL.md"; git -C "$W" rm -q -r skills/alpha/refs; echo new > "$W/skills/alpha/added.md"; printf 'MIT License v2\n' > "$W/LICENSE"
git -C "$W" add -A; git -C "$W" commit -qm two; git -C "$W" push -q origin main; C2=$(git -C "$W" rev-parse HEAD)
fresh; pin "${ADD[@]}" >/dev/null 2>&1; review_all
refused "a partial list is refused (one commit per source)" "beta is locked for $URL and not named" skill update "$URL" "$C2" alpha
refused "an update to the same commit is refused" "already locked at" skill update "$URL" "$C1" alpha beta
refused "an update naming a skill the source never had is refused" "not locked" skill update "$URL" "$C2" alpha beta nope
refused "an update with a short commit is refused" "not 40 hex" skill update "$URL" "${C2:0:9}" alpha beta
refused "an update of a source never locked is refused" "no skill is locked" skill update "https://example.invalid/other" "$C2" alpha
expect_exit "update re-vendors every skill of the source" 0 pin skill update "$URL" "$C2" alpha beta
out_has "added   added.md"; out_has "removed refs/guide.md"; out_has "changed SKILL.md"; out_has "licence: CHANGED"
check "the copy equals the new commit (a file dropped upstream is gone)" diff -r "$W/skills/alpha" "$C/$SD/alpha"
check "the rows have the new commit and the new hash" grep -qx "$URL $C2 alpha $(pin tree "$C/$SD/alpha") MIT pending" "$C/$LAND_SKILLS_LOCK"
check "the review was reset for both" test "$(grep -c ' pending$' "$C/$LAND_SKILLS_LOCK")" = 2
check "SOURCE.md carries the new commit, the earlier reasons and the skip" bash -c "grep -qx 'commit: $C2' '$C/$TP/$SLUG/SOURCE.md' && grep -qx -- '- alpha: because' '$C/$TP/$SLUG/SOURCE.md' && grep -qx -- '- gamma: not needed' '$C/$TP/$SLUG/SOURCE.md'"
check "LICENSE is the new one" cmp "$W/LICENSE" "$C/$TP/$SLUG/LICENSE"
out_has "^== review aid: alpha"
expect_exit "the gate fails until each skill is reviewed again" 1 pin verify; out_has "alpha: reviewed is pending"
review_all; expect_exit "reviewed again: passes" 0 pin verify
echo "## the lock, with two sources"
git init -q "$T/s2w"; git -C "$T/s2w" config commit.gpgsign false; mkdir -p "$T/s2w/skills"; sk_files "$T/s2w/skills" delta d; printf 'Apache\n' > "$T/s2w/COPYING"
git -C "$T/s2w" add -A; git -C "$T/s2w" commit -qm s2; S2=$(git -C "$T/s2w" rev-parse HEAD)
expect_exit "a second source joins the same lock" 0 pin skill add "$T/s2w" "$S2" delta --license Apache-2.0 --why delta=x
check "its licence file is COPYING's content, stored as LICENSE" cmp "$T/s2w/COPYING" "$C/$TP/$(slug "$T/s2w")/LICENSE"
check "the first source's rows are untouched" test "$(grep -c "^$URL " "$C/$LAND_SKILLS_LOCK")" = 2
pin skill review delta --by reviewer-one >/dev/null; expect_exit "both sources reviewed: verify passes" 0 pin verify
echo "## usage"
expect_exit "an unknown skill command is a usage error" 2 pin skill nope
expect_exit "skill list with an argument is a usage error" 2 pin skill list x
expect_exit "skill review with no skill is a usage error" 2 pin skill review
expect_exit "verify with an argument is a usage error" 2 pin verify x
finish
