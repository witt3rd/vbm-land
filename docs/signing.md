# Signing vbm-land releases

A release is an annotated tag `vX.Y.Z` signed with an ssh key (no gpg), whose message records `manifest_sha256=<hash of MANIFEST.sha256>`. `bin/land-release` makes it.
Consumers verify the signature against their own `scripts/land.signers` before anything of the release runs or is written (README, "Signed releases").

## The release key

- Principal: `vbm-land-release`
- Algorithm: ed25519
- **Fingerprint: `SHA256:+jAjhPWRPGVCFEtRLfKv11xxppyqCUzDhjtnh5/9xKk`**
- The public key is `scripts/land.signers` in this repository. Check the fingerprint out of band before you trust the file: `ssh-keygen -lf <(cut -d' ' -f2- scripts/land.signers)` prints it.
- The private half lives only on the maintainer's machine (mode 0600, never copied, printed or committed). It is not registered anywhere (not on GitHub): verification is local, against the signers file.

Every release from `v0.2.0` on is signed; `v0.1.0` predates signing and does not verify (a consumer pins `v0.2.0` or later).

## Trusting it in a consumer

First install: `install --source OWNER/vbm-land --signers scripts/land.signers vX.Y.Z` (the file taken from a source you trust, with its fingerprint checked as above). It is copied to the consumer's `scripts/land.signers`,
which is the consumer's own file from then on: from the next `land-update` the signature is mandatory.

## Verifying a tag by hand (from a fresh clone)

```
git clone <source> fresh && cd fresh
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=scripts/land.signers verify-tag vX.Y.Z
```

## Rotation

A rotation is a **new line** in `scripts/land.signers` (a new principal or the same one with the new key); the old line stays so that old tags still verify. Releases after the rotation are signed with the new key. Consumers
copy the new line into their own `scripts/land.signers` in a reviewed change (a key change is reviewed like one); until they do, `land-update` refuses the new releases, loudly. A lost or leaked key: say so in the CHANGELOG, rotate, and tell
consumers to remove the old line once they no longer need to verify tags it signed.
