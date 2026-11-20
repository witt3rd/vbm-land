#!/usr/bin/env bash
# land-secrets (docs/secrets-gate.md): the secret gate the tool ships. Tested at its boundary with a STUB scanner named gitleaks (first on PATH), so the test needs no real scanner: the stub exits 1 when
# what it is asked to scan holds a marker string, 0 otherwise, records its arguments, and prints the marker itself unless it was given --redact (so "the output never carries the secret" is a real check).
# Proved: clean 0; a marked file 1 with the rotate-first sentence and not the marker; a marker in an old commit gone from the tree still 1 (the history is scanned); a missing config 2; a missing scanner 2
# (fail closed); the scanner is always given --redact; --staged passes the pre-commit mode; the self-test passes with the honest stub and FAILS with a blind one (the negative self-test WATCHED to fail);
# the runner order (flag, environment, mise, bare); the pre-commit hook template (refuses a staged secret, commits a clean change, fails closed). One case runs the real gitleaks only when `gitleaks version` runs (a shim that cannot run, or no gitleaks, is a stated skip, never a failure).
. "$(dirname "$0")/lib.sh"
sandbox
real=$(command -v gitleaks 2>/dev/null || true); REALPATH=$PATH
MARK=MARKER-LEAK-0042
cat > "$T/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
# stub scanner: gitleaks git [--pre-commit --staged] | dir PATH, then --redact --no-banner --config FILE
echo "$*" >> "${STUB_LOG:?}"
[ "${STUB_MODE:-}" != fail ] || { echo "stub: broke" >&2; exit 2; }
[ "${STUB_MODE:-}" != fatal ] || { echo "9:00AM FTL failed to load config" >&2; exit 1; }
[ "${STUB_MODE:-}" != blind ] || exit 0
[ "${STUB_MODE:-}" != wolf ] || { echo "Finding: REDACTED"; exit 1; }
red=0; for a in "$@"; do [ "$a" != --redact ] || red=1; done
pat='MARKER-LEAK-0042|ghp_[A-Za-z0-9]{36}'
case $1 in
  dir) hit=$(grep -rEho "$pat" -- "$2" || true);;
  git) if [[ " $* " == *" --staged "* ]]; then hit=$(git diff --cached -U0 | grep -Eo "$pat" || true); else hit=$(git log --all -p 2>/dev/null | grep -Eo "$pat" || true); fi;;
  *) exit 2;;
esac
[ -n "$hit" ] || exit 0
if [ "$red" = 1 ]; then echo "Finding: REDACTED"; else echo "Secret: $hit"; fi
exit 1
STUB
chmod +x "$T/bin/gitleaks"
export STUB_LOG=$T/args.log; : > "$STUB_LOG"
R=$T/repo; git init -q -b main "$R"; git -C "$R" config commit.gpgsign false
printf '[extend]\nuseDefault = true\n' > "$R/.gitleaks.toml"
printf 'hello\n' > "$R/a.txt"; git -C "$R" add -A; git -C "$R" commit -qm "chore: clean"
ls_() { ( cd "$R" && "$ROOT/bin/land-secrets" "$@" ); }
nomark() { ! grep -q -- "$MARK" "$T/out" && pass "the output does not carry the secret" || { fail "the output carries the secret"; }; }

echo "## default: history, then tree"
expect_exit "a clean repository passes" 0 ls_; out_has "ok"
grep -q '^git \. ' "$STUB_LOG" && grep -q '^dir \. ' "$STUB_LOG" && pass "both the history (git) and the tree (dir) were scanned" || fail "history and tree were not both scanned"
check "every scanner call carries --redact --no-banner --config" bash -c '! grep -vq -e "--redact" -e "^$" "$1" && ! grep -vq -e "--no-banner --config" -e "^$" "$1"' _ "$STUB_LOG"
echo "$MARK" > "$R/leak.txt"
expect_exit "a marked file in the tree fails" 1 ls_; out_has "rotate it first, then remove it; never allowlist a real one"; nomark
git -C "$R" add -A; git -C "$R" commit -qm "chore: leak"; git -C "$R" rm -q leak.txt; git -C "$R" commit -qm "chore: remove the leak"
check "the tree is clean again" test ! -e "$R/leak.txt"
expect_exit "a marker in an old commit, no longer in the tree, still fails (the history is scanned)" 1 ls_; out_has "history: a secret was found"; out_has "rotate it first"; nomark
expect_exit "it works from a subdirectory of the repository" 1 bash -c 'cd "$1/.." 2>/dev/null; mkdir -p "$1/sub"; cd "$1/sub" && "$2/bin/land-secrets"' _ "$R" "$ROOT"

