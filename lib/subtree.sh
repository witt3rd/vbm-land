# lib/subtree.sh: `land-pin vendor NAME URL TAG --path PATH` and the subtree checks of `land-pin verify` and `land-pin outdated` (docs/family-repo.md section 4). Sourced by bin/land-pin, never run: it uses land-pin's
# readers and globals (read_lock and the L_* arrays, root, scratch, note, die, refuse) and verify.sh (tree_hash, export_commit, src_tag_signed): the signature and the tree hash are checked by the one verifier, only the
# SUBTREE is new. A library is a directory lib/NAME of one repository; its in-repo dependencies are named, one per line, in lib/NAME/deps, and are vendored FLAT beside it from the same commit.
ST_NAME_RE='^[a-z0-9][a-z0-9_-]*$'

# st_export REPO REV PATH DEST: the files of PATH at REV, the prefix removed, into the existing directory DEST. 1 when PATH is not a directory of REV.
st_export() {
  local strip
  [ "$(git -C "$1" cat-file -t "$2:$3" 2>/dev/null)" = tree ] || return 1
  strip=$(awk -F/ '{ print NF }' <<<"$3")
  git -C "$1" archive --format=tar "$2" "$3" | tar -x --strip-components="$strip" -C "$4"
}

# st_hash_at REPO REV PATH: the tree hash (docs/pin.md section 1) of exactly PATH at REV.
st_hash_at() {
  local d h
  d=$(mktemp -d "$scratch/h.XXXXXX")
  st_export "$1" "$2" "$3" "$d" || { rm -rf "$d"; echo "$3 is not a directory at $2" >&2; return 1; }
  h=$(tree_hash "$d") || { rm -rf "$d"; return 1; }
  rm -rf "$d"; printf '%s\n' "$h"
}

# st_deps_at REPO REV NAME: the direct dependencies in lib/NAME/deps at REV, one per line. 3 when there is no such file (a legacy release), 1 when it is malformed:
# names only, sorted bytewise, no duplicate, no blank line, a final newline.
st_deps_at() {
  local f="$2:lib/$3/deps" t bad=0
  git -C "$1" cat-file -e "$f" 2>/dev/null || return 3
  t=$(mktemp "$scratch/d.XXXXXX"); git -C "$1" show "$f" > "$t"
  if [ -s "$t" ]; then
    [ -z "$(tail -c1 "$t")" ] || bad=1
    LC_ALL=C sort -cu "$t" 2>/dev/null || bad=1
    ! grep -qvE "$ST_NAME_RE" "$t" || bad=1
  fi
  [ "$bad" = 0 ] || { rm -f "$t"; echo "REFUSED: lib/$3/deps at $2 is malformed (names only, sorted, no duplicate, no blank line, a final newline)" >&2; return 1; }
  cat "$t"; rm -f "$t"
}

# st_closure_at REPO REV NAME: the transitive in-repo dependencies of NAME at REV (not NAME itself), sorted, one per line. A root with no deps file has an empty closure (a legacy release);
# a member with none, or a dependency on NAME itself, is refused.
st_closure_at() {
  local repo=$1 rev=$2 top=$3 n d rc deps seen=" "
  local -a queue=("$3")
  while [ ${#queue[@]} -gt 0 ]; do
    n=${queue[0]}; queue=("${queue[@]:1}"); rc=0; deps=$(st_deps_at "$repo" "$rev" "$n") || rc=$?
    if [ "$rc" = 3 ]; then [ "$n" = "$top" ] || { echo "REFUSED: lib/$n has no deps file at $rev" >&2; return 1; }; continue; fi
    [ "$rc" = 0 ] || return 1
    for d in $deps; do
      [ "$d" != "$top" ] || { echo "REFUSED: $top is in its own closure (a cycle through lib/$n/deps)" >&2; return 1; }
      case $seen in *" $d "*) ;; *) seen+="$d "; queue+=("$d");; esac
    done
  done
  for d in $seen; do echo "$d"; done | LC_ALL=C sort
}

