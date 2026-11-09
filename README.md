# vbm-land

A small, language-neutral tool for landing changes **directly on the main branch** of a repository that only you and your own agents work in: one lander, one mechanical gate before the push (nothing runs after it), and a hold switch. Plain bash and git. Nothing in it knows what language your repository is written in.

It is a tool, not a verified library: it is not scored by the [VBM](https://github.com/witt3rd/vbm) scorecard (which measures proofs), and its own assurance is its test suite, including a negative test for every refusal and a mutation self-test that cuts each guard out in turn ([6.1](#61-what-is-here-today)).

> **Status: early (0.x), used in production by its author's own repositories.** The lander (no lock, bounded retries), pinned vendoring with a drift check, signed releases, the hooks and the test suite exist. Group landing is not built yet ([6.1](#61-what-is-here-today)). The interface (configuration keys, exit codes, the JSON last line, hook names, marker names) is versioned: additive changes are minor releases, anything else is major ([6.6](#66-installing-it-into-a-repository-a-pinned-vendored-copy)).

**Who it is for.** A repository whose only writers are you and agents you control, whose main branch is not deployed, and whose fast gate runs in about a minute. **Who it is not for:** repositories with outside contributors, or where a merge to main is automatically a production change ([3](#3-choosing-a-mechanism-is-this-tool-for-your-repository)). It does not defend against an adversary with write access ([6.5](#65-trust-model)).

## Quick start

Requirements: bash 4+, git 2.30+, `timeout`, util-linux `flock` (only `scripts/bootstrap-land`, the recovery lander), and, for the tests, `jq`, `python3`, `ps` (procps) and `ssh-keygen` (openssh-client). Linux only for now.

```
# 1. Get a release and check its signature (the maintainer's public key is .land/land.signers; its fingerprint is in docs/signing.md)
git clone https://github.com/witt3rd/vbm-land && cd vbm-land
TAG=$(git tag --sort=-v:refname | head -n1)      # or pick a version
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=.land/land.signers verify-tag "$TAG"

# 2. Vendor that release into YOUR repository (writes files, commits nothing)
./install --source https://github.com/witt3rd/vbm-land --target /path/to/your/repo --signers .land/land.signers "$TAG"

# 3. In your repository: review, commit, land
cd /path/to/your/repo && git add -A && git commit -m "chore(land): vbm-land ${TAG#v}"
.land/tool/bin/land-check              # the drift check: the vendored copy is exactly the release
.land/land-direct --dry-run            # everything except the push
```

Edit the starter `.land/land.conf` (at least `LAND_TEST_CMD`, your Tier 1 command) before the first landing. The whole sequence for an existing repository is in [Adopting it in an existing repository](#adopting-it-in-an-existing-repository).

## The discipline on one page

1. **Land small changes directly on main**, within minutes, through one lander. No pull requests, no queue of reviewers: a mechanical gate decides.
2. **Tier 1 gates landing** (target under 60 s) and runs once, on the exact combination that will land: your change rebased on current main. **Nothing runs after the push**: no CI, no second tier, no watchdog.
3. **If main is ever red, whoever sees it reverts the offending commit with `git revert`** and lands the revert; the author reproduces in a new worktree and resubmits. A landing must not add a failure; a failure already on main does not refuse yours ("inherited red").
4. **Landing stops only by a person's explicit hold or freeze: a named owner and an expiry.** While frozen only a fix or a revert lands, recognised by its commit subject: `fix:`, `fix(<scope>):` or a subject that starts with `Revert`/`revert`.
5. **New behaviour lands switched off.** Landing is not release.
6. **Small means small**: 150 lines of production code and 45 minutes without a passing build are the defaults. Over either, cut the work.
7. **The lander never forces.** It pushes a plain fast-forward, with no lock (any number of landers run at once; git's refusal of a push that is not a fast-forward is the only arbiter), after up to `LAND_ATTEMPTS` rebase-and-retest attempts (default 30, within `LAND_DEADLINE` seconds). A hold marker stops landings at any moment.
8. **The rules come from main, not from your change**: `land.conf` and the hooks are read from `origin/main`, so a commit cannot loosen the rules it is judged by. Gate-defining files are protected and a gate edit lands only when every gate passes.
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
- Commit locally with Conventional Commits. Land only with [LANDER, e.g. .land/land-direct]; never push main yourself, never force-push it, never open a PR.
- New behaviour lands behind a flag that defaults OFF. Interface changes: add beside the old, migrate callers, delete at zero references.
- Everything runs before the push, once (Tier 1 on the rebased tree); nothing runs after it. If main is ever red, whoever sees it reverts the offending commit with `git revert` and lands the revert; the author fixes forward in a new worktree. A landing must not add a failure.
- Decide anything reversible and log it. Escalate only money, data loss, secrets, publishing, or harm to a third party; say so in one line and stop.
```

### 4.2 One gate, before the push

- **Tier 1, before landing, target under 60 s.** Build with zero warnings, type check, lints, affected tests, the repository's own fast ratchets. It runs once, on the exact combination that will land (the change rebased on current main). It gates landing.
- **Nothing runs after the push.** No CI, no second tier, no watchdog. A slow check is made fast or left out; it is never moved to after the push.

### 4.3 The lander

Workers never push main by hand; the lander does, with no lock (each run has its own directory; the remote's refusal of a non-fast-forward push is the only arbiter). It: checks nobody has held or frozen landing (a red main does not stop it); rebases the change onto current main; regenerates generated files (never merges them by hand); runs Tier 1 on that combination; if main moved meanwhile, rebases and runs again (up to `LAND_ATTEMPTS` attempts within `LAND_DEADLINE` seconds, then exit 16); then pushes a plain fast-forward, never forced. History stays linear, each commit its own. When one gate run per commit becomes the bottleneck, it takes groups: one Tier 1 for the group, binary search on failure to eject the culprit, the rest land. The exit status tells the worker what to do (landed; conflict: fix and run again; gate failed; held; moved: run again).

### 4.4 RED, exactly

**Main is red when its Tier 1 fails on main's own tip.** Nothing runs after the push, so whoever runs Tier 1 there next finds it (a lander's run, a worker, a person) and reverts the commit that made it red with `git revert` (`triage-red`). Landing never reads CI and does not ask whether main is red. A landing's own Tier 1 may fail only with failures the bare base already has ("inherited red": every line of its output matching `LAND_FAIL_PATTERN` is also a failure of the same Tier 1 on the base, one extra run, only then); a failure it adds, or one that prints no failure line, refuses it (13).

### 4.5 Freeze

- While frozen the lander takes only a fix or a revert, recognised by its commit subject alone: `fix:` or `fix(<scope>):` with any scope, or a subject that starts with `Revert`/`revert`. What it touches is not judged. A red main does not freeze anything.
- A freeze is a person's: a named owner and an expiry (`--freeze REASON --owner NAME --for 6h`), lifted by `--thaw` or its expiry; landing a fix does not lift it.
- A hold marker lets a person stop landings at any moment, even one already in flight.

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


## 6. The tool

### 6.1 What is here today

| Path | What it is |
|---|---|
| `.land/tool/bin/land-direct` (vendored; `bin/land-direct` here) | The lander: the configurable core of section 4.3. Hold and freeze markers, a run directory of its own per run, land-time checks, rebase in a scratch worktree, regeneration of generated files, hooks, Tier 1 on the rebased combination, bounded retries, plain fast-forward push, an exit code that says what to do next, a JSON last line, a metrics log. |
| `bin/run-probe`, `bin/no-crash-record`, `lib/no-crash-record.sh` | Crash-probe hygiene: deliberate-crash probes run in a private TMPDIR with `ulimit -c 0` plus the dumpable-clear preload (a probe launched otherwise is refused); the landing's no-crash-record check reads only crashes of its own process tree, session, scope or private directories. |
| `bin/no-build-guard`, `lib/no-build-host.sh`, `templates/run-scoped.sh` | The heavy-host guard (`docs/no-build-host.md`): a host that carries a no-build marker (`/etc/vbm/no-build-host` or `<config dir>/vbm/no-build-host`) makes the helpers refuse (exit 2, nothing started; no override); `--lint` is the Tier 1 check that every declared long runner goes through a helper. |
| `lib/` | `conf.sh` (the configuration reader), `freeze.sh`, `no-build-host.sh`, `no-crash-record.sh`, `source.sh` (the pinned source). |
| `install`, `bin/land-check`, `bin/land-update`, `bin/land-manifest`, `MANIFEST.sha256` | Pinned vendoring (6.6): the installer, the drift check, the updater, and the manifest of every file a consumer vendors. Whole tool in `.land/tool/` in a consumer. |
| `skills/` | Agent skills (`SKILL.md`): new-repo, land-a-change, triage-red, update-vbm-land, hold-and-freeze, adopt-in-existing-repo, release. A consumer gets them in `.agents/skills/` (installed and updated with the tool, drift-checked like it). |
| `templates/` | A starter `land.conf` with examples for four ecosystems, the agent-instructions block, the branch and tag rulesets, and the public-repository settings checklist. |
| `.land/` | This repository's own folder: `land.conf` (settings), `land.signers` (release keys), `land-direct` (the entry script: the repository lands itself with its own lander). |
| `scripts/bootstrap-land` | A minimal, dependency-light lander. It landed this repository's first commits and stays as the recovery path if the full lander is ever broken on main. |
| `tests/` | The test suite (below). `tests/run.sh` is this repository's Tier 1: the lints, then every `tests/test_*.sh` in parallel (about half a minute). |

Not built yet: a batch coordinator (the lander has its half: `--group`).

Requirements: bash 4+, git 2.30+, `timeout`, util-linux `flock` (only `scripts/bootstrap-land`). The tests also need `jq`. Linux only for now.

**The tests.** Each test script builds a scratch repository with a bare "remote", worker clones and a fake `gh`, and drives the real scripts. `test_land_direct.sh` has a negative test for every refusal (each exit code, and that nothing reached the remote); `test_vendor.sh` covers install, update, audit, every kind of drift (an edit, a deleted or extra file, a lost executable bit, a forged pin and tree) and the lander refusing a change to its own vendored copy; `test_mutations.sh` cuts each guard out of a copy of the lander in turn and requires the matching scenario to stop being refused (a guard nothing depends on would be found there); `test_bootstrap.sh` covers the recovery lander; `lint.sh` keeps internal names and local paths out of this repository.

### 6.2 Using it

A repository that lands with this tool has a `.land/land.conf` (below), lands with `.land/land-direct`, and tells its agents to run that entry script from their worktree:

```
.land/land-direct                       # land the local commits that are not on origin/main yet
.land/land-direct --dry-run             # everything except the push
.land/land-direct --check               # only the land-time checks (commit messages)
.land/land-direct --group               # accepted and ignored (there is no size budget any more)
.land/land-direct --hold "reason"       # stop every landing in this clone (even one in flight, right before its push) ...
.land/land-direct --release             # ... until released
.land/land-direct --freeze "reason" --owner NAME --for 6h   # only fixes and true reverts land, until the expiry or --thaw
.land/land-direct --status
```

Exit codes: `0` landed; `1` stopped with a message (base kept moving, push refused, a bad commit message); `2` bad input or bad configuration; `11` rebase conflict (the files are named; rebase in your worktree and run again); `12` refused by a hook, by the regeneration, or by the drift check; `13` Tier 1 failed (nothing landed); `14` held or frozen; `16` main moved faster than the lander could validate (nothing was pushed: run it again; after a crash that followed an accepted push, a rerun exits 0, "already landed"). The last line of standard output is JSON: `{"sha","commits","tier1_seconds","result","exit"}` plus any keys a `json-fields` hook adds.

Hold and freeze markers, logs and the scratch worktree live in `<git common dir>/vbm-land/`, shared by every worktree of the clone. The lander never runs `git worktree prune` and never removes a worktree it did not create: other lanes' worktrees live in the same clone.

### 6.3 Configuration

`.land/land.conf` is **data**: one `LAND_KEY=value` per line, `#` comment lines, nothing is expanded or executed while it is read, and an unknown key is an error, so a typo cannot silently switch a gate off. The lander reads it from `origin/<base>`, not from your change: a commit cannot loosen the rules it is judged by (only the very first landing, when main has no such file yet, uses the working tree's copy).

| Key | Default | Meaning |
|---|---|---|
| `LAND_BASE`, `LAND_REMOTE` | `main`, `origin` | The branch landed on and the remote that holds it. |
| `LAND_GATES_CMD`, `LAND_TEST_CMD` | none | **Tier 1**: the gates command, then the test command, run with `bash -c` in the scratch worktree on the rebased combination. At least one is required. |
| `LAND_REGEN_CMD` | none | Regenerates generated files after a rebase conflict confined to them (the conflict takes base's file, then this runs). Failing refuses (exit 12). |
| `LAND_GEN_CMD` | none | Always run on the rebased tree; anything it changes lands as a commit of the lander. |
| `LAND_GENERATED_LIST` | none | Path of a file listing generated paths, one per line, read from base. |
| `LAND_REQUIRE_TRAILERS` | none | Trailer names every commit must carry (for example `Task-ID`). |
| `LAND_CONVENTIONAL`, `LAND_COMMIT_TYPES` | `1`, the usual types | Require `type(scope): summary` subjects; git's own `Revert "..."` is accepted. |
| `LAND_PROTECTED` | none | Shell patterns (`*` matches `/`): the gate-defining set. A change that touches it is judged by the `post-rebase` hook. |
| `LAND_FAIL_PATTERN` | `^(FAIL\|FAILED)([ :]\|$)` | Extended regular expression: the lines of Tier 1's output that name a failure. A Tier 1 that fails ONLY with failures the bare base also has passes as inherited red (4.4). |
| `LAND_HOOKS_DIR` | `.land/land.d` | Where the repository's hooks live. |
| `LAND_LOCALE` | `C` | Pinned for collation and glob order. |
| `LAND_ATTEMPTS`, `LAND_DEADLINE` | `30`, `900` s | When main moves under a landing it is rebased and validated again: at most this many attempts, none started after this many seconds (then exit 16). Hooks and Tier 1 see `LAND_ATTEMPT` and `LAND_PREV_BASE` (the base the previous attempt validated against; empty on the first) so a repository may re-run only what the new base can affect. |
| `LAND_TIER1_TIMEOUT`, `LAND_STEP_TIMEOUT`, `LAND_GIT_TIMEOUT` | `1800`, `600`, `180` s | The bound on every step. A step that runs over is killed with one plain line and the run stops as that step's failure. |

Policy is never read from the environment. The operator may set `LAND_CONF` (another config file), `LAND_FIX_FOR_RED=1` (declare this change a fix, so it passes a freeze), `LAND_DIRECT_LOG` and the three timeouts. A key this tool has retired is not a key: a `land.conf` that names one is refused as unknown, by file and line. Commands the lander runs see `LAND_TOP`, `LAND_BASE_REF` (`origin/main`), `LAND_STATE_DIR` (shared by every run of the clone), `LAND_RUN_DIR` (this run's own), `LAND_ATTEMPT`, `LAND_PREV_BASE` and `LAND_TASK`.

### 6.4 Hooks

Hooks are executables in `.land/land.d/`, taken from `origin/<base>` (so a change cannot rewrite the check that judges it) and run in the scratch worktree, bounded. A hook is gate-defining code: put the directory in `LAND_PROTECTED`.

| Hook | When | A non-zero exit |
|---|---|---|
| `prepare` | once, when the scratch worktree is created (warm a cache, for example) | refuses (12) |
| `pre-rebase` | before the rebase, on your commits | refuses (12) |
| `post-rebase` | on the rebased and regenerated tree; gets `LAND_TOUCHED_FILE` (the changed paths) and `LAND_PROTECTED_TOUCHED` | refuses (12) |
| `post-tier1` | after Tier 1 passed: a gate that judges the tree Tier 1 just built (an attack suite, say) | refuses (12) |
| `json-fields` | after Tier 1; prints `key=value` lines added to the JSON result (keys `[a-z_]+`; the contract keys cannot be overridden) | ignored |
| `on-run` | at the end of every run, with `LAND_RESULT` | ignored |

### 6.5 Trust model

The tool is for a repository whose only writers are cooperating agents and people, not for adversaries. It makes mistakes mechanical failures: the gate runs on the exact combination, config and hooks come from main, the push is a plain fast-forward, and there is no lock for a dead lander to wedge (a crash leaves only its own run directory). A lander runs repository-supplied commands with your credentials; protect the gate-defining set accordingly. The lander is the copy in the worktree it is run from; what protects the main branch is the drift check on the rebased tree (6.6) and the configuration and hooks read from main.


### 6.6 Installing it into a repository: a pinned, vendored copy

A repository does not depend on this one at run time. It **vendors a pinned copy** and commits it: a worktree is self-contained and offline, the lander of a landing is the one in the tree being landed, and the history shows exactly which release landed what. (Rejected: a git submodule, which breaks fresh and detached worktrees; a language package manager, which is not language-neutral; fetching the tool when landing, which would let the lander change under a landing.)

One command, run in the target repository (`SRC` is a git URL or path, or `OWNER/NAME` on GitHub, read through `gh`, which also reaches a private source):

```
# from a checkout of this repository (see the Quick start), or any other source:
/path/to/vbm-land/install --source https://github.com/witt3rd/vbm-land --signers /path/to/vbm-land/.land/land.signers <tag>
# through gh, without a checkout:
gh api repos/witt3rd/vbm-land/contents/install?ref=<tag> -H 'Accept: application/vnd.github.raw' | bash -s -- --source witt3rd/vbm-land <tag>
```

It writes, and commits nothing (review the diff, commit it as `chore(land): vbm-land <version>`, land it like any other change):

- `.land/tool/` the tool, read-only by contract, replaced whole on every update;
- `.land/tool/MANIFEST.sha256` the hash of every vendored file, copied from the release;
- `.land/PIN` `source`, `version`, the 40-hex **`commit`** (a tag can move, a commit cannot) and `manifest_sha256` (beside the tool folder, so replacing the folder never removes it);
- `.agents/skills/<name>/SKILL.md` the agent skills, one per file in `skills/` of the release;
- `.land/land-direct` a three-line entry script that runs the vendored lander, so "land with `.land/land-direct`" stays true, **only if absent**: it is the repository's own afterwards (add an environment variable before the exec); the drift check only requires that it is executable and still runs `.land/tool/bin/land-direct`;
- `.land/land.conf` a starter, **only if there is none**.

Everything the tool owns in a consumer is under `.land/` (`.land/tool/`, `PIN`, `land.conf`, `land.signers`, `land.d/`, `land-direct`); the skills are the one thing outside it, in `.agents/skills/`. The repository's own `scripts/` stays its own. The first install or update of 0.8.0 on an older repository **migrates** it: it moves `land.conf`, `land.signers`, `land.d` and the entry script, removes the old `scripts/land/` tree, and prints the references to the old paths that the repository's own files still carry (it edits none of them).

Before writing anything the installer checks every file it fetched against the manifest at that same commit, and refuses a release that does not match or has no manifest. `templates/AGENTS-block.md` is the agent-instructions block to paste;

**No local patches.** A repository that needs something different adds a configuration key or a hook upstream (one change, one release), or uses a hook of its own; it never edits the copy. The rule is mechanical:

- `.land/tool/bin/land-check` is the **drift check**. Offline (run it in Tier 1; the lander also runs it on the rebased tree and refuses with exit 12): the manifest must hash to the pin, every vendored file (the tool, the templates, the skills) must hash to its entry and keep its executable bit, nothing else may sit in `.land/tool/`, and the repository's own `.land/land.conf` (known keys) and `.land/land.d/` (hooks have the fixed names above and must be executable; `*.sh` files are helpers the hooks source) must be well formed. Any difference fails: *edit vbm-land, not the copy*.
- `.land/tool/bin/land-check --upstream` (by hand) also fetches the manifest at the **pinned commit** from the source and requires it to match, so a forged pin and tree edited together fail; it prints when a newer release exists (advice, never a failure) and exits 3 when the source cannot be reached (not verified).
- `.land/tool/bin/land-update <tag|commit>` replaces the tool folder and the pin with another release and verifies it; it commits nothing. `--diff <tag>` shows what an update would change and `--land <tag>` lands it (see Updating).

A repository takes the next release itself, with `land-update` (see Updating).

**Signed releases.** A release is a signed, annotated tag made by `bin/land-release` (maintainer only; an ssh key in `LAND_SIGNING_KEY`, no gpg): the tag message records the hash of `MANIFEST.sha256`, so the signature binds the manifest and, through it, every vendored file. A consumer lists the public keys it trusts in its own `.land/land.signers` (an ssh allowed-signers file, taken from the source out of band: `install --signers FILE`; this repository's own is `.land/land.signers`, fingerprint and rotation in [docs/signing.md](docs/signing.md)). With that file present, `install` and `land-update` **refuse**, before anything of the new release runs or is written, a ref that is not a signed annotated tag, a signature that does not verify against the file, an unknown signer, or a tag whose recorded manifest hash differs from the manifest at that commit. Without a signers file they say `UNVERIFIED` and go on (the pin records `signature=unverified`). `land-update --land <tag>` is the whole update as the repository's own act: verify, stage, commit `chore(land): vbm-land <version>` (with the trailers its `land.conf` requires), and land it through the repository's **own** lander and gates, run from a pristine fresh clone of the base branch (the old lander lands the new copy); a hold, a red main, a failed Tier 1 or a refusing hook stops it with the lander's exit code, the commit stays local, nothing is forced. `land-update --diff <tag>` verifies the release and prints what it would change (changed, added and removed files with their diffs, and the CHANGELOG entries newer than the pin) without changing anything.

A release is a tag whose commit has a fresh `MANIFEST.sha256` (`bin/land-manifest`; Tier 1 here fails on a stale one). Additive changes to the interface (configuration keys, exit codes, the JSON line, hook names, marker names) are minor, anything else is major; `CHANGELOG.md` has a line per interface change.

### 6.7 Protecting the branch

The lander **never force-pushes**: it pushes a plain fast-forward (`git push <remote> <sha>:<branch>`), so a remote that refuses non-fast-forward updates changes nothing about how it works, and a test and a mutation self-test keep it that way. Make the remote say the same: apply `templates/ruleset-protect-main.json` to the default branch (deletion and non-fast-forward updates refused; **no required pull request and no bypass list**, so a fast-forward landing still works) and `templates/ruleset-protect-release-tags.json` to release tags (no deletion, no update: a pin by tag cannot be moved). `templates/PUBLIC-REPO-SETTINGS.md` is the checklist for a repository that is, or is about to be, public (approval of fork pull-request workflows for all outside contributors, a read-only workflow token that cannot approve pull requests, private vulnerability reporting, secret scanning with push protection, deleting merged branches). `bin/land-audit` warns when a repository's default branch lacks the branch protection (asked of GitHub through `gh`; offline it says "unknown"). `skills/new-repo/SKILL.md` is the whole sequence for a new repository.

## Adopting it in an existing repository

Preconditions (all three): only you and your agents write to it; main is not deployed; Tier 1 can be about a minute or less. If not, keep pull requests.

1. **Define Tier 1**: one command that builds, lints and runs the fast tests. Time it. Over a minute: make the slow checks fast first (nothing runs after the push).
2. **No CI**: delete the repository's workflows (`.github/workflows/`) and any merge-queue or pull-request automation; nothing runs after the push.
3. **Vendor a signed release** (Quick start, in a fresh worktree off `origin/main`).
4. **Configure `.land/land.conf`**: `LAND_TEST_CMD` or `LAND_GATES_CMD`, `LAND_PROTECTED` (gate-defining files).
5. **Agent instructions**: paste `templates/AGENTS-block.md` into your `AGENTS.md` and delete any "open a PR" text.
6. **Land the adoption itself** with the new lander: `.land/tool/bin/land-check && git add -A && git commit -m 'chore(land): adopt vbm-land vX.Y.Z' && .land/land-direct`.
7. **Retire the PR flow**: archive each open PR's diff and a reason, then close it.

The same steps as an agent skill, with the do-not list: `skills/adopt-in-existing-repo/SKILL.md` (vendored into your repository with the tool). A repository created from scratch: `skills/new-repo/SKILL.md`.

## Updating

Pull only: a repository decides when it takes a release, and runs the update itself. From a clean worktree off fresh `origin/main`:

```
.land/tool/bin/land-update --check        # read-only: "pinned X, latest Y, behind N (patch|minor|major)"
.land/tool/bin/land-update --diff <tag>   # verify the release and show what it would change (files, diffs, the CHANGELOG entries since your pin)
.land/tool/bin/land-update --land <tag>   # verify, stage, commit `chore(land): vbm-land <version>`, land it through your own lander and gates
```

`--land` refuses before anything is written when the release does not verify; a hold, a failed Tier 1 or a refusing hook stops it with the lander's exit code and the commit stays local. By hand instead: `land-update <tag>` (stages only), `land-check`, review `git status`, one commit, `.land/land-direct`. A major release is a person's decision: read the "Upgrade notes" in its CHANGELOG section first (0.8.0 migrates the layout, see 6.6). Nothing schedules an update and nothing takes one by itself: there is no CI, no workflow and no Tier 2, and a repository decides when to run `land-update`.

## Versions and signed tags

Releases are annotated, ssh-signed tags `vX.Y.Z` made by `bin/land-release`. The tag message records the sha256 of `MANIFEST.sha256`, which lists every file a consumer vendors, so the signature covers the whole vendored tree. A consumer that holds `.land/land.signers` makes `install` and `land-update` refuse anything that is not a signed tag from a listed signer. The key, its fingerprint (check it out of band), how to verify a tag by hand and how rotation works: [docs/signing.md](docs/signing.md). Each release has a section in [CHANGELOG.md](CHANGELOG.md); a release that adds or changes an interface item carries "Upgrade notes". Pins record the 40-hex commit, never only the tag. `v0.1.0` predates signing and does not verify; `v0.2.0` is the first signed release.

## Honest limits

- **Not for adversaries.** A lander runs repository-supplied commands with your credentials; the protections (config and hooks read from main, the drift check) turn mistakes into mechanical failures. They do not stop an agent that holds landing rights and wants to cheat ([6.5](#65-trust-model)).
- **Not built yet:** a batch coordinator (the lander has its half). Linux only.
- **One writer population.** Pull requests are the right tool for outside contributors. This one is not, and a repository that adopts it should say so.
- **Early.** The interface is versioned, but 0.x: read the CHANGELOG before a minor update.
- **Public history as published.** The history was published as it stood, not re-written: early commit messages carry internal task identifiers and the author's name ([docs/flip-record.md](docs/flip-record.md)).
- **Security and conduct of contributions:** [SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
