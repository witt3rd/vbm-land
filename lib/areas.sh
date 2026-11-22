#!/usr/bin/env bash
# lib/areas.sh: areas (docs/areas.md): the project's own factoring of what a change can affect. Sourced, never run. Used by bin/land-areas (the read-only command), bin/land-direct (the decision and
# the steps), bin/land-check (--areas, the offline refusal of a malformed file) and bin/land-release (the release candidate runs every area).
#
# The areas file is JSON, read by python3's json module (a real decoder, on every supported host: it is already required by land-lean); the matcher, the selection, the closest
# enclosing area and the reuse decision are one program, lib/areas.py, so that every caller decides the same way. It decides from PATHS ONLY: it reads no source, traces no import and runs nothing.
# Exit 2 with the reason on a malformed file, a duplicate name, an area with no paths, a glob outside the language, a step with no run.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.sh"


# areas_run ARGS...: the program (land-areas's whole interface: docs/areas.md section 10 and `land-areas` with no argument).
areas_run() {
  command -v python3 >/dev/null 2>&1 || { echo "land-areas: python3 is required to read $LAND_AREAS_FILE (it is the JSON decoder)" >&2; return 2; }
  python3 "$(dirname "${BASH_SOURCE[0]}")/areas.py" "$@"
}
# areas_fetch TOP REF DEST: the repository's areas file from REF (what the base already says: a commit cannot loosen the rules it is judged by), else the working tree's copy (the offline report and the release candidate; the lander does NOT judge by it, see areas_setup). 1 when there is none.
areas_fetch() {
  if git -C "$1" cat-file -e "$2:$LAND_AREAS_FILE" 2>/dev/null; then git -C "$1" show "$2:$LAND_AREAS_FILE" > "$3"
  elif [ -r "$1/$LAND_AREAS_FILE" ]; then cp "$1/$LAND_AREAS_FILE" "$3"
  else return 1; fi
}
# areas_setup TOP REF RUN: does REF (the base) have an areas file? Sets have_areas (0 or 1) and LAND_AREAS_ON (read by conf_validate), and leaves the file at RUN/areas.json. A malformed one: 2 with the reason.
# ONLY the base's file judges a landing (docs/areas.md section 7). A base with none is judged by its own land.conf entirely; the working tree's file, if any, is validated (a malformed one refuses) and not applied.
areas_setup() {
  have_areas=0; LAND_AREAS_ON=0
  if git -C "$1" cat-file -e "$2:$LAND_AREAS_FILE" 2>/dev/null; then git -C "$1" show "$2:$LAND_AREAS_FILE" > "$3/areas.json"
  elif [ -r "$1/$LAND_AREAS_FILE" ]; then
    cp "$1/$LAND_AREAS_FILE" "$3/areas.pending.json"
    areas_run validate --file "$3/areas.pending.json" || { echo "land-direct: $LAND_AREAS_FILE is refused (above); nothing landed" >&2; return 2; }
    echo "land-direct: $LAND_AREAS_FILE is valid and NOT applied: $2 has none yet, so this landing is judged by $2's own rules; areas apply from the next landing on (docs/areas.md section 7)"
    return 0
  else return 0; fi
  areas_run validate --file "$3/areas.json" || { echo "land-direct: $LAND_AREAS_FILE is refused (above); nothing landed" >&2; return 2; }
  have_areas=1; LAND_AREAS_ON=1
}
# areas_steps WT RUN BUDGET: run the steps of RUN/areas.d/steps0 in order (area, cwd, run), each in WT/cwd, stopping at the first red and naming the area and the step. Needs land-direct's t1stage and inherited_red.
areas_steps() {
  local wt=$1 run=$2 a c r i=0 left
  while IFS= read -r -d '' a && IFS= read -r -d '' c && IFS= read -r -d '' r; do
    i=$((i + 1)); left=$(( $3 - ($(date +%s) - ts) )); [ "$left" -gt 0 ] || stop 13 tier1 "Tier 1 ran past its bound (LAND_TIER1_TIMEOUT=$3 s) before area $a, step '$r'; nothing lands."
    echo "land-direct: area $a: step $i: $r$([ "$c" = . ] || echo " (in $c)")"
    LAND_TEST_CMD=$r; stepcwd=$c; lt=$left; step=tier1-$a   # a step is run as the `tests` stage (an areas file refuses LAND_TEST_CMD, so it is free): the same bound, log, failed-names record and inherited-red rule
    t1stage tests "$wt/$c" "$run/tier1.$i.log" "$run/failed.step" || {
      inherited_red tests || { logfile=$run/tier1.$i.log; tail -15 "$logfile" >&2; lastlines=$(tail -5 "$logfile"); stop 13 tier1 "Tier 1: area $a, step '$r' fails on the rebased commits${newfail:+ (a failure $base does not have: $newfail)} (log: $logfile); nothing lands. The steps are those of the areas file on $base, never of this change: a commit that deletes what they run lands second (docs/areas.md section 7)."; }
      inherited=1; echo "land-direct: area $a, step '$r' fails, but only with failures $base already has (inherited red: not yours); landing"; }
  done < "$run/areas.d/steps0"
  LAND_TEST_CMD=; stepcwd=; lt=$3
}
# areas_decide WT BSHA RUN FILE PREV REGENNED: decide the net change of WT against BSHA. Writes RUN/areas.d (steps0: NUL-separated area, cwd, run; vjson; validation; passed ...), sets vjson and validation, prints one line per
# area run, skipped or reused, and every unmapped and gate-defining path. With LAND_REUSE=1 the areas of the last passing attempt (RUN/areas.passed, on base PREV) that the trunk's move did not touch are reused.
areas_decide() {
  local wt=$1 bsha=$2 run=$3 file=$4 prev=$5 regenned=$6 mv=() l
  rm -rf "$run/areas.d"; mkdir -p "$run/areas.d"
  git -C "$wt" diff --name-status --no-renames "$bsha" > "$run/touched.paths.txt" || return 2
  if [ "$LAND_REUSE" = 1 ] && [ -n "$prev" ] && [ "$prev" != "$bsha" ] && [ "$regenned" = 0 ] && [ -e "$run/areas.passed" ] \
     && git -C "$wt" merge-base --is-ancestor "$prev" "$bsha" && git -C "$wt" diff --name-status --no-renames "$prev" "$bsha" > "$run/moved.paths.txt" \
     && ! grep -qE "^[A-Z]	(${LAND_HOOKS_DIR%/}/|$LAND_CONF_FILE\$)" "$run/moved.paths.txt"; then   # the settings and the hooks moving: what judges a change moved, nothing is reused
    mv=(--moved "$run/moved.paths.txt" --validated "$run/areas.passed")
  fi
  areas_run decide --file "$file" --inert "$LAND_INERT" --protected "$LAND_PROTECTED" --into "$run/areas.d" ${mv[@]+"${mv[@]}"} < "$run/touched.paths.txt" || return 2
  vjson=$(cat "$run/areas.d/vjson"); validation=$(cat "$run/areas.d/validation")
  while IFS= read -r l; do echo "land-direct: area: $l"; done < "$run/areas.d/explain"
}
# areas_tier1: Tier 1 of a repository with an areas file, in place of the gates and test commands (called by land-direct with its variables: wt, run, bsha, prev, regenned, ts, inert, reuse, t1). The steps of the touched areas, in file order, the
# first red stops the landing naming its area and step; an inert or a reused verdict runs nothing and says so. The post-tier1 hook runs exactly when a step ran.
areas_tier1() {
  areas_decide "$wt" "$bsha" "$run" "$run/areas.json" "$prev" "$regenned" || stop 2 error "the areas decision failed (above); nothing landed"
  inert=0; reuse=0; t1=0
  case $validation in
    inert) inert=1; echo "land-direct: every area this change touches has no steps: nothing runs (validation inert); the post-tier1 hook is not run";;
    reused) reuse=1; echo "land-direct: reused: every touched area with steps passed on ${prev:0:12} and nothing that moved since touches it: nothing is run again";;
    *) areas_steps "$wt" "$run" "$lt"; t1=$(( $(date +%s) - ts ))
       step=post-tier1-hook; run_hook post-tier1 || stop 12 refused "the post-tier1 hook refused this change (a gate that judges the tree after Tier 1, such as an attack suite; see above)";;
  esac
  cp "$run/areas.d/passed" "$run/areas.passed"; prev=$bsha
}
# areas_candidate ROOT REF TIMEOUT [NAME]: every step of every area of REF's areas file, in file order, on ROOT's tree, with LAND_RC=1 (nothing cached, selected or skipped). 0 green or no areas file, 1 red, 2 malformed.
# With NAME (docs/family-repo.md section 5, land-release --area): only the areas a change to lib/NAME/ touches, which by the declared overlap (docs/areas.md rule 4) are the area NAME and every area that lists lib/NAME/*,
# the dependents; the areas not run are named. 2 when no area NAME owns lib/NAME/.
areas_candidate() {
  local tmp rc=0 a c r; tmp=$(mktemp -d "${TMPDIR:-/tmp}/land-areas.XXXXXX")
  if areas_fetch "$1" "$2" "$tmp/areas.json"; then
    if [ -n "${4:-}" ]; then
      printf 'M\tlib/%s/VERSION\n' "$4" | areas_run touched --file "$tmp/areas.json" --into "$tmp" > /dev/null || rc=2
      if [ "$rc" = 0 ] && { [ -s "$tmp/unmapped" ] || ! grep -qx -- "$4" "$tmp/areas"; }; then echo "land-release: no area $4 owns lib/$4/ in $LAND_AREAS_FILE" >&2; rc=2; fi
      [ "$rc" != 0 ] || echo "land-release: area $4 and the areas that depend on it run: $(tr '\n' ' ' < "$tmp/areas")(not run: $(tr '\n' ' ' < "$tmp/skipped" | sed 's/ $//'))"
    else
      areas_run touched --rc --file "$tmp/areas.json" --into "$tmp" < /dev/null > /dev/null || rc=2
    fi
    if [ "$rc" = 0 ]; then
      while IFS= read -r -d '' a && IFS= read -r -d '' c && IFS= read -r -d '' r; do
        echo "land-release: area $a: step: $r${c:+ (in $c)}"
        (cd "$1/$c" && LAND_RC=1 timeout --foreground "$3" bash -c "$r") || { echo "land-release: area $a: step: $r FAILED" >&2; rc=1; break; }
      done < "$tmp/steps0"
    fi
  fi
  rm -rf "$tmp"; return "$rc"
}
