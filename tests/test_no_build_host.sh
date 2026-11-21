#!/usr/bin/env bash
# The heavy-host guard (lib/no-build-host.sh, bin/no-build-guard, bin/run-scoped.sh, bin/run-probe): a host that carries a no-build marker (/etc/vbm/no-build-host or <config dir>/vbm/no-build-host) REFUSES (exit 2) and starts NOTHING;
# without a marker the same call runs. No variable overrides it. Negative tests: marker present => refused, no process started (a sentinel file the command would create stays absent); marker absent => runs and its status passes through;
# the attacks of docs/no-build-host.md that the code can stop (an override variable, a moved XDG_CONFIG_HOME or HOME, a dangling-symlink marker, calling the scoped side directly, a missing guard) and the lint that finds a runner started without it.
# The test needs a host WITHOUT a marker (it runs real commands in the marker-absent cases): on a marked host it fails, which is the guard working.
. "$(dirname "$0")/lib.sh"
G=$ROOT/bin/no-build-guard; RS=$ROOT/bin/run-scoped.sh; RP=$ROOT/bin/run-probe; tmp=$(mktemp -d); T=$tmp; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/hm" "$tmp/cfg/vbm" "$tmp/other"
env_clean() { env -u VBM_ALLOW_BUILD_HERE HOME="$tmp/hm" XDG_CONFIG_HOME="$tmp/cfg" "$@"; }
marker_on() { : > "$tmp/cfg/vbm/no-build-host"; }; marker_off() { rm -f "$tmp/cfg/vbm/no-build-host" "$tmp/hm/.config/vbm/no-build-host"; }
# started NAME: the sentinel a command creates when it really ran
refused() {   # refused DESCRIPTION CMD...: exit 2, the REFUSED message, and the sentinel $tmp/ran absent
  local d=$1 rc=0; shift; rm -f "$tmp/ran"; "$@" >"$tmp/out" 2>&1 || rc=$?
  if [ "$rc" = 2 ] && grep -q REFUSED "$tmp/out" && [ ! -e "$tmp/ran" ]; then pass "$d: refused (exit 2), nothing started"; else fail "$d: wanted exit 2 + REFUSED + nothing started; got $rc, started=$([ -e "$tmp/ran" ] && echo yes || echo no): $(head -c 200 "$tmp/out")"; fi
}
runs() {      # runs DESCRIPTION CMD...: exit 0 and the sentinel created
  local d=$1 rc=0; shift; rm -f "$tmp/ran"; "$@" >"$tmp/out" 2>&1 || rc=$?
  if [ "$rc" = 0 ] && [ -e "$tmp/ran" ]; then pass "$d: runs"; else fail "$d: wanted it to run; got $rc, started=$([ -e "$tmp/ran" ] && echo yes || echo no): $(head -c 200 "$tmp/out")"; fi
}
modes=fallback; if systemctl --user is-system-running >/dev/null 2>&1 || [ "$(systemctl --user is-system-running 2>/dev/null)" = degraded ]; then modes="scope fallback"; fi
# 1. the guard itself
marker_off; runs "guard, no marker" env_clean "$G" -- touch "$tmp/ran"
rc=0; env_clean "$G" >/dev/null 2>&1 || rc=$?; [ "$rc" = 0 ] && pass "guard alone, no marker: exit 0" || fail "guard alone, no marker: exit $rc"
rc=0; env_clean "$G" -- sh -c 'exit 7' >/dev/null 2>&1 || rc=$?; [ "$rc" = 7 ] && pass "guard: the command's exit status passes through" || fail "guard: exit status $rc"
marker_on
refused "guard, marker in the config dir" env_clean "$G" -- touch "$tmp/ran"
rc=0; env_clean "$G" >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] && pass "guard alone, marker: exit 2" || fail "guard alone, marker: exit $rc"
refused "guard, marker present AND VBM_ALLOW_BUILD_HERE=1 (no override exists)" env_clean VBM_ALLOW_BUILD_HERE=1 "$G" -- touch "$tmp/ran"
refused "guard, marker present, every plausible override set" env_clean VBM_ALLOW_BUILD_HERE=1 ALLOW_BUILD_HERE=1 VBM_NO_GUARD=1 NO_BUILD_GUARD=0 nbh_etc=/nonexistent "$G" -- touch "$tmp/ran"
marker_off; mkdir -p "$tmp/hm/.config/vbm"; : > "$tmp/hm/.config/vbm/no-build-host"
refused "guard, marker under HOME while XDG_CONFIG_HOME points elsewhere (moving the variable hides nothing)" env_clean XDG_CONFIG_HOME="$tmp/other" "$G" -- touch "$tmp/ran"
marker_off; ln -s "$tmp/nonexistent-target" "$tmp/cfg/vbm/no-build-host"
refused "guard, a dangling symlink as the marker" env_clean "$G" -- touch "$tmp/ran"
marker_off; runs "guard, marker removed again" env_clean "$G" -- touch "$tmp/ran"
# the system marker: the library is sourced here (the path is a plain variable of the library, not an environment knob, so the real /etc is never touched)
( . "$ROOT/lib/no-build-host.sh"; nbh_etc=$tmp/etc-marker; rm -f "$nbh_etc"; HOME=$tmp/hm XDG_CONFIG_HOME=$tmp/cfg nbh_found >/dev/null ) && fail "lib: found a marker where there is none" || pass "lib: no marker found where there is none"
( . "$ROOT/lib/no-build-host.sh"; nbh_etc=$tmp/etc-marker; : > "$nbh_etc"; HOME=$tmp/hm XDG_CONFIG_HOME=$tmp/cfg nbh_guard t >/dev/null 2>&1; [ $? = 2 ] ) && pass "lib: the system marker refuses (2)" || fail "lib: the system marker did not refuse"
( nbh_etc=/nonexistent; export nbh_etc; . "$ROOT/lib/no-build-host.sh"; [ "$nbh_etc" = /etc/vbm/no-build-host ] ) && pass "lib: an exported nbh_etc does not move the system marker" || fail "lib: the environment moved the system marker"
# 2. run-scoped.sh, both paths
for mode in $modes; do
  if [ $mode = fallback ]; then x=RUN_SCOPED_NO_SYSTEMD=1; else x=RUN_SCOPED_X=1; fi
  marker_off; runs "run-scoped ($mode), no marker" env_clean "$x" "$RS" g 10 touch "$tmp/ran"
  marker_on;  refused "run-scoped ($mode), marker" env_clean "$x" "$RS" g 10 touch "$tmp/ran"
  refused "run-scoped ($mode), marker and VBM_ALLOW_BUILD_HERE=1" env_clean "$x" VBM_ALLOW_BUILD_HERE=1 "$RS" g 10 touch "$tmp/ran"
