#!/usr/bin/env bash
# lib/no-crash-record.sh and bin/run-probe: the landing's crash check reads only crashes that BELONG TO THIS LANDING (its pid tree, session, own scope, own private dirs), and never another lane's; it fails closed;
# a deliberate-crash probe runs only under ulimit -c 0 PLUS the dumpable-clear preload and a private TMPDIR, and a probe without that is REFUSED. Records are fed through a journalctl shim (no real crash is ever left on the host).
. "$(dirname "$0")/lib.sh"
L=$ROOT/lib/no-crash-record.sh; RP=$ROOT/bin/run-probe; tmp=$(mktemp -d); trap 'kill $(jobs -p) $(cat "$tmp/g" "$tmp/sc" 2>/dev/null) 2>/dev/null || true; rm -rf "$tmp"' EXIT   # only the processes this test started
command -v jq >/dev/null && command -v cc >/dev/null || { echo "SKIPPED: needs jq and cc" >&2; exit 1; }
. "$L"
rec() {   # rec PID PPID SID CGROUP EXE [CMDLINE]: one journal record, the crash happening now
  jq -nc --arg pid "$1" --arg pp "$2" --arg sid "$3" --arg cg "$4" --arg exe "$5" --arg cmd "${6:-$5}" --arg ts "${REC_TS:-$(( $(date +%s) * 1000000 ))}" \
    '{MESSAGE_ID:"fc2e22bc6ee647b6b90729ab34a250b1",COREDUMP_PID:$pid,COREDUMP_PROC_STATUS:("Name:\tx\nPid:\t\($pid)\nPPid:\t\($pp)\nNSsid:\t\($sid)\n"),COREDUMP_CGROUP:$cg,COREDUMP_EXE:$exe,COREDUMP_TIMESTAMP:$ts,COREDUMP_CMDLINE:$cmd}'
}
shim() { { printf '#!/usr/bin/env bash\ncat <<"EOF"\n'; cat; printf 'EOF\n'; } > "$tmp/jc"; chmod +x "$tmp/jc"; }
export NOCRASH_JOURNALCTL=$tmp/jc
verdict() {   # verdict DESCRIPTION own|ignored: the shim holds the records on stdin; begin was done by the caller
  local d=$1 want=$2 rc=0; nocrash_end >"$tmp/o" 2>"$tmp/e" || rc=$?
  if [ "$want" = own ] && [ $rc = 1 ]; then pass "$d: fails (the landing's own crash)"; elif [ "$want" = ignored ] && [ $rc = 0 ]; then pass "$d: ignored"; else fail "$d: wanted $want, rc=$rc: $(cat "$tmp/e")"; fi
}
nocrash_begin 2>/dev/null   # a record is stamped with the time it is made (after the processes it names were born)
me=$$; mysid=$nocrash_sid
# 1. another lane's deliberate probe: foreign pid tree (parent 1), foreign session and scope, a fixed /tmp name: NOT this landing's
rec 4242424 1 4242000 /user.slice/app.slice/run-p1-i1.scope /tmp/abi_t "/tmp/abi_t /tmp/v.jsonl" | shim; verdict "another lane's /tmp/abi_t probe" ignored
# 2. its own tree: a direct child, a grandchild, a setsid child's child, a systemd-run scope child's child
sleep 40 >/dev/null 2>&1 & kid=$!; rec 4242425 $kid 4242000 /x/other.scope /tmp/x/t | shim; verdict "a crash whose parent is a child of the landing" own
bash -c 'sleep 40 & echo $! > "$1"; wait' _ "$tmp/g" >/dev/null 2>&1 & gk=$!; for _ in $(seq 50); do [ -s "$tmp/g" ] && break; sleep 0.1; done
rec 4242426 "$gk" 4242000 /x/other.scope /usr/bin/foo | shim; verdict "a crash inside a grandchild's tree" own
setsid bash -c 'sleep 40 & wait' >/dev/null 2>&1 & sk=$!; sleep 0.3
rec 4242427 "$sk" 4242001 /x/other.scope /usr/bin/foo | shim; verdict "a crash inside a setsid child of the landing (new session, same parent chain)" own
if systemd-run --user --scope --quiet true 2>/dev/null; then
  rm -f "$tmp/sc"; printf '#!/usr/bin/env bash\necho $$ > "$1"\nsleep 40 &\nwait\n' > "$tmp/scs"; chmod +x "$tmp/scs"   # (systemd-run rewrites a dollar in its own arguments: the script is a file)
  systemd-run --user --scope --quiet "$tmp/scs" "$tmp/sc" >/dev/null 2>&1 & ssk=$!
  for _ in $(seq 50); do [ -s "$tmp/sc" ] && break; sleep 0.1; done
  rec 4242428 "$(cat "$tmp/sc")" 4242002 /user.slice/run-r1.scope /usr/bin/foo | shim; verdict "a crash inside a systemd-run --scope child of the landing (another cgroup)" own
