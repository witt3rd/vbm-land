#!/usr/bin/env bash
# Shared helpers for the test scripts: a scratch sandbox with a bare "remote", worker clones and a fake `gh`.
# A test sources this file, calls `sandbox`, builds what it needs, and ends with `finish`.
set -euo pipefail
export LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/lib/paths.sh"   # every consumer path a test names comes from here (LAND_DIR, LAND_CONF_FILE, LAND_ENTRY, LAND_SKILLS_DIR, ...): never a literal
TESTTMP=${TMPDIR:-/tmp}; T=; SANDBOXES=(); MAINPID=$$; RESULTS=$(mktemp "$TESTTMP/vbm-land-results.XXXXXX")   # results outlive the sandboxes; subshells append to the file
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

sandbox() {   # sandbox [base-branch]: $T/remote.git (bare), $T/seed (one commit pushed), $T/bin/gh (fake), PATH set
  local base=${1:-main}
  T=$(mktemp -d "$TESTTMP/vbm-land-test.XXXXXX"); BASE=$base
  mkdir -p "$T/tmp"; export TMPDIR=$T/tmp   # a test has its OWN tmp dir: whatever the tools under test leave there is this test's, and a check for leftovers never sees another lane's
  # the main shell removes every sandbox and the results file; a ( subshell ) or $( substitution ) that made a sandbox removes only its own
  export GIT_CEILING_DIRECTORIES=$(dirname "$T")   # a scratch directory must never be inside some enclosing repository
  SANDBOXES+=("$T"); trap 'if [ "$BASHPID" = "$MAINPID" ]; then rm -rf "${SANDBOXES[@]}" "$RESULTS"; else rm -rf "$T"; fi' EXIT
  git init -q --bare -b "$base" "$T/remote.git"
  git init -q -b "$base" "$T/seed"
  ( cd "$T/seed" && git config commit.gpgsign false && echo seed > a.txt && git add a.txt && git commit -qm "chore: seed" && git remote add origin "$T/remote.git" && git push -q origin "$base" )
  mkdir -p "$T/bin"
  cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
# fake gh for the tests: answers `run list`, `run view` and `variable get` from files in $FAKE_GH_DIR, applying --jq with the real jq.
#   mode: noworkflow (HTTP 404: the workflow is not on main yet) | ok | red | infra (red because of the infrastructure) | fail (every call fails) | running (tier1 not finished) | none (no runs)
#         | dispatch (latest run is a workflow_dispatch run, tier1 red) | t2red (tier1 green, tier2 failed)
#   Optional files: tier2 (conclusion of the tier2 job, default none), failedlog (text of `--log-failed`)
d=${FAKE_GH_DIR:?}; mode=$(cat "$d/mode" 2>/dev/null || echo none); echo "$*" >> "$d/calls.log"
[ "$mode" != fail ] || exit 1
[ "$mode" != noworkflow ] || { echo "HTTP 404: workflow ci.yml not found on the default branch (https://api.github.com/x)" >&2; exit 1; }
jq_expr=; args=("$@"); for ((i=0;i<${#args[@]};i++)); do [ "${args[i]}" = --jq ] && jq_expr=${args[i+1]}; done
emit() { if [ -n "$jq_expr" ]; then jq -r "$jq_expr"; else cat; fi; }
t1=success t2=$(cat "$d/tier2" 2>/dev/null || echo success) ev=push
case $mode in red|infra|dispatch) t1=failure;; running) t1=null;; t2red) t2=failure;; esac
[ "$(cat "$d/attempt" 2>/dev/null)" != 2 ] || [ "$t1" != failure ] || t1=$(cat "$d/rerun_conclusion" 2>/dev/null || echo success)   # the rerun's result (default green)
[ "$mode" != dispatch ] || ev=workflow_dispatch
q() { [ "$1" = null ] && echo null || echo "\"$1\""; }
case "$1 $2" in
  "run list") [ "$mode" = none ] && { echo '[]' | emit; exit 0; }
     echo "[{\"databaseId\":100,\"headSha\":\"deadbeefdeadbeef\",\"displayTitle\":\"some title\",\"event\":\"$ev\",\"status\":\"completed\"}]" | emit;;
  "run rerun") [ -e "$d/rerun_refused" ] && exit 1; echo 2 > "$d/attempt"; exit 0;;
  "run view") case "$*" in
      *--log-failed*) if [ -r "$d/failedlog" ]; then cat "$d/failedlog"; elif [ "$mode" = infra ]; then echo "fatal: unable to access 'https://x/': Could not resolve host"; else echo "FAIL tests/test_x.sh: real failure"; fi;;
      *--json\ attempt*) echo '{"attempt":'"$(cat "$d/attempt" 2>/dev/null || echo 1)"'}' | emit;;
      *--json\ jobs*) echo "{\"jobs\":[{\"name\":\"tier1\",\"conclusion\":$(q $t1),\"databaseId\":7},{\"name\":\"tier2\",\"conclusion\":$(q $t2),\"databaseId\":8}]}" | emit;;
      *) exit 0;; esac;;
  api*) [ -r "$d/annotations" ] && cat "$d/annotations"; exit 0;;
  "variable get") [ -r "$d/var.$3" ] && cat "$d/var.$3" || exit 1;;
  *) exit 0;;
