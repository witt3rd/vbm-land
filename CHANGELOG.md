# Changelog

Interface (the stable part): the `land.conf` keys, the exit codes, the JSON last line, the hook names and the marker file names.
Additive changes to it are minor releases; anything else is major.

## Unreleased

## 0.3.0
- Gate-edit approvals (`lib/approvals.sh`, `docs/gate-edit-approvals.md`): a removed or changed line in a gate-defining file is accepted only on an exact diff-hash match against an approval already on the base branch. New keys, all optional: `LAND_GATE_APPEND_ONLY` (patterns of files that may only gain lines; default none), `LAND_APPROVALS` (default `scripts/gate-edit-approvals.txt`; always judged, always protected, cannot be empty), `LAND_APPROVAL_DAYS` (default 7). New: `land-direct --print-gate-diff-hash FILE [rev]` and `--print-gate-diff FILE [rev]`; the hooks see `LAND_GATE_APPROVED_FILE`; `land-direct` prints `APPROVAL COMMIT: announce to the judge before landing the edit`. Rules: approvals are read from base; an approval lands alone (its commit and its landing change no other file) and is announced to the judge before the edit; one-time (the edit's landing removes the record it uses); stale, future-dated, malformed, self-referencing and quietly removed records are refused (a fresh one is withdrawn by an `Approval-Withdrawn: FILE <12+ hex of the hash>` trailer in a landing that changes nothing else, announced to the judge); the judge fails closed. Honest limit (in the document): an agent with landing rights could write its own approval line; the control is the visible record the judge reads first. Upgrade notes: every repository now has the always-on rules for `scripts/gate-edit-approvals.txt` (it is added to the protected set automatically; a repository whose own judge or protected-paths list names its protected files should list it too); to use the approvals set `LAND_GATE_APPEND_ONLY`, or have your own `post-rebase` judge read `$LAND_GATE_APPROVED_FILE`. New vendored file `lib/approvals.sh`.

## 0.2.2
- Skill and docs wording only: no internal name ("fleet") in the vendored skills (a consumer's public-readiness lint refused v0.2.1). v0.2.1 is superseded; roll to v0.2.2.

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
