# AGENTS.md

This repository is the **source tree of vbm-land**: the lander that lands an agent's local commits direct on `main`, no pull request. The tool is the product; a consumer repository vendors a pinned copy of it. `README.md` is the operator's manual and `CHANGELOG.md` the interface history (the stable part: the `land.conf` keys, the exit codes, the JSON last line, the hook and marker names). `VERSION` says 0.6.1; the newest tag in this clone is `v0.6.0`.

## Landing here

- Land with `scripts/land-direct` (a wrapper: `exec bin/land-direct "$@"`). Never push `main` yourself, never force-push it, never open a PR. The repository's own policy text is `templates/AGENTS-block.md`.
- The payload is what a consumer vendors, and it is published byte for byte: `bin/land-check`, `bin/land-direct`, `bin/land-revert`, `bin/land-update`, `bin/no-build-guard`, `bin/no-crash-record`, `bin/run-probe`, all of `lib/`, `VERSION`, every file in `templates/` and every `skills/*/SKILL.md`, plus `docs/packages.md`, `docs/crash-probes.md`, `docs/no-build-host.md` — 35 files, the exact list `MANIFEST.sha256` records.
- `bin/land-manifest`, `bin/land-release` and `bin/land-audit` are source-repository only (not vendored); `bin/land-release` is the maintainer's.
- Never edit `MANIFEST.sha256` by hand: `bin/land-manifest` rewrites it and `bin/land-manifest --check` fails on a stale one.
- Tier 1 is `tests/run.sh`: `tests/lint.sh`, then every `tests/test_*.sh` in its own scratch sandbox, in parallel. A test script must print `ran: NAME: N cases` with N > 0 and no `SKIPPED` line or the run counts as failed.

## Invariants a small edit breaks

- This repository is **public** (`.github/visibility` says `public`): no internal names, hosts or local paths anywhere — `tests/lint.sh` refuses them, and a workflow naming `self-hosted` is refused while that file does not say `private`.
- A change under `bin/`, `lib/` or `scripts/` is gate-defining (`CONTRIBUTING.md`) and judged by the owner before it lands. Every file in `bin/`, `install`, every `scripts/*` but a `*.conf`, and every `tests/*.sh` must stay executable; `tests/lint.sh` enforces it and exempts `tests/lib.sh`. `lib/*.sh` are sourced, not executable.
- `install` writes the vendored copy; `bin/land-check` is the offline drift check that a vendored copy is exactly its pin; `bin/land-update` moves a pin. An interface change (a key, an exit code, the JSON last line, a hook or marker name) needs a `CHANGELOG.md` line and is a minor release if additive, a major one otherwise.

## Map

- `bin/` the published tools; `lib/` their shared shell libraries (`lib/conf.sh` documents every `land.conf` key).
- `templates/` what a consumer copies: `AGENTS-block.md`, `PUBLIC-REPO-SETTINGS.md`, `ci.yml.example`, `land.conf.example`, `land-direct-stub`, `run-scoped.sh`, `ruleset-protect-main.json`, `ruleset-protect-release-tags.json`, `vbm-land-revert.yml`, `vbm-land-update.yml` — all ten.
- `docs/` design notes: `signing.md`, `packages.md`, `update-propagation.md`, `freeze-source.md`, `flip-record.md`, `no-build-host.md`, `crash-probes.md`, `ran-evidence.md`, `gate-mechanism-acceptance.md`.
- `skills/` the seven agent skills that ship to a consumer: `adopt-in-existing-repo`, `hold-and-freeze`, `land-a-change`, `new-repo`, `release`, `triage-red`, `update-vbm-land`.
- `scripts/` this repository's own `land-direct` wrapper, its `land.conf`, its signers file (`land.signers`) and `bootstrap-land`.
