# Changelog

Interface (the stable part): the `land.conf` keys, the exit codes, the JSON last line, the hook names and the marker file names.
Additive changes to it are minor releases; anything else is major.

## Unreleased
- Signed releases: `bin/land-release` (signed annotated tag recording the manifest hash), `scripts/land.signers`, verification in `install` and `land-update` before anything is written or run, `install --signers`, `land-update --diff`; the PIN gains `signature=verified|unverified`.
- `land-update --check`: read-only comparison of the pin with the source's release tags (`pinned X, latest Y, behind N (patch|minor|major)`; exit 0 current, 1 behind, 3 unreachable).
- `templates/vbm-land-update.yml`: a scheduled, read-only, non-gating workflow that `install` adds when absent (drift check with `--upstream`, then `land-update --check`).

## 0.1.0
- `bin/land-audit` warns when a repository's default branch is not protected against deletion and force-push; `templates/ruleset-protect-main.json`, `ruleset-protect-release-tags.json`, `PUBLIC-REPO-SETTINGS.md`, `skills/new-repo`.
- The drift check knows hook names (`*.sh` helpers allowed, a misspelled hook fails).
- First release: everything below.

- Pinned vendoring: `install`, `scripts/land/PIN`, `MANIFEST.sha256`, `bin/land-check` (offline and `--upstream`), `bin/land-update`, `bin/land-audit`, `bin/land-manifest`; the lander refuses (exit 12) a change that makes the vendored copy differ from its pin.
- `skills/<name>/SKILL.md` (new-repo, land-a-change, triage-red, update-vbm-land, hold-and-freeze, adopt-in-existing-repo, release): agent skills, in the manifest; `install` / `land-update` copy them to `.agents/skills/` of the consumer and `land-check` drift-checks them.
- Mutation self-test: every guard of the lander is cut out in turn and its scenario must stop being refused.
- `templates/`: starter `land.conf`, agent-instructions block, CI workflow.

- `bin/land-direct`: configurable lander (lock with lease, hold and freeze markers, land-time checks, regeneration of generated files, hooks, bounded steps, metrics log).
- `bin/land-red`: one red definition with the modes `push`, `push+dispatch`, `off`, an infrastructure classifier and the freeze marker.
- `scripts/bootstrap-land`: minimal lander, the recovery path.
- Test suite with a negative test per refusal.
