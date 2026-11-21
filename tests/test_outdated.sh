#!/usr/bin/env bash
# land-pin outdated and update --all (docs/pin.md section 9). No network: every source is a local git repository built here (a library, a skill source with branches for each shape of change, the tool itself).
# Every negative case is WATCHED to fail: at the end each guard is cut out of a copy of the tool (a mutant) and the scenario that depends on it must go red.
. "$(dirname "$0")/lib.sh"
sandbox
command -v ssh-keygen >/dev/null && command -v jq >/dev/null || { fail "ssh-keygen and jq are needed"; finish; exit; }
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue
C=$T/c; B=$T/base; SW=$T/sw; LW=$T/libw; LU=$T/libu; LR=$T/libr; LV=$T/libv; LV2=$T/libv2; TS=$T/tool; TU=$T/toolu; NOWHERE=$T/nowhere.git
PINBIN=$ROOT/bin/land-pin
pin() { LAND_PIN_ROOT=$C "$PINBIN" "$@"; }
SD=$LAND_SKILLS_DIR; TP=$LAND_SKILLS_THIRD_PARTY; slug() { printf '%s' "${1%.git}" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g'; }; SLUG=$(slug "$SW")
H64=$(printf 'b%.0s' $(seq 64)); H40=$(printf 'a%.0s' $(seq 40))
gitq() { git -c commit.gpgsign=false "$@"; }
state() { { find "$C" -type d | LC_ALL=C sort; find "$C" \( -type f -o -type l \) | LC_ALL=C sort | xargs -r sha256sum; } | sha256sum | cut -d' ' -f1; }   # every directory and every file, .git included
refs_state() { { git -C "$C" rev-parse HEAD; git -C "$C" for-each-ref; git -C "$C" stash list; git -C "$C" reflog; } | sha256sum | cut -d' ' -f1; }
sk_files() { mkdir -p "$1/$2"; printf -- '---\nname: %s\ndescription: does %s\n---\n%s\n' "$2" "$2" "$3" > "$1/$2/SKILL.md"; }
mktag() {   # mktag REPO NAME KEY|none MESSAGE...: an annotated tag on REPO's HEAD, signed by KEY (or not)
  local r=$1 n=$2 k=$3; shift 3; local m=(-m "release $n"); for l in "$@"; do m+=(-m "$l"); done
  if [ "$k" = none ]; then git -C "$r" -c tag.gpgsign=false tag -a "$n" "${m[@]}"; else git -C "$r" -c gpg.format=ssh -c "user.signingkey=$K/$k" tag -s "$n" "${m[@]}"; fi
}
newrepo() { git init -q -b main "$1"; git -C "$1" config commit.gpgsign false; }

# ---- the sources -------------------------------------------------------------------------------------------------------------------------------------------------------------------
# a library: v1.0.0 and v1.1.0 signed by the maintainer
newrepo "$LW"; mkdir -p "$LW/d"; printf 'hello\n' > "$LW/a.txt"; printf 'world\n' > "$LW/d/b.txt"; git -C "$LW" add -A; git -C "$LW" commit -qm one; LREV1=$(git -C "$LW" rev-parse HEAD); mktag "$LW" v1.0.0 maint "tree_sha256=$(tree_of "$LW")"
printf 'new\n' > "$LW/new.txt"; git -C "$LW" add -A; git -C "$LW" commit -qm two; LREV2=$(git -C "$LW" rev-parse HEAD); mktag "$LW" v1.1.0 maint "tree_sha256=$(tree_of "$LW")"
git clone -q "$LW" "$LU"; git -C "$LU" tag -d v1.1.0 >/dev/null; mktag "$LU" v1.1.0 none "tree_sha256=$(tree_of "$LU")"     # the same, whose newer tag is UNSIGNED
git clone -q "$LW" "$LR"; git -C "$LR" tag -d v1.1.0 >/dev/null; mktag "$LR" v1.1.0 rogue "tree_sha256=$(tree_of "$LR")"     # signed by a key that is not listed
git clone -q "$LW" "$LV"; for t in v1.9.0 v1.10.0 v1.2 v1.2.3-rc1 latest; do git -C "$LV" tag "$t"; done                     # a version order that a string comparison gets wrong, and tags that are not versions
git clone -q "$LW" "$LV2"; git -C "$LV2" tag v1.9.0
# the tool: v1.0.0 and v1.1.0 signed (the copy of THIS tree, a release as `install` wants it)
newrepo "$TS"; ( cd "$ROOT" && cp -r bin lib lean docs templates skills install VERSION "$TS/" )
rel() { ( cd "$TS" && echo "$1" > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "release $1" ) && mktag "$TS" "v$1" maint "tree_sha256=$(tree_of "$TS")" "manifest_sha256=$(sha256sum < "$TS/MANIFEST.sha256" | cut -d' ' -f1)"; }
rel 1.0.0; rel 1.1.0
git clone -q "$TS" "$TU"; git -C "$TU" tag -d v1.1.0 >/dev/null; mktag "$TU" v1.2.0 none "tree_sha256=$(tree_of "$TU")"          # the newest release of this source is UNSIGNED
# a skill source: main starts at C1; one branch per shape of change, each made from C1
newrepo "$SW"; mkdir -p "$SW/skills"; sk_files "$SW/skills" alpha 'Read the notes.'; mkdir -p "$SW/skills/alpha/refs"; echo old > "$SW/skills/alpha/refs/old.md"; echo x > "$SW/skills/alpha/x.md"
sk_files "$SW/skills" beta 'Second.'; sk_files "$SW/skills" gamma 'Third, left out.'; printf 'MIT License\n' > "$SW/LICENSE"; echo readme > "$SW/README.md"
git -C "$SW" add -A; git -C "$SW" commit -qm one; C1=$(git -C "$SW" rev-parse HEAD)
br() {   # br NAME CMD...: a branch from C1 with one commit made by the commands (run in the work tree); br_NAME is its commit
  git -C "$SW" checkout -q -B "$1" "$C1"; shift; ( cd "$SW" && eval "$*" ); git -C "$SW" add -A; git -C "$SW" commit -qm "branch"; git -C "$SW" checkout -q main
}
NLP=$(printf 'skills/alpha/a b"c\nd.md'); NLREL=$(printf 'a b"c\nd.md')
br files "echo changed >> skills/alpha/SKILL.md; echo n > skills/alpha/refs/new.md; rm skills/alpha/refs/old.md; git mv skills/alpha/x.md skills/alpha/y.md; printf x > \"\$(printf 'skills/alpha/a b\"c\nd.md')\"; echo changed >> skills/beta/SKILL.md"
br outside "echo more >> README.md"
br prose "echo 'one more sentence of prose.' >> skills/alpha/SKILL.md"
br code "echo 'rm -rf x' > skills/alpha/run.sh"
br licmod "echo v2 >> LICENSE"; br licren "git mv LICENSE COPYING"; br licrm "git rm -q LICENSE"; br twolic "echo c > COPYING"
br nolic "git rm -q LICENSE"; P0=$(git -C "$SW" rev-parse nolic); git -C "$SW" checkout -q -B licadd nolic; ( cd "$SW" && printf 'MIT License\n' > LICENSE && git add -A && git commit -qm readd ); git -C "$SW" checkout -q main
br undec "mkdir skills/delta; printf -- '---\nname: delta\ndescription: d\n---\nx\n' > skills/delta/SKILL.md"
br gone "git rm -q -r skills/beta"
br c2 "echo changed >> skills/alpha/SKILL.md; echo v2 >> LICENSE"
tipof() { git -C "$SW" rev-parse "$1"; }
sw_to() { git -C "$SW" checkout -q main; git -C "$SW" reset -q --hard "$1"; }   # the source's tip (its HEAD) is now that branch (or C1)

# ---- a repository to run in ----------------------------------------------------------------------------------------------------------------------------------------------------
mkpin() { printf 'source=%s\nversion=%s\ncommit=%s\nmanifest_sha256=%s\nsignature=verified\n' "$1" "$2" "$H40" "$H64"; }
lite() {   # lite [LIBLINE] [SKILLPIN]: a repository whose pins are written by hand (outdated verifies nothing): the tool at v1.1.0 (current), optionally a library line and the skill source at a commit
  rm -rf "$C"; mkdir -p "$C/$LAND_HOME"; newrepo "$C"; mkpin "$TS" v1.1.0 > "$C/$LAND_PIN"; : > "$C/$LAND_PINS_FILE"
  [ -z "${1:-}" ] || echo "$1" > "$C/$LAND_PINS_FILE"
  if [ -n "${2:-}" ]; then
    printf '%s %s alpha %s MIT pending\n%s %s beta %s MIT pending\n' "$SW" "$2" "$H64" "$SW" "$2" "$H64" > "$C/$LAND_SKILLS_LOCK"; mkdir -p "$C/$TP/$SLUG"
    printf '# Source: %s\nurl: %s\ncommit: %s\nlicense: MIT\nroot: skills\n\n## Taken\n- alpha: a\n- beta: b\n\n## Not taken\n- gamma: left out\n' "$SLUG" "$SW" "$2" > "$C/$TP/$SLUG/SOURCE.md"
  fi
  git -C "$C" add -A; git -C "$C" commit -qm lite -m x
}
libline() { echo "libx $1 $2 $LREV1 $H64"; }   # libline URL TAG
jq1() { pin outdated --json 2>/dev/null; }

# ---- the full world: the tool, a library and a skill source, vendored for real at their OLD pins; the sources have moved on ----------------------------------------------------------
newrepo "$B"; mkdir -p "$B/$LAND_HOME"; echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$B/$LAND_SIGNERS_FILE"
"$TS/install" --source "$TS" --target "$B" v1.0.0 >/dev/null 2>&1 || fail "setup: the tool could not be installed"
LAND_PIN_ROOT=$B "$ROOT/bin/land-pin" vendor libx "$LW" v1.0.0 >/dev/null 2>&1 || fail "setup: the library could not be vendored"
LAND_PIN_ROOT=$B "$ROOT/bin/land-pin" skill add "$SW" "$C1" alpha beta --license MIT --why alpha=because --why "beta=also: a colon" --skip "gamma=not needed" >/dev/null 2>&1 || fail "setup: the skills could not be added"
for s in alpha beta; do LAND_PIN_ROOT=$B "$ROOT/bin/land-pin" skill review $s --by reviewer-one >/dev/null 2>&1; done
echo ignored.tmp > "$B/.gitignore"; git -C "$B" add -A; git -C "$B" commit -qm "the world" -m x
check "setup: the world verifies" bash -c "LAND_PIN_ROOT='$B' '$ROOT/bin/land-pin' verify >/dev/null 2>&1"
world() { rm -rf "$C"; cp -a "$B" "$C"; sw_to c2; }   # the full world, behind in all three kinds (the skill source's tip is the c2 branch)

echo "## outdated: misuse is exit 2"
lite
expect_exit "an unknown option" 2 pin outdated --nope; out_has "usage: land-pin outdated"
expect_exit "an extra argument" 2 pin outdated x
expect_exit "a bare update is misuse (--all is required)" 2 pin update; out_has "--all is required"
rm "$C/$LAND_PIN"; expect_exit "no PIN: the tool is not installed" 2 pin outdated; out_has "not installed"
lite; echo garbage > "$C/$LAND_PIN"; expect_exit "a malformed PIN" 2 pin outdated
for bad in "source=$TS|version=1.1.0" "source=$TS|version=v1.1.0|commit=abc" "source=$TS|version=v1.1.0|commit=$H40|manifest_sha256=abc" "version=v1.1.0|commit=$H40|manifest_sha256=$H64"; do
  lite; printf '%s\n' "${bad//|/$'\n'}" > "$C/$LAND_PIN"; expect_exit "a PIN with a bad field ($bad)" 2 pin outdated
done
for bad in "libx $LW v1.0.0 $LREV1" "libx $LW 1.0.0 $LREV1 $H64" "libx $LW v1.0.0 abc $H64" "libx $LW v1.0.0 $LREV1 abc" "Libx $LW v1.0.0 $LREV1 $H64" "libx $LW v1.0.0 $LREV1 $H64 extra"; do
  lite "$bad"; expect_exit "a malformed pins.lock ($bad)" 2 pin outdated
done
lite "$(libline "$LW" v1.0.0)"; echo "libx $LW v1.1.0 $LREV1 $H64" >> "$C/$LAND_PINS_FILE"; expect_exit "a duplicate library" 2 pin outdated
lite "" "$C1"; for bad in "$SW $C1 alpha $H64 MIT" "$SW abc alpha $H64 MIT pending" "$SW $C1 Alpha $H64 MIT pending" "$SW $C1 alpha $H64 MIT maybe"; do
  lite "" "$C1"; echo "$bad" > "$C/$LAND_SKILLS_LOCK"; expect_exit "a malformed skills.lock ($bad)" 2 pin outdated
done
rm -rf "$T/plain"; mkdir -p "$T/plain/$LAND_HOME"; mkpin "$TS" v1.1.0 > "$T/plain/$LAND_PIN"
expect_exit "outside a git work tree" 2 env LAND_PIN_ROOT="$T/plain" "$PINBIN" outdated

echo "## outdated: nothing behind is exit 0 (the case that must be ACCEPTED)"
lite; expect_exit "no lock at all: only the tool, current" 0 pin outdated; out_has "outdated: 0 behind, 0 unreachable, 1 pins"
check "  and --json says behind 0" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '.v == 1 and .behind == 0 and .unreachable == 0 and (.pins|length) == 1' >/dev/null"
lite "$(libline "$LW" v1.1.0)" "$(tipof c2)"; sed -i "s/ $(tipof c2) / $(tipof c2) /" "$C/$LAND_SKILLS_LOCK"
sw_to c2; expect_exit "a library at its newest tag, a skill source at its tip, the tool at its newest: exit 0" 0 pin outdated; out_has "0 behind, 0 unreachable, 5 pins"
sw_to "$C1"

echo "## outdated: libraries"
lite "$(libline "$LW" v1.0.0)"
expect_exit "a newer tag is exit 1, named, and the line says the signature is not verified" 1 pin outdated; out_has "land-pin: library libx v1.0.0 -> v1.1.0 (the signature is not verified here)"; out_has "1 behind, 0 unreachable, 2 pins"
check "  the lock is as it was" grep -qx "$(libline "$LW" v1.0.0)" "$C/$LAND_PINS_FILE"
lite "$(libline "$LV" v1.9.0)"; expect_exit "v1.10.0 is newer than v1.9.0 (by number)" 1 pin outdated; out_has "v1.9.0 -> v1.10.0"
check "  and the tags v1.2, v1.2.3-rc1 and latest are ignored" bash -c "! grep -qE 'v1.2|latest' '$T/out'"
lite "$(libline "$LV" v1.10.0)"; expect_exit "the newest tag is the pinned one: current" 0 pin outdated
lite "$(libline "$LV2" v1.10.0)"; expect_exit "v1.9.0 against a pin v1.10.0 is not behind (a string comparison says it is)" 0 pin outdated
lite "$(libline "$LU" v1.0.0)"; expect_exit "an UNSIGNED newer tag is reported all the same" 1 pin outdated; out_has "v1.0.0 -> v1.1.0 (the signature is not verified here)"
lite "$(libline "$LR" v1.0.0)"; expect_exit "a newer tag signed by an unlisted key is reported all the same" 1 pin outdated; out_has "v1.0.0 -> v1.1.0"
lite "$(libline "$NOWHERE" v1.0.0)"; expect_exit "an unreachable library source is exit 3" 3 pin outdated; out_has "libx v1.0.0 unreachable"; out_has "0 behind, 1 unreachable"
check "  and --json shows it unreachable, never hidden" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '.unreachable == 1 and (.pins[] | select(.kind==\"library\") | .status == \"unreachable\" and .newer == null)' >/dev/null"
git -C "$LW" tag -d v1.1.0 >/dev/null; lite "$(libline "$LW" v1.1.0)"; expect_exit "a pinned tag the source no longer has is not this command's finding" 0 pin outdated; mktag "$LW" v1.1.0 maint "tree_sha256=$(tree_of "$LW")"

echo "## outdated: skill sources"
sk_pin() { lite "" "${1:-$C1}"; }
sk_pin; sw_to "$C1"; expect_exit "a tip equal to the pin is current" 0 pin outdated
sw_to files; sk_pin
expect_exit "a changed tip is behind (exit 1): the source line shows the pin and the tip" 1 pin outdated; out_has "land-pin: skill source $SLUG ${C1:0:12} -> $(tipof files | cut -c1-12) (tip)"
out_has "  alpha: M SKILL.md"; out_has "  alpha: A refs/new.md"; out_has "  alpha: D refs/old.md"; out_has "  alpha: D x.md"; out_has "  alpha: A y.md"; out_has "  beta: M SKILL.md"
check "  a renamed file is a D and an A, never an R" bash -c "! grep -qE ': R' '$T/out'"
check "  the licence did not change: no licence line" bash -c "! grep -q 'licence: CHANGED' '$T/out'"
check "  JSON: the path with a space, a quote and a newline survives, as A" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e --arg p \"\$1\" '.pins[] | select(.kind==\"skill\" and .name==\"alpha\") | .files | any(.path == \$p and .status == \"A\")' >/dev/null" _ "$NLREL"
check "  JSON: another skill's change is not listed under this one" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '[.pins[] | select(.kind==\"skill\" and .name==\"alpha\") | .files[].path] | index(\"SKILL.md\") != null' >/dev/null && LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '[.pins[] | select(.kind==\"skill\" and .name==\"beta\") | .files[]] | length == 1' >/dev/null"
sw_to outside; sk_pin; expect_exit "a change outside every locked skill is behind, with no file listed" 1 pin outdated; out_has "  alpha: no file differs"; out_has "  beta: no file differs"
check "  JSON: files is [] for both skills and the source is behind" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '[.pins[] | select(.kind==\"skill\") | .files] == [[],[]] and ([.pins[] | select(.kind==\"skill-source\")][0].status == \"behind\")' >/dev/null"
sw_to prose; sk_pin; pin outdated >/dev/null 2>&1 || true; PROSE=$(pin outdated 2>&1 || true); sw_to code; PCODE=$(pin outdated 2>&1 || true)
check "a tip that differs only in the prose of a SKILL.md gives the same kind of report as one that differs in code" bash -c "echo \"\$1\" | grep -q '  alpha: M SKILL.md' && echo \"\$2\" | grep -q '  alpha: A run.sh'" _ "$PROSE" "$PCODE"
for v in licmod:LICENSE licren:COPYING licrm:none; do b=${v%%:*}; sw_to "$b"; sk_pin; expect_exit "the licence file changed ($b): its own line, never folded into a file list" 1 pin outdated; out_has "  licence: CHANGED (${v#*:}"
  check "  JSON license_changed is true" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '[.pins[] | select(.kind==\"skill-source\")][0].license_changed == true' >/dev/null"; done
sw_to licadd; sk_pin "$P0"; expect_exit "a licence file ADDED since the pin is the licence line" 1 pin outdated; out_has "  licence: CHANGED (LICENSE)"
sw_to undec; sk_pin; expect_exit "a new skill neither locked nor under '## Not taken' is undecided and named" 1 pin outdated; out_has "  undecided: delta (neither locked nor skipped: decide before an update)"
check "  and gamma, which is under '## Not taken', is not" bash -c "! grep -q 'undecided: gamma' '$T/out'"
check "  JSON: undecided is [delta]" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '[.pins[] | select(.kind==\"skill-source\")][0].undecided == [\"delta\"]' >/dev/null"
sw_to gone; sk_pin; expect_exit "a locked skill with no directory at the tip is missing_at_tip, its files deleted" 1 pin outdated; out_has "  beta: missing_at_tip"; out_has "  beta: D SKILL.md"
check "  JSON missing_at_tip is true for beta only" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '[.pins[] | select(.kind==\"skill\" and .missing_at_tip == true) | .name] == [\"beta\"]' >/dev/null"
sw_to "$C1"; git -C "$SW" tag -a v2.1.0 -m rel; sk_pin; expect_exit "a release tag of a skill source is information: with nothing else different the exit is 0" 0 pin outdated
check "  JSON: it is listed as the release, with its commit" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e --arg r '$C1' '[.pins[] | select(.kind==\"skill-source\")][0].release == {tag:\"v2.1.0\",rev:\$r}' >/dev/null"
sw_to files; sk_pin; expect_exit "and with the tip behind it is printed as information" 1 pin outdated; out_has "  release: v2.1.0 (information; the pin stays a commit)"; git -C "$SW" tag -d v2.1.0 >/dev/null
sw_to "$C1"

echo "## outdated: unreachable (3), behind (1), and 1 wins"
lite; sed -i "s|^source=.*|source=$NOWHERE|" "$C/$LAND_PIN"; expect_exit "an unreachable tool source is exit 3" 3 pin outdated; out_has "tool vbm-land v1.1.0 unreachable"
lite "" "$C1"; sed -i "s|^$SW |$NOWHERE |" "$C/$LAND_SKILLS_LOCK"; expect_exit "an unreachable skill source is exit 3" 3 pin outdated; out_has "unreachable"
check "  JSON: the source and both its skills are unreachable" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '.unreachable == 3 and .behind == 0' >/dev/null"
git init -q "$T/other"; git -C "$T/other" config commit.gpgsign false; git -C "$T/other" commit -q --allow-empty -m e; OTHER=$(git -C "$T/other" rev-parse HEAD)
sk_pin "$OTHER"; sed -i "s|^source=.*|source=$TS|" "$C/$LAND_PIN"; sw_to "$C1"; expect_exit "a skill source whose pinned commit cannot be fetched from it is exit 3" 3 pin outdated; out_has "unreachable"
lite "$(libline "$LW" v1.0.0)"; sed -i "s|^source=.*|source=$NOWHERE|" "$C/$LAND_PIN"; expect_exit "a library behind and the tool unreachable: 1 wins" 1 pin outdated; out_has "1 behind, 1 unreachable"
check "  JSON counts both" bash -c "LAND_PIN_ROOT='$C' '$PINBIN' outdated --json | jq -e '.behind == 1 and .unreachable == 1' >/dev/null"

echo "## outdated: read-only, and the typed output is the same report"
for dirty in clean dirty; do
  sw_to files; sk_pin; lite "$(libline "$LW" v1.0.0)" "$C1"; echo readme > "$C/README.md"; git -C "$C" add -A; git -C "$C" commit -qm readme
  if [ $dirty = dirty ]; then echo changed >> "$C/README.md"; echo stray > "$C/untracked.txt"; fi
  S=$(state); RS=$(refs_state); expect_exit "outdated on a $dirty tree reports (exit 1)" 1 pin outdated
  check "  the tree, the lock files and .git are byte for byte as before ($dirty)" test "$(state)" = "$S" -a "$(refs_state)" = "$RS"
  check "  no scratch directory remains ($dirty)" test -z "$(ls -A "$TMPDIR")"
  pin outdated --json >/dev/null 2>&1 || true; check "  nor after --json ($dirty)" test "$(state)" = "$S" -a -z "$(ls -A "$TMPDIR")"
done
lite "$(libline "$LW" v1.0.0)" "$C1"; sw_to files
pin outdated --json > "$T/json" 2>"$T/err" || true
check "--json is ONE line and nothing else on stdout" test "$(wc -l < "$T/json")" = 1
check "  it is valid JSON with v, behind and unreachable" jq -e '.v == 1 and (.behind|type) == "number" and (.unreachable|type) == "number" and (.pins|type) == "array"' "$T/json"
check "  every pin has every key of the contract" jq -e 'all(.pins[]; has("kind") and has("name") and has("source") and has("pinned") and has("newer") and has("status") and has("files") and has("license_changed") and has("undecided") and has("release"))' "$T/json"
check "  kinds: one library, one source, two skills, one tool" jq -e '[.pins[].kind] | sort == ["library","skill","skill","skill-source","tool"]' "$T/json"
pin outdated > "$T/human" 2>&1 || true
check "  the human form is a rendering of it: the same behind count, the same names" bash -c "j=\$(jq -r '.behind' '$T/json'); tail -n1 '$T/human' | grep -q \"outdated: \$j behind, 0 unreachable, \$(jq '.pins|length' '$T/json') pins\" && grep -q 'library libx' '$T/human' && grep -q 'skill source $SLUG' '$T/human' && jq -e '.pins[] | select(.kind==\"tool\") | .status == \"current\"' '$T/json' >/dev/null"
sw_to "$C1"

echo "## update --all: misuse is exit 2"
world
expect_exit "--only with no name" 2 pin update --all --only; out_has "needs at least one NAME"
expect_exit "a name that is no pin" 2 pin update --all --only nonesuch; out_has "is no pin"
expect_exit "an unknown option" 2 pin update --all --nope
expect_exit "a name with no --only" 2 pin update --all libx
echo "libx $LW v1.0.0 $LREV1" > "$C/$LAND_PINS_FILE"; git -C "$C" commit -qam bad; expect_exit "a malformed lock" 2 pin update --all

echo "## update --all: it refuses a dirty tree and changes nothing"
world; echo changed >> "$C/$LAND_CONF_FILE"; S=$(state); R=$(refs_state)
expect_exit "a modified tracked file" 1 pin update --all; out_has "working tree is not clean"; check "  nothing changed" test "$(state)" = "$S" -a "$(refs_state)" = "$R"
git -C "$C" checkout -q -- .; echo x > "$C/untracked.txt"; S=$(state); expect_exit "an untracked file" 1 pin update --all; out_has "untracked.txt"; check "  nothing changed" test "$(state)" = "$S"

echo "## update --all: refused before anything is written"
world; sw_to undec; S=$(state); R=$(refs_state)
expect_exit "an undecided new skill is refused, naming the source and the skill" 1 pin update --all; out_has "skill source $SW has a new skill 'delta'"; check "  nothing changed (the library and the tool were not applied either)" test "$(state)" = "$S" -a "$(refs_state)" = "$R"
expect_exit "--only another pin proceeds" 0 pin update --all --only libx; check "  the library moved" grep -q " v1.1.0 $LREV2 " "$C/$LAND_PINS_FILE"
check "  the skills and the tool did not" bash -c "grep -q ' $C1 alpha ' '$C/$LAND_SKILLS_LOCK' && grep -qx 'version=v1.0.0' <(grep '^version=' '$C/$LAND_PIN')"
world; sw_to gone; S=$(state); expect_exit "a locked skill gone at the tip is refused, naming it" 1 pin update --all; out_has "skill beta is locked and has no directory at the tip"; check "  nothing changed" test "$(state)" = "$S"
world; sed -i "s|^source=.*|source=$NOWHERE|" "$C/$LAND_PIN"; git -C "$C" commit -qam "pin"; S=$(state)
expect_exit "a selected source that cannot be reached is exit 3, nothing changed" 3 pin update --all; out_has "UNREACHABLE tool vbm-land"; check "  nothing changed" test "$(state)" = "$S"
expect_exit "an unreachable source that is not selected is no reason" 0 pin update --all --only libx; check "  the library moved" grep -q " v1.1.0 " "$C/$LAND_PINS_FILE"
world; sed -i "s|^source=.*|source=$TU|" "$C/$LAND_PIN"; git -C "$C" commit -qam pin; S=$(state)
expect_exit "an UNVERIFIED release of the tool (the newest tag is unsigned) is refused" 1 pin update --all; out_has "FAILED tool vbm-land"; check "  and the library and the skills applied before it are put back (atomic)" test "$(state)" = "$S"
check "  git status prints what it printed before (nothing)" test -z "$(git -C "$C" status --porcelain)"

echo "## update --all: a library that is refused"
for v in "$LU:unsigned" "$LR:signed by an unlisted key"; do world; sed -i "s|^libx $LW |libx ${v%%:*} |" "$C/$LAND_PINS_FILE"; git -C "$C" commit -qam pin; S=$(state)
  expect_exit "a newer library tag that is ${v#*:} is refused" 1 pin update --all; out_has "FAILED library libx"; check "  the tree is as it was (the skills and the tool untouched)" test "$(state)" = "$S"; done

echo "## update --all: atomic across the kinds"
world; sw_to twolic; S=$(state)
expect_exit "a skill source with two licence files fails AFTER the library was applied" 1 pin update --all; out_has "FAILED skill source"; out_has "2 licence files"
check "  every kind already applied is put back: the tree is as it was" test "$(state)" = "$S"; check "  git status --porcelain prints nothing" test -z "$(git -C "$C" status --porcelain)"
check "  no stray directory (no .agents/skills leftovers beyond what was there)" test -z "$(find "$C" -name '*.new' -o -name 'snap' | head -n1)"

echo "## update --all: the success path, and what it never does"
world; echo scratch > "$C/ignored.tmp"; HEAD0=$(git -C "$C" rev-parse HEAD); R=$(refs_state); SKB=$(sha256sum "$C/$SD/gamma"/* 2>/dev/null || true)
expect_exit "everything behind is updated in one run, an ignored file is not a dirty tree" 0 pin update --all
out_has "update --all: done. Nothing is committed and nothing is reviewed"; out_has "library libx v1.0.0 -> v1.1.0: read it with: git diff -- vendor/libx"
out_has "skill alpha ${C1:0:12} -> $(tipof c2 | cut -c1-12): read the aid and the files, then: land-pin skill review alpha --by NAME"; out_has "skill beta"; out_has "licence: CHANGED (LICENSE)"; out_has "    M SKILL.md"
out_has "tool vbm-land v1.0.0 -> v1.1.0"; out_has "then: land-pin verify"
check "the library moved to v1.1.0, with the new file" bash -c "grep -q ' v1.1.0 $LREV2 ' '$C/$LAND_PINS_FILE' && test -f '$C/vendor/libx/new.txt'"
check "the skills moved: both rows at the tip the report named (40 hex), pending" bash -c "[ \$(grep -c ' $(tipof c2) ' '$C/$LAND_SKILLS_LOCK') = 2 ] && [ \$(grep -c ' pending\$' '$C/$LAND_SKILLS_LOCK') = 2 ]"
check "the tool moved to v1.1.0" bash -c "grep -qx 'version=v1.1.0' '$C/$LAND_PIN' && grep -qx 1.1.0 '$C/$LAND_DIR/VERSION'"
check "the licence, the reasons and the skips of the earlier add are kept" bash -c "grep -qx 'license: MIT' '$C/$TP/$SLUG/SOURCE.md' && grep -qx -- '- beta: also: a colon' '$C/$TP/$SLUG/SOURCE.md' && sed -n '/^## Not taken/,\$p' '$C/$TP/$SLUG/SOURCE.md' | grep -qx -- '- gamma: not needed' && grep -q ' MIT pending\$' '$C/$LAND_SKILLS_LOCK'"
check "it NEVER COMMITS: HEAD, every ref, the stash and the reflog are as before" test "$(refs_state)" = "$R" -a "$(git -C "$C" rev-parse HEAD)" = "$HEAD0"
check "the change is in the working tree" test -n "$(git -C "$C" status --porcelain)"
check "nothing outside vendor/, .land/ and .agents/skills/ is written" bash -c "! git -C '$C' status --porcelain --untracked-files=all | cut -c4- | grep -vE '^(vendor/|\.land/|\.agents/skills/)'"
check "the ignored file is untouched" test "$(cat "$C/ignored.tmp")" = scratch
check "no scratch directory is left" test -z "$(ls -A "$TMPDIR")"
expect_exit "UNREAD CANNOT PASS: verify is red" 1 pin verify; out_has "alpha: reviewed is pending"; out_has "beta: reviewed is pending"
check "  both named, beta (no file changed in it) as well" bash -c "grep -q 'BAD alpha: reviewed is pending' '$T/out' && grep -q 'BAD beta: reviewed is pending' '$T/out'"
pin skill review alpha --by reviewer-one >/dev/null; expect_exit "one skill still unreviewed: verify stays red" 1 pin verify
pin skill review beta --by reviewer-one >/dev/null; expect_exit "after each is reviewed verify is exit 0 (the case that must be ACCEPTED)" 0 pin verify
git -C "$C" add -A; git -C "$C" commit -qm "the reviewed update"
expect_exit "a second update --all finds nothing behind and touches nothing" 0 pin update --all; out_has "nothing is behind"
expect_exit "outdated now says nothing is behind" 0 pin outdated
S=$(state); expect_exit "--only a current pin is exit 0 with the tree untouched" 0 pin update --all --only libx; check "  untouched" test "$(state)" = "$S"

echo "## update --all --only: a skill name selects its whole source"
world; expect_exit "--only a skill updates its source whole (both skills, one commit)" 0 pin update --all --only beta
check "  both rows moved, the library and the tool did not" bash -c "[ \$(grep -c ' $(tipof c2) ' '$C/$LAND_SKILLS_LOCK') = 2 ] && grep -q ' v1.0.0 ' '$C/$LAND_PINS_FILE' && grep -qx 'version=v1.0.0' '$C/$LAND_PIN'"
world; expect_exit "--only vbm-land updates the tool alone" 0 pin update --all --only vbm-land; check "  only the tool moved" bash -c "grep -qx 'version=v1.1.0' '$C/$LAND_PIN' && grep -q ' v1.0.0 ' '$C/$LAND_PINS_FILE' && grep -q ' $C1 alpha ' '$C/$LAND_SKILLS_LOCK'"

# ---- every negative WATCHED to fail: a mutant of the tool with one guard cut out must make its scenario red ------------------------------------------------------------------------
echo "## the negatives are watched to fail (a mutant with one guard removed)"
MUT=$T/mut; REAL=$ROOT/bin/land-pin
mutant() {   # mutant FILE SED: a copy of bin/ and lib/ with the sed expression applied to FILE; it must change it
  rm -rf "$MUT"; mkdir -p "$MUT"; cp -r "$ROOT/bin" "$ROOT/lib" "$MUT/"; sed -i "$2" "$MUT/$1"
  if cmp -s "$MUT/$1" "$ROOT/$1"; then fail "the mutation of $1 changed nothing (the sed expression is stale): $2"; return 1; fi
}
watch() {   # watch DESCRIPTION FILE SED SCENARIO: the scenario passes with the real tool and FAILS with the mutant
  local d=$1 f=$2 e=$3 s=$4
  PINBIN=$REAL; if "$s" >/dev/null 2>&1; then :; else fail "the scenario for '$d' is red with the real tool"; return; fi
  mutant "$f" "$e" || return
  PINBIN=$MUT/bin/land-pin; if "$s" >/dev/null 2>&1; then fail "MUTANT SURVIVED: $d (the scenario is still green with the guard cut out)"; else pass "mutant caught: $d"; fi
  PINBIN=$REAL
}
rc_of() { local rc=0; "$@" >"$T/mout" 2>&1 || rc=$?; echo "$rc"; }
s_lib_behind() { lite "$(libline "$LW" v1.0.0)"; [ "$(rc_of pin outdated)" = 1 ] && grep -q 'v1.1.0' "$T/mout"; }
s_numeric() { lite "$(libline "$LV" v1.9.0)"; [ "$(rc_of pin outdated)" = 1 ] && lite "$(libline "$LV2" v1.10.0)" && [ "$(rc_of pin outdated)" = 0 ]; }
s_one_wins() { lite "$(libline "$LW" v1.0.0)"; sed -i "s|^source=.*|source=$NOWHERE|" "$C/$LAND_PIN"; [ "$(rc_of pin outdated)" = 1 ]; }
s_unreach() { lite; sed -i "s|^source=.*|source=$NOWHERE|" "$C/$LAND_PIN"; [ "$(rc_of pin outdated)" = 3 ] && grep -q unreachable "$T/mout"; }
s_rename() { sw_to files; lite "" "$C1"; [ "$(rc_of pin outdated)" = 1 ] && grep -q '  alpha: D x.md' "$T/mout" && grep -q '  alpha: A y.md' "$T/mout"; }
s_licence() { sw_to licmod; lite "" "$C1"; [ "$(rc_of pin outdated)" = 1 ] && grep -q 'licence: CHANGED' "$T/mout"; }
s_undec_report() { sw_to undec; lite "" "$C1"; [ "$(rc_of pin outdated)" = 1 ] && grep -q 'undecided: delta' "$T/mout"; }
s_dirty() { world; echo x > "$C/untracked.txt"; S=$(state); [ "$(rc_of pin update --all)" = 1 ] && [ "$(state)" = "$S" ]; }
s_undec_refused() { world; sw_to undec; S=$(state); [ "$(rc_of pin update --all)" = 1 ] && [ "$(state)" = "$S" ] && grep -q "has a new skill 'delta'" "$T/mout"; }
s_atomic() { world; sw_to twolic; S=$(state); [ "$(rc_of pin update --all)" = 1 ] && [ "$(state)" = "$S" ]; }
s_nocommit() { world; H=$(git -C "$C" rev-parse HEAD); [ "$(rc_of pin update --all)" = 0 ] && [ "$(git -C "$C" rev-parse HEAD)" = "$H" ] && [ -n "$(git -C "$C" status --porcelain)" ]; }
s_pending() { world; [ "$(rc_of pin update --all)" = 0 ] && [ "$(grep -c ' pending$' "$C/$LAND_SKILLS_LOCK")" = 2 ] && [ "$(rc_of pin verify)" = 1 ]; }
s_unreach_update() { world; sed -i "s|^source=.*|source=$NOWHERE|" "$C/$LAND_PIN"; git -C "$C" commit -qam pin; S=$(state); [ "$(rc_of pin update --all)" = 3 ] && [ "$(state)" = "$S" ]; }
s_only() { world; [ "$(rc_of pin update --all --only libx)" = 0 ] && grep -qx 'version=v1.0.0' "$C/$LAND_PIN"; }
watch "outdated that exits 0 whatever it finds" lib/outdated.sh 's/^  exit "\$rc"$/  exit 0/' s_lib_behind
watch "a string comparison of versions" lib/outdated.sh 's/^tag_gt() {$/tag_gt() { [[ $1 > $2 ]]; return/' s_numeric
watch "3 wins over 1" lib/outdated.sh 's/^od_exit() .*$/od_exit() { if [ "$OD_UNR" -gt 0 ]; then return 3; elif [ "$OD_BEHIND" -gt 0 ]; then return 1; fi; return 0; }/' s_one_wins
watch "an unreachable source reported as current" lib/outdated.sh 's/else rec status unreachable; fi$/else rec status current; fi/' s_unreach
watch "a listing that lets git detect renames" lib/outdated.sh 's/ --no-renames//' s_rename
watch "a licence change never flagged" lib/outdated.sh 's/|| lic=true$/|| lic=false/' s_licence
watch "undecided skills never reported" lib/outdated.sh 's/\[ "\$k" = 1 \] || \[ -n "\${NT\[\$n\]+x}" \] || cand+=("\$n")/true/' s_undec_report
watch "update --all on a dirty tree" lib/outdated.sh 's/if \[ -n "\$dirty" \]; then/if false; then/' s_dirty
watch "update --all with an undecided skill" lib/outdated.sh 's/for s in "\${a\[@\]}"; do refusals+=/for s in; do refusals+=/' s_undec_refused
watch "an update that does not roll back" lib/outdated.sh 's/^ua_rollback() {$/ua_rollback() { return 0/' s_atomic
watch "an update that commits" lib/outdated.sh 's/^  UA_ACTIVE=0$/  UA_ACTIVE=0; git -C "$root" add -A; git -C "$root" commit -qm x/' s_nocommit
watch "an update that records a review" lib/outdated.sh 's/^  UA_ACTIVE=0$/  UA_ACTIVE=0; sed -i "s| pending$| 2026-01-01:auto|" "$root\/$LAND_SKILLS_LOCK"/' s_pending
watch "an unreachable selected source that does not stop the update" lib/outdated.sh 's/^  if \[ \${#unreach\[@\]} -gt 0 \]; then/  if false; then/' s_unreach_update
watch "--only ignored" lib/outdated.sh 's/^od_sel() .*$/od_sel() { return 0; }/' s_only
rm -rf "$MUT"
finish
