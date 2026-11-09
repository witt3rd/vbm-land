#!/usr/bin/env bash
# A PUBLIC source needs no credentials: install, land-check --upstream and land-update --check clone OWNER/NAME anonymously over https (here: a local http server standing for it), with no token in the environment and a `gh` that always
# fails (a hosted runner without a login: the failure that made the upstream check red in a consumer's manual Tier 2). A private source still works through gh, and an unreachable one says what it needs.
. "$(dirname "$0")/lib.sh"
sandbox
S=$T/srcwork; mkdir -p "$S"; ( cd "$ROOT" && cp -r bin lib docs templates skills install VERSION "$S/" )
( cd "$S" && git init -q -b main && git config commit.gpgsign false && echo 1.0.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release 1.0.0" && git tag -a v1.0.0 -m v1.0.0 )
mkdir -p "$T/www/acme"; git clone -q --bare "$S" "$T/www/acme/tool.git"; git -C "$T/www/acme/tool.git" update-server-info
( cd "$T/www" && exec python3 -u -m http.server 0 --bind 127.0.0.1 >"$T/www.log" 2>&1 ) & srv=$!; trap 'kill $srv 2>/dev/null; rm -rf "${SANDBOXES[@]}" "$RESULTS"' EXIT
port=; for _ in $(seq 50); do port=$(sed -n 's/.*port \([0-9]*\).*/\1/p' "$T/www.log" | sed -n 1p); [ -n "$port" ] && break; sleep 0.1; done
[ -n "$port" ] || { fail "the local server did not start"; finish; exit 1; }
printf '#!/usr/bin/env bash\necho "gh: not logged in" >&2\nexit 1\n' > "$T/gh-none"; chmod +x "$T/gh-none"
anon() { env -u GH_TOKEN -u GITHUB_TOKEN -u VBM_LAND_TOKEN GH="$T/gh-none" VBM_LAND_URL_BASE="http://127.0.0.1:$port" HOME="$T/h" XDG_CONFIG_HOME="$T/h/c" "$@"; }
mkdir -p "$T/h"
git init -q -b main "$T/c"; git -C "$T/c" config commit.gpgsign false
expect_exit "install from a public source with no token and a gh that fails" 0 anon "$S/install" --source acme/tool --target "$T/c" v1.0.0
out_has "vendored into"
expect_exit "land-check --upstream reaches the public source with no token" 0 anon "$T/c/$LAND_DIR/bin/land-check" --upstream --root "$T/c"; out_has "the source confirms the manifest"
expect_exit "land-update --check reaches it too (current)" 0 anon "$T/c/$LAND_DIR/bin/land-update" --check --root "$T/c"
( cd "$S" && echo 1.1.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release 1.1.0" && git tag -a v1.1.0 -m v1.1.0 ); git -C "$S" push -q "$T/www/acme/tool.git" main v1.1.0 2>&1 | grep -v '^$' || true; git -C "$T/www/acme/tool.git" update-server-info
expect_exit "land-update --check sees the new release, anonymously (behind: exit 1)" 1 anon "$T/c/$LAND_DIR/bin/land-update" --check --root "$T/c"; out_has "v1.1.0"
# THE SIGNATURE STAYS MANDATORY on the anonymous path: with a signers file, an unsigned, lightweight, wrongly-signed or manifest-tampered tag served over the same anonymous https is REFUSED and writes nothing; a good one passes (control)
K=$T/keys; mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -f "$K/maint" -C maint; ssh-keygen -q -t ed25519 -N '' -f "$K/rogue" -C rogue; echo "maint $(cut -d' ' -f1,2 "$K/maint.pub")" > "$K/signers"
( cd "$S" && echo 2.0.0 > VERSION && bin/land-manifest >/dev/null && git add -A && git commit -qm "chore: release 2.0.0" && m=$(sha256sum < MANIFEST.sha256 | cut -d' ' -f1) \
  && git -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s v2.0.0 -m "tool v2.0.0" -m "manifest_sha256=$m" \
  && git -c gpg.format=ssh -c user.signingkey="$K/rogue" tag -s v2.1.0 -m "tool v2.1.0" -m "manifest_sha256=$m" \
  && git tag v2.2.0 \
  && git -c gpg.format=ssh -c user.signingkey="$K/maint" tag -s v2.3.0 -m "tool v2.3.0" -m "manifest_sha256=$(printf x | sha256sum | cut -d' ' -f1)" \
  && git tag -a v2.4.0 -m "tool v2.4.0 unsigned" && git push -q "$T/www/acme/tool.git" main --tags ); git -C "$T/www/acme/tool.git" update-server-info
for t in v2.1.0:"signed by an unknown signer" v2.2.0:"a lightweight tag" v2.3.0:"a signed tag recording the wrong manifest" v2.4.0:"an unsigned annotated tag"; do
  git init -q -b main "$T/n${t%%:*}"; expect_exit "anonymous install REFUSES ${t#*:}" 1 anon "$S/install" --source acme/tool --target "$T/n${t%%:*}" --signers "$K/signers" "${t%%:*}"; out_has "REFUSED"
  check "(and wrote nothing: no $LAND_DIR)" test ! -e "$T/n${t%%:*}/$LAND_DIR"
done
git init -q -b main "$T/ng"; expect_exit "control: anonymous install of the properly signed tag passes with the signers file" 0 anon "$S/install" --source acme/tool --target "$T/ng" --signers "$K/signers" v2.0.0; out_has "verified: tag v2.0.0"
cp "$K/signers" "$T/c/$LAND_SIGNERS_FILE"
for t in v2.1.0 v2.2.0 v2.3.0 v2.4.0; do before=$(cat "$T/c/$LAND_PIN"); expect_exit "anonymous land-update to $t is REFUSED (signers file present)" 1 anon "$T/c/$LAND_DIR/bin/land-update" "$t" --root "$T/c"; out_has "REFUSED"; [ "$before" = "$(cat "$T/c/$LAND_PIN")" ] && pass "(the pin is untouched)" || fail "the pin changed on a refused update"; done
# negative: nothing reachable and no login: exit 3 and the message names what a private source needs
expect_exit "an unreachable source is exit 3 (not verified), never a pass" 3 env -u GH_TOKEN -u GITHUB_TOKEN GH="$T/gh-none" VBM_LAND_URL_BASE="http://127.0.0.1:1" "$T/c/$LAND_DIR/bin/land-check" --upstream --root "$T/c"; out_has "read token"
# a private source: anonymous fails (404), gh succeeds
printf '#!/usr/bin/env bash\n[ "$1 $2" = "repo clone" ] && exec git clone -q --bare -- "%s" "$4"\nexit 1\n' "$T/www/acme/tool.git" > "$T/gh-ok"; chmod +x "$T/gh-ok"
expect_exit "a private source still works through gh when the anonymous clone fails" 0 env GH="$T/gh-ok" VBM_LAND_URL_BASE="http://127.0.0.1:1" "$T/c/$LAND_DIR/bin/land-check" --upstream --root "$T/c"
# the real thing, when the network allows: the public vbm-land over https, no credentials
if timeout 20 git -c credential.helper= ls-remote https://github.com/witt3rd/vbm-land.git HEAD >/dev/null 2>&1; then
  . "$ROOT/lib/source.sh"; c=$(env -u GH_TOKEN -u GITHUB_TOKEN GH=false GIT_TERMINAL_PROMPT=0 HOME="$T/h" bash -c '. "$1"; src_fetch witt3rd/vbm-land HEAD "$2"' _ "$ROOT/lib/source.sh" "$T/live" 2>&1) && [[ "$c" =~ ^[0-9a-f]{40}$ ]] && pass "live: witt3rd/vbm-land cloned anonymously over https (no token, gh unavailable)" || fail "live anonymous clone failed: $c"
else echo "note: the live https check did not run (github.com unreachable from here); the local-server cases above cover the same code path"; fi
finish
