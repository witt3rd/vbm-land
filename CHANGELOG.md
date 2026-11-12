# Changelog

Interface (the stable part): the `land.conf` keys, the exit codes, the JSON last line, the hook names and the marker file names.
Additive changes to it are minor releases; anything else is major.


## 0.15.2 (patch: a rule that was too strict)

- `land-lean ledger` required every proved or partial claim to cite a clause whenever a clause index was configured. That is one repository's rule (every claim is about the standard, and a library's own policy is tagged `vbm:`), not everyone's: another has proved claims about the library itself that cite no clause. The requirement is now the key `LAND_LEAN_LEDGER_TAGGED=1` (default `0`); an unknown tag fails either way. Found migrating the second repository to the shared gate: each keeps its own guarantee.

## 0.15.1 (patch: a bug in 0.15.0)

- `land-lean ledger` imports two of the tool's modules (`LandLedger`, `LandWalk`), but a repository whose build names its targets (`lake build A B C`) never built the second, so the gate could not find it. The command now builds the `LandLedger` library itself first (a cached no-op when current), so no repository's build line has to name it; a repository without the `lean_lib` gets a message saying to declare it. The test no longer builds the library, so it exercises exactly this. Found migrating the first repository.

## 0.15.0 (minor: a new command)

- `land-lean ledger [--write|--selftest]`: the obligation-ledger gate every Lean repository shares, replacing four hand-edited copies that had drifted (142, 157, 76 and 172 lines). The tool ships the vocabulary (`lean/LandLedger.lean`: `Status`, `Obligation` with optional clause tags and a caveat that lives with the claim, `O`, `OC`) and the gate (`lean/LedgerGate.lean`); a repository keeps only its data and a `lean_lib` line. Reach, the ratchet, the clause tags and their coverage are each turned on by a key in `.land/lean.conf` (`LAND_LEAN_LEDGER_*`). `lean/LandWalk.lean` is the reach walk, written once; it uses the CLOSED set of skipped kinds (a name-based filter let a definition leave the count by being renamed), so a repository that carried the older filter may see its counts move. `tests/test_lean_ledger.sh` has 48 cases on a real toy project, mutation-checked (theorem check, reach, ratchet and clause check each switched off are all caught). New payload: `lean/LandLedger.lean`, `lean/LandWalk.lean`, `lean/LedgerGate.lean`.

## 0.14.2 (patch: a bug in 0.14.0 and 0.14.1)

