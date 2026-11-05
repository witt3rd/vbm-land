# Changelog

Interface (the stable part): the `land.conf` keys, the exit codes, the JSON last line, the hook names and the marker file names.
Additive changes to it are minor releases; anything else is major.

## Unreleased

## 0.2.1
- `install` ships the update workflow dispatch-only unless the source's `.github/visibility` says `public` (then weekly too): a private source needs a secret and a scheduled run would be red. Upgrade notes: in an existing repository the workflow is yours; remove its `schedule:` while the source is private; check by hand with `land-update --check`. Flip-to-public checklist item 11 enables the schedule.
- Tests only (the vendored files are unchanged): the test runner requires ran-evidence from every test script (`ran: NAME: N cases`, N > 0, no SKIPPED line): a script that ran nothing no longer passes (docs/ran-evidence.md).
- `install` creates the repository's own files (entry script, `land.conf`, the scheduled workflow) on the FIRST install only; an update never brings back a file the repository removed. Upgrade notes: delete `.github/workflows/vbm-land-update.yml` if a repository cannot use it (for example one that allows no workflow secrets).

## 0.2.0
- First signed release (key and rotation: docs/signing.md; `scripts/land.signers` is the maintainer's public key).
- `land-red`: known-flaky rerun (`LAND_KNOWN_FLAKY`, `LAND_FLAKY_RERUN_WAIT`; the list is main's) and the Tier 2 freeze read from the CI runs (`LAND_TIER2_JOB`; lifts on green, never lifts a person's freeze). `land-direct`: `--group` (size budget waived for a coordinator's entries) and `LAND_LOCK_HELD=1` (the caller holds the lock; not inherited by Tier 1 or the hooks). Upgrade notes: new keys, all optional; the lock file for a coordinator is `<git common dir>/vbm-land/lock`.
- The `update-vbm-land` skill describes the pull flow: the behind report, `--diff`, `--land`, `LAND_AUTO_UPDATE`, signed releases. Convention: a release that adds or changes an interface item (key, exit code, hook, marker) carries an "Upgrade notes" line in its CHANGELOG section; `land-update --diff` prints those sections.
- `LAND_AUTO_UPDATE=none|patch|minor` (new key, default none) and `land-update --auto`: the scheduled workflow lands the newest release of the allowed class through the repository's own lander; a major never; the workflow template uses it.
- `land-update --land`: verify, stage, commit and land the update through the repository's own lander from a pristine clone of the base branch; stops on the first refusal.
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
