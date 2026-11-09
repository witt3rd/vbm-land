#!/usr/bin/env bash
# The heavy-host guard (lib/no-build-host.sh, bin/no-build-guard, scripts/run-scoped.sh, bin/run-probe): a host that carries a no-build marker (/etc/vbm/no-build-host or <config dir>/vbm/no-build-host) REFUSES (exit 2) and starts NOTHING;
# without a marker the same call runs. No variable overrides it. Negative tests: marker present => refused, no process started (a sentinel file the command would create stays absent); marker absent => runs and its status passes through;
# the attacks of docs/no-build-host.md that the code can stop (an override variable, a moved XDG_CONFIG_HOME or HOME, a dangling-symlink marker, calling the scoped side directly, a missing guard) and the lint that finds a runner started without it.
# The test needs a host WITHOUT a marker (it runs real commands in the marker-absent cases): on a marked host it fails, which is the guard working.
. "$(dirname "$0")/lib.sh"
G=$ROOT/bin/no-build-guard; RS=$ROOT/scripts/run-scoped.sh; RP=$ROOT/bin/run-probe; tmp=$(mktemp -d); T=$tmp; trap 'rm -rf "$tmp"' EXIT
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
mkdir -p "$tmp/noguard" "$tmp/.land/tool/bin"; cp "$RS" "$tmp/noguard/run-scoped.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/.land/tool/bin/no-build-guard"; chmod +x "$tmp/.land/tool/bin/no-build-guard"; marker_on
runs "self-test: a helper whose guard does nothing starts the command (the check can fail)" env_clean "$tmp/noguard/run-scoped.sh" g 10 touch "$tmp/ran"
# 3. run-probe
if command -v cc >/dev/null; then
  marker_on;  refused "run-probe, marker" env_clean "$RP" touch "$tmp/ran"
  marker_off; runs "run-probe, no marker" env_clean "$RP" touch "$tmp/ran"
else fail "run-probe: no C compiler (the preload needs one): the case cannot run"; fi
# 4. the lint: a repository fixture
marker_off; fx=$tmp/fx; mkdir -p "$fx/scripts" "$fx/$LAND_DIR/bin" "$fx/$LAND_DIR/lib"; git -C "$fx" init -q
cp "$G" "$fx/$LAND_DIR/bin/"; cp "$ROOT/lib/no-build-host.sh" "$fx/$LAND_DIR/lib/"; cp "$RS" "$fx/scripts/run-scoped.sh"
printf 'mutants.py\nself abi.sh\n' > "$fx/scripts/long-runners.txt"
printf '#!/usr/bin/env bash\n%s/bin/no-build-guard || exit 2\nexit 0\n' "$LAND_DIR" > "$fx/scripts/abi.sh"; chmod +x "$fx/scripts/abi.sh"
printf '#!/usr/bin/env bash\nscripts/run-scoped.sh mutants 3600 python3 scripts/mutants.py --jobs 4\nscripts/abi.sh\n' > "$fx/scripts/tier1.sh"
lintfx() { git -C "$fx" add -A >/dev/null; env_clean "$fx/$LAND_DIR/bin/no-build-guard" --lint "$fx"; }
expect_exit "lint: a repository that runs everything through the helper passes" 0 lintfx
printf '#!/usr/bin/env bash\npython3 scripts/mutants.py --jobs 4\n' > "$fx/scripts/tier1.sh"
expect_exit "lint: a direct call of a declared runner fails" 1 lintfx; out_has "runs mutants.py outside run-scoped.sh"
printf '#!/usr/bin/env bash\nmise exec -- scripts/mutants.py\n' > "$fx/scripts/tier1.sh"; expect_exit "lint: a mise-prefixed call fails" 1 lintfx
printf '#!/usr/bin/env bash\nscripts/run-scoped.sh mutants 3600 python3 scripts/mutants.py\n' > "$fx/scripts/tier1.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fx/scripts/abi.sh"; expect_exit "lint: a self runner with no guard call fails" 1 lintfx
printf '#!/usr/bin/env bash\n# %s/bin/no-build-guard\nexit 0\n' "$LAND_DIR" > "$fx/scripts/abi.sh"; expect_exit "lint: a guard call that is only a comment fails" 1 lintfx
printf '#!/usr/bin/env bash\n%s/bin/no-build-guard || exit 2\n' "$LAND_DIR" > "$fx/scripts/abi.sh"; expect_exit "lint: restored, passes again" 0 lintfx
cp "$RS" "$fx/scripts/run-scoped.sh"; grep -v 'no-build-guard' "$RS" > "$fx/scripts/run-scoped.sh"; chmod +x "$fx/scripts/run-scoped.sh"
expect_exit "lint: a helper without the guard fails" 1 lintfx; out_has "does not call no-build-guard"
# a helper that mentions the guard in a comment only, or calls it after it started something
sed 's|^"\$nbg" .*|# no-build-guard skipped|' "$RS" > "$fx/scripts/run-scoped.sh"; expect_exit "lint: a helper that finds the guard but never calls it fails (the marker probe starts the command)" 1 lintfx
cp "$RS" "$fx/scripts/run-scoped.sh"; rm "$fx/scripts/long-runners.txt"; printf 'mutants.py\n' > "$fx/scripts/heavy-runners.txt"; printf 'mutants.py\n' > "$fx/scripts/x.sh"
expect_exit "lint: scripts/heavy-runners.txt is read too" 1 lintfx
rm "$fx/scripts/run-scoped.sh" "$fx/scripts/x.sh"; expect_exit "lint: declared runners and no helper fails" 1 lintfx
expect_exit "lint: --selftest" 0 "$G" --selftest
finish
