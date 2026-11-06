#!/usr/bin/env bash
# Repository lints: every shell file parses; executables are executable; the repository stays free of internal names and local paths
# (it is meant to be public); no worktree prune and no force push in the tool itself.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"; bad=0
fail() { echo "lint: $*" >&2; bad=1; }
files=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*' | sed 's|^\./||')
for f in $files; do
  [ -f "$f" ] || continue
  if head -n1 "$f" | grep -q '^#!.*\(bash\|sh\)'; then bash -n "$f" || fail "$f does not parse"; fi
  case $f in *.conf|*.txt|*.md|*.signers) ;; bin/*|install|scripts/*|tests/*.sh) [ -x "$f" ] || [ "$f" = tests/lib.sh ] || fail "$f is not executable";; esac
done
# names that must never appear in this repository (internal projects, hosts, people, local paths)
deny='(first''mate|rog''er|mcfee''ly|sp''ire|ja''nus|/hom''e/|c''aptain|\bk''ing\b|\bpr''ince\b|fle''et|\blu''ng\b)'
for f in $files; do
  [ -f "$f" ] && [ "$f" != LICENSE ] || continue
  # while the repository is private, a workflow's self-hosted line (the runner label) is exempt; the flip-day change removes it
  src=$f; [ "$(cat .github/visibility 2>/dev/null)" = private ] && case $f in .github/workflows/*) src=/dev/stdin;; esac
  if [ "$src" = "$f" ]; then hits=$(grep -nEi -- "$deny" "$f" || true); else hits=$(grep -v 'self-hosted' "$f" | grep -nEi -- "$deny" || true); fi
  if [ -n "$hits" ]; then fail "$f names something internal: $(echo "$hits" | tr '\n' ' ' | cut -c1-200)"; fi
done
# a workflow may name a self-hosted runner only while .github/visibility says exactly "private" (missing or anything else = public)
if grep -lE 'self-hosted' .github/workflows/* >/dev/null 2>&1 && [ "$(cat .github/visibility 2>/dev/null)" != private ]; then fail "a workflow names self-hosted but .github/visibility is not 'private': runs-on back to hosted before going public"; fi
# under `set -o pipefail` a producer piped into an early-exiting consumer (`grep -q`, `grep -m`, `head`) can die of SIGPIPE: capture then test, or let the consumer drain the pipe (a repository that vendors this tool lints for it too)
hits=$(grep -nE '\|[[:space:]]*(grep[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--max-count)([[:space:]]|=)|head([[:space:]]|$))' bin/* lib/*.sh install 2>/dev/null | grep -v 'pipefail-ok' || true)
[ -z "$hits" ] || fail "a pipe into an early-exiting consumer (SIGPIPE under pipefail): $(echo "$hits" | head -2 | tr '\n' ' ')"
# the lander takes no lock (0.5.0): no flock, lease, lock file, held descriptor or "busy" exit in bin/ and lib/ (scripts/bootstrap-land, the single-lander recovery tool, keeps its own). tests/test_harness.sh proves this check can fail.
hits=$(grep -nE 'flock|lease_|exec [0-9]+>|(stop|exit) 15([^0-9]|$)|/lock([^A-Za-z]|$)' bin/* lib/*.sh install 2>/dev/null || true)
[ -z "$hits" ] || fail "a lock is back in the lander (the push is the only arbiter): $(echo "$hits" | head -2 | tr '\n' ' ' | cut -c1-200)"
# a test builds its OWN world: it never reads the real repository's approvals, protected list, baselines, config or tags (a test that did failed the first real approval). tests/test_harness.sh proves this check can fail.
hits=$(grep -nE '(\$\{?(ROOT|root|here)\}?|\.\./)[^ "]*(approvals|protected-paths|baseline|known-flaky|land\.conf|land\.signers)|git +-C +"?\$\{?(ROOT|root)\}?"? +(tag|log|show|describe|rev-parse|ls-files|cat-file|for-each-ref|diff)|(cat|grep|sed|head|tail|wc|source|\.) +[^|;&]*(^| |")scripts/[a-z.-]*(approvals|protected-paths)' tests/lib.sh tests/test_*.sh || true)
[ -z "$hits" ] || fail "a test reads the real repository's approvals, protected list, baselines, config or tags (build a scratch world instead): $(echo "$hits" | head -2 | tr '\n' ' ' | cut -c1-200)"
# the heavy-host guard: this repository's own helper carries it, refuses with a marker present, and the vendored template is that helper
bin/no-build-guard --selftest >/dev/null && bin/no-build-guard --lint . >/dev/null || fail "the heavy-host guard lint (bin/no-build-guard --lint .) fails"
cmp -s scripts/run-scoped.sh templates/run-scoped.sh || fail "templates/run-scoped.sh differs from scripts/run-scoped.sh (the template is the helper a consumer copies)"
exit "$bad"