done
# the scoped side called directly (TOCTOU: the marker appears between the outer check and the exec; or a caller that skips the outer side) re-checks before it execs
printf '%s\0' touch "$tmp/ran" > "$tmp/argf"; marker_on
refused "run-scoped --exec-argfile (the inner side) re-checks the marker" env_clean "$RS" --exec-argfile "$tmp/argf"
# a helper with no guard next to it refuses (fail closed); the same copy WITH the guard line removed would run: the guard line is what refuses, and the lint insists on it
mkdir -p "$tmp/lone"; cp "$RS" "$tmp/lone/run-scoped.sh"; marker_off
refused "run-scoped copied away from its guard" env_clean "$tmp/lone/run-scoped.sh" g 10 touch "$tmp/ran"
mkdir -p "$tmp/noguard"; cp "$RS" "$tmp/noguard/run-scoped.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/noguard/no-build-guard"; chmod +x "$tmp/noguard/no-build-guard"; marker_on
runs "self-test: a helper whose guard does nothing starts the command (the check can fail)" env_clean "$tmp/noguard/run-scoped.sh" g 10 touch "$tmp/ran"
# 3. run-probe
if command -v cc >/dev/null; then
  marker_on;  refused "run-probe, marker" env_clean "$RP" touch "$tmp/ran"
  marker_off; runs "run-probe, no marker" env_clean "$RP" touch "$tmp/ran"