else pass "no systemd user manager here: the setsid and process-tree cases above stand for it"; fi
# 3. session, scope and private directories
rec 4242429 1 "$mysid" /x/other.scope /usr/bin/foo | shim; verdict "a crash in the landing's session whose parent is gone" own
nocrash_cg=/u/vbm-t-1-2.scope
rec 4242430 1 4242000 /u/vbm-t-1-2.scope /usr/bin/foo | shim; verdict "a crash in the landing's own scope" own
rec 4242430 1 4242000 /u/vbm-t-1-2.scope/sub.scope /usr/bin/foo | shim; verdict "a crash in a scope below the landing's" own
rec 4242431 1 4242000 /u/vbm-t-1-2.scopeX /usr/bin/foo | shim; verdict "a look-alike scope name" ignored
rec 4242432 1 4242000 /u/other.scope /usr/bin/foo | shim; verdict "another scope" ignored
nocrash_cg=/u/user@1000.service/init.scope; rec 4242433 1 4242000 /u/user@1000.service/init.scope /usr/bin/foo | shim; verdict "a shared init scope is never the landing's scope" ignored
nocrash_cg=; rec 4242434 1 4242000 "" /usr/bin/foo | shim; verdict "an EMPTY cgroup id matches nothing (and not everything): a foreign record with no cgroup" ignored
nocrash_tmp=$tmp/private; rec 4242435 1 4242000 /x/o.scope "$tmp/private/t/layout" | shim; verdict "an executable under the landing's private TMPDIR" own
rec 4242435 1 4242000 /x/o.scope /usr/bin/env "/usr/bin/env $tmp/private/t/layout" | shim; verdict "a command line under the landing's private TMPDIR" own
nocrash_tmp=; nocrash_repo=$tmp/repo; rec 4242436 1 4242000 /x/o.scope "$tmp/repo/build/probe" | shim; verdict "an executable under the repository" own
nocrash_repo=$(pwd -P)
# 4. forged or stale fields
export REC_TS=$(( $(date +%s) * 1000000 - 900000000 )); rec 4242437 "$me" "$mysid" /x/o.scope /usr/bin/foo | shim; nocrash_t0=$(( $(date +%s) - 3000 )); nocrash_sid=999999; verdict "a record older than begin is not read; a parent born after the crash is no ancestor (pid reuse)" ignored
nocrash_t0=$(( $(date +%s) - 3000 )); unset REC_TS; rec 4242443 "$me" 888888 /x/o.scope /usr/bin/foo | shim; verdict "(control: the same parent with a current time IS the landing's)" own
nocrash_rstart=1; rec 4242438 "$me" 888888 /x/o.scope /usr/bin/foo | shim; verdict "a reused root pid (different start time) is not the root" ignored
# 5. fail closed
unset REC_TS; nocrash_begin 2>/dev/null; nocrash_t0=; rec 1 1 1 /x /usr/bin/foo | shim; verdict "no begin state" own
nocrash_t0=junk; verdict "a bad time" own
nocrash_begin 2>/dev/null; nocrash_root=; nocrash_cg=; rec 4242439 1 4242000 /x/o.scope /tmp/abi_t | shim; verdict "no scope id at all: the broad old filter applies (a /tmp executable fails)" own
rec 4242440 1 4242000 /x/o.scope /usr/bin/firefox | shim; verdict "no scope id: an executable outside /tmp and the repository is still ignored" ignored
# 6. the wrapper: state in a file, the CALLER is the root (a driver process calls begin, then end, like a Tier 1 script does)
unset REC_TS; export TMPDIR=$tmp; export -f rec shim; export tmp ROOT
bash -c 'cd "$ROOT"; w=$ROOT/bin/no-crash-record; "$w" begin 2>/dev/null; echo "root=$(sed -n "s/^root=//p" "$tmp/no-crash-record.state") me=$$"
  rec 4242441 1 4242000 /x/o.scope /tmp/abi_t | shim; "$w" end >/dev/null 2>&1; echo "foreign=$?"
  rec 4242442 $$ 4242000 /x/o.scope /usr/bin/foo | shim; "$w" end >/dev/null 2>&1; echo "own=$?"
  rm -f "$tmp/no-crash-record.state"; "$w" end >/dev/null 2>&1; echo "nostate=$?"' > "$tmp/drv" 2>&1