- `land-lean recheck` passed all the modules of `LAND_LEAN_RECHECK_MODULES` to ONE `leanchecker --fresh` run, which accepts only a single module ("--fresh flag is only valid when specifying a single module"): with two or more listed it failed every time, on a good tree too. It now runs one replay per module, side by side (each replays its whole import closure), prints one verdict per module (`recheck: M ok` / `recheck: M REJECTED` and the checker's words) and exits 1 if any was rejected. The test that was meant to prove every listed module is replayed passed for the wrong reason (the failing invocation looked like a rejection); it now also requires two clean modules to PASS and names which module was rejected, in either order.

## 0.14.1 (patch: wording)

- `land-lean recheck` said it was an INDEPENDENT kernel checker. It is not: `leanchecker --fresh` replays every declaration through Lean's own kernel code in a fresh process. It catches a declaration that reached the environment without passing the kernel (the check skipped, an option or tactic that bypasses it) and an `.olean` an honest build did not produce; it does not catch a bug in the kernel, which it shares with the build (that needs a different implementation: nanoda, not wired). The command's comment and message, `docs/lean-gates.md`, the README and the test header now say exactly that. No behaviour changes.

## 0.14.0 (minor: a new command)

- `land-lean recheck [--selftest]`: replays every proof of the modules in `LAND_LEAN_RECHECK_MODULES` (new key in `.land/lean.conf`), and of everything they import, with Lean's independent kernel checker (`leanchecker --fresh`). `--selftest` proves the gate can reject: it plants a false theorem added with the kernel check skipped, and a checker that accepts everything fails it. `tests/test_lean_recheck.sh` has 17 cases on a real toy project, mutation-checked (a no-op replay and a self-test that stops checking rejection are both caught). New payload file `lean/recheck-selftest.sh`.
- `docs/lean-gates.md`: a trust ledger belongs to a formally verified repository only ("every repository has one" was wrong: a repository that proves nothing has no claims to qualify).

## 0.13.2 (patch)

- `land-lean trust` requires each vendored library's OWN `include/*.h` (named by the library, at any depth of vendoring), not every `include/` directory inside it: 0.13.1's pattern also matched a library's freestanding `runtime/include/` copies and named them `dep:runtime/include/...`, which a consumer neither compiles against nor can sensibly cover (it would also have broken repositories that passed on 0.13.0). `tests/test_lean_trust.sh` has the case (red first).

## 0.13.1 (patch)

- `land-lean trust` derives the C headers and `@[extern]` symbols of EVERY vendored library, at any depth: a library vendored inside a vendored library (`vendor/vbm-json/vendor/vbm-simd`) runs in the consumer's artifacts all the same, and the derivation had skipped it (so its trusted shim header and externs could be left out of a ledger unseen). `tests/test_lean_trust.sh` has the nested cases (red first). A ledger that already names them is unaffected; one that did not must now.

## 0.13.0 (minor: additive; a repository with `scripts/trust_ledger.py` or `scripts/trust-ledger-check.sh` deletes them and calls the tool, in the same commit that takes this release)

- **The trust ledger joins the Lean gates: `land-lean trust [--count]`** (`lean/trust_ledger.py`, `lean/trust-keys.sh`, docs/lean-gates.md). The discipline: what cannot be proven is marked as trusted, and what must appear in `docs/trust-ledger.md` is DERIVED from the tree and `.land/lean.conf`, never from the ledger. It derives the build pins, the Lean toolchain pieces, the configured trusted files and externs, `pin:NAME` for every vendored library (and the headers and externs it carries), the tools the scripts run, and whatever `LAND_LEAN_TRUST_KEYS_CMD` prints; the checker requires every key covered, no stale cover, complete entries, cited files that exist, and negative-tests itself on every run.
- New keys of `.land/lean.conf`: `LAND_LEAN_TRUST_FILES`, `LAND_LEAN_TRUST_EXTERN_DIRS`, `LAND_LEAN_TRUST_TOOLS`, `LAND_LEAN_TRUST_KEYS_CMD`.
- `scripts/trust_ledger.py` and `scripts/trust-ledger-check.sh` are retired paths (three drifting copies each).

## 0.12.0 (minor: additive; a repository that has `scripts/AxiomGate.lean` deletes it and calls the tool, in the same commit that takes this release)

- **The Lean gates join the payload (docs/payload.md 4a, docs/lean-gates.md): `bin/land-lean axiom [--selftest]` and `lean/AxiomGate.lean`.** One axiom gate with the richer algorithm (one shared walk, differential-tested against Lean's own `collectAxioms`), replacing eight copies in two algorithms. It is configured by the new `.land/lean.conf` (`LAND_LEAN_AXIOM_IMPORTS`, `LAND_LEAN_AXIOM_ROOTS`): the file's PRESENCE is the opt-in, it has `land.conf`'s grammar and parser, `land-check` validates it, and a root that matches no constant fails (a gate that audited nothing proves nothing).
- `lib/conf.sh`: `conf_parse NAME [KEYS]` takes the key list of the file it parses (one parser, one key list per file); `lean_conf_keys`, `lean_conf_defaults`, `lean_conf_validate`. `lib/paths.sh`: `LAND_LEAN_CONF_FILE`.
- `scripts/AxiomGate.lean` is a retired path.
- This repository pins the Lean toolchain in `mise.toml` (its tests of the gates run on a real toy Lean project).

## 0.11.5 (patch)

- `land-check` prints a retired path with its reason as written in `lib/retired-paths.txt` (`the tool ships lib/ran.sh`, or `tested by the tool itself (...)`); it used to say "the tool ships it" even for a test the tool does not ship.
- `land-pin vendor` warns on an ssh-style URL (a lock is shared data: use the public https URL), and the `vendor-a-library` skill says so and why (a scorer accepts only allowlisted https GitHub repositories).

## 0.11.4 (patch)

- `bin/run-tests-parallel` says again, as the copies it replaced did, "the ENVIRONMENT is the failure, not a test; free it or set TMPDIR elsewhere" when the temp directory is nearly full (the merge had reworded it, dropping the advice); `tests/test_runner.sh` checks the wording.
- `lib/retired-paths.txt` also names `scripts/test_reap.sh`, `scripts/test_run_scoped.sh`, `scripts/test_tmp_preflight.sh` (tests of the retired copies, now this tool's own) and `scripts/lint-scoped-runners.sh` (`no-build-guard --lint` is the one lint).

## 0.11.3 (patch)

- The tree hash ignores a `.lake` or `.git` directory at ANY depth, not only at the top of the hashed directory. Building a repository that vendors a library which itself vendors another (vbm-llm, vbm-json, vbm-simd) makes Lake write build products inside the nested copy, and `land-pin verify` then reported the outer library as edited. `tests/test_pin.sh` has the case; hashes of trees with no nested build products are unchanged.

## 0.11.2 (patch)

- The tree hash no longer refuses harmless file names. It refused any path outside `[A-Za-z0-9._+/-]`, which stopped `land-release` on a real repository (a test vector named `n_structure_trailing_#.json`); only a NEWLINE or a BACKSLASH (which `sha256sum` escapes) is an error now, and every other name (a space, `#`, `<`, non-ASCII) is hashed as it is, sorted by bytes. `tests/test_pin.sh` checks a tree of awkward names against a value computed independently with Python. Hashes of trees with ordinary names are unchanged.

## 0.11.1 (patch)

- A RELATIVE `--signers` path now works: the verifier runs `git` inside its scratch clone, so a relative path was looked up there and a good signature was reported as "unsigned, or an unknown signer". `lib/verify.sh` makes the path absolute (and so does the embedded copy in `install`); `tests/test_signing.sh` has the case.

## 0.11.0 (minor: additive; a repository takes it by deleting its own copies of what moved into the tool)

- **One verifier.** `lib/verify.sh` is the only code that verifies a release tag and hashes a tree (`land-update`, `land-pin`, `land-release`); a release is verified by the tree hash its signed tag records, which covers the manifest and every file (tags keep recording `manifest_sha256=` until every consumer has taken this release). `install` embeds the file verbatim, and `tests/test_verifier_one.sh` fails if the copy differs or a second verifier appears. `lib/treehash.sh` is merged into it.
- **SECURITY: `install` verifies before it reads or runs anything the release says.** Before this release `install` sourced the release's `lib/paths.sh` before checking the signature, so a hostile release's code ran even when the install was then refused, and the release could move the signers file and turn a required signature into "unverified, allowed". Both are fixed and tested. Install new repositories from the newest tag; an installer taken from an older tag still has the problem. `land-update` was not affected.
- **The test-running runtime moved into the payload**, one canonical version of what was seven hand-edited copies: `lib/ran.sh` and `bin/ran-evidence` (ran-evidence), `bin/run-tests-parallel` (with optional `TEST_TIMEOUT` and `TEST_JOBS`, abort-safe), `bin/run-scoped.sh` and `lib/reap.sh`. The copy-me `templates/run-scoped.sh` is gone. The heavy-host guard's lint checks the vendored `run-scoped.sh` beside the guard (still executed with a marker present; it must refuse). This repository's own `tests/run.sh` uses the same runner.
- **Retired paths.** `lib/retired-paths.txt` lists the files that moved; `land-check` fails a repository that holds one (a file or a link). On update: delete those copies, point their callers at `.land/tool/...`, and delete the tests of the copies, in the same commit (skill `update-vbm-land`).
- New docs: `docs/payload.md` (what the tool ships and what a repository may not copy), `docs/ran-evidence.md` (where the code lives).

## 0.10.0 (minor: additive)

- `bin/land-pin` (`tree`, `vendor`, `verify`, `online`, `list`) and `lib/treehash.sh`: one tree hash, one lock (`.land/pins.lock`), one vendoring command, one fast-gate check, from the contract `docs/pin.md`. New consumer paths: `.land/pins.lock`, `vendor/`.
- `bin/land-release` works for ANY repository: the signed tag records `tree_sha256=`; a repository with no `MANIFEST.sha256` is not asked for one. It is now part of the payload.
- New skills `vendor-a-library` and `release-a-library`.

## 0.9.0 (MAJOR: dead machinery removed; a land.conf naming a retired key is now refused)

A consumer updates with `.land/tool/bin/land-update v0.9.0` after removing any retired key (the list is in the entry) from its `.land/land.conf`.

Nothing here is kept for compatibility with a thing that no longer exists.

- **Removed:** the auto-update mode `land-update --auto` and the key `LAND_AUTO_UPDATE` (they served a scheduled workflow whose templates are gone: nothing schedules an update any more); the GitHub Actions warning annotation and step-summary line `land-update --check` wrote under Actions (`--check`, `--diff` and the update itself behave as they did). `land-update` has three modes again: `--check`, `--diff` and the update itself.
- **Removed: the retired-key tolerance.** `lib/conf.sh` no longer lists the retired keys as known, and `bin/land-direct` no longer reads and ignores them with a notice: `LAND_LOCK_WAIT`, `LAND_CI_WORKFLOW`, `LAND_TIER1_JOB`, `LAND_RED_MODE`, `LAND_RED_WAIT`, `LAND_KNOWN_FLAKY`, `LAND_FLAKY_RERUN_WAIT`, `LAND_TIER2_JOB`, `LAND_APPROVALS`, `LAND_APPROVAL_DAYS`, `LAND_PROTECTED_LIST`, `LAND_PROTECTED_APPROVALS`, `LAND_GATE_APPEND_ONLY`, `LAND_PROD_PATHS`, `LAND_BUDGET_LINES` (and, in the environment, `LAND_LOCK_WAIT_SECONDS` and `LAND_LEASE_STALE_SECONDS`, which were only ever read to be named). **A `land.conf` that names a retired key now fails**: conf parsing refuses it like any other unknown key (exit 2, the message naming the key, the file it was read from and the line). Upgrade notes: delete those lines from `.land/land.conf` (the lander reads the copy on the base branch, so that is the copy that must be clean) before the first landing with this version.
- **Removed:** `docs/freeze-source.md` (a design note about watchdog-driven freezes; no watchdog exists) and `bin/no-build-guard --lint` no longer reads `.github/workflows/*`.
- **Removed: `LAND_FIX_PATHS`,** a CI-era rule ("a freeze fix may touch only test and CI paths"). A fix for a freeze is now recognised by its commit subject alone: `fix:` or `fix(<scope>):` with any scope, or a subject that starts with `Revert`/`revert`. The `ci|tests` scope list is gone (any scope counts), and the paths a fix touches are not judged.

## 0.8.1 (PATCH: the migration repoints symlinks into the old tool folder)

The 0.8.0 migration missed tracked symlinks: a consumer that tracks a link into `scripts/land/` (vbm-sse: `scripts/lib-no-crash-record.sh -> land/lib/no-crash-record.sh`) was left with a dangling link once the old folder was removed. `install` now repoints every tracked symlink that resolves inside `scripts/land/` to the same sub-path under `.land/tool/` (relative to the link's own directory, e.g. `../.land/tool/lib/no-crash-record.sh`) before removing the old folder, names it in the migration's summary line, and leaves a link that points anywhere else alone.

## 0.8.0 (MAJOR: everything the tool owns in a consumer is one folder, .land/)

A consumer on 0.7.x updates with `scripts/land/bin/land-update v0.8.0`: the first update migrates it (it moves `land.conf`, `land.signers`, `land.d` and the entry script into `.land/`, removes `scripts/land/`, and prints the consumer's own references to the old names for it to fix). The entry script is now `.land/land-direct`; the move is one `chore(land)` commit, and a repository's own scripts, docs, protected set and Tier 1 must be renamed by hand (the update only lists them).

- **Layout** (major): everything the tool owns in a consumer moves into one folder, `.land/`: the vendored tool in `.land/tool/` (was `scripts/land/`), the pin `.land/PIN`, the settings `.land/land.conf`, the signers file `.land/land.signers`, the hooks `.land/land.d/` and the entry script `.land/land-direct`; the agent skills stay in `.agents/skills/`, and the repository's own `scripts/` stays its own. `land-check` still verifies one checksum per folder (`.land/tool/MANIFEST.sha256`, recorded by the pin), `land-check` and `land-update` act on it, and the update replaces `.land/tool/` whole. The first install or update of 0.8.0 migrates an old-layout repository (moves `land.conf`, `land.signers`, `land.d` and the entry script, removes `scripts/land/`) and prints the consumer's own references to the old paths; upgrade notes: the move is one `chore(land)` commit, and a repository's own scripts, docs, protected set and Tier 1 must be renamed by hand (the install only lists them). The package mechanism (`land-update --pkg`) is gone; no CI, no Tier 2 and no revert tool remain.
- **Removed:** the package mechanism (`land-update --pkg`, `--source`, `--signers`, `lib/pkg.sh`, `docs/packages.md`, `land-check --pkg` and the per-package checks) is gone: nothing used it. `land-check` and `land-update` act on this tool's own pin only.
- **Internal:** lib/paths.sh defines every consumer path in one place (no behaviour change).

## 0.7.1 (PATCH: the agent-instructions block carries the family's principles)

The agent-instructions block (`templates/AGENTS-block.md`) carries the family's principles (everything runs before the push; proofs, not tests; nothing added to the process without deleting something; the worker owns its change). Additive; no interface change.

## 0.7.0

Nothing runs after the push. **Removed** (major for a consumer that used them): `bin/land-revert` (the red-main watchdog) and its
`on-revert` hook, `templates/vbm-land-revert.yml`, `templates/ci.yml.example`, `templates/vbm-land-update.yml` (install no longer
writes `.github/workflows/vbm-land-update.yml`; land-update no longer stages it) `lib/infra-re.sh` and `docs/update-propagation.md`; this repository's
own CI workflow. `scripts/bootstrap-land` reads no CI. Tier 1 runs once, before the push, on the rebased combination; if main is ever
red, whoever sees it reverts the offending commit with `git revert` (`triage-red`).
Upgrade notes: delete your `.github/workflows/` (CI, the watchdog and the update check), drop `LAND_CI_WORKFLOW`, `LAND_TIER1_JOB`,
`LAND_RED_MODE` from `scripts/land.conf` (already ignored), and take releases by hand with `land-update`.

## Unreleased

- internal: lib/paths.sh defines every consumer path in one place (no behaviour change).
## Strip (a deletion release: nothing is added, 1.4k lines go)
- **Removed: gate-edit approvals, protected-paths lists, the `Protected:` trailer, the append-only judge, the diff budget, `--print-gate-diff[-hash]`.** The keys `LAND_APPROVALS`, `LAND_APPROVAL_DAYS`, `LAND_PROTECTED_LIST`, `LAND_PROTECTED_APPROVALS`, `LAND_GATE_APPEND_ONLY`, `LAND_PROD_PATHS` and `LAND_BUDGET_LINES` are read and ignored (named once). Reason: in a week 50 of 59 stops were false and approvals stopped nothing.
- **Kept:** the lander, the red-main watchdog, the drift check of the vendored copy (the protection of the lander's own files), the hooks, signed releases. A signing keys file (`*.signers`) that already exists changes only with `LAND_OWNER=1` (a first install of one is not a change).
- The metrics line keeps `exit`, `step`, `reason`, `last_lines` for every non-landing.

## 0.6.1 (PATCH: a refusal is no longer reported as a crash)
- A refusal by the gate-edit judge used to end with `the gate-edit judge failed unexpectedly (line N)` printed over the refusal's real reasons (the judge's last command, the verdict test, failed under `set -e`). It now returns normally and the verdict is the exit status; a genuine crash is still reported as one.
- The judge's own messages are kept: they are recorded as `last_lines` of the non-landing in `metrics.jsonl`.

## 0.6.0 (MINOR in the interface, a simplification: fewer refusals; nothing is added to what a repository must do)
Upgrade notes:
- **`Protected: <reason>` trailer.** A landing that touches a protected path (`LAND_PROTECTED_LIST`) or removes or changes a line of an append-only file (`LAND_GATE_APPEND_ONLY`) lands on one conscious trailer line in any of its commits, no hash and no approval. Without the trailer it is refused (exit 12) and says so. Only the lander's own files still need an exact-hash approval: `scripts/land/`, `scripts/land-direct`, any `*.signers`, the configuration, the hooks directory and the protected-paths list itself. `--print-gate-diff-hash @protected` prints the hash of those paths only.
- **The diff budget is a number, never a refusal.** Over `LAND_BUDGET_LINES` the lander prints the count and lands; `Diff-Budget:` and `--group` are accepted and now only annotate the line.
- **A used approval is deleted by the lander.** The landing that consumes an approval no longer has to delete its line: land-direct adds a `chore(approvals)` commit (carrying the Task-ID trailer) that removes it and judges the tree again. A landing that deletes it itself still lands.
- **Every non-landing is recorded.** The metrics line (`metrics.jsonl`, appended, never overwritten) now carries `exit`, `step` (where it stopped), `reason` (the lander's own message) and `last_lines` (the last lines of a failing Tier 1).

## 0.5.0 (MAJOR: no lock, no CI reads in landing; exit 15, exit 10, `LAND_LOCK_HELD` and `bin/land-red` are removed)
Upgrade notes (read before `land-update`; the landing contract changed):
- **Exit `15` ("busy") and the result `busy` no longer exist.** The lander takes no lock: any number of landers run at once in one clone, each in its own run directory, and git's refusal of a push that is not a fast-forward is the only arbiter. A caller that retried on 15 can drop that branch. New exit `16` (result `moved`): the base moved faster than the lander could validate (`LAND_ATTEMPTS`, default 30; `LAND_DEADLINE`, default 900 s); nothing was pushed; run it again. A rerun after a crash that followed an accepted push exits 0, "already landed".
- **Exit `10` and the result `blocked-red` no longer exist; `bin/land-red`, the Tier 2 freeze and the known-flaky rerun are removed.** Landing does not read CI and a red main does not stop it. The watchdog `bin/land-revert` (new; `templates/vbm-land-revert.yml`, hook `on-revert`) reverts the commit that made main red. Landing stops only for a person's hold or freeze (a named owner and an expiry); a fix or a true revert still passes a freeze, and landing a fix no longer lifts one. **Inherited red:** a Tier 1 that fails only with failures the bare base also has (lines of its output matching the new key `LAND_FAIL_PATTERN`, default `^(FAIL|FAILED)([ :]|$)`) lands, flagged `inherited_red` in the metrics line; a new failure, or one that prints no such line, refuses it (13). Wording of the rule: README 4.4/4.5 and `templates/AGENTS-block.md`.
- **Legacy keys are read and ignored, with one notice naming those a `land.conf` still sets** (whatever their value): `LAND_LOCK_WAIT`, `LAND_CI_WORKFLOW`, `LAND_TIER1_JOB`, `LAND_RED_MODE`, `LAND_RED_WAIT`, `LAND_KNOWN_FLAKY`, `LAND_FLAKY_RERUN_WAIT`, `LAND_TIER2_JOB`; and, in the environment, `LAND_LOCK_WAIT_SECONDS` and `LAND_LEASE_STALE_SECONDS`. Remove them from your `land.conf`; a later release may stop knowing them.
- **Removed:** `LAND_LOCK_HELD`; the `GH` operator knob; the `wait_s` field of the metrics line (which gains `commit`, `attempts`, `inherited_red`). Tier 1 logs are `tier1.gates.log` and `tier1.tests.log` in the run directory.
- **New in the environment of hooks and Tier 1:** `LAND_RUN_DIR` (this run's own directory; shared state is only hold, freeze and metrics), `LAND_ATTEMPT`, `LAND_PREV_BASE`. A hook that wrote scratch files under `LAND_STATE_DIR` should use `LAND_RUN_DIR`. `LAND_BASE_REF` is unchanged.
- **Packages:** `land-update --pkg NAME` vendors another signed package into `scripts/NAME/` with its own signers file (`scripts/NAME.signers`); the drift check covers every pinned package (`docs/packages.md`). Additive.
- `scripts/bootstrap-land` (the recovery lander) is unchanged: it keeps its own lock, its own red check and its exits 10 and 15.
Changes in this release (one entry each):
- BREAKING: landing no longer reads CI and a red main no longer stops it. `bin/land-red`, exit `10`, the result `blocked-red`, the Tier 2 freeze and the known-flaky rerun are removed; the keys `LAND_CI_WORKFLOW`, `LAND_TIER1_JOB`, `LAND_RED_MODE`, `LAND_RED_WAIT`, `LAND_KNOWN_FLAKY`, `LAND_FLAKY_RERUN_WAIT` and `LAND_TIER2_JOB` are read and ignored, with one notice naming those a `land.conf` still sets. The watchdog `bin/land-revert` reverts what made main red. Landing stops only for a person's hold or freeze (a named owner and an expiry; a fix or a true revert still passes a freeze; landing a fix no longer lifts a freeze). INHERITED RED: a Tier 1 that fails only with failures the bare base also has (the output lines matching the new key `LAND_FAIL_PATTERN`, default `^(FAIL|FAILED)([ :]|$)`; one extra run, only then) lands, flagged `inherited_red` in the metrics line; a new failure, or a failure that prints no such line, refuses it (13). Tier 1 logs are now `tier1.gates.log` and `tier1.tests.log` in the run directory. The `GH` operator knob is no longer read.
- NEW (additive, minor): `bin/land-revert`, the watchdog. `land-revert --bad SHA --good SHA` runs the repository's Tier 1 on the bad commit (a failure that does not reproduce is never reverted), bisects `good..bad` for the first failing commit, reverts it as a true revert carrying its required trailers and a `Diff-Budget:` trailer, and lands it through `land-direct`; when the revert conflicts it reverts the later commits on the same files too, newest first, at most 5; otherwise (or when the landing is refused) it alerts with exit 3 and changes nothing. New hook `on-revert`; new template `templates/vbm-land-revert.yml`. Nothing calls it yet from the landing path.
- The retry loop: when main moves under a landing it is rebased and validated again, at most `LAND_ATTEMPTS` (new key, 30: a burst of twenty landers measured up to 18 attempts for one) attempts and none started after `LAND_DEADLINE` (new key, 900) seconds, with jitter after a lost push race; past either bound exit `16` (result `moved`, nothing pushed). Each attempt's base is pinned when it starts. A refused push is retried only if main has in fact moved (else it is final, exit 1); a push whose report was lost (timeout) is resolved by asking the remote. A rerun after an accepted push exits 0, "already landed". Hooks and Tier 1 get `LAND_ATTEMPT` and `LAND_PREV_BASE`; the metrics line gains `commit` and `attempts`. Additive except exit 16 (a new code).
- PINNED PACKAGES (additive, minor; `lib/pkg.sh`, `docs/packages.md`): `land-update --pkg NAME` vendors another signed package (a repository with `MANIFEST.sha256`, `VERSION` and signed tags recording the manifest hash) into `scripts/NAME/` with its own `PIN` and `MANIFEST.sha256`: `--source` and `--signers` on the first install, then `--check`, `--diff`, `--land` (`chore(land): NAME vX.Y.Z`) and `--auto` as for vbm-land. A package has its own signers file `scripts/NAME.signers` and is refused without one (never UNVERIFIED); files are verified against the manifest before anything is written; a file is executable iff it starts with `#!`. `land-check` with no arguments now also checks every pinned package (`scripts/*/PIN`; a directory with a manifest and no PIN is drift; `--pkg NAME` checks one) and `scripts/NAME.conf` (known keys only, from the package's `scripts/NAME/KEYS`, `pkgconf_load`). With no package installed nothing changes. Upgrade notes: none required.
- BREAKING (0.5.0 will be a major release): `land-direct` takes no lock. The flock, the lease and its heartbeat, stale-lease breaking, every "busy" path, exit `15`, the result `busy`, `LAND_LOCK_HELD` and the `wait_s` field of the metrics line are gone. `LAND_LOCK_WAIT` (key), `LAND_LOCK_WAIT_SECONDS` and `LAND_LEASE_STALE_SECONDS` (environment) are read and ignored with one notice for a release. Any number of landers run at once (each in its own run directory); the remote's refusal of a push that is not a fast-forward is the only arbiter. `scripts/bootstrap-land` (the recovery lander) is unchanged and keeps its lock.
- `land-direct` keeps everything one run writes in its own directory, `<git common dir>/vbm-land/run.<pid>.<random>/` (scratch worktree, hooks, logs, scratch files), removed at exit (a failed run keeps only its `*.log` files; a later run sweeps directories of dead runs older than a day). The hold, freeze and metrics files stay shared. New in the environment of hooks and Tier 1: `LAND_RUN_DIR`. A hook that wrote scratch files under `LAND_STATE_DIR` should write them under `LAND_RUN_DIR`.

## 0.4.1
- Tests and docs only (no interface change; patch). `tests/lint.sh` now fails a test that reads the real repository's approvals, protected list, baselines, config or tags (a test builds its OWN world: a test that read the repository's real approvals file failed the first real approval in a consumer). New `docs/gate-mechanism-acceptance.md` and `tests/acceptance.sh`: before a gate mechanism is rolled, one real approval goes end to end on the real tree (a scratch clone, a real approval line committed into each real approvals file, the real Tier 1 must pass). vbm-land's own tests were already self-contained; this makes the class a lint failure. Upgrade notes: none required; a consumer's tests that read its real approvals file or protected list should build a scratch copy instead.

## 0.4.0
- A NEW GATE CLASS: protected-set approvals, opt-in via `LAND_PROTECTED_LIST` (additive, minor; with the key unset nothing changes; `lib/approvals.sh`, `docs/gate-edit-approvals.md`). New optional keys `LAND_PROTECTED_LIST` (a protected-paths list on base) and `LAND_PROTECTED_APPROVALS` (its approvals file; default `LAND_APPROVALS`). With the list set, a landing whose net diff touches any path it covers is refused (12) unless base holds a one-time approval `FILE-SET | sha256 of the net diff over exactly that set | reason | date`: the FILE-SET is the touched paths sorted and comma-joined (one path is the existing single-file record). The list, the configuration and the hooks directory are always in the set; an empty, missing or malformed list refuses everything; renames, mode changes, symlinks and submodules count as touches; the judge runs again after Tier 1 regenerated files. `--print-gate-diff-hash` and `--print-gate-diff` take a comma-joined set or `@protected`. Records may now name paths with a leading dot. With the key unset nothing changes.
  What it stops: a MISREAD (a protected change landed on a message that was not a land decision) is impossible without a line on base. A deliberate self-approval in two landings is stopped only by the announcement to the owner and the operating rule that approval lines land only through the owner after an explicit land decision (`docs/gate-edit-approvals.md`). A revert of a protected change needs the approval too; on a red base the approval landing needs the operator's `LAND_FIX_FOR_RED=1`. This repository's own `land.conf` does not enable the key. Consumers enable it one at a time, each enabling being a normal protected change with its own approval line. New test script `tests/test_protected.sh` and a `protected set:` family of mutants in `tests/test_mutations.sh`.

## 0.3.5
- Heavy-host guard (new vendored files `bin/no-build-guard`, `lib/no-build-host.sh`, `docs/no-build-host.md`, `templates/run-scoped.sh`). A host that carries a no-build marker (an empty file at `/etc/vbm/no-build-host` or `<config dir>/vbm/no-build-host`, either one) runs nothing heavy: `scripts/run-scoped.sh`, `bin/run-probe` and `bin/no-build-guard [-- CMD...]` refuse (exit 2, a clear message, nothing started). There is NO override: `VBM_ALLOW_BUILD_HERE=1` and every other variable are ignored, a moved `XDG_CONFIG_HOME` or `HOME` hides nothing, a dangling symlink counts. The scoped side of `run-scoped.sh` re-checks just before it execs; a helper with no guard installed next to it refuses. `bin/no-build-guard --lint [ROOT]` (+ `--selftest`) is the Tier 1 lint: the helper calls the guard before it starts anything and really refuses with a marker present; every runner declared in `scripts/long-runners.txt` or the new optional `scripts/heavy-runners.txt` (`NAME` or `self NAME`) goes through a helper. The attack list and what cannot be prevented (a deleted marker, a marker created after the check, indirection) are in `docs/no-build-host.md`. Upgrade notes: copy `scripts/land/templates/run-scoped.sh` over the repository's `scripts/run-scoped.sh` (it differs from the previous helper by the guard stanza only), add `scripts/land/bin/no-build-guard --selftest && scripts/land/bin/no-build-guard --lint .` next to the scoped-runner lint in Tier 1, and declare a probe or ABI test script that is run plainly in `scripts/heavy-runners.txt` as `self NAME` with a `scripts/land/bin/no-build-guard || exit 2` line near its top (or as `NAME` and wrap the call in `run-scoped.sh`). The machine's owner (or its configuration tool) creates the marker; a repository never does.

## 0.3.4
- Crash-probe hygiene (new vendored files `bin/run-probe`, `bin/no-crash-record`, `lib/no-crash-record.sh`, `docs/crash-probes.md`). Residual hole, accepted: an orphan that also setsid's, runs from a shared dir and leaves our scope is NOT caught. `no-crash-record end` fails only for a crash record that belongs to the landing's own tree (pid tree with start-time identity, session, own transient scope, own private TMPDIR or repository), never for another process's crash on the host; it fails closed (no begin state, a bad time, no scope id: the broad old filter). `run-probe CMD...` runs a deliberate-crash probe in a private TMPDIR with `ulimit -c 0` PLUS the dumpable-clear preload (`ulimit` alone still writes a crash-journal record: measured); `run-probe --require` refuses (exit 2) a probe not launched that way; `run-probe --lint LIST` finds a listed probe binary run outside the helper. Upgrade notes: a consumer's own `lib-no-crash-record.sh` and `no-crash-record.sh` become thin wrappers over the vendored lib (`exec scripts/land/bin/no-crash-record "$@"`); records are read from `journalctl -o json` (needs `jq`), `NOCRASH_JOURNALCTL` replaces the old `NOCRASH_COREDUMPCTL`.

## 0.3.3
- Fix: the upstream check (`land-check --upstream`), `land-update` and `install` clone a GitHub `OWNER/NAME` source ANONYMOUSLY over https first, and use `gh` only when that fails (a private source). A public source therefore needs no token, no `gh` login and no secret: on a hosted runner without a login the check used to fail with "cannot clone OWNER/NAME with gh" (exit 3). `VBM_LAND_URL_BASE` replaces `https://github.com` (the tests serve a local copy). The update workflow template says a public source needs no secret. Upgrade notes: none required; a private source still needs `GH_TOKEN` (the secret `VBM_LAND_TOKEN`).

## 0.3.2
- Gate-edit approvals: an approval commit adds exactly ONE line (one record), removes none and changes no other file; the landing that carries it is the same (one approval per landing, no tidying alongside): refused (12) otherwise. The `APPROVAL COMMIT` reminder now says the announcement to the judge carries the diff hash and the FULL edit diff. Upgrade notes: a landing that added several records at once, or tidied stale ones in the approval's landing, must now be split (one approval per landing; a stale record is tidied in a landing of its own).

## 0.3.1
- Fix: `lib/approvals.sh` no longer pipes into `head` under `set -o pipefail` (a repository's pipefail lint refused v0.3.0). v0.3.0 is superseded; roll to v0.3.1. `tests/lint.sh` now lints bin/ and lib/ for that class (`grep -q`, `grep -m`, `head` after a pipe).

## 0.3.0
- Gate-edit approvals (`lib/approvals.sh`, `docs/gate-edit-approvals.md`): a removed or changed line in a gate-defining file is accepted only on an exact diff-hash match against an approval already on the base branch. New keys, all optional: `LAND_GATE_APPEND_ONLY` (patterns of files that may only gain lines; default none), `LAND_APPROVALS` (default `scripts/gate-edit-approvals.txt`; always judged, always protected, cannot be empty), `LAND_APPROVAL_DAYS` (default 7). New: `land-direct --print-gate-diff-hash FILE [rev]` and `--print-gate-diff FILE [rev]`; the hooks see `LAND_GATE_APPROVED_FILE`; `land-direct` prints `APPROVAL COMMIT: announce to the judge before landing the edit`. Rules: approvals are read from base; an approval lands alone (its commit and its landing change no other file) and is announced to the judge before the edit; one-time (the edit's landing removes the record it uses); stale, future-dated, malformed, self-referencing and quietly removed records are refused (a fresh one is withdrawn by an `Approval-Withdrawn: FILE <12+ hex of the hash>` trailer in a landing that changes nothing else, announced to the judge); the judge fails closed. Honest limit (in the document): an agent with landing rights could write its own approval line; the control is the visible record the judge reads first. Upgrade notes: every repository now has the always-on rules for `scripts/gate-edit-approvals.txt` (it is added to the protected set automatically; a repository whose own judge or protected-paths list names its protected files should list it too); to use the approvals set `LAND_GATE_APPEND_ONLY`, or have your own `post-rebase` judge read `$LAND_GATE_APPROVED_FILE`. New vendored file `lib/approvals.sh`.

## 0.2.2
- Skill and docs wording only: no internal name in the vendored skills (a consumer's public-readiness lint refused v0.2.1). v0.2.1 is superseded; roll to v0.2.2.

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
