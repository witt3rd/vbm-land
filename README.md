# vbm-land

A small, language-neutral tool for landing changes **directly on the main branch** of a repository that only you and your own agents work in: one lander, a mechanical gate, a single definition of "main is red", and a hold switch. Plain bash, git and `gh`. Nothing in it knows what language your repository is written in.

It is a tool, not a verified library: it is not scored by the [VBM](https://github.com/witt3rd/vbm) scorecard (which measures proofs), and its own assurance is its test suite, including a negative test for every refusal and a mutation self-test that cuts each guard out in turn ([6.1](#61-what-is-here-today)).

> **Status: early (0.3.x), used in production by its author's own repositories.** The lander, the red check, the known-flaky rerun, the Tier 2 freeze, pinned vendoring with a drift check, signed releases, gate-edit approvals and the test suite exist. The revert-first watchdog and group landing are not built yet ([6.1](#61-what-is-here-today)). The interface (configuration keys, exit codes, the JSON last line, hook names, marker names) is versioned: additive changes are minor releases, anything else is major ([6.6](#66-installing-it-into-a-repository-a-pinned-vendored-copy)).

**Who it is for.** A repository whose only writers are you and agents you control, whose main branch is not deployed, and whose fast gate runs in about a minute. **Who it is not for:** repositories with outside contributors, or where a merge to main is automatically a production change ([3](#3-choosing-a-mechanism-is-this-tool-for-your-repository)). It does not defend against an adversary with write access ([6.5](#65-trust-model)).

## Quick start

Requirements: bash 4+, git 2.30+, util-linux `flock`, `timeout`, `gh` (only for the red check, which reads your CI), and, for the tests, `jq`, `python3`, `ps` (procps) and `ssh-keygen` (openssh-client). Linux only for now.

```
# 1. Get a release and check its signature (the maintainer's public key is scripts/land.signers; its fingerprint is in docs/signing.md)
git clone https://github.com/witt3rd/vbm-land && cd vbm-land
TAG=$(git tag --sort=-v:refname | head -n1)      # or pick a version
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=scripts/land.signers verify-tag "$TAG"

# 2. Vendor that release into YOUR repository (writes files, commits nothing)
./install --source https://github.com/witt3rd/vbm-land --target /path/to/your/repo --signers scripts/land.signers "$TAG"

# 3. In your repository: review, commit, land
cd /path/to/your/repo && git add -A && git commit -m "chore(land): vbm-land ${TAG#v}"
scripts/land/bin/land-check            # the drift check: the vendored copy is exactly the release
scripts/land-direct --dry-run          # everything except the push
```

Edit the starter `scripts/land.conf` (at least `LAND_TEST_CMD`, your Tier 1 command) before the first landing. The whole sequence for an existing repository is in [Adopting it in an existing repository](#adopting-it-in-an-existing-repository).

## The discipline on one page

1. **Land small changes directly on main**, within minutes, through one lander. No pull requests, no queue of reviewers: a mechanical gate decides.
2. **Tier 1 gates landing** (target under 60 s) and runs on the exact combination that will land: your change rebased on current main. **Tier 2 never gates landing**; it runs after the merge and can only start the watchdog.
3. **Main is red when the Tier 1 job of its latest push failed.** One definition, in one place. A failure of the infrastructure (a runner that never started, a billing limit) is not red; not knowing is not green either: the lander refuses.
4. **While main is red or frozen only a fix or a revert lands**, recognised by what it touches (tests and CI paths, nothing protected), not by its title.
5. **New behaviour lands switched off.** Landing is not release.
6. **Small means small**: 150 lines of production code and 45 minutes without a passing build are the defaults. Over either, cut the work.
7. **The lander never forces.** It pushes a plain fast-forward, under a lock with a lease, after up to three rebase-and-retest tries. A hold marker stops landings at any moment.
8. **The rules come from main, not from your change**: `land.conf` and the hooks are read from `origin/main`, so a commit cannot loosen the rules it is judged by. Gate-defining files are protected and a gate edit that removes or changes a line needs a recorded approval.
9. **Nothing is deleted before it is archived**: a diff and a one-line reason first.
10. **Escalate only** money, data loss, secrets, publishing and harm to a third party. Decide the rest, and log it.

Sections 1 to 5 below are this page in full; section 6 is the tool.

## 1. The one idea

**A small change reaches `main` within minutes, `main` is always green, and a mechanical gate (never a person's mood or a queue of reviewers) decides.**

Everything below serves that sentence. A person still decides what to build and what a gate checks. A person does not decide, change by change, whether a gate-passing change may land.

## 2. The three things trunk-based work needs

1. **A fast gate.** Minutes, not an hour. The gate is the ceiling on how many changes can land: if it takes 5 minutes and changes land one at a time, the best case is 12 an hour. Slow checks run after the merge, not before.
2. **Landing decoupled from release.** Landing means "on main". It does not mean "in production". Unfinished work lands switched off; a release is a separate, reversible act. Without this, every landing is a production event and has to be slow and careful.
3. **Small changes.** Size and conflicts are strongly linked: in one measured, busy codebase, changes of at most 300 lines and 60 minutes conflicted 3.3% of the time, and everything else 25.4%. A sensible house limit is 150 lines of production code and 45 minutes without a passing build; over either, stop and cut the work into pieces that land in order.

## 3. Choosing a mechanism: is this tool for your repository?

Ask three questions in this order:

1. **Who else works in the repository?** Only your own agents on one machine: one lander can serialise everything, so land directly with no pull requests. People outside your control, or other teams: use pull requests, because the pull request is the shared place for their review and consent. **vbm-land is not for repositories with outside contributors.**
2. **Does main deploy?** If a landing is automatically a production change, landing is not yet decoupled from release. Keep a merge queue and a human-readable record until a staged roll-out exists. If main is not deployed (a library, a spec, an internal tool), direct landing is fine. **vbm-land is not for a deployed main.**
3. **How slow is the gate?**
   - Under 60 s ("Tier 1"): direct landing works, one commit per gate run.
   - 1 to 5 minutes: batch the gate (one run per group, bisect on failure), or use a speculative merge queue.
   - Over 5 minutes: fix the gate before choosing anything. Split it into tiers; nothing downstream helps until the gate is fast.

Compact form: **alone + not deployed + fast gate = direct to main. Shared or deployed = pull requests through a queue. Slow gate = tier it first.**

## 4. The policy a repository adopts

### 4.1 The agent-instructions block

Paste at the top of the repository's agent instructions (`AGENTS.md` or equivalent) and fill the bracketed name:

```markdown
## Landing (direct to main, no PRs)
- Work in a worktree off a fresh origin/main. Diff ≤150 production lines, ≤45 min without a passing build; over either, stop and write a decomposition plan.
- Commit locally with Conventional Commits. Land only with [LANDER, e.g. scripts/land-direct]; never push main yourself, never force-push it, never open a PR.
- New behaviour lands behind a flag that defaults OFF. Interface changes: add beside the old, migrate callers, delete at zero references.
- Main is RED when the Tier 1 job of its latest push failed. While red or frozen, only a fix or revert lands. Never hotfix on main: pull the revert, reproduce in a new worktree, resubmit.
- Decide anything reversible and log it. Escalate only money, data loss, secrets, publishing, or harm to a third party; say so in one line and stop.
```

### 4.2 Two gate tiers

- **Tier 1, before landing, target under 60 s.** Build with zero warnings, type check, lints, affected tests, the repository's own fast ratchets. It runs on the exact combination that will land (the change rebased on current main). It gates landing.
- **Tier 2, after the merge, target under 5 minutes.** The slow checks: full integration, fuzzing, deep proofs, end to end. It runs on main's head. **Tier 2 never gates landing.** It can only start the watchdog (4.5).

### 4.3 The lander

One coordinator per repository; workers never push main. Under one lock it: checks main is not red or frozen; rebases the change onto current main; regenerates generated files (never merges them by hand); runs Tier 1 on that combination; if main moved meanwhile, rebases and runs again (three tries); then pushes a plain fast-forward, never forced. History stays linear, each commit its own. When one gate run per commit becomes the bottleneck, it takes groups: one Tier 1 for the group, binary search on failure to eject the culprit, the rest land. The exit status tells the worker what to do (landed; conflict: fix and run again; gate failed; held; busy: run again).

### 4.4 RED, exactly

**Main is red when the Tier 1 job of its latest push failed.** That is the whole definition, in one place in the repository, read by the lander and the watchdog. Tier 2 does not define red. A failure that is the infrastructure's (a runner that never started, a network error, a billing limit) says nothing about the commit and is not red; neither is a run that has not finished. Not knowing (the CI service cannot be asked) is not green either: the lander refuses.

### 4.5 Freeze and watchdog

- When Tier 2 fails on main, the watchdog **reverts first** and debugs second: it reverts the failing commit and freezes landing.
- **Re-check HEAD before reverting**: if main has moved on or someone already fixed it, do not revert a good commit.
- While frozen or red, the lander takes only a fix or a revert, recognised by what it touches (only test or CI paths, nothing protected), not by what its title says.
- A freeze has a named owner, an expiry and a clearing action; it lifts on a green run.
- A hold marker lets a person stop landings at any moment, even one already in flight.
- For repositories with an owner and a ruleset: the watchdog first alerts and opens a revert for a person, and reverts by itself only after two green weeks.

### 4.6 Archive, then discard

Before a worktree, branch or pull request is thrown away (time limit hit, work decomposed, change superseded), save its diff and a one-line reason where a person can find it. Then discard. Nothing is deleted that has not been archived, and a declared source tree is never removed by hand.

### 4.7 Escalation threshold

Decide everything reversible yourself and log it. Escalate **only** for: money (spending past the caps), data loss (deleting data or history), secrets, publishing (anything leaving the repository or the organisation), and harm to a third party. Say it in one line and stop.

## 5. The three metrics

Measure the same three numbers in every repository:

| Metric | What it is | Aim |
|---|---|---|
| **Landings per hour** | commits merged to main | throughput; the gate time is the ceiling |
| **p90 commit-to-main** | minutes from "ready" to "on main" for the slowest 10% | a few minutes |
| **Red minutes on main** | minutes per week main is red or frozen | near zero; every red minute is a reported incident |

Hosted CI minutes are usually a budgeted resource. A cheap pattern: run Tier 1 in CI only on a push to main (an independent check of what the lander already ran locally) and Tier 2 on a schedule, not on every pull request.

## 6. The tool

### 6.1 What is here today

| Path | What it is |
|---|---|
| `bin/land-direct` | The lander: the configurable core of section 4.3. Lock with a lease, hold and freeze markers, land-time checks, rebase in a scratch worktree, regeneration of generated files, hooks, Tier 1 on the rebased combination, three tries, plain fast-forward push, an exit code that says what to do next, a JSON last line, a metrics log. |
| `bin/land-red` | The one definition of a red main (4.4): modes `push`, `push+dispatch`, `off`; the infrastructure classifier; the freeze marker. |
| `bin/run-probe`, `bin/no-crash-record`, `lib/no-crash-record.sh` | Crash-probe hygiene: deliberate-crash probes run in a private TMPDIR with `ulimit -c 0` plus the dumpable-clear preload (a probe launched otherwise is refused); the landing's no-crash-record check reads only crashes of its own process tree, session, scope or private directories. |
| `bin/no-build-guard`, `lib/no-build-host.sh`, `templates/run-scoped.sh` | The heavy-host guard (`docs/no-build-host.md`): a host that carries a no-build marker (`/etc/vbm/no-build-host` or `<config dir>/vbm/no-build-host`) makes the helpers refuse (exit 2, nothing started; no override); `--lint` is the Tier 1 check that every declared long runner goes through a helper. |
| `lib/` | `conf.sh` (the configuration reader), `infra-re.sh` (the infrastructure classifier), `freeze.sh`, `approvals.sh` (the gate-edit approvals judge, `docs/gate-edit-approvals.md`). |
| `install`, `bin/land-check`, `bin/land-update`, `bin/land-audit`, `bin/land-manifest`, `MANIFEST.sha256` | Pinned vendoring (6.6): the installer, the drift check, the updater, the audit across repositories, and the manifest of every file a consumer vendors. |
| `skills/` | Agent skills (`SKILL.md`): new-repo, land-a-change, triage-red, update-vbm-land, hold-and-freeze, adopt-in-existing-repo, release. A consumer gets them in `.agents/skills/` (installed and updated with the tool, drift-checked like it). |
| `templates/` | A starter `land.conf` with examples for four ecosystems, the agent-instructions block, a CI workflow with Tier 1 on push and Tier 2 on a schedule, the branch and tag rulesets, and the public-repository settings checklist. |
| `scripts/land.conf`, `scripts/land-direct` | This repository's own configuration and entry script: the repository lands itself with its own lander. |
| `scripts/bootstrap-land` | A minimal, dependency-light lander. It landed this repository's first commits and stays as the recovery path if the full lander is ever broken on main. |
| `tests/` | The test suite (below). `tests/run.sh` is this repository's Tier 1: the lints, then every `tests/test_*.sh` in parallel (about half a minute). |
| `.github/workflows/ci.yml` | Tier 1 on a push to main. |

Not built yet: the revert-first watchdog (the freeze marker and its Tier 2 trigger exist; the revert does not), a batch coordinator (the lander has its half: `--group`, `LAND_LOCK_HELD`), a known-flaky list lint, a macOS lock fallback.

Requirements: bash 4+, git 2.30+, util-linux `flock`, `timeout`, `gh` (the red check). The tests also need `jq`. Linux only for now.

**The tests.** Each test script builds a scratch repository with a bare "remote", worker clones and a fake `gh` (answers `run list`/`run view` from files), and drives the real scripts. `test_land_direct.sh` has a negative test for every refusal (each exit code, and that nothing reached the remote); `test_vendor.sh` covers install, update, audit, every kind of drift (an edit, a deleted or extra file, a lost executable bit, a forged pin and tree) and the lander refusing a change to its own vendored copy; `test_mutations.sh` cuts each guard out of a copy of the lander in turn and requires the matching scenario to stop being refused (a guard nothing depends on would be found there); `test_approvals.sh` drives the gate-edit approvals through the real lander (every attack on them is refused: a forged approval, a hash over a different diff, a reused approval, a stale one, one removed afterward, the approvals file edited in the same commit or landing as the edit); `test_bootstrap.sh` covers the recovery lander; `lint.sh` keeps internal names and local paths out of this repository.

### 6.2 Using it

A repository that lands with this tool has a `scripts/land.conf` (below) and tells its agents to run the lander from their worktree:

```
bin/land-direct                       # land the local commits that are not on origin/main yet
bin/land-direct --dry-run             # everything except the push
bin/land-direct --check               # only the land-time checks (commit messages, size budget)
bin/land-direct --group               # a batch coordinator's entries: the size budget is waived (it checked each one); with LAND_LOCK_HELD=1 in the environment the coordinator holds the lock and none is taken
bin/land-direct --hold "reason"       # stop every landing in this clone (even one in flight, right before its push) ...
bin/land-direct --release             # ... until released
bin/land-direct --freeze "reason" --owner NAME --for 6h   # only fixes and reverts land, until the expiry, --thaw, or a landed fix
bin/land-direct --status
```

Exit codes: `0` landed; `1` stopped with a message (base kept moving, push refused, a bad commit message, over the size budget); `2` bad input or bad configuration; `10` main is red or cannot be known; `11` rebase conflict (the files are named; rebase in your worktree and run again); `12` refused by a hook, by the regeneration, or by the drift check; `13` Tier 1 failed (nothing landed); `14` held or frozen; `15` busy (run it again). The last line of standard output is JSON: `{"sha","commits","tier1_seconds","result","exit"}` plus any keys a `json-fields` hook adds.

Locks, markers, logs and the scratch worktree live in `<git common dir>/vbm-land/`, shared by every worktree of the clone. The lander never runs `git worktree prune` and never removes a worktree it did not create: other lanes' worktrees live in the same clone.

### 6.3 Configuration

`scripts/land.conf` is **data**: one `LAND_KEY=value` per line, `#` comment lines, nothing is expanded or executed while it is read, and an unknown key is an error, so a typo cannot silently switch a gate off. The lander reads it from `origin/<base>`, not from your change: a commit cannot loosen the rules it is judged by (only the very first landing, when main has no such file yet, uses the working tree's copy).

| Key | Default | Meaning |
|---|---|---|
| `LAND_BASE`, `LAND_REMOTE` | `main`, `origin` | The branch landed on and the remote that holds it. |
| `LAND_GATES_CMD`, `LAND_TEST_CMD` | none | **Tier 1**: the gates command, then the test command, run with `bash -c` in the scratch worktree on the rebased combination. At least one is required. |
| `LAND_REGEN_CMD` | none | Regenerates generated files after a rebase conflict confined to them (the conflict takes base's file, then this runs). Failing refuses (exit 12). |
| `LAND_GEN_CMD` | none | Always run on the rebased tree; anything it changes lands as a commit of the lander. |
| `LAND_GENERATED_LIST` | none | Path of a file listing generated paths, one per line, read from base. |
| `LAND_PROD_PATHS`, `LAND_BUDGET_LINES` | none, `150` | The size budget: changed lines under these paths (not generated ones) may not exceed the budget unless a commit carries a `Diff-Budget: <decomposition note>` trailer. |
| `LAND_REQUIRE_TRAILERS` | none | Trailer names every commit must carry (for example `Task-ID`). |
| `LAND_CONVENTIONAL`, `LAND_COMMIT_TYPES` | `1`, the usual types | Require `type(scope): summary` subjects; git's own `Revert "..."` is accepted. |
| `LAND_PROTECTED` | none | Shell patterns (`*` matches `/`): the gate-defining set. A change that touches it is judged by the `post-rebase` hook; it never counts as a fix for a red main. |
| `LAND_GATE_APPEND_ONLY` | none | Shell patterns: gate-defining files that may only GAIN lines. A removed or changed line, a deletion or a mode change is refused (12) unless an approval for exactly that diff is already on base (`docs/gate-edit-approvals.md`). |
| `LAND_APPROVALS`, `LAND_APPROVAL_DAYS` | `scripts/gate-edit-approvals.txt`, `7` | The gate-edit approvals file (always on, always protected, never empty) and how many days an approval stays usable. Records `FILE \| sha256 of the exact diff \| reason \| YYYY-MM-DD`; `land-direct --print-gate-diff-hash FILE` prints the hash. One-time, read from base, landed alone and announced to the judge first. The honest limit is in the document. |
| `LAND_PROTECTED_LIST`, `LAND_PROTECTED_APPROVALS` | none, the gate-edit approvals file | Path (read from base) of a **protected-paths list**, and the approvals file for it. A landing whose net diff touches any path the list covers (the list itself, the configuration and the hooks always count) is refused (12) unless an approval `FILE-SET \| sha256 of the net diff over that set \| reason \| date` is on base: one-time, exactly that set. An empty or missing list refuses everything. `land-direct --print-gate-diff-hash @protected`. `docs/gate-edit-approvals.md`, "Protected sets". |
| `LAND_FIX_PATHS` | none | When set, a fix for a red main may touch only these paths (tests, CI). |
| `LAND_RED_MODE` | `push` | `push`, `push+dispatch` or `off` (see 4.4). |
| `LAND_CI_WORKFLOW`, `LAND_TIER1_JOB`, `LAND_RED_WAIT` | `ci.yml`, `tier1`, `60` | What the red check reads, and how long it waits for a Tier 1 that is still running. |
| `LAND_KNOWN_FLAKY`, `LAND_FLAKY_RERUN_WAIT` | none, `300` | Path (in the repository, read from base) of the **known-flaky list** (`name owner YYYY-MM-DD issue`, one per line; an entry that is expired or lacks an owner or an issue is not listed: entries are debt), and the seconds to wait for the one rerun. When Tier 1 of base failed and **every** test its failed log names (`FAIL <path>` or `FLAKY <path>`) is listed, the failed job is rerun once (never a second time, never for an unlisted failure); green means not red. Each rerun is a line in `<git common dir>/vbm-land/known-flaky.log`. |
| `LAND_TIER2_JOB` | none | The name of the Tier 2 job. When set, a real failure of it in the latest completed run freezes landing for 24 h (owner `land-red`; an infrastructure failure does not), a green run lifts the freeze `land-red` set (never one a person set); a fix or a revert still lands. |
| `LAND_HOOKS_DIR` | `scripts/land.d` | Where the repository's hooks live. |
| `LAND_AUTO_UPDATE` | `none` | `none`, `patch` or `minor`: what the scheduled update workflow may land by itself (`land-update --auto`); a major release never. |
| `LAND_LOCALE` | `C` | Pinned for collation and glob order. |
| `LAND_LOCK_WAIT`, `LAND_TIER1_TIMEOUT`, `LAND_STEP_TIMEOUT`, `LAND_GIT_TIMEOUT` | `90`, `1800`, `600`, `180` s | The lock wait and the bound on every step. A step that runs over is killed with one plain line and the run stops as that step's failure. |

Policy is never read from the environment. The operator may set `GH` (the `gh` binary), `LAND_CONF` (another config file), `LAND_FIX_FOR_RED=1` (declare this change the fix for a red main), `LAND_LOCK_WAIT_SECONDS`, `LAND_LEASE_STALE_SECONDS`, `LAND_DIRECT_LOG` and the three timeouts. Commands the lander runs see `LAND_TOP`, `LAND_BASE_REF` (`origin/main`), `LAND_STATE_DIR` and `LAND_TASK`.

### 6.4 Hooks

Hooks are executables in `scripts/land.d/`, taken from `origin/<base>` (so a change cannot rewrite the check that judges it) and run in the scratch worktree, bounded. A hook is gate-defining code: put the directory in `LAND_PROTECTED`.

| Hook | When | A non-zero exit |
|---|---|---|
| `prepare` | once, when the scratch worktree is created (warm a cache, for example) | refuses (12) |
| `pre-rebase` | before the rebase, on your commits | refuses (12) |
| `post-rebase` | on the rebased and regenerated tree; gets `LAND_TOUCHED_FILE` (the changed paths), `LAND_PROTECTED_TOUCHED` and `LAND_GATE_APPROVED_FILE` (`FILE HASH` of every gate-edit approval this landing consumes) | refuses (12) |
| `post-tier1` | after Tier 1 passed: a gate that judges the tree Tier 1 just built (an attack suite, say) | refuses (12) |
| `json-fields` | after Tier 1; prints `key=value` lines added to the JSON result (keys `[a-z_]+`; the contract keys cannot be overridden) | ignored |
| `on-run` | at the end of every run, with `LAND_RESULT` | ignored |

### 6.5 Trust model

The tool is for a repository whose only writers are cooperating agents and people, not for adversaries. It makes mistakes mechanical failures: the gate runs on the exact combination, config and hooks come from main, the push is a plain fast-forward, an unknowable CI state refuses, and a lock with a lease cannot be wedged by a dead holder. A lander runs repository-supplied commands with your credentials; protect the gate-defining set accordingly. The lander is the copy in the worktree it is run from; what protects the main branch is the drift check on the rebased tree (6.6), the configuration and hooks read from main, and the independent push CI.

**Gate-edit approvals.** A gate file that may only gain lines (`LAND_GATE_APPEND_ONLY`) loses or changes a line only on an exact diff-hash approval that is already on main: a record in `scripts/gate-edit-approvals.txt`, landed alone (one line, nothing else) in its own commit, announced to the independent judge BEFORE the edit lands, consumed (removed) by the edit's own landing, valid for 7 days (or withdrawn by an `Approval-Withdrawn:` trailer, also announced). Honest limit: an agent with landing rights could write its own approval line; the control is that approvals are visible one-commit records the judge reads before the edit lands, so the approval commit is announced to the judge before the edit commit, always. `land-direct` prints `APPROVAL COMMIT: announce to the judge before landing the edit` whenever one is on its way. Rules, hash definition and steps: `docs/gate-edit-approvals.md`.

### 6.6 Installing it into a repository: a pinned, vendored copy

A repository does not depend on this one at run time. It **vendors a pinned copy** and commits it: a worktree is self-contained and offline, the lander of a landing is the one in the tree being landed, and the history shows exactly which release landed what. (Rejected: a git submodule, which breaks fresh and detached worktrees; a language package manager, which is not language-neutral; fetching the tool when landing, which would let the lander change under a landing.)

One command, run in the target repository (`SRC` is a git URL or path, or `OWNER/NAME` on GitHub, read through `gh`, which also reaches a private source):

```
# from a checkout of this repository (see the Quick start), or any other source:
/path/to/vbm-land/install --source https://github.com/witt3rd/vbm-land --signers /path/to/vbm-land/scripts/land.signers <tag>
# through gh, without a checkout:
gh api repos/witt3rd/vbm-land/contents/install?ref=<tag> -H 'Accept: application/vnd.github.raw' | bash -s -- --source witt3rd/vbm-land <tag>
```

It writes, and commits nothing (review the diff, commit it as `chore(land): vbm-land <version>`, land it like any other change):

- `scripts/land/` the tool, read-only by contract;
- `scripts/land/MANIFEST.sha256` the hash of every vendored file, copied from the release;
- `scripts/land/PIN` `source`, `version`, the 40-hex **`commit`** (a tag can move, a commit cannot) and `manifest_sha256`;
- `.agents/skills/<name>/SKILL.md` the agent skills, one per file in `skills/` of the release;
- `scripts/land-direct` a three-line entry script that runs the vendored lander, so "land with `scripts/land-direct`" stays true, **only if absent**: it is the repository's own afterwards (add an environment variable before the exec); the drift check only requires that it is executable and still runs `scripts/land/bin/land-direct`;
- `.github/workflows/vbm-land-update.yml` the scheduled check (on dispatch, plus weekly only when the source is public (`.github/visibility`); read-only, a workflow of its own so it can never make the base branch red): the drift check with `--upstream`, then `scripts/land/bin/land-update --auto`: with the default `LAND_AUTO_UPDATE=none` it only reports `pinned X, latest Y, behind N (patch|minor|major)` as a warning and a summary line (like `--check`); with `LAND_AUTO_UPDATE=patch` or `minor` in `scripts/land.conf` it lands the newest release of that class itself through the repository's own lander (`land-update --land`), using a push token the repository holds (`VBM_LAND_PUSH_TOKEN`) on a runner that has its Tier 1 toolchain; a major release is never automatic, and a red or a refusal stops it with a failing job; only if absent;
- `scripts/land.conf` a starter, **only if there is none**.

Before writing anything the installer checks every file it fetched against the manifest at that same commit, and refuses a release that does not match or has no manifest. `templates/AGENTS-block.md` is the agent-instructions block to paste; `templates/ci.yml.example` is the CI workflow.

**No local patches.** A repository that needs something different adds a configuration key or a hook upstream (one change, one release), or uses a hook of its own; it never edits the copy. The rule is mechanical:

- `scripts/land/bin/land-check` is the **drift check**. Offline (run it in Tier 1; the lander also runs it on the rebased tree and refuses with exit 12): the manifest must hash to the pin, every vendored file (the tool, the templates, the skills) must hash to its entry and keep its executable bit, nothing else may sit in `scripts/land/`, and the repository's own `scripts/land.conf` (known keys) and `scripts/land.d/` (hooks have the fixed names above and must be executable; `*.sh` files are helpers the hooks source) must be well formed. Any difference fails: *edit vbm-land, not the copy*.
- `scripts/land/bin/land-check --upstream` (the scheduled Tier 2, or by hand) also fetches the manifest at the **pinned commit** from the source and requires it to match, so a forged pin and tree edited together fail; it prints when a newer release exists (advice, never a failure) and exits 3 when the source cannot be reached (not verified).
- `scripts/land/bin/land-update <tag|commit>` replaces the tree and the pin with another release and verifies it; it commits nothing.
- `bin/land-audit DIR...`, run from this repository, prints for each repository its pin, whether it is intact, and how far behind it is: the rollout table, from the repositories themselves.

How a repository gets the next release (pull only: a scheduled check and `land-update` in the consumer) is designed in [docs/update-propagation.md](docs/update-propagation.md).

**Signed releases.** A release is a signed, annotated tag made by `bin/land-release` (maintainer only; an ssh key in `LAND_SIGNING_KEY`, no gpg): the tag message records the hash of `MANIFEST.sha256`, so the signature binds the manifest and, through it, every vendored file. A consumer lists the public keys it trusts in its own `scripts/land.signers` (an ssh allowed-signers file, taken from the source out of band: `install --signers FILE`; this repository's own is `scripts/land.signers`, fingerprint and rotation in [docs/signing.md](docs/signing.md)). With that file present, `install` and `land-update` **refuse**, before anything of the new release runs or is written, a ref that is not a signed annotated tag, a signature that does not verify against the file, an unknown signer, or a tag whose recorded manifest hash differs from the manifest at that commit. Without a signers file they say `UNVERIFIED` and go on (the pin records `signature=unverified`). `land-update --land <tag>` is the whole update as the repository's own act: verify, stage, commit `chore(land): vbm-land <version>` (with the trailers its `land.conf` requires), and land it through the repository's **own** lander and gates, run from a pristine fresh clone of the base branch (the old lander lands the new copy); a hold, a red main, a failed Tier 1 or a refusing hook stops it with the lander's exit code, the commit stays local, nothing is forced. `land-update --diff <tag>` verifies the release and prints what it would change (changed, added and removed files with their diffs, and the CHANGELOG entries newer than the pin) without changing anything.

A release is a tag whose commit has a fresh `MANIFEST.sha256` (`bin/land-manifest`; Tier 1 here fails on a stale one). Additive changes to the interface (configuration keys, exit codes, the JSON line, hook names, marker names) are minor, anything else is major; `CHANGELOG.md` has a line per interface change.

### 6.7 Protecting the branch

The lander **never force-pushes**: it pushes a plain fast-forward (`git push <remote> <sha>:<branch>`), so a remote that refuses non-fast-forward updates changes nothing about how it works, and a test and a mutation self-test keep it that way. Make the remote say the same: apply `templates/ruleset-protect-main.json` to the default branch (deletion and non-fast-forward updates refused; **no required pull request and no bypass list**, so a fast-forward landing still works) and `templates/ruleset-protect-release-tags.json` to release tags (no deletion, no update: a pin by tag cannot be moved). `templates/PUBLIC-REPO-SETTINGS.md` is the checklist for a repository that is, or is about to be, public (approval of fork pull-request workflows for all outside contributors, a read-only workflow token that cannot approve pull requests, private vulnerability reporting, secret scanning with push protection, deleting merged branches). `bin/land-audit` warns when a repository's default branch lacks the branch protection (asked of GitHub through `gh`; offline it says "unknown"). `skills/new-repo/SKILL.md` is the whole sequence for a new repository.

## Adopting it in an existing repository

Preconditions (all three): only you and your agents write to it; main is not deployed; Tier 1 can be about a minute or less. If not, keep pull requests.

1. **Define Tier 1**: one command that builds, lints and runs the fast tests. Time it. Over a minute: move the slow checks to Tier 2 first.
2. **CI shape**: Tier 1 on `push` to main only, in a job named `tier1`; Tier 2 on a schedule (`templates/ci.yml.example`). Remove the `pull_request` trigger and any merge-queue workflow.
3. **Vendor a signed release** (Quick start, in a fresh worktree off `origin/main`).
4. **Configure `scripts/land.conf`**: `LAND_TEST_CMD` or `LAND_GATES_CMD`, `LAND_PROTECTED` (gate-defining files), `LAND_FIX_PATHS` (tests and CI), `LAND_PROD_PATHS`. Start with `LAND_RED_MODE=push` if CI already runs on push, else `off`.
5. **Agent instructions**: paste `templates/AGENTS-block.md` into your `AGENTS.md` and delete any "open a PR" text.
6. **Land the adoption itself** with the new lander: `scripts/land/bin/land-check && git add -A && git commit -m 'chore(land): adopt vbm-land vX.Y.Z' && scripts/land-direct`, then read the push CI.
7. **Retire the PR flow**: archive each open PR's diff and a reason, then close it.

The same steps as an agent skill, with the do-not list: `skills/adopt-in-existing-repo/SKILL.md` (vendored into your repository with the tool). A repository created from scratch: `skills/new-repo/SKILL.md`.

## Updating

Pull only: a repository decides when it takes a release. `scripts/land/bin/land-update --check` reports `pinned X, latest Y, behind N (patch|minor|major)`; `--diff <tag>` verifies a release and shows what would change (files, diffs, the CHANGELOG entries since your pin, including "Upgrade notes"); `--land <tag>` verifies, stages, commits and lands the update through your own lander and your own gates. A scheduled workflow (`.github/workflows/vbm-land-update.yml`, installed with the tool) runs the drift check against the pinned commit and the check above; with `LAND_AUTO_UPDATE=patch|minor` it can land patch or minor releases itself, never a major. Design and rationale: [docs/update-propagation.md](docs/update-propagation.md).

## Versions and signed tags

Releases are annotated, ssh-signed tags `vX.Y.Z` made by `bin/land-release`. The tag message records the sha256 of `MANIFEST.sha256`, which lists every file a consumer vendors, so the signature covers the whole vendored tree. A consumer that holds `scripts/land.signers` makes `install` and `land-update` refuse anything that is not a signed tag from a listed signer. The key, its fingerprint (check it out of band), how to verify a tag by hand and how rotation works: [docs/signing.md](docs/signing.md). Each release has a section in [CHANGELOG.md](CHANGELOG.md); a release that adds or changes an interface item carries "Upgrade notes". Pins record the 40-hex commit, never only the tag. `v0.1.0` predates signing and does not verify; `v0.2.0` is the first signed release.

## Honest limits

- **Not for adversaries.** A lander runs repository-supplied commands with your credentials; the protections (config and hooks read from main, the drift check, the independent push CI, gate-edit approvals) turn mistakes into mechanical failures. They do not stop an agent that holds landing rights and wants to cheat ([6.5](#65-trust-model); the approvals' limit is stated in [docs/gate-edit-approvals.md](docs/gate-edit-approvals.md)).
- **Not built yet:** the revert-first watchdog (the freeze marker and its Tier 2 trigger exist; the revert does not), a batch coordinator (the lander has its half), a known-flaky list lint, a macOS lock fallback. Linux only.
- **One writer population.** Pull requests are the right tool for outside contributors. This one is not, and a repository that adopts it should say so.
- **The red check depends on your CI** being readable through `gh`; when it cannot be asked, landing stops rather than guessing.
- **Early.** The interface is versioned, but 0.x: read the CHANGELOG before a minor update.
- **Public history as published.** The history was published as it stood, not re-written: early commit messages carry internal task identifiers and the author's name ([docs/flip-record.md](docs/flip-record.md)).
- **Security and conduct of contributions:** [SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
