# Security policy

## Reporting a vulnerability

Please report a vulnerability **privately**: on the repository page open **Security**, then **Report a vulnerability** (GitHub private vulnerability reporting). Do not open a public issue or pull request for it.

Include what you found, the release (`VERSION`, or the tag) and a way to reproduce it. You will get an acknowledgement within a few days; a fix is released as a patch release with a signed tag and a CHANGELOG entry that says what was fixed.

## Supported versions

The latest release only (see [CHANGELOG.md](CHANGELOG.md)). The project is 0.x: older releases get no backports.

## What counts

In scope: a way to land a change that the lander should refuse (a bypass of the gate, the hold or freeze markers, the protected set, the gate-edit approvals, the drift check, or the red check); a way to make `install` or `land-update` accept an unsigned, wrongly signed, tampered or substituted release; a way to run code or write outside what the documentation says, with the credentials of the person running the tool; a leak of a secret through its logs.

Out of scope (see "Honest limits" in the README): an attacker who already has write access to the repository that runs the lander and wants to cheat (the tool is for cooperating writers, not adversaries), and the contents of `land.conf` hooks and commands that a repository supplies for itself.

## Release signatures

Releases are ssh-signed annotated tags. The public key is `scripts/land.signers`; its fingerprint is in [docs/signing.md](docs/signing.md). Check the fingerprint out of band before trusting the file.