r=$(sed -n 's/^root=\([0-9]*\) me=.*/\1/p' "$tmp/drv"); m=$(sed -n 's/.* me=//p' "$tmp/drv"); [ -n "$r" ] && [ "$r" = "$m" ] && pass "the root is the calling process" || fail "root '$r' is not the caller '$m'"
grep -qx 'foreign=0' "$tmp/drv" && pass "end passes with only a foreign crash" || fail "end failed on a foreign crash"
grep -qx 'own=1' "$tmp/drv" && pass "end fails with the landing's own crash (the pid tree)" || fail "end passed with the landing's own crash"
grep -qx 'nostate=1' "$tmp/drv" && pass "end without a state file fails (closed)" || fail "end passed without a state file"
unset NOCRASH_JOURNALCTL
# 7. bin/run-probe: refusals, private TMPDIR, no record for a real crash
printf '#include <stdlib.h>\nint main(int c, char **v) { if (c > 1) abort(); *(volatile int *)0 = 1; return 0; }\n' > "$tmp/c.c"; cc -o "$tmp/crash" "$tmp/c.c"
unset TMPDIR; T=$tmp
expect_exit "a probe without ulimit -c 0 is refused by --require" 2 bash -c "ulimit -c unlimited; '$RP' --require"; out_has "REFUSED"
expect_exit "a faked marker does not help: core limit not 0 is refused" 2 bash -c "ulimit -c unlimited; RUN_PROBE_ACTIVE=1 '$RP' --require"
expect_exit "a faked marker with limit 0 but no preload is refused" 2 bash -c "ulimit -c 0; RUN_PROBE_ACTIVE=1 '$RP' --require"
expect_exit "a helper call that raises the core limit (flag) is refused, nothing runs" 2 "$RP" --core-limit unlimited touch "$tmp/ran"; check "(and the probe did not run)" test ! -e "$tmp/ran"
expect_exit "a helper call that raises the core limit (environment) is refused" 2 env RUN_PROBE_CORE_LIMIT=1 "$RP" touch "$tmp/ran"; check "(and the probe did not run either)" test ! -e "$tmp/ran"
expect_exit "run-probe without a command is a usage error" 2 "$RP"
expect_exit "inside run-probe the probe is verified: --require passes" 0 "$RP" "$RP" --require
expect_exit "the probe gets a private TMPDIR, not a fixed name" 0 "$RP" bash -c 'case $TMPDIR in */run-probe.*) [ -d "$TMPDIR" ];; *) exit 1;; esac; echo "$TMPDIR" > "$1"' _ "$tmp/td"
check "(and it is removed afterwards)" test ! -e "$(cat "$tmp/td")"
expect_exit "the probe runs with ulimit -c 0" 0 "$RP" bash -c '[ "$(ulimit -Sc)" = 0 ]'
t0=$(date +%s); rc=0; "$RP" "$tmp/crash" 2>/dev/null || rc=$?; [ $rc = 139 ] && pass "a deliberate SIGSEGV under run-probe exits 139" || fail "SIGSEGV exit $rc"
rc=0; "$RP" "$tmp/crash" abort 2>/dev/null || rc=$?; [ $rc = 134 ] && pass "a deliberate SIGABRT under run-probe exits 134" || fail "SIGABRT exit $rc"
if command -v journalctl >/dev/null; then sleep 3; n=$(journalctl -o json --no-pager --since "@$t0" MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 2>/dev/null | jq -r 'select((.COREDUMP_EXE // "") | test("/crash$")) | .COREDUMP_PID' | wc -l); [ "$n" = 0 ] && pass "and the real journal has no record of either crash" || fail "a run-probe crash left $n record(s)"; fi
# 8. the lint: a probe binary named in the list and run outside the helper is found
mkdir -p "$tmp/r/scripts"; git -C "$tmp/r" init -q; printf 'abi_t\n' > "$tmp/r/scripts/probes.txt"
printf '#!/usr/bin/env bash\n/tmp/abi_t /tmp/v.jsonl\n' > "$tmp/r/scripts/bad.sh"; git -C "$tmp/r" add -A
expect_exit "lint: a probe run outside the helper fails" 1 "$RP" --lint scripts/probes.txt "$tmp/r"; out_has "bad.sh:2"
printf '#!/usr/bin/env bash\nscripts/land/bin/run-probe "$D/abi_t" /tmp/v.jsonl\n' > "$tmp/r/scripts/bad.sh"; git -C "$tmp/r" add -A
expect_exit "lint: the same call through the helper passes" 0 "$RP" --lint scripts/probes.txt "$tmp/r"
printf '#!/usr/bin/env bash\n"$D/abi_t" x   # probe-ok: not a crash\n' > "$tmp/r/scripts/bad.sh"; git -C "$tmp/r" add -A
expect_exit "lint: an explicit probe-ok marker is allowed" 0 "$RP" --lint scripts/probes.txt "$tmp/r"
finish
