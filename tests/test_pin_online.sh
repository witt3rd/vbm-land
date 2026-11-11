#!/usr/bin/env bash
# land-pin online and list (docs/pin.md section 4). online is the slow tier: it asks each locked library's remote whether the tag still points at the locked commit (a moved or deleted tag is a
# finding) and reports newer tags without applying them. list prints the locked names.
. "$(dirname "$0")/lib.sh"
sandbox
C=$T/c; O=$T/lib.git; W=$T/libw
pin() { LAND_PIN_ROOT=$C "$ROOT/bin/land-pin" "$@"; }
git init -q --bare -b main "$O"; git init -q -b main "$W"; git -C "$W" remote add origin "$O"; git -C "$W" config commit.gpgsign false
echo 1 > "$W/f"; git -C "$W" add -A; git -C "$W" commit -qm one; R1=$(git -C "$W" rev-parse HEAD)
git -C "$W" -c tag.gpgsign=false tag -a v1.0.0 -m one; git -C "$W" push -q origin main v1.0.0
echo 2 > "$W/f"; git -C "$W" commit -qam two; R2=$(git -C "$W" rev-parse HEAD)
H=$(printf 'a%.0s' $(seq 64))
mkdir -p "$C/$LAND_HOME"; lock() { echo "libx $O $1 $2 $H" > "$C/$LAND_PINS_FILE"; echo "liby https://example.invalid/liby v1.0.0 $R1 $H" >> "$C/$LAND_PINS_FILE"; }

echo "## list"
lock v1.0.0 "$R1"; expect_exit "list prints the locked names, one per line" 0 pin list; check "  libx then liby" test "$(cat "$T/out" | tr '\n' ' ')" = "libx liby "
rm "$C/$LAND_PINS_FILE"; expect_exit "list of no lock is empty" 0 pin list; check "  prints nothing" test ! -s "$T/out"

echo "## online"
echo "libx $O v1.0.0 $R1 $H" > "$C/$LAND_PINS_FILE"
expect_exit "the tag points at the locked commit: ok" 0 pin online; out_has "libx v1.0.0: ok"
echo "libx $O v1.0.0 $R2 $H" > "$C/$LAND_PINS_FILE"; expect_exit "the locked commit is not what the tag points at: refused" 1 pin online; out_has "points at $R1"
echo "libx $O v1.0.0 $R1 $H" > "$C/$LAND_PINS_FILE"
git -C "$W" -c tag.gpgsign=false tag -a v1.1.0 -m two "$R2"; git -C "$W" push -q origin v1.1.0
expect_exit "a newer tag is reported and never applied; still ok" 0 pin online; out_has "newer: v1.1.0"; check "  the lock is unchanged" grep -q " v1.0.0 $R1 " "$C/$LAND_PINS_FILE"
git -C "$W" -c tag.gpgsign=false tag -fa v1.0.0 -m moved "$R2"; git -C "$W" push -qf origin v1.0.0
expect_exit "a MOVED tag is refused" 1 pin online; out_has "points at $R2"
git -C "$O" tag -d v1.0.0 >/dev/null; expect_exit "a DELETED tag is refused" 1 pin online; out_has "does not exist"
echo "libx $T/nowhere.git v1.0.0 $R1 $H" > "$C/$LAND_PINS_FILE"; expect_exit "an unreachable remote is refused (the check could not be made)" 1 pin online; out_has "cannot reach"
rm "$C/$LAND_PINS_FILE"; expect_exit "no lock: nothing to check, ok" 0 pin online
finish