esac
GH
  chmod +x "$T/bin/gh"; mkdir -p "$T/gh"; echo ok > "$T/gh/mode"
  export FAKE_GH_DIR=$T/gh GH=$T/bin/gh PATH=$T/bin:$PATH
}
seed_push() {   # seed_push FILE CONTENT [SUBJECT]: commit a file straight onto the remote's base branch (through the seed clone)
  local f=$1 c=$2 m=${3:-"chore: seed $1"}
  ( cd "$T/seed" && git pull -q origin "$BASE" && mkdir -p "$(dirname "$f")" && printf '%s\n' "$c" > "$f" && git add -- "$f" && git commit -qm "$m" -m "Task-ID: seed" && git push -q origin "$BASE" )
}
seed_exec() {   # seed_exec FILE CONTENT [SUBJECT]: the same, executable
  seed_push "$@"; ( cd "$T/seed" && chmod +x "$1" && git add -- "$1" && git commit -qm "chore: make $1 executable" -m "Task-ID: seed" && git push -q origin "$BASE" )
}
set_conf() {   # set_conf LINES...: the repository's own $LAND_CONF_FILE on the remote's base branch (one LAND_KEY=value per argument)
  local c; c=$(printf '%s\n' "$@"); seed_push "$LAND_CONF_FILE" "$c" "chore: land.conf"
}
gh_mode() { echo "$1" > "$T/gh/mode"; }
worker() {    # worker NAME: a fresh clone of the remote at $T/NAME
  git clone -q "$T/remote.git" "$T/$1"; git -C "$T/$1" config commit.gpgsign false
}
commit() {    # commit DIR FILE CONTENT [SUBJECT]: write FILE and commit it
  local d=$1 f=$2 c=$3 s=${4:-"feat: change $2"}
  mkdir -p "$(dirname "$d/$f")"; printf '%s\n' "$c" > "$d/$f"; git -C "$d" add -- "$f"; git -C "$d" commit -qm "$s" -m "Task-ID: t1"
}
# race_hook K: the remote's pre-receive hook advances main by one competitor commit (same tree) during each of the first K pushes, so git itself refuses those pushes
race_hook() {
  cat > "$T/remote.git/hooks/pre-receive" <<HOOK
#!/bin/sh
n=\$(cat "$T/race.count" 2>/dev/null || echo 0)
if [ "\$n" -lt $1 ]; then echo \$((n+1)) > "$T/race.count"
  unset GIT_QUARANTINE_PATH GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  tip=\$(git rev-parse refs/heads/main)
  c=\$(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x git commit-tree -p "\$tip" -m "chore: competitor \$n" -m "Task-ID: c" "\$tip^{tree}")
  git update-ref refs/heads/main "\$c" "\$tip"
fi
exit 0
HOOK
  chmod +x "$T/remote.git/hooks/pre-receive"; rm -f "$T/race.count"
}
remote_head() { git -C "$T/remote.git" rev-parse "$BASE"; }
remote_has()  { git -C "$T/remote.git" cat-file -e "$BASE:$1" 2>/dev/null; }
# results are appended to a file, so a check run inside a ( subshell ) still counts
pass() { echo P >> "$RESULTS"; echo "ok   $*"; }
fail() { echo F >> "$RESULTS"; echo "FAIL $*" >&2; }
check() {     # check DESCRIPTION CMD...: the command must succeed
  local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}
expect_exit() {   # expect_exit DESCRIPTION CODE CMD...: run CMD (stdout+stderr to $T/out), its exit code must be CODE
  local d=$1 want=$2 rc=0; shift 2; "$@" >"$T/out" 2>&1 || rc=$?
  if [ "$rc" = "$want" ]; then pass "$d (exit $rc)"; else fail "$d: wanted exit $want, got $rc"; sed 's/^/     | /' "$T/out" >&2; fi
}
out_has() { grep -q -- "$1" "$T/out" && pass "output says: $1" || { fail "output lacks: $1"; sed 's/^/     | /' "$T/out" >&2; }; }
json_last() { tail -n1 "$T/out"; }
finish() {
  local p f; p=$(grep -c P "$RESULTS" 2>/dev/null || true); f=$(grep -c F "$RESULTS" 2>/dev/null || true)
  echo "== $(basename "$0"): ${p:-0} passed, ${f:-0} failed"
  # RAN-EVIDENCE: the one line tests/run.sh reads, `ran: NAME: N cases` (N > 0). A script that ran no check prints none and fails: a refused tool, a skip or an early exit is a failure, never a pass.
  [ "${f:-0}" = 0 ] && [ "${p:-0}" -gt 0 ] && echo "ran: $(basename "$0" .sh): ${p} cases"
}
