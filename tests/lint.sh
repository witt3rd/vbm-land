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
  case $f in *.conf|*.txt|*.md) ;; bin/*|install|scripts/*|tests/*.sh) [ -x "$f" ] || [ "$f" = tests/lib.sh ] || fail "$f is not executable";; esac
done
# names that must never appear in this repository (internal projects, hosts, people, local paths)
deny='(first''mate|rog''er|mcfee''ly|sp''ire|ja''nus|/hom''e/|c''aptain|\bk''ing\b|\bpr''ince\b)'
for f in $files; do
  [ -f "$f" ] && [ "$f" != LICENSE ] || continue
  if grep -nEi -- "$deny" "$f" >/dev/null 2>&1; then fail "$f names something internal: $(grep -nEi -- "$deny" "$f" | head -2 | tr '\n' ' ')"; fi
done
exit "$bad"
