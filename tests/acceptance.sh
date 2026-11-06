#!/usr/bin/env bash
# Acceptance step for a gate mechanism: ONE REAL APPROVAL END TO END ON THE REAL TREE (docs/gate-mechanism-acceptance.md). Run by hand before a gate mechanism is rolled, never from Tier 1.
# In a scratch CLONE of this repository (at REV, default HEAD) a real, well-formed approval line is committed into every approvals file the tree has or names, then the real Tier 1 runs on it: it must pass.
# A test that reads the real approvals file fails here, the first time, instead of at the first real approval. Usage: tests/acceptance.sh [REV]
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/.." && pwd); rev=${1:-HEAD}; d=$(mktemp -d "${TMPDIR:-/tmp}/vbm-land-accept.XXXXXX"); trap 'rm -rf "$d"' EXIT
git clone -q "$root" "$d/t"; git -C "$d/t" checkout -q "$(git -C "$root" rev-parse "$rev")"; git -C "$d/t" config commit.gpgsign false
cd "$d/t"; today=$(date -u +%F); h=$(printf '%s' "acceptance $rev" | sha256sum | cut -d' ' -f1)
files=$(git ls-files 'scripts/*approvals*.txt'; sed -n 's/^LAND_\(PROTECTED_\)\{0,1\}APPROVALS=//p' scripts/land.conf); files=$(printf '%s\n' scripts/gate-edit-approvals.txt scripts/protected-approvals.txt $files | sort -u)
for f in $files; do printf 'bin/land-direct | %s | acceptance: one real approval on the real tree | %s\n' "$h" "$today" >> "$f"; echo "record added to $f"; done
git add -A; git -c user.name=t -c user.email=t@example.invalid commit -qm "chore(approvals): acceptance record" -m "Task-ID: acceptance"
tests/run.sh && echo "ACCEPTANCE PASSED: the real Tier 1 is green with a real approval line in $(echo $files)"
