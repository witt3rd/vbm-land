# lib/outdated.sh: `land-pin outdated` and `land-pin update --all` (docs/pin.md section 9). Sourced by bin/land-pin, never run: it uses land-pin's own readers (read_lock, read_skills_lock, src_slug,
# src_field, src_bullets, die) and adds no way to change the tree: `update --all` runs `land-pin vendor`, `land-pin skill update` and `land-update`, each as the command it is.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/source.sh"   # src_fetch: the tool's own source is reached the way land-check --upstream reaches it

RE_TAG='^v[0-9]+\.[0-9]+\.[0-9]+$'      # a library or tool release tag: the form the lock accepts; any other tag is not a version
RE_REL='^v?[0-9]+\.[0-9]+\.[0-9]+$'     # a release tag of a skill source (information only)
OD=; OD_N=0; DRY=0; REC=; SEL_ON=0; declare -A SEL=() SELU=()

# tag_gt A B: A is a newer version than B, by their three NUMBERS (v1.10.0 is newer than v1.9.0; never a string comparison).
tag_gt() {
  local -a a b; local i x y
  IFS=. read -ra a <<<"${1#v}"; IFS=. read -ra b <<<"${2#v}"
  for i in 0 1 2; do x=$((10#${a[$i]})); y=$((10#${b[$i]})); [ "$x" -eq "$y" ] || { [ "$x" -gt "$y" ]; return; }; done
  return 1
}
# newest_of RE: read tag names, print the newest (by number) of those matching RE, nothing when none. The ONE place that names the newest tag.
newest_of() {
  local t best=
  while IFS= read -r t; do [[ $t =~ $1 ]] || continue; if [ -z "$best" ] || tag_gt "$t" "$best"; then best=$t; fi; done
  printf '%s' "$best"
}

js() {   # js STRING: a JSON string (the escapes JSON requires; a newline, a quote and a backslash survive)
  local s=$1 i c out=
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
  if [[ $s == *[[:cntrl:]]* ]]; then
    for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; if [[ $c == [[:cntrl:]] ]]; then printf -v c '\\u%04x' "'$c"; fi; out+=$c; done; s=$out
  fi
  printf '"%s"' "$s"
}
jn() { if [ -n "$1" ]; then js "$1"; else printf null; fi; }

pin_read() {   # the PIN of the tool: source, version, 40-hex commit, 64-hex manifest hash (exit 2 when malformed)
  P_SRC=; P_VER=; P_COMMIT=; P_MAN=; local line
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      source=*) [ -n "$P_SRC" ] || P_SRC=${line#source=};;
      version=*) [ -n "$P_VER" ] || P_VER=${line#version=};;
      commit=*) [ -n "$P_COMMIT" ] || P_COMMIT=${line#commit=};;
      manifest_sha256=*) [ -n "$P_MAN" ] || P_MAN=${line#manifest_sha256=};;
    esac
  done < "$root/$LAND_PIN"
  [[ -n $P_SRC && $P_SRC != *[[:space:]]* ]] || die "$LAND_PIN: source= is missing or has a space"
  [[ $P_VER =~ $RE_TAG ]] || die "$LAND_PIN: version= must be vX.Y.Z, got '$P_VER'"
  [[ $P_COMMIT =~ ^[0-9a-f]{40}$ ]] || die "$LAND_PIN: commit= must be 40 hex digits"
  [[ $P_MAN =~ ^[0-9a-f]{64}$ ]] || die "$LAND_PIN: manifest_sha256= must be 64 hex digits"
}

od_ctx() {   # everything misuse is: not a work tree, no PIN, a malformed PIN or lock (exit 2)
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git work tree ($root)"
  [ -f "$root/$LAND_PIN" ] || die "no $LAND_PIN: the tool is not installed here"
  pin_read; read_lock; read_skills_lock
}

# ---- the report: one record directory per pin under $OD/p/, the one source of truth that both renderings read ----
rec_new() {   # rec_new KIND NAME SOURCE PINNED: sets REC
  local k; OD_N=$((OD_N + 1)); REC=$OD/p/$(printf '%04d' "$OD_N"); mkdir -p "$REC"
  for k in newer status note lic missing relt relr srcrec licname cc ccon path; do : > "$REC/$k"; done
  : > "$REC/files"; : > "$REC/undecided"
  printf '%s' "$1" > "$REC/kind"; printf '%s' "$2" > "$REC/name"; printf '%s' "$3" > "$REC/source"; printf '%s' "$4" > "$REC/pinned"
}
rec() { printf '%s' "$2" > "$REC/$1"; }   # rec KEY VALUE
od_sel() { [ "$SEL_ON" = 0 ] || [ -n "${SEL[$1]+x}" ]; }
od_selu() { [ "$SEL_ON" = 0 ] || [ -n "${SELU[$1]+x}" ]; }

rb_library() {   # a whole-repository line compares vX.Y.Z tags; a subtree line (a PATH) compares the tags of ITS library, NAME/vX.Y.Z, only, and reports closure_changed (docs/family-repo.md section 4); a dep line is its root's, never alone
  local name=${L_NAME[$1]} url=${L_URL[$1]} tag=${L_TAG[$1]} out new pre= cc
  od_sel "$name" || return 0
  [ "${L_ROLE[$1]}" != dep ] || return 0
  [ -z "${L_PATH[$1]}" ] || pre=$name/
  rec_new library "$name" "$url" "$tag"
  if out=$(timeout 120 git ls-remote --tags --refs "$url" 2>"$REC/note"); then
    if [ -n "$pre" ]; then new=$(awk -F'\t' -v p="$pre" '{ sub("^refs/tags/", "", $2); if (index($2, p) == 1) print substr($2, length(p) + 1) }' <<<"$out" | newest_of "$RE_TAG"); [ -z "$new" ] || new=$pre$new
    else new=$(awk -F'\t' '{ sub("^refs/tags/", "", $2); print $2 }' <<<"$out" | newest_of "$RE_TAG"); fi
    if [ -n "$new" ] && tag_gt "${new#"$pre"}" "${tag#"$pre"}"; then
      rec newer "$new"; rec status behind
      if [ -n "$pre" ]; then
        if cc=$(st_closure_changed "$name" "$url" "$tag" "${L_REV[$1]}" "$new" 2>"$REC/note"); then rec ccon 1; printf '%s\n' "$cc" | awk 'NF' | tr '\n' '\0' > "$REC/cc"
        else rec status unreachable; rec newer ""; fi
      fi
    else rec status current; fi
    [ -z "$pre" ] || rec path "${L_PATH[$1]}"
  else rec status unreachable; fi
}

rb_tool() {
  local new
  od_sel vbm-land || return 0
  rec_new tool vbm-land "$P_SRC" "$P_VER"
  if src_fetch "$P_SRC" HEAD "$OD/tool.git" >/dev/null 2>"$REC/note"; then
    new=$(git -C "$OD/tool.git" tag --list | newest_of "$RE_TAG")
    if [ -n "$new" ] && tag_gt "$new" "$P_VER"; then rec newer "$new"; rec status behind; else rec status current; fi
  else rec status unreachable; fi
}

lic_sig() { git -C "$1" ls-tree "$2" -- LICENSE LICENSE.md LICENSE.txt COPYING; }   # the licence file(s) of a commit, as git lists them: name and blob

rb_source() {   # rb_source URL: the skill source and, under it, one record per locked skill
  local url=$1 i first=-1 pinned slug sm sroot pre tip= out sha ref t j k fr srec status=current newer= lic=false licname= rel= relrev= p s pfx st
  local -a names=() arr=() DS=() DP=() cand=() undec=()
  local -A TAGO=() TAGP=() NT=() ; local n x
  od_selu "$url" || return 0
  for ((i = 0; i < ${#S_URL[@]}; i++)); do [ "${S_URL[$i]}" != "$url" ] || { [ "$first" -ge 0 ] || first=$i; names+=("${S_NAME[$i]}"); }; done
  pinned=${S_COMMIT[$first]}; slug=$(src_slug "$url"); sm=$root/$LAND_SKILLS_THIRD_PARTY/$slug/SOURCE.md
  sroot=; [ ! -f "$sm" ] || sroot=$(src_field "$sm" root); [ -n "$sroot" ] || sroot=skills
  pre=$sroot/; [ "$sroot" != . ] || pre=
  rec_new skill-source "$slug" "$url" "$pinned"; srec=$REC
  if ! out=$(timeout 120 git ls-remote "$url" 2>"$srec/note"); then status=unreachable
  else
    while IFS=$'\t' read -r sha ref; do
      case $ref in
        HEAD) tip=$sha;;
        refs/tags/*) t=${ref#refs/tags/}
          if [[ ${t%'^{}'} =~ $RE_REL ]]; then if [[ $t == *'^{}' ]]; then TAGP[${t%'^{}'}]=$sha; else TAGO[$t]=$sha; fi; fi;;
      esac
    done <<<"$out"
    [ -n "$tip" ] || { status=unreachable; echo "$url has no HEAD" > "$srec/note"; }
  fi
  if [ "${#TAGO[@]}" -gt 0 ]; then
    rel=$(printf '%s\n' "${!TAGO[@]}" | LC_ALL=C sort | newest_of "$RE_REL"); relrev=${TAGP[$rel]:-${TAGO[$rel]}}
  fi
  if [ "$status" != unreachable ] && [ "$tip" != "$pinned" ]; then
    fr=$OD/f$OD_N; git init -q --bare "$fr"
    if git -C "$fr" fetch -q --no-tags --depth 1 "$url" "$tip" "$pinned" 2>"$srec/note" ||
       { git -C "$fr" fetch -q --no-tags "$url" '+refs/heads/*:refs/remotes/src/*' '+refs/tags/*:refs/tags/*' 2>"$srec/note" &&
         git -C "$fr" cat-file -e "$pinned^{commit}" 2>>"$srec/note" && git -C "$fr" cat-file -e "$tip^{commit}" 2>>"$srec/note"; }; then
      status=behind; newer=$tip
      mapfile -d '' -t arr < <(git -C "$fr" diff --name-status --no-renames -z "$pinned" "$tip")
      for ((j = 0; j + 1 < ${#arr[@]}; j += 2)); do st=${arr[$j]}; case $st in A|D|M) ;; *) st=M;; esac; DS+=("$st"); DP+=("${arr[$((j + 1))]}"); done
      [ "$(lic_sig "$fr" "$pinned")" = "$(lic_sig "$fr" "$tip")" ] || lic=true
      licname=$(git -C "$fr" ls-tree --name-only "$tip" -- LICENSE LICENSE.md LICENSE.txt COPYING | paste -sd' ' -)
      if [ -f "$sm" ]; then while IFS=$'\t' read -r n x; do NT[$n]=1; done < <(src_bullets "$sm" "Not taken"); fi
      if [ -n "$pre" ]; then mapfile -d '' -t arr < <(git -C "$fr" ls-tree -d -z --name-only "$tip" -- "$pre"); else mapfile -d '' -t arr < <(git -C "$fr" ls-tree -d -z --name-only "$tip"); fi
      for p in "${arr[@]}"; do
        n=${p#"$pre"}; git -C "$fr" cat-file -e "$tip:$p/SKILL.md" 2>/dev/null || continue
        k=0; for x in "${S_NAME[@]}"; do [ "$x" != "$n" ] || k=1; done
        [ "$k" = 1 ] || [ -n "${NT[$n]+x}" ] || cand+=("$n")
      done
      if [ ${#cand[@]} -gt 0 ]; then mapfile -d '' -t undec < <(printf '%s\0' "${cand[@]}" | LC_ALL=C sort -z); fi
    else status=unreachable; fi
  fi
  [ "$status" != unreachable ] || lic=
  REC=$srec; rec status "$status"; rec newer "$newer"; rec lic "$lic"; rec licname "$licname"; rec relt "$rel"; rec relr "$relrev"
  if [ ${#undec[@]} -gt 0 ]; then printf '%s\0' "${undec[@]}" > "$srec/undecided"; fi
  for s in "${names[@]}"; do
    rec_new skill "$s" "$url" "$pinned"; rec status "$status"; rec newer "$newer"; rec srcrec "$(basename "$srec")"; rec missing false; cp "$srec/note" "$REC/note"
    if [ "$status" = behind ]; then
      pfx=$pre$s/
      [ "$(git -C "$fr" cat-file -t "$tip:$pre$s" 2>/dev/null || true)" = tree ] || rec missing true
      for ((j = 0; j < ${#DP[@]}; j++)); do
        if [[ ${DP[$j]} == "$pfx"* ]]; then printf '%s\0%s\0' "${DS[$j]}" "${DP[$j]#"$pfx"}" >> "$REC/files"; fi
      done
    fi
  done
  return 0
}

report_build() {   # fills $OD/p/ for the pins selected (all, unless SEL_ON); read-only: it works in its own scratch directory
  local i u
  OD=$(mktemp -d); scratch=$OD; mkdir "$OD/p"; OD_N=0
  for ((i = 0; i < ${#L_NAME[@]}; i++)); do rb_library "$i"; done
  for ((i = 0; i < ${#S_URL[@]}; i++)); do
    for u in "${S_URL[@]:0:i}"; do [ "$u" != "${S_URL[$i]}" ] || continue 2; done   # a source once
    rb_source "${S_URL[$i]}"
  done
  rb_tool
  OD_BEHIND=0; OD_UNR=0; OD_PINS=0
  for REC in "$OD"/p/*/; do REC=${REC%/}; OD_PINS=$((OD_PINS + 1))
    case $(<"$REC/status") in behind) OD_BEHIND=$((OD_BEHIND + 1));; unreachable) OD_UNR=$((OD_UNR + 1));; esac
  done
}

od_exit() { if [ "$OD_BEHIND" -gt 0 ]; then return 1; elif [ "$OD_UNR" -gt 0 ]; then return 3; fi; return 0; }   # 1 wins over 3

od_obj() {   # one JSON object for the record dir $1
  local d=$1 k a j lic undec rel
  printf '{"kind":%s,"name":%s,"source":%s,"pinned":%s,"newer":%s,"status":%s,"files":[' "$(js "$(<"$d/kind")")" "$(js "$(<"$d/name")")" "$(js "$(<"$d/source")")" "$(js "$(<"$d/pinned")")" "$(jn "$(<"$d/newer")")" "$(js "$(<"$d/status")")"
  mapfile -d '' -t a < "$d/files"
  for ((j = 0; j + 1 < ${#a[@]}; j += 2)); do [ "$j" = 0 ] || printf ,; printf '{"status":%s,"path":%s}' "$(js "${a[$j]}")" "$(js "${a[$((j + 1))]}")"; done
  printf '],"license_changed":%s,"undecided":' "$(if [ -n "$(<"$d/lic")" ]; then cat "$d/lic"; else printf null; fi)"
  if [ "$(<"$d/kind")" = skill-source ]; then
    mapfile -d '' -t a < "$d/undecided"; printf '['; for ((j = 0; j < ${#a[@]}; j++)); do [ "$j" = 0 ] || printf ,; js "${a[$j]}"; done; printf ']'
  else printf null; fi
  printf ',"release":'
  if [ -n "$(<"$d/relt")" ]; then printf '{"tag":%s,"rev":%s}' "$(js "$(<"$d/relt")")" "$(js "$(<"$d/relr")")"; else printf null; fi
  printf ',"missing_at_tip":%s' "$(if [ -n "$(<"$d/missing")" ]; then cat "$d/missing"; else printf null; fi)"
  printf ',"closure_changed":'   # a library with a PATH that is behind: the sorted names whose subtree hash differs between the pinned commit and the newer tag's; null otherwise
  if [ -n "$(<"$d/ccon")" ]; then mapfile -d '' -t a < "$d/cc"; printf '['; for ((j = 0; j < ${#a[@]}; j++)); do [ "$j" = 0 ] || printf ,; js "${a[$j]}"; done; printf ']'; else printf null; fi
  if [ "$DRY" = 1 ]; then   # update --dry-run: `would` is null when the pin stays, else what the update does to it
    if [ "$(<"$d/status")" = behind ]; then printf ',"would":{"from":%s,"to":%s,"pending_review":%s}' "$(js "$(<"$d/pinned")")" "$(js "$(<"$d/newer")")" "$([ "$(<"$d/kind")" = skill ] && echo true || echo false)"; else printf ',"would":null'; fi
  fi
  printf '}'
}

od_json() {
  local d first=1
  printf '{"v":1,"behind":%d,"unreachable":%d,"pins":[' "$OD_BEHIND" "$OD_UNR"
  for d in "$OD"/p/*/; do d=${d%/}; [ "$first" = 1 ] || printf ,; first=0; od_obj "$d"; done
  printf ']}\n'
}

od_path() { case $1 in *[[:cntrl:]]*) printf '%s' "${1@Q}";; *) printf '%s' "$1";; esac; }
od_human() {
  local d s kind name pin new st a j sk label suffix ln
  for d in "$OD"/p/*/; do d=${d%/}; kind=$(<"$d/kind"); name=$(<"$d/name"); pin=$(<"$d/pinned"); new=$(<"$d/newer"); st=$(<"$d/status")
    [ "$st" != current ] || continue
    case $kind in
      skill) continue;;
      skill-source) label="skill source $name"; pin=${pin:0:12}; new=${new:0:12}; suffix=" (tip)";;
      *) label="$kind $name"; suffix=; [ "$kind" != library ] || suffix=" (the signature is not verified here)";;
    esac
    if [ "$st" = unreachable ]; then echo "land-pin: $label $pin unreachable ($(sed -n 1p "$d/note"))"; continue; fi
    echo "land-pin: $label $pin -> $new$suffix"
    [ "$kind" = skill-source ] || continue
    for s in "$OD"/p/*/; do s=${s%/}; [ "$(<"$s/srcrec")" = "$(basename "$d")" ] || continue; sk=$(<"$s/name")
      [ "$(<"$s/missing")" != true ] || echo "  $sk: missing_at_tip"
      mapfile -d '' -t a < "$s/files"
      if [ ${#a[@]} = 0 ]; then echo "  $sk: no file differs"; fi
      for ((j = 0; j + 1 < ${#a[@]}; j += 2)); do echo "  $sk: ${a[$j]} $(od_path "${a[$((j + 1))]}")"; done
    done
    [ "$(<"$d/lic")" != true ] || { ln=$(<"$d/licname"); echo "  licence: CHANGED (${ln:-none at the tip})"; }
    mapfile -d '' -t a < "$d/undecided"
    for ((j = 0; j < ${#a[@]}; j++)); do echo "  undecided: $(od_path "${a[$j]}") (neither locked nor skipped: decide before an update)"; done
    [ -z "$(<"$d/relt")" ] || echo "  release: $(<"$d/relt") (information; the pin stays a commit)"
  done
  echo "land-pin: outdated: $OD_BEHIND behind, $OD_UNR unreachable, $OD_PINS pins"
}

outdated_cmd() {
  local json=0
  while [ $# -gt 0 ]; do case $1 in --json) json=1;; *) die "usage: land-pin outdated [--json]";; esac; shift; done
  od_ctx; SEL_ON=0; report_build
  if [ "$json" = 1 ]; then od_json; else od_human; fi
  local rc=0; od_exit || rc=$?
  exit "$rc"
}

# ---- update --all: one change in the working tree, never a commit; atomic; composed from vendor, skill update and land-update ----
UA_SNAP=; UA_ACTIVE=0; UA_AGENTS=0; UA_PATHS=(vendor "$LAND_HOME" "$LAND_SKILLS_DIR")
ua_snapshot() {   # the snapshot is taken by the tool itself: never a git stash, reset or checkout (those are the repository's)
  local i=0 d; UA_SNAP=$OD/snap; mkdir "$UA_SNAP"
  [ ! -e "$root/.agents" ] || UA_AGENTS=1
  for d in "${UA_PATHS[@]}"; do
    if [ -e "$root/$d" ] || [ -L "$root/$d" ]; then cp -a --reflink=auto "$root/$d" "$UA_SNAP/$i" || { echo "land-pin: cannot snapshot $d: nothing was changed" >&2; exit 1; }; fi
    i=$((i + 1))
  done
  UA_ACTIVE=1
}
ua_rollback() {
  [ "$UA_ACTIVE" = 1 ] || return 0
  UA_ACTIVE=0; local i=0 d
  for d in "${UA_PATHS[@]}"; do
    rm -rf "${root:?}/$d"
    if [ -e "$UA_SNAP/$i" ] || [ -L "$UA_SNAP/$i" ]; then mkdir -p "$(dirname "$root/$d")"; mv "$UA_SNAP/$i" "$root/$d"; fi
    i=$((i + 1))
  done
  [ "$UA_AGENTS" = 1 ] || rmdir "$root/.agents" 2>/dev/null || true
}
ua_exit() { ua_rollback || echo "land-pin: ROLLBACK FAILED: the tree may be half updated: look at git status" >&2; [ -z "$scratch" ] || rm -rf "$scratch"; }
ua_fail() {   # ua_fail KIND PIN: put every kind already applied back, name what failed, exit 1
  ua_rollback; echo "land-pin: update --all: FAILED $1 $2: nothing is left of this run (the tree is as it was)" >&2; exit 1
}
ua_state() { printf '%s' "$1" | sed -n 1p; }

update_all_cmd() {
  local sawonly=0 mode= dry=0 n i j k found d dirty
  local -a a=() only=()
  while [ $# -gt 0 ]; do
    case $1 in
      --all) mode=;;
      --dry-run) dry=1; mode=;;
      --only) sawonly=1; mode=only;;
      -*) die "usage: land-pin update [--all] [--only NAME...] [--dry-run]";;
      *) [ "$mode" = only ] || die "usage: land-pin update [--all] [--only NAME...] [--dry-run]"; only+=("$1");;
    esac; shift
  done
  { [ "$sawonly" = 0 ] || [ ${#only[@]} -gt 0 ]; } || die "--only needs at least one NAME"
  od_ctx
  if [ "$sawonly" = 1 ]; then
    SEL_ON=1
    for n in "${only[@]}"; do
      found=0
      for ((i = 0; i < ${#L_NAME[@]}; i++)); do [ "${L_NAME[$i]}" != "$n" ] || { SEL[$n]=1; found=1; }; done
      for ((i = 0; i < ${#S_NAME[@]}; i++)); do [ "${S_NAME[$i]}" != "$n" ] || { SELU[${S_URL[$i]}]=1; found=1; }; done
      [ "$n" != vbm-land ] || { SEL[$n]=1; found=1; }
      [ "$found" = 1 ] || die "'$n' is no pin here (a library name, a skill name or vbm-land)"
    done
  fi
  dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$root" status --porcelain)
  if [ "$dry" = 0 ] && [ -n "$dirty" ]; then echo "land-pin: REFUSED: the working tree is not clean (the whole change must be the update, to be reviewed as one):" >&2; printf '%s\n' "$dirty" | sed 's/^/  /' >&2; exit 1; fi
  report_build
  trap 'ua_exit' EXIT; trap 'exit 1' INT TERM
  # what the report named as behind, and what refuses the run before anything is written
  local -a ul_path=() ul_name=() ul_url=() ul_old=() ul_new=() us_url=() us_slug=() us_tip=() us_old=() us_lic=() us_licname=() refusals=() unreach=()
  local kind name st url pin new tool_new= tool_old= sk s
  local -A SKREC=()
  for d in "$OD"/p/*/; do d=${d%/}; kind=$(<"$d/kind"); name=$(<"$d/name"); st=$(<"$d/status"); url=$(<"$d/source"); pin=$(<"$d/pinned"); new=$(<"$d/newer")
    [ "$st" != unreachable ] || unreach+=("$kind $name ($url): $(sed -n 1p "$d/note")")
    [ "$st" = behind ] || continue
    case $kind in
      library) ul_name+=("$name"); ul_url+=("$url"); ul_old+=("$pin"); ul_new+=("$new"); ul_path+=("$(<"$d/path")");;
      tool) tool_new=$new; tool_old=$pin;;
      skill) SKREC[$name]=$d
        [ "$(<"$d/missing")" != true ] || refusals+=("skill $name is locked and has no directory at the tip $new of $url (an update needs each skill at the new commit)");;
      skill-source) us_url+=("$url"); us_slug+=("$name"); us_tip+=("$new"); us_old+=("$pin"); us_lic+=("$(<"$d/lic")"); us_licname+=("$(<"$d/licname")")
        mapfile -d '' -t a < "$d/undecided"
        for s in "${a[@]}"; do refusals+=("skill source $url has a new skill '$s' that is neither locked nor skipped: decide it with land-pin skill add or --skip in skill update, then run again (--only may leave the source out)"); done;;
    esac
  done
  if [ -n "$tool_new" ] && [ ! -r "$root/$LAND_SIGNERS_FILE" ]; then refusals+=("the release $tool_new of the tool cannot be verified: there is no $LAND_SIGNERS_FILE"); fi
  if [ ${#refusals[@]} -gt 0 ]; then for s in "${refusals[@]}"; do echo "land-pin: REFUSED $s" >&2; done; echo "land-pin: update --all: nothing was changed" >&2; exit 1; fi
  if [ ${#unreach[@]} -gt 0 ]; then for s in "${unreach[@]}"; do echo "land-pin: UNREACHABLE $s" >&2; done; echo "land-pin: update --all: a selected source could not be reached, so nothing was changed" >&2; exit 3; fi
  if [ ${#ul_name[@]} = 0 ] && [ ${#us_url[@]} = 0 ] && [ -z "$tool_new" ]; then echo "land-pin: update --all: nothing is behind"; if [ "$dry" = 1 ]; then DRY=1; od_json; DRY=0; fi; return 0; fi
  if [ "$dry" = 1 ]; then DRY=1; od_json; DRY=0; return 1; fi   # nothing is written: the typed report plus `would`; exit 1, something would change
  # apply: a snapshot first, then libraries, skills, the tool (last: it replaces the code that is running)
  ua_snapshot
  local moving="${ul_name[*]}"   # the roots this run moves: a closure member they share moves with them (no diamond between two of them)
  for ((i = 0; i < ${#ul_name[@]}; i++)); do
    if [ -n "${ul_path[$i]}" ]; then LAND_PIN_MOVING=$moving LAND_PIN_ROOT=$root "$here/land-pin" vendor "${ul_name[$i]}" "${ul_url[$i]}" "${ul_new[$i]}" --path "${ul_path[$i]}" || ua_fail library "${ul_name[$i]}"
    else LAND_PIN_ROOT=$root "$here/land-pin" vendor "${ul_name[$i]}" "${ul_url[$i]}" "${ul_new[$i]}" || ua_fail library "${ul_name[$i]}"; fi
  done
  for ((i = 0; i < ${#us_url[@]}; i++)); do
    local -a names=(); for ((j = 0; j < ${#S_URL[@]}; j++)); do [ "${S_URL[$j]}" != "${us_url[$i]}" ] || names+=("${S_NAME[$j]}"); done
    LAND_PIN_ROOT=$root "$here/land-pin" skill update "${us_url[$i]}" "${us_tip[$i]}" "${names[@]}" || ua_fail "skill source" "${us_url[$i]}"
  done
  if [ -n "$tool_new" ]; then "$here/land-update" "$tool_new" --root "$root" || ua_fail tool vbm-land; fi
  UA_ACTIVE=0
  # what to review, and nothing decided
  echo "land-pin: update --all: done. Nothing is committed and nothing is reviewed. To review:"
  for ((i = 0; i < ${#ul_name[@]}; i++)); do echo "  library ${ul_name[$i]} ${ul_old[$i]} -> ${ul_new[$i]}: read it with: git diff -- $LAND_VENDOR_DIR/${ul_name[$i]}"; done
  for ((i = 0; i < ${#us_url[@]}; i++)); do
    for ((j = 0; j < ${#S_URL[@]}; j++)); do
      [ "${S_URL[$j]}" = "${us_url[$i]}" ] || continue; sk=${S_NAME[$j]}
      echo "  skill $sk ${us_old[$i]:0:12} -> ${us_tip[$i]:0:12}: read the aid and the files, then: land-pin skill review $sk --by NAME"
      if [ "${us_lic[$i]}" = true ]; then echo "    licence: CHANGED (${us_licname[$i]:-none at the tip})"; else echo "    licence: unchanged"; fi
      mapfile -d '' -t a < "${SKREC[$sk]}/files"
      if [ ${#a[@]} = 0 ]; then echo "    no file differs"; fi
      for ((k = 0; k + 1 < ${#a[@]}; k += 2)); do echo "    ${a[$k]} $(od_path "${a[$((k + 1))]}")"; done
    done
  done
  [ -z "$tool_new" ] || echo "  tool vbm-land $tool_old -> $tool_new: read it in $LAND_DIR/ (land-update --diff shows it before an update)"
  echo "  then: land-pin verify (it stays red until every skill above is reviewed), the repository's own gate, then commit and land the change like any other (land-direct)"
}
