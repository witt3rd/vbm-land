#!/usr/bin/env bash
# land-pin tree and verify (docs/pin.md): the tree hash against a golden vector computed independently of the tool, and every refusal of section 5 with a negative case.
# vendor, online and list have their own tests when they land (the build order of docs/pin.md section 7).
. "$(dirname "$0")/lib.sh"
sandbox
C=$T/c; GOLD=f3e9efef2e6b617c7effdee61b5e52eaf808d542e2acdd8879c6f260574148b4; REV=$(printf 'a%.0s' $(seq 40))
pin() { LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" "$@"; }
lock() { echo "libx https://example.invalid/libx v1.2.3 $REV $1" > "$C/$LAND_PINS_FILE"; }
fresh() {   # a repository vendoring libx (two files and Lake build products, which must not count), locked at the golden hash
  rm -rf "$C"; mkdir -p "$C/$LAND_HOME" "$C/vendor/libx/d" "$C/vendor/libx/.lake/build"
  printf 'hello\n' > "$C/vendor/libx/a.txt"; printf 'world\n' > "$C/vendor/libx/d/b.txt"; echo junk > "$C/vendor/libx/.lake/build/x.o"; lock "$GOLD"
}
badlock() { fresh; printf '%s\n' "$1" > "$C/$LAND_PINS_FILE"; expect_exit "malformed lock refused: $2" 2 pin verify; }

echo "## the tree hash"
fresh
check "the golden vector (computed independently): $GOLD" test "$(pin tree "$C/vendor/libx")" = "$GOLD"
echo more > "$C/vendor/libx/.lake/build/y.o"; mkdir -p "$C/vendor/libx/.git"; echo x > "$C/vendor/libx/.git/HEAD"
check "files under .lake and .git do not change it" test "$(pin tree "$C/vendor/libx")" = "$GOLD"
echo x >> "$C/vendor/libx/a.txt"; check "an edited file changes it" test "$(pin tree "$C/vendor/libx")" != "$GOLD"
fresh; echo x > "$C/vendor/libx/new.txt"; check "an added file changes it" test "$(pin tree "$C/vendor/libx")" != "$GOLD"
fresh; rm "$C/vendor/libx/a.txt"; check "a deleted file changes it" test "$(pin tree "$C/vendor/libx")" != "$GOLD"
fresh; mv "$C/vendor/libx/a.txt" "$C/vendor/libx/c.txt"; check "a renamed file changes it" test "$(pin tree "$C/vendor/libx")" != "$GOLD"
fresh; ln -s a.txt "$C/vendor/libx/link"; expect_exit "a symlink is refused" 1 pin tree "$C/vendor/libx"; out_has "not a regular file"
fresh; echo x > "$C/vendor/libx/a\\b.txt"; expect_exit "a path with a backslash is refused (sha256sum escapes it: never a silently different hash)" 1 pin tree "$C/vendor/libx"; out_has "unsafe path"
fresh; echo x > "$C/vendor/libx/$(printf 'a\nb.txt')"; expect_exit "a path with a newline is refused" 1 pin tree "$C/vendor/libx"; out_has "unsafe path"
GOLD2=ebad6abee300d1f575db30b0ac5d0bfbce7acc54ab394b2d743e1ab2f301e007   # five files with awkward names (a space, a #, non-ASCII, <angle brackets>, an uppercase name), computed independently with Python: lines sorted by BYTES
rm -rf "$T/odd"; mkdir -p "$T/odd/d"; printf 'hello\n' > "$T/odd/a b.txt"; printf 'world\n' > "$T/odd/n_structure_trailing_#.json"; printf 'x\n' > "$T/odd/é.txt"; printf 'y\n' > "$T/odd/d/<angle>.txt"; printf 'z\n' > "$T/odd/Z.txt"
check "awkward but legal names (a space, #, non-ASCII, <>) hash to the independently computed vector: $GOLD2" test "$(pin tree "$T/odd")" = "$GOLD2"
expect_exit "a missing directory is refused" 1 pin tree "$C/nothing"
expect_exit "tree without a directory is a usage error" 2 pin tree

echo "## verify: accepted"
fresh; expect_exit "a vendored, locked library with build products under .lake is accepted" 0 pin verify; out_has "pin libx v1.2.3"
rm -rf "$C"; mkdir -p "$C"; expect_exit "no lock and no vendor directory is an empty lock: accepted" 0 pin verify

echo "## verify: refused"
fresh; echo x >> "$C/vendor/libx/a.txt"; expect_exit "an edited vendored file is refused" 1 pin verify; out_has "libx: the tree hash"
fresh; echo x > "$C/vendor/libx/new.txt"; expect_exit "an added file is refused" 1 pin verify
fresh; rm "$C/vendor/libx/d/b.txt"; expect_exit "a deleted file is refused" 1 pin verify
fresh; ln -s a.txt "$C/vendor/libx/link"; expect_exit "a symlink in a vendored library is refused" 1 pin verify
fresh; mkdir -p "$C/vendor/liby"; echo y > "$C/vendor/liby/f"; expect_exit "a vendored library with no lock line is refused" 1 pin verify; out_has "liby: vendor/liby is vendored but not in the lock"
fresh; rm -rf "$C/vendor/libx"; expect_exit "a lock line with no vendored directory is refused" 1 pin verify; out_has "libx: vendor/libx is missing"
fresh; lock "$(printf 'b%.0s' $(seq 64))"; expect_exit "a flipped lock hash is refused" 1 pin verify
fresh; echo x > "$C/vendor/libx/a\\b.txt"; expect_exit "an unsafe path in a vendored library is refused" 1 pin verify

echo "## verify: one version of each library in the closure"
fresh; mkdir -p "$C/vendor/libx/vendor/libz"; echo z > "$C/vendor/libx/vendor/libz/f"; mkdir -p "$C/vendor/liby/vendor/libz"; echo z > "$C/vendor/liby/vendor/libz/f"
H=$(pin tree "$C/vendor/libx"); lock "$H"; echo "liby https://example.invalid/liby v1.0.0 $REV $(pin tree "$C/vendor/liby")" >> "$C/$LAND_PINS_FILE"
expect_exit "the same nested library at two depths, identical: accepted" 0 pin verify
echo changed > "$C/vendor/liby/vendor/libz/f"; echo "liby https://example.invalid/liby v1.0.0 $REV $(pin tree "$C/vendor/liby")" > "$T/l2"; { head -n1 "$C/$LAND_PINS_FILE"; cat "$T/l2"; } > "$T/l3"; cp "$T/l3" "$C/$LAND_PINS_FILE"
expect_exit "the same nested library with different content at two depths (a diamond): refused" 1 pin verify; out_has "libz: copies of it differ in the closure"

echo "## verify: the lock is read strictly"
badlock "libx https://e.invalid/x v1.2.3 $REV" "four fields"
badlock "libx https://e.invalid/x v1.2.3 $REV $GOLD extra" "six fields"
badlock "Libx https://e.invalid/x v1.2.3 $REV $GOLD" "an uppercase name"
badlock "../x https://e.invalid/x v1.2.3 $REV $GOLD" "an unsafe name"
badlock "libx https://e.invalid/x 1.2.3 $REV $GOLD" "a tag without the v"
badlock "libx https://e.invalid/x v1.2.3 abc123 $GOLD" "a short rev"
badlock "libx https://e.invalid/x v1.2.3 $REV abc123" "a short hash"
badlock "$(printf 'libx https://e.invalid/x v1.2.3 %s %s\nlibx https://e.invalid/x v1.2.4 %s %s' "$REV" "$GOLD" "$REV" "$GOLD")" "a duplicate name"
fresh; printf '# a comment\n\nlibx https://e.invalid/x v1.2.3 %s %s  # trailing\n' "$REV" "$GOLD" > "$C/$LAND_PINS_FILE"; expect_exit "comments and blank lines are allowed" 0 pin verify
finish