else fail "run-probe: no C compiler (the preload needs one): the case cannot run"; fi
# 4. the lint: a repository fixture
marker_off; fx=$tmp/fx; mkdir -p "$fx/scripts" "$fx/$LAND_DIR/bin" "$fx/$LAND_DIR/lib"; git -C "$fx" init -q
cp "$G" "$fx/$LAND_DIR/bin/"; cp "$ROOT/lib/no-build-host.sh" "$fx/$LAND_DIR/lib/"; cp "$RS" "$fx/$LAND_DIR/bin/run-scoped.sh"
printf 'mutants.py\nself abi.sh\n' > "$fx/scripts/long-runners.txt"
printf '#!/usr/bin/env bash\n%s/bin/no-build-guard || exit 2\nexit 0\n' "$LAND_DIR" > "$fx/scripts/abi.sh"; chmod +x "$fx/scripts/abi.sh"
printf '#!/usr/bin/env bash\n%s/bin/run-scoped.sh mutants 3600 python3 scripts/mutants.py --jobs 4\nscripts/abi.sh\n' "$LAND_DIR" > "$fx/scripts/tier1.sh"
lintfx() { git -C "$fx" add -A >/dev/null; env_clean "$fx/$LAND_DIR/bin/no-build-guard" --lint "$fx"; }
expect_exit "lint: a repository that runs everything through the helper passes" 0 lintfx
printf '#!/usr/bin/env bash\npython3 scripts/mutants.py --jobs 4\n' > "$fx/scripts/tier1.sh"
expect_exit "lint: a direct call of a declared runner fails" 1 lintfx; out_has "runs mutants.py outside run-scoped.sh"
printf '#!/usr/bin/env bash\nmise exec -- scripts/mutants.py\n' > "$fx/scripts/tier1.sh"; expect_exit "lint: a mise-prefixed call fails" 1 lintfx
printf '#!/usr/bin/env bash\n%s/bin/run-scoped.sh mutants 3600 python3 scripts/mutants.py\n' "$LAND_DIR" > "$fx/scripts/tier1.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fx/scripts/abi.sh"; expect_exit "lint: a self runner with no guard call fails" 1 lintfx
printf '#!/usr/bin/env bash\n# %s/bin/no-build-guard\nexit 0\n' "$LAND_DIR" > "$fx/scripts/abi.sh"; expect_exit "lint: a guard call that is only a comment fails" 1 lintfx
printf '#!/usr/bin/env bash\n%s/bin/no-build-guard || exit 2\n' "$LAND_DIR" > "$fx/scripts/abi.sh"; expect_exit "lint: restored, passes again" 0 lintfx
cp "$RS" "$fx/$LAND_DIR/bin/run-scoped.sh"; grep -v 'no-build-guard' "$RS" > "$fx/$LAND_DIR/bin/run-scoped.sh"; chmod +x "$fx/$LAND_DIR/bin/run-scoped.sh"
expect_exit "lint: a helper without the guard fails" 1 lintfx; out_has "does not call no-build-guard"
# a helper that mentions the guard in a comment only, or calls it after it started something
sed 's|^"\$nbg" .*|# no-build-guard skipped|' "$RS" > "$fx/$LAND_DIR/bin/run-scoped.sh"; expect_exit "lint: a helper that finds the guard but never calls it fails (the marker probe starts the command)" 1 lintfx
cp "$RS" "$fx/$LAND_DIR/bin/run-scoped.sh"; rm "$fx/scripts/long-runners.txt"; printf 'mutants.py\n' > "$fx/scripts/heavy-runners.txt"; printf 'mutants.py\n' > "$fx/scripts/x.sh"
expect_exit "lint: scripts/heavy-runners.txt is read too" 1 lintfx
rm "$fx/$LAND_DIR/bin/run-scoped.sh" "$fx/scripts/x.sh"; expect_exit "lint: declared runners and no helper fails" 1 lintfx
expect_exit "lint: --selftest" 0 "$G" --selftest
# 5. the lander (bin/land-direct) asks the guard at the HEAVY command (heavy_gate), not at the door: a landing or --validate that needs Tier 1 on a marked host exits 2 and starts no heavy command
# (the Tier 1 witness file stays absent, nothing is pushed or pinned); the read-only commands still work there; with the marker removed the same landing proceeds (the negative: the check can fail the other way);
# --push only pushes what --validate pinned, so it does not ask. An inert landing (section 6) needs no heavy command and lands on a marked host.
sandbox; trap 'rm -rf "$tmp" "${SANDBOXES[@]}" "$RESULTS"' EXIT   # the lib's sandbox replaced the trap: remove both
LD=$ROOT/bin/land-direct; t1ran=$tmp/tier1ran
set_conf "LAND_TEST_CMD=touch $t1ran"
worker w1; commit "$T/w1" x.txt 1; worker w2; commit "$T/w2" y.txt 1
ld() { local d=$1; shift; ( cd "$d" && env_clean "$@" ) >"$T/out" 2>&1; }   # ld DIR CMD...: output to $T/out
untouched() {   # untouched DESC DIR BEFORE: no heavy command was started and nothing was pushed or pinned
  local d=$1 dir=$2 before=$3
  [ ! -e "$t1ran" ] && [ "$(remote_head)" = "$before" ] && [ -z "$(git -C "$dir" for-each-ref refs/vbm-land)" ] && pass "$d: nothing heavy started (no Tier 1, nothing pushed or pinned)" || fail "$d: something was started or pushed"
}
head0=$(remote_head); rm -f "$t1ran"
marker_on
for mode in land validate; do
  a=(); [ $mode = validate ] && a=(--validate)
  rc=0; ld "$T/w1" "$LD" "${a[@]}" || rc=$?; [ "$rc" = 2 ] && pass "land-direct ${a[*]:-(landing)}, marker: exit 2" || fail "land-direct ${a[*]:-(landing)}, marker: exit $rc"; out_has REFUSED
  [ "$(json_last | sed -n 's/.*"result":"\([a-z]*\)".*"exit":\([0-9]*\).*/\1 \2/p')" = "refused 2" ] && pass "land-direct ${a[*]:-(landing)}, marker: the last line is the JSON summary (refused, exit 2)" || fail "last line: $(json_last)"
  untouched "land-direct ${a[*]:-(landing)}, marker" "$T/w1" "$head0"
  rc=0; ld "$T/w1" env VBM_ALLOW_BUILD_HERE=1 ALLOW_BUILD_HERE=1 VBM_NO_GUARD=1 NO_BUILD_GUARD=0 nbh_etc=/nonexistent LAND_TIER1_TIMEOUT=1 "$LD" "${a[@]}" || rc=$?; [ "$rc" = 2 ] && pass "land-direct ${a[*]:-(landing)}, marker and every plausible override variable: still exit 2" || fail "override variable: exit $rc"
  untouched "land-direct ${a[*]:-(landing)}, marker and override variables" "$T/w1" "$head0"