echo "## --staged"
R2=$T/repo2; git init -q -b main "$R2"; git -C "$R2" config commit.gpgsign false; cp "$R/.gitleaks.toml" "$R2/"; echo hi > "$R2/a.txt"; git -C "$R2" add -A; git -C "$R2" commit -qm "chore: clean"
s2() { ( cd "$R2" && "$ROOT/bin/land-secrets" "$@" ); }
: > "$STUB_LOG"; expect_exit "--staged: nothing staged passes" 0 s2 --staged
grep -q -e '--pre-commit' "$STUB_LOG" && grep -q -e '--staged' "$STUB_LOG" && pass "--staged passes the scanner's pre-commit mode" || fail "--staged did not pass --pre-commit --staged"
check "--staged does not scan the whole history or the tree" bash -c '! grep -q "^dir" "$1"' _ "$STUB_LOG"
echo "$MARK" > "$R2/new.txt"; git -C "$R2" add new.txt
expect_exit "--staged: a staged marker fails" 1 s2 --staged; out_has "rotate it first"; nomark

echo "## fail closed: exit 2"
mv "$R/.gitleaks.toml" "$R/cfg.toml"
expect_exit "a missing configuration is exit 2 (never scanned with defaults)" 2 ls_; out_has "no scanner configuration"
expect_exit "--config FILE names another configuration" 1 ls_ --config cfg.toml
grep -q -e '--config '"$R"'/cfg.toml' "$STUB_LOG" && pass "the scanner was given the named configuration" || fail "the scanner was not given the --config path"
mv "$R/cfg.toml" "$R/.gitleaks.toml"; git -C "$R" rm -q --cached leak.txt 2>/dev/null || true
NG=$T/nogl; mkdir "$NG"; for c in git mktemp rm tail grep; do ln -s "$(command -v $c)" "$NG/$c"; done
expect_exit "a missing scanner is exit 2 (fail closed), and says so" 2 bash -c 'cd "$1" && PATH="$2" "$3" "$4/bin/land-secrets"' _ "$R2" "$NG" "$(command -v bash)" "$ROOT"; out_has "no scanner"
expect_exit "a scanner that breaks (exit 2) is exit 2" 2 env STUB_MODE=fail bash -c 'cd "$1" && "$2/bin/land-secrets"' _ "$R2" "$ROOT"; out_has "fails closed"
expect_exit "a scanner fatal error (exit 1 with a FTL line) is exit 2, not a finding" 2 env STUB_MODE=fatal bash -c 'cd "$1" && "$2/bin/land-secrets"' _ "$R2" "$ROOT"
expect_exit "outside a repository the history cannot be scanned: exit 2" 2 bash -c 'cd "$1" && "$2/bin/land-secrets"' _ "$T/tmp" "$ROOT"
expect_exit "an unknown option is a usage error" 2 ls_ --nope

echo "## the negative self-test"
expect_exit "--selftest passes with the honest scanner" 0 ls_ --selftest; out_has "ran: secrets-selftest: 2 cases"
expect_exit "--selftest FAILS with a scanner that finds nothing (watched to fail)" 1 env STUB_MODE=blind bash -c 'cd "$1" && "$2/bin/land-secrets" --selftest' _ "$R2" "$ROOT"; out_has "the gate is blind"
expect_exit "--selftest FAILS with a scanner that reports everything" 1 env STUB_MODE=wolf bash -c 'cd "$1" && "$2/bin/land-secrets" --selftest' _ "$R2" "$ROOT"; out_has "clean file was reported"
expect_exit "--selftest with a broken scanner is exit 2" 2 env STUB_MODE=fail bash -c 'cd "$1" && "$2/bin/land-secrets" --selftest' _ "$R2" "$ROOT"
check "--selftest leaves no temporary directory behind" bash -c '! ls "$1"/land-secrets* >/dev/null 2>&1' _ "$TMPDIR"
check "the planted token is not a literal in the tool's source" bash -c '! grep -Eq "ghp_[A-Za-z0-9]{36}" "$1/bin/land-secrets" "$1/tests/test_secrets.sh" "$1/docs/secrets-gate.md"' _ "$ROOT"

