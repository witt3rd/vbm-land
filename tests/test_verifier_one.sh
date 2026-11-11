#!/usr/bin/env bash
# One verifier (docs/payload.md 6a): lib/verify.sh is the only code that verifies a release tag and hashes a tree. `install` must run without a checkout, so it embeds that file; this test fails when the copy differs
# and when any other file grows a verifier of its own.
. "$(dirname "$0")/lib.sh"
sandbox
embedded() { sed -n '/^# VERIFIER BEGIN/,/^# VERIFIER END/p' "$1" | sed '1d;$d'; }
same() { [ "$(embedded "$1")" = "$(cat "$ROOT/lib/verify.sh")" ]; }
check "install embeds lib/verify.sh verbatim" same "$ROOT/install"
cp "$ROOT/install" "$T/install.drift"; sed -i 's/^src_verify() {/src_verify() { :;/' "$T/install.drift"
check "the comparison catches a drifted copy (negative self-test)" bash -c '! { [ "$(sed -n "/^# VERIFIER BEGIN/,/^# VERIFIER END/p" "$1" | sed "1d;\$d")" = "$(cat "$2")" ]; }' _ "$T/install.drift" "$ROOT/lib/verify.sh"
only=$(cd "$ROOT" && grep -l -E 'verify-tag|allowedSignersFile' bin/* lib/*.sh install 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
check "no verifier outside lib/verify.sh and its embedded copy in install (found: $only)" test "$only" = "install lib/verify.sh "
only=$(cd "$ROOT" && grep -l -E '^tree_hash\(\)' bin/* lib/*.sh install 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
check "no tree hash outside lib/verify.sh and its embedded copy (found: $only)" test "$only" = "install lib/verify.sh "
want=$(. "$ROOT/lib/paths.sh"; printf 'LAND_SIGNERS_FILE=%s; LAND_LEGACY_SIGNERS_FILE=%s' "$LAND_SIGNERS_FILE" "$LAND_LEGACY_SIGNERS_FILE")
check "install's trust anchor (where the signers file lives) equals lib/paths.sh: $want" grep -qxF "$want" "$ROOT/install"
check "install reads the release's lib/paths.sh only AFTER it verifies" bash -c "[ \$(grep -n 'src_verify \"\$tmp/src\"' '$ROOT/install' | head -n1 | cut -d: -f1) -lt \$(grep -n 'show \"\$commit:lib/paths.sh\"' '$ROOT/install' | head -n1 | cut -d: -f1) ]"
finish