done
marker_off; mkdir -p "$tmp/hm/.config/vbm"; : > "$tmp/hm/.config/vbm/no-build-host"; rc=0; ld "$T/w1" XDG_CONFIG_HOME="$tmp/other" "$LD" --validate || rc=$?
[ "$rc" = 2 ] && pass "land-direct: marker under HOME while XDG_CONFIG_HOME points elsewhere: exit 2" || fail "land-direct: moved XDG_CONFIG_HOME: exit $rc"; marker_off
untouched "land-direct, marker under HOME" "$T/w1" "$head0"
# the exit code is the guard's, and a guard that is missing refuses (a stub guard beside a copy of the lander; the copy is a fixture, never the real tool)
stub=$tmp/stub; mkdir -p "$stub/bin"; cp "$LD" "$stub/bin/"; cp -r "$ROOT/lib" "$stub/lib"; cp "$ROOT/VERSION" "$stub/" 2>/dev/null || true
printf '#!/usr/bin/env bash\necho "stub guard says no" >&2\nexit 7\n' > "$stub/bin/no-build-guard"; chmod +x "$stub/bin/no-build-guard"
rc=0; ld "$T/w1" "$stub/bin/land-direct" || rc=$?; [ "$rc" = 7 ] && pass "land-direct: the exit code is the guard's (7)" || fail "land-direct: the guard exited 7, the lander $rc"; out_has "stub guard says no"; untouched "land-direct, a guard that exits 7" "$T/w1" "$head0"
rm "$stub/bin/no-build-guard"; rc=0; ld "$T/w1" "$stub/bin/land-direct" --validate || rc=$?; [ "$rc" = 2 ] && pass "land-direct: no guard beside it refuses (2)" || fail "land-direct: no guard: exit $rc"; untouched "land-direct, no guard" "$T/w1" "$head0"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/bin/no-build-guard"; chmod +x "$stub/bin/no-build-guard"; marker_on
rc=0; ld "$T/w1" "$stub/bin/land-direct" --validate || rc=$?; [ "$rc" = 0 ] && [ -e "$t1ran" ] && pass "self-test: a lander whose guard does nothing runs Tier 1 on a marked host (the check can fail)" || fail "self-test: stub guard that passes: exit $rc"
rm -f "$t1ran"; rm -rf "$(git -C "$T/w1" rev-parse --path-format=absolute --git-common-dir)/vbm-land"; git -C "$T/w1" for-each-ref --format='%(refname)' refs/vbm-land | while read -r r; do git -C "$T/w1" update-ref -d "$r"; done
# the read-only commands work on a marked host
marker_on
rc=0; ld "$T/w1" "$LD" --status || rc=$?; [ "$rc" = 0 ] && pass "land-direct --status, marker: exit 0" || fail "land-direct --status, marker: exit $rc"; out_has "hold: none"
rc=0; ld "$T/w1" "$LD" --hold "maintenance" || rc=$?; [ "$rc" = 0 ] && pass "land-direct --hold, marker: exit 0" || fail "land-direct --hold, marker: exit $rc"
ld "$T/w1" "$LD" --status; out_has "hold: maintenance"
rc=0; ld "$T/w1" "$LD" --release || rc=$?; [ "$rc" = 0 ] && pass "land-direct --release, marker: exit 0" || fail "land-direct --release, marker: exit $rc"
rc=0; ld "$T/w1" "$LD" --freeze "t" --owner me --for 1h || rc=$?; [ "$rc" = 0 ] && pass "land-direct --freeze, marker: exit 0" || fail "land-direct --freeze, marker: exit $rc"
rc=0; ld "$T/w1" "$LD" --thaw || rc=$?; [ "$rc" = 0 ] && pass "land-direct --thaw, marker: exit 0" || fail "land-direct --thaw, marker: exit $rc"
rc=0; ld "$T/w1" "$LD" --version || rc=$?; [ "$rc" = 0 ] && pass "land-direct --version, marker: exit 0" || fail "land-direct --version, marker: exit $rc"
rc=0; ld "$T/w1" "$LD" --print-gate-diff-hash x || rc=$?; ! grep -q REFUSED "$T/out" && pass "land-direct --print-gate-diff-hash: not refused by the guard" || fail "land-direct --print-gate-diff-hash was refused by the guard"
[ ! -e "$t1ran" ] && pass "the read-only commands started no Tier 1" || fail "a read-only command ran Tier 1"
# the negative: the marker removed, the same attempts proceed. --validate runs Tier 1 and pins; on a marked host --push of that pin only pushes (it runs nothing heavy)
rm -rf "$(git -C "$T/w1" rev-parse --path-format=absolute --git-common-dir)/vbm-land"; marker_off
rc=0; ld "$T/w1" "$LD" --validate || rc=$?; [ "$rc" = 0 ] && [ -e "$t1ran" ] && pass "land-direct --validate, no marker: runs Tier 1 (exit 0)" || fail "land-direct --validate, no marker: exit $rc, tier1 ran=$([ -e "$t1ran" ] && echo yes || echo no)"
pin=$(git -C "$T/w1" for-each-ref --format='%(refname)' refs/vbm-land/validated | sed -n 1p | sed 's|.*/||'); rm -f "$t1ran"
marker_on; rc=0; ld "$T/w1" "$LD" --push "$pin" || rc=$?
[ "$rc" = 0 ] && [ "$(remote_head)" = "$pin" ] && [ ! -e "$t1ran" ] && pass "land-direct --push SHA on a marked host: pushes exactly what was validated, runs nothing" || fail "land-direct --push, marker: exit $rc"
marker_off; head1=$(remote_head); rc=0; ld "$T/w2" "$LD" || rc=$?
[ "$rc" = 0 ] && [ "$(remote_head)" != "$head1" ] && [ -e "$t1ran" ] && pass "land-direct landing, no marker: lands (exit 0), Tier 1 ran" || fail "land-direct landing, no marker: exit $rc"
marker_on; head2=$(remote_head); worker w3; commit "$T/w3" z.txt 1; rm -f "$t1ran"
rc=0; ld "$T/w3" "$LD" || rc=$?; [ "$rc" = 2 ] && [ "$(remote_head)" = "$head2" ] && [ ! -e "$t1ran" ] && pass "land-direct landing, marker back: refused again, nothing pushed" || fail "land-direct landing, marker back: exit $rc"
# 6. the guard is asked at the heavy command: on a marked host an inert landing lands, a landing that needs Tier 1 or a hook does not start it, a missing guard refuses only a heavy command
sandbox; trap 'rm -rf "$tmp" "${SANDBOXES[@]}" "$RESULTS"' EXIT
marker_on; t1ran=$T/tier1ran; hran=$T/hookran
set_conf "LAND_TEST_CMD=touch $t1ran" 'LAND_INERT=docs/*'
worker n1; commit "$T/n1" docs/a.md 1; worker n2; commit "$T/n2" code.txt 1; head0=$(remote_head)
rc=0; ld "$T/n1" "$LD" || rc=$?; [ "$rc" = 0 ] && [ "$(remote_head)" != "$head0" ] && [ ! -e "$t1ran" ] && pass "marked host, inert landing: lands (exit 0), no Tier 1" || fail "marked host, inert landing: exit $rc, started=$([ -e "$t1ran" ] && echo yes || echo no)"
json_last | grep -q '"validation":"inert"' && pass 'marked host, inert landing: the summary says "validation":"inert"' || fail "inert summary: $(json_last)"
head0=$(remote_head)
rc=0; ld "$T/n2" "$LD" || rc=$?; [ "$rc" = 2 ] && [ ! -e "$t1ran" ] && [ "$(remote_head)" = "$head0" ] && pass "marked host, non-inert landing: exit 2, the Tier 1 command never started, nothing pushed" || fail "marked host, non-inert landing: exit $rc, started=$([ -e "$t1ran" ] && echo yes || echo no)"
out_has REFUSED; out_has "nothing landed and nothing was pushed"
[ "$(json_last | sed -n 's/.*"result":"\([a-z]*\)".*"exit":\([0-9]*\).*/\1 \2/p')" = "refused 2" ] && pass "marked host, non-inert landing: the JSON summary says refused, exit 2" || fail "summary: $(json_last)"
# a configured hook is a heavy command too: it never starts on a marked host (even for an inert landing, which would not run Tier 1)
seed_exec "$LAND_HOOKS_DEFAULT/prepare" "#!/bin/sh
touch $hran"
worker n3; commit "$T/n3" docs/b.md 1; head0=$(remote_head)
rc=0; ld "$T/n3" "$LD" || rc=$?; [ "$rc" = 2 ] && [ ! -e "$hran" ] && [ "$(remote_head)" = "$head0" ] && pass "marked host, a configured hook: exit 2 before the hook started" || fail "marked host, hook: exit $rc, hook ran=$([ -e "$hran" ] && echo yes || echo no)"
marker_off; rc=0; ld "$T/n3" "$LD" || rc=$?; [ "$rc" = 0 ] && [ -e "$hran" ] && pass "self-test: no marker, the same landing runs the hook and lands" || fail "no marker, hook landing: exit $rc"
# a guard missing beside the lander: a non-inert landing refuses (fail closed); an inert one needs no guard
marker_off; rm -f "$t1ran" "$hran"; git -C "$T/seed" pull -q origin main; git -C "$T/seed" rm -q "$LAND_HOOKS_DEFAULT/prepare"; git -C "$T/seed" commit -qm "chore: no hook" -m "Task-ID: seed"; git -C "$T/seed" push -q origin main
worker n4; commit "$T/n4" code2.txt 1; worker n5; commit "$T/n5" docs/c.md 1; head0=$(remote_head)
rm -f "$stub/bin/no-build-guard"
rc=0; ld "$T/n4" "$stub/bin/land-direct" || rc=$?; [ "$rc" = 2 ] && [ ! -e "$t1ran" ] && [ "$(remote_head)" = "$head0" ] && pass "guard missing, non-inert landing: exit 2, Tier 1 never started" || fail "guard missing, non-inert: exit $rc"; out_has "is missing"
rc=0; ld "$T/n5" "$stub/bin/land-direct" || rc=$?; [ "$rc" = 0 ] && [ "$(remote_head)" != "$head0" ] && [ ! -e "$t1ran" ] && pass "guard missing, inert landing: lands (it starts no heavy command)" || fail "guard missing, inert: exit $rc"
marker_off
finish