echo "## the runner order: flag, environment, mise, bare"
for n in a b; do printf '#!/usr/bin/env bash\necho "runner-%s" >> "$STUB_LOG"\nexec "$@"\n' "$n" > "$T/bin/runner-$n"; chmod +x "$T/bin/runner-$n"; done
printf '#!/usr/bin/env bash\necho "mise $*" >> "$STUB_LOG"\n[ "$1 $2" = "exec --" ] && shift 2\nexec "$@"\n' > "$T/bin/mise"; chmod +x "$T/bin/mise"
rm -f "$R2/new.txt"; git -C "$R2" reset -q; : > "$STUB_LOG"; expect_exit "bare: no runner, no mise.toml: the scanner on PATH" 0 s2 --config .gitleaks.toml --staged
grep -q 'runner-\|^mise' "$STUB_LOG" && fail "bare: a runner was used" || pass "bare: the scanner ran directly"
touch "$R2/mise.toml"; : > "$STUB_LOG"; expect_exit "mise.toml and mise on PATH: mise exec --" 0 s2 --staged; grep -q '^mise exec -- gitleaks' "$STUB_LOG" && pass "mise.toml present: the scanner ran through mise exec --" || fail "mise.toml present but mise was not the runner"
: > "$STUB_LOG"; LAND_SECRETS_RUNNER=runner-a expect_exit "the environment beats mise" 0 s2 --staged; grep -q '^runner-a' "$STUB_LOG" && ! grep -q '^mise' "$STUB_LOG" && pass "LAND_SECRETS_RUNNER named the runner" || fail "the environment did not beat mise"
: > "$STUB_LOG"; LAND_SECRETS_RUNNER=runner-a expect_exit "the flag beats the environment" 0 s2 --staged --runner runner-b; grep -q '^runner-b' "$STUB_LOG" && ! grep -q '^runner-a' "$STUB_LOG" && pass "--runner beat LAND_SECRETS_RUNNER" || fail "the flag did not beat the environment"
expect_exit "a runner that is not on PATH is exit 2" 2 s2 --staged --runner no-such-runner-xyz; out_has "not on PATH"

echo "## the pre-commit hook template (templates/pre-commit-secrets)"
H=$T/hookrepo; git init -q -b main "$H"; git -C "$H" config commit.gpgsign false
mkdir -p "$H/.githooks" "$H/.land/tool/bin"; cp "$ROOT/bin/land-secrets" "$H/.land/tool/bin/"; cp "$ROOT/templates/pre-commit-secrets" "$H/.githooks/pre-commit"; chmod +x "$H/.githooks/pre-commit"
cp "$R/.gitleaks.toml" "$H/"; echo hi > "$H/a.txt"; git -C "$H" config core.hooksPath .githooks
check "the template is executable" test -x "$ROOT/templates/pre-commit-secrets"
hc() { ( cd "$H" && git commit -q -m "$1" ); }
git -C "$H" add -A; expect_exit "a clean staged change commits" 0 hc "chore: clean"
check "the clean commit is in" test "$(git -C "$H" rev-list --count HEAD)" = 1
echo "$MARK" > "$H/leak.txt"; git -C "$H" add leak.txt
expect_exit "a staged marked file is refused" 1 hc "chore: leak"; out_has "Nothing was committed. Secrets live in doppler, never in a repository."; nomark
check "nothing was committed" test "$(git -C "$H" rev-list --count HEAD)" = 1
git -C "$H" rm -q -f --cached leak.txt; rm -f "$H/leak.txt"; echo more >> "$H/a.txt"; git -C "$H" add a.txt
expect_exit "a scanner that cannot run (exit 2) refuses the commit (fails closed)" 1 env STUB_MODE=fail bash -c 'cd "$1" && git commit -q -m x' _ "$H"; out_has "Nothing was committed"
NG2=$T/nogl2; mkdir "$NG2"; for c in git bash env mktemp rm tail grep cat dirname; do ln -s "$(command -v $c)" "$NG2/$c"; done
expect_exit "no scanner on PATH refuses the commit (fails closed)" 1 bash -c 'cd "$1" && PATH="$2" git commit -q -m x' _ "$H" "$NG2"; out_has "Nothing was committed"
mv "$H/.land/tool/bin/land-secrets" "$H/land-secrets.away"
expect_exit "a missing .land/tool refuses the commit (fails closed)" 1 hc "chore: x"; out_has "Nothing was committed"
mv "$H/land-secrets.away" "$H/.land/tool/bin/land-secrets"
check "the commit count is still one" test "$(git -C "$H" rev-list --count HEAD)" = 1
expect_exit "the hook commits again once the scanner is back" 0 hc "chore: more"
expect_exit "a commit made from a subdirectory runs from the top level" 0 bash -c 'cd "$1" && mkdir -p sub && echo s > sub/s.txt && git add sub/s.txt && cd sub && git commit -q -m sub' _ "$H"

