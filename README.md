# vbm-land

A small, language-neutral tool for landing changes **directly on the main branch** of a repository that only your own agents (or you) work in: one lander, a mechanical gate, a single definition of "main is red", and a hold switch. Plain bash, git and `gh`. Nothing in it knows what language your repository is written in.

> **Status: early.** What exists today is listed in [What is here](#what-is-here-today). The policy below is the contract the tool is being built to; the sections on install, configuration and drift checks are added as the tool lands them.

The rest of this file is the landing guide: the policy first, then the tool.

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

## What is here today

| Path | What it is |
|---|---|
| `scripts/bootstrap-land` | The minimal, dependency-light lander (lock, hold marker, red check, rebase, Tier 1 on the combination, three tries, plain fast-forward push). It lands this repository's own first commits and stays as the recovery path if the full lander is ever broken. |
| `tests/` | The test suite: every test builds a scratch repository with a bare remote and exercises the lander, including a negative test for each refusal. `tests/run.sh` is this repository's Tier 1. |
| `.github/workflows/ci.yml` | Tier 1 on a push to main. |

Requirements: bash 4+, git 2.30+, util-linux `flock`, `timeout`, and `gh` (the red check). The tests also need `jq`. Linux only for now.

Landing this repository: `scripts/bootstrap-land` from a worktree with local commits; see the header of the script for the exit codes.

## License

Apache-2.0. See [LICENSE](LICENSE).