# st_vclosure NAME: the closure of NAME from the VENDORED deps files (offline), sorted. A name that is not a name is ignored: verify judges the files.
st_vclosure() {
  local n d seen=" " f
  local -a queue=("$1")
  while [ ${#queue[@]} -gt 0 ]; do
    n=${queue[0]}; queue=("${queue[@]:1}"); f=$root/$LAND_VENDOR_DIR/$n/deps
    [ -f "$f" ] || continue
    while IFS= read -r d || [ -n "$d" ]; do
      [[ $d =~ $ST_NAME_RE ]] || continue
      case $seen in *" $d "*) ;; *) seen+="$d "; queue+=("$d");; esac
    done < "$f"
  done
  for d in $seen; do [ "$d" = "$1" ] || echo "$d"; done | LC_ALL=C sort
}

st_at() { local i; for ((i = 0; i < ${#L_NAME[@]}; i++)); do [ "${L_NAME[$i]}" != "$1" ] || { echo "$i"; return 0; }; done; return 1; }   # the index of a locked name
st_roots() { local i; for ((i = 0; i < ${#L_NAME[@]}; i++)); do if [ -n "${L_PATH[$i]}" ] && [ "${L_ROLE[$i]}" = root ]; then echo "${L_NAME[$i]}"; fi; done | LC_ALL=C sort; }   # the names of the subtree roots (a line with a PATH and the role root)
st_holds() { local r; for r in $(st_vclosure "$1"); do [ "$r" != "$2" ] || return 0; done; return 1; }   # st_holds ROOT NAME: ROOT's vendored closure holds NAME

st_lock_apply() {   # st_lock_apply ROWSFILE: a row replaces the line of its name (or is appended); "-NAME" deletes it; comments and other lines stay
  local f=$root/$LAND_PINS_FILE
  awk -v rows="$1" 'BEGIN { while ((getline l < rows) > 0) { if (substr(l, 1, 1) == "-") rm[substr(l, 2)] = 1; else { split(l, a, " "); nw[a[1]] = l; ord[++c] = a[1] } } close(rows) }
    { t = $0; sub(/#.*/, "", t); split(t, f, " "); if (f[1] in rm) next; if (f[1] in nw) { if (!(f[1] in dn)) print nw[f[1]]; dn[f[1]] = 1; next } print }
    END { for (i = 1; i <= c; i++) if (!(ord[i] in dn)) print nw[ord[i]] }' "$f" > "$f.new" && mv "$f.new" "$f"
}

vendor_subtree() {   # vendor_subtree NAME URL TAG PATH
  local name=$1 url=$2 tag=$3 path=$4 signers=$root/$LAND_SIGNERS_FILE vend=$root/$LAND_VENDOR_DIR r x rev want msg ndep members m h i j rt holder rows
  [[ $name =~ $ST_NAME_RE ]] || die "bad name '$name'"
  [ "$path" = "lib/$name" ] || die "the path of $name must be lib/$name, got '$path'"
  [[ $tag =~ ^$name/v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the tag must be $name/vX.Y.Z, got '$tag'"
  [[ $url =~ ^[^[:space:]]+$ ]] || die "bad url"
  case $url in git@*|ssh://*) echo "land-pin: warning: $url is an ssh address: a lock is shared data, so use the public https URL" >&2;; esac
  read_lock
  scratch=$(mktemp -d); r=$scratch/r; x=$scratch/x; mkdir "$x"; git init -q "$r"
  git -C "$r" fetch -q --depth 1 "$url" "refs/tags/$tag:refs/tags/$tag" 2>/dev/null || refuse "cannot fetch the tag $tag from $url"
  src_tag_signed "$r" "$tag" "$signers" || exit 1
  rev=$(git -C "$r" rev-parse "refs/tags/$tag^{commit}")
  msg=$(git -C "$r" tag -l --format='%(contents)' "$tag")
  want=$(sed -n -E 's/^tree_sha256=([0-9a-f]{64})$/\1/p' <<<"$msg")
  [ "$(printf '%s\n' "$want" | grep -c .)" = 1 ] || refuse "the message of $tag does not record exactly one tree_sha256="
  mkdir "$x/$name"; st_export "$r" "$rev" "$path" "$x/$name" || refuse "$tag has no directory $path"
  h=$(tree_hash "$x/$name" 2>&1) || refuse "the exported subtree $path of $tag cannot be hashed: $h"
  [ "$h" = "$want" ] || refuse "tag $tag records tree_sha256=$want, but its exported subtree $path hashes to $h"
  members=$(st_closure_at "$r" "$rev" "$name") || exit 1
  ndep=$(grep -c '^dep_tree_sha256=' <<<"$msg" || true)
  rows=$(sed -n -E 's/^dep_tree_sha256=([a-z0-9][a-z0-9_-]*):([0-9a-f]{64})$/\1 \2/p' <<<"$msg")
  [ "$ndep" = "$(printf '%s\n' "$rows" | grep -c . || true)" ] || refuse "the message of $tag has a malformed dep_tree_sha256= line"
  [ "$(printf '%s\n' "$rows" | cut -d' ' -f1 | LC_ALL=C sort)" = "$members" ] || refuse "the dep_tree_sha256= lines of $tag are not exactly one for each member of the closure of $name at $rev (the deps files say: $(echo $members))"
  for m in $members; do
    mkdir "$x/$m"; st_export "$r" "$rev" "lib/$m" "$x/$m" || refuse "$tag has no directory lib/$m"
    h=$(tree_hash "$x/$m" 2>&1) || refuse "the exported subtree lib/$m of $tag cannot be hashed: $h"
    [ "$h" = "$(awk -v n="$m" '$1 == n { print $2 }' <<<"$rows")" ] || refuse "tag $tag records another tree hash for $m than its exported subtree lib/$m ($h)"
  done
  for m in $name $members; do   # one version of each library: another root that holds it, or is it, with another hash, refuses (a diamond)
    h=$(tree_hash "$x/$m"); i=$(st_at "$m") || continue
    [ "${L_HASH[$i]}" != "$h" ] || continue
    holder=; for rt in $(st_roots); do [ "$rt" != "$name" ] || continue; case " ${LAND_PIN_MOVING:-} " in *" $rt "*) continue;; esac; if [ "$rt" = "$m" ] || st_holds "$rt" "$m"; then holder+=" $rt"; fi; done
    [ -z "$holder" ] || refuse "a diamond: $name at $tag brings $m with another tree hash than the one vendored for${holder} (one version of each library: take a tag of one of them whose $m matches)"
  done
  mkdir -p "$vend" "$(dirname "$root/$LAND_PINS_FILE")"; touch "$root/$LAND_PINS_FILE"; rows=$scratch/rows; : > "$rows"
  for m in $name $members; do
    h=$(tree_hash "$x/$m"); i=$(st_at "$m" || true)
    if [ "$m" != "$name" ] && [ -n "$i" ] && [ "${L_HASH[$i]}" = "$h" ] && [ -d "$vend/$m" ]; then continue; fi   # equal: the line and the copy stay
    rm -rf "${vend:?}/$m"; mv "$x/$m" "$vend/$m"
    if [ "$m" = "$name" ]; then echo "$m $url $tag $rev $path $h root" >> "$rows"; else echo "$m $url $tag $rev lib/$m $h dep" >> "$rows"; fi
  done
  st_lock_apply "$rows"; st_relock
  echo "land-pin: vendored $name $tag ($rev) into $LAND_VENDOR_DIR/$name with its closure:$(printf ' %s' $members)"
  verify
}

# st_relock: the dep lines are derived data (family-repo.md 4, rule 5): each carries the url, TAG and COMMIT of the first root, by name, whose closure holds it; one no root holds is removed with its copy.
st_relock() {
  local i j rt rows d
  read_lock; rows=$(mktemp "$scratch/rows.XXXXXX"); local -a stale=()
  for ((i = 0; i < ${#L_NAME[@]}; i++)); do
    [ "${L_ROLE[$i]}" = dep ] || continue
    d=${L_NAME[$i]}; j=
    for rt in $(st_roots); do st_holds "$rt" "$d" || continue; j=$(st_at "$rt"); break; done
    if [ -z "$j" ]; then echo "-$d" >> "$rows"; stale+=("$d"); continue; fi
    echo "$d ${L_URL[$j]} ${L_TAG[$j]} ${L_REV[$j]} ${L_PATH[$i]} ${L_HASH[$i]} dep" >> "$rows"
  done
  st_lock_apply "$rows"
  for d in ${stale[@]+"${stale[@]}"}; do rm -rf "${root:?}/$LAND_VENDOR_DIR/$d"; done
}

# st_verify: rules 4 and 5 of family-repo.md section 4, offline, on the vendored deps files (rule 1 to 3 are verify's own: the tree hash, the unlocked directory, the nested copy).
st_verify() {
  local i j n d rt first
  local -A LISTED=()
  for ((i = 0; i < ${#L_NAME[@]}; i++)); do
    [ -n "${L_PATH[$i]}" ] || continue; n=${L_NAME[$i]}
    [ -f "$root/$LAND_VENDOR_DIR/$n/deps" ] || continue
    while IFS= read -r d || [ -n "$d" ]; do
      [ -n "$d" ] || continue; LISTED[$d]=1
      { j=$(st_at "$d") && [ -d "$root/$LAND_VENDOR_DIR/$d" ]; } || note "$n: its deps file names $d, which is not a locked, vendored library (the closure is incomplete)"
    done < "$root/$LAND_VENDOR_DIR/$n/deps"
  done
  for ((i = 0; i < ${#L_NAME[@]}; i++)); do
    [ "${L_ROLE[$i]}" = dep ] || continue; n=${L_NAME[$i]}
    [ -n "${LISTED[$n]+x}" ] || note "$n: a dep line that no vendored library's deps file names (a stale dependency)"
    first=; for rt in $(st_roots); do if st_holds "$rt" "$n"; then first=$rt; break; fi; done
    if [ -z "$first" ]; then note "$n: a dep line that no root's closure holds"; continue; fi
    j=$(st_at "$first")
    [ "${L_TAG[$i]}" = "${L_TAG[$j]}" ] && [ "${L_REV[$i]}" = "${L_REV[$j]}" ] || note "$n: its TAG and COMMIT are not those of its first root, $first (${L_TAG[$j]} ${L_REV[$j]:0:12})"
  done
}

# st_closure_changed NAME URL OLDTAG OLDREV NEWTAG: the names, sorted, of NAME and of the members of its closure at either commit whose subtree hash differs between OLDREV and NEWTAG's commit (absent on one side is a difference).
st_closure_changed() {
  local name=$1 url=$2 oldtag=$3 oldrev=$4 newtag=$5 g n new
  g=$(mktemp -d "$scratch/cc.XXXXXX"); git init -q --bare "$g"
  git -C "$g" fetch -q --no-tags "$url" "+refs/tags/$newtag:refs/tags/$newtag" "+refs/tags/$oldtag:refs/tags/$oldtag" 2>/dev/null || git -C "$g" fetch -q --no-tags "$url" "+refs/tags/$newtag:refs/tags/$newtag" 2>/dev/null || return 1
  git -C "$g" cat-file -e "$oldrev^{commit}" 2>/dev/null || git -C "$g" fetch -q --no-tags "$url" "$oldrev" 2>/dev/null || return 1
  new=$(git -C "$g" rev-parse "refs/tags/$newtag^{commit}")
  for n in $({ echo "$name"; st_closure_at "$g" "$oldrev" "$name"; st_closure_at "$g" "$new" "$name"; } | LC_ALL=C sort -u); do
    [ "$(st_hash_at "$g" "$oldrev" "lib/$n" 2>/dev/null || echo absent)" = "$(st_hash_at "$g" "$new" "lib/$n" 2>/dev/null || echo absent)" ] || echo "$n"
  done
}