echo "## the real scanner"
# Availability is decided by RUNNING the scanner (`gitleaks version`, bare on PATH, the runner the case uses), never by `command -v`: a mise shim with no version set is on PATH and cannot run.
# A case that cannot run is reported `skip NAME: REASON` (not a pass, not a failure: it adds nothing to the `ran: secrets: N cases` total).
gl_usable() {   # sets GL_WHY; returns 0 when `gitleaks version` exits 0 and prints a version
  local out rc=0
  if ! command -v gitleaks >/dev/null 2>&1; then GL_WHY="no gitleaks on PATH"; return 1; fi
  if command -v timeout >/dev/null 2>&1; then out=$(timeout 20 gitleaks version 2>&1) || rc=$?; else out=$(gitleaks version 2>&1) || rc=$?; fi
  if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Eq '^v?[0-9]+\.[0-9]+'; then GL_WHY=; return 0; fi
  GL_WHY="gitleaks is on PATH but cannot run: $(printf '%s\n' "$out" | head -n1)"; [ -n "$out" ] || GL_WHY="gitleaks is on PATH but cannot run: exit $rc, no output"; return 1
}
real_case() {
  if ! gl_usable; then echo "skip the real gitleaks: --selftest passes: $GL_WHY"; return 0; fi
  W=$T/realrepo; git init -q -b main "$W"; git -C "$W" config commit.gpgsign false; cp "$R/.gitleaks.toml" "$W/"; echo hi > "$W/a.txt"; git -C "$W" add -A; git -C "$W" commit -qm "chore: clean"
  expect_exit "the real gitleaks: --selftest passes (planted token found, clean file passes)" 0 bash -c 'cd "$1" && "$2/bin/land-secrets" --runner "" --selftest' _ "$W" "$ROOT"
}
PATH=$REALPATH; export PATH; rm -f "$T/bin/gitleaks" "$T/bin/mise"
real_case
BR=$T/brokengl; mkdir "$BR"; printf '#!/usr/bin/env bash\necho "mise ERROR No version is set for shim: gitleaks" >&2\necho "Set a global default version with one of the following:" >&2\nexit 1\n' > "$BR/gitleaks"; chmod +x "$BR/gitleaks"
sub_real_case() ( PATH="$BR:$REALPATH"; real_case )
expect_exit "a gitleaks shim that cannot run (exit 1, the mise error): the real-scanner case is skipped and the test is not failed (watched: the old command -v rule ran it and got exit 2)" 0 sub_real_case
out_has "skip the real gitleaks: --selftest passes: gitleaks is on PATH but cannot run: mise ERROR No version is set for shim: gitleaks"
check "the broken shim really is on PATH, and land-secrets fails closed on it (exit 2): the tool is right, only the availability rule was wrong" bash -c 'PATH="$1:$PATH"; command -v gitleaks | grep -q "$1" && cd "$2" && "$3/bin/land-secrets" --runner "" --selftest; [ $? = 2 ]' _ "$BR" "$R2" "$ROOT"
sub_no_gl() ( PATH="$NG"; real_case )
expect_exit "no gitleaks on PATH: the real-scanner case is skipped with its own reason" 0 sub_no_gl
out_has "skip the real gitleaks: --selftest passes: no gitleaks on PATH"
finish
