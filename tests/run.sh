#!/usr/bin/env bash
# Tier 1 of this repository: the lints, then every tests/test_*.sh in parallel through the payload's own runner (bin/run-tests-parallel; docs/payload.md 4c), each script bounded at 300 s. Run from anywhere.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
"$here/lint.sh"
cd "$here/.."
TEST_JOBS=1000 TEST_TIMEOUT=300 exec bin/run-tests-parallel tests/test_*.sh
