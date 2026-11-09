# AGENTS.md

This repository is the **source tree of vbm-land**: the lander that lands an agent's local commits direct on `main`, no pull request. The tool is the product; a consumer repository vendors a pinned copy of it. `README.md` is the operator's manual and `CHANGELOG.md` the interface history (the stable part: the `land.conf` keys, the exit codes, the JSON last line, the hook and marker names). `VERSION` holds the version; releases are signed tags.

## Design: the 0.8.0 layout (built; the migration of old consumers and the prose are the next commits)

A consumer repository keeps everything the lander owns in **one folder, `.land/`**, so the repository's own `scripts/` stays its own and our footprint is self-contained. The lander's agent skills stay in `.agents/skills/` (an agent convention); nothing else of ours lives outside `.land/`.

```
.land/
  tool/          the vendored lander, replaced whole on every update, never edited
  PIN            version, commit and the manifest checksum
  land.conf      the repository's own settings
  land.signers   who may sign releases
  land.d/        the repository's own hooks
  land-direct    the entry script an agent runs
```

- **One folder, one checksum.** `.land/tool/` holds the payload and its `MANIFEST.sha256`; `PIN` and the signed release tag record the hash of that manifest, and `bin/land-check` verifies every file against it. That is already one checksum for the whole folder, so it does not change.
- **Update replaces the whole folder:** delete `.land/tool/`, copy the new one in, write `PIN`. A file dropped upstream disappears with it. `land-update --diff` still shows the added, changed and removed files before anything is written, and the update refuses to write outside `.land/` and `.agents/skills/`.
- **Protection is one entry, `.land/`,** for a repository that wants its lander off limits to agents. `scripts/` is the repository's and is not protected on our account.
- **Migration.** The first 0.8.0 update moves a repository from the old layout (`scripts/land/`, `scripts/land-direct`, `scripts/land.conf`, `scripts/land.d/`, `scripts/land.signers`) as one `chore(land)` commit, removes the old files, and rewrites the references in the repository's `scripts/` and Tier 1.
- **An upgrade removes what the old version left behind.** That is part of the upgrade, not a follow-up.
- **Build order, each slice green on its own:** (0) delete the unused package mechanism (done); (1) one place, `lib/paths.sh`, defines every path (done); (2) the checksum is already one, so no slice; (3) the tests take their paths from `lib/paths.sh`, then the `.land/` layout and the migration are one flip of those values. Prove it on one repository before any other.
- Nothing runs after the push: no CI, no Tier 2, no watchdog. The remaining wording about them in `bin/` and `lib/` goes in this release.

## Landing here

- Land with `.land/land-direct` (a wrapper: `exec bin/land-direct "$@"`; this repository is laid out as a consumer is, its own settings in `.land/`). Never push `main` yourself, never force-push it, never open a PR. The repository's own policy text is `templates/AGENTS-block.md`.
- The payload is what a consumer vendors, and it is published byte for byte: `bin/land-check`, `bin/land-direct`, `bin/land-update`, `bin/no-build-guard`, `bin/no-crash-record`, `bin/run-probe`, all of `lib/`, `VERSION`, every file in `templates/` and every `skills/*/SKILL.md`, plus `docs/crash-probes.md`, `docs/no-build-host.md` — 28 files, the exact list `MANIFEST.sha256` records.
- `bin/land-manifest`, `bin/land-release` and `bin/land-audit` are source-repository only (not vendored); `bin/land-release` is the maintainer's.
- Never edit `MANIFEST.sha256` by hand: `bin/land-manifest` rewrites it and `bin/land-manifest --check` fails on a stale one.
- Tier 1 is `tests/run.sh`: `tests/lint.sh`, then every `tests/test_*.sh` in its own scratch sandbox, in parallel. A test script must print `ran: NAME: N cases` with N > 0 and no `SKIPPED` line or the run counts as failed.

## Invariants a small edit breaks

- This repository is **public** (`.github/visibility` says `public`): no internal names, hosts or local paths anywhere — `tests/lint.sh` refuses them, and a workflow naming `self-hosted` is refused while that file does not say `private`.
- A change under `bin/`, `lib/` or `scripts/` is gate-defining (`CONTRIBUTING.md`) and judged by the owner before it lands. Every file in `bin/`, `install`, every `scripts/*` but a `*.conf`, and every `tests/*.sh` must stay executable; `tests/lint.sh` enforces it and exempts `tests/lib.sh`. `lib/*.sh` are sourced, not executable.
- `install` writes the vendored copy; `bin/land-check` is the offline drift check that a vendored copy is exactly its pin; `bin/land-update` moves a pin. An interface change (a key, an exit code, the JSON last line, a hook or marker name) needs a `CHANGELOG.md` line and is a minor release if additive, a major one otherwise.

## Map

- `bin/` the published tools; `lib/` their shared shell libraries (`lib/conf.sh` documents every `land.conf` key).
- `templates/` what a consumer copies: `AGENTS-block.md`, `PUBLIC-REPO-SETTINGS.md`, `land.conf.example`, `land-direct-stub`, `run-scoped.sh`, `ruleset-protect-main.json`, `ruleset-protect-release-tags.json`, `vbm-land-revert.yml`, `vbm-land-update.yml` — all ten.
- `docs/` design notes: `signing.md`, `freeze-source.md`, `flip-record.md`, `no-build-host.md`, `crash-probes.md`, `ran-evidence.md`, `gate-mechanism-acceptance.md`.
- `skills/` the seven agent skills that ship to a consumer: `adopt-in-existing-repo`, `hold-and-freeze`, `land-a-change`, `new-repo`, `release`, `triage-red`, `update-vbm-land`.
- `.land/` this repository's own entry script (`land-direct`), `land.conf` and signers file (`land.signers`); `scripts/` its helpers (`bootstrap-land`, `run-scoped.sh`).
