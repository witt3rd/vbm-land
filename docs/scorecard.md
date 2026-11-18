# Scorecard

Status: draft by a worker, 2026-11-18; goals and targets are the owner's to set.

This scorecard measures vbm-land against what vbm-land says it is for. It is a tool, not a verified library: the VBM proof scorecard does not score it (`README.md:5`), so it has no proof ledger, vectors or trust ledger. Its assurance is its test suite, its negative tests and its mutation self-test. There is no `docs/decisions/` directory here. Every value was measured on 2026-11-18 at v0.21.0 (HEAD is the release commit), in a sandbox with no systemd user manager.

## Goals as the repository states them

1. **A small change reaches `main` within minutes; a fast mechanical gate decides, and the release candidate is verified in full before anything ships.** `README.md:49`, `README.md:3`.
2. **Tier 1, the landing gate, is fast: target under 60 s, "about half a minute" for this repository.** `README.md:35`, `README.md:101`, `README.md:170`, `CONTRIBUTING.md:14`, `.land/land.conf:3`.
3. **The release candidate runs the full suite, nothing skipped, and is green before a tag; a break Tier 1 passed and the candidate caught is an escape, and escapes are counted.** `README.md:38`, `README.md:141`, `README.md:142`.
4. **Small changes: 150 lines of production code, 45 minutes.** `README.md:39`, `README.md:57`, `CONTRIBUTING.md:18`.
5. **Design for disjointness: no file every change must edit, narrow modules, many tests that exercise little, and the overlap is measured and "let fall and never rise".** `README.md:63`, `README.md:64`, `README.md:66`, `README.md:67`.
6. **The three metrics in every repository: landings per hour, p90 commit-to-main, red minutes on main (near zero).** `README.md:146`-`README.md:152`.
7. **The gate cannot be silently loosened, and each refusal is tested: rules come from `main`, the lander never forces, there is a negative test for every refusal and a mutation self-test that cuts each guard out.** `README.md:5`, `README.md:40`, `README.md:41`, `README.md:176`.
8. **A check that never ran must not pass: every test script prints `ran: NAME: N cases` with N > 0 and no `SKIPPED`.** `AGENTS.md:34`, `docs/ran-evidence.md:3`.
9. **Releases are signed, and the vendored copy is exactly its pin (one manifest checksum, a fresh `MANIFEST.sha256`).** `README.md:298`, `README.md:300`, `AGENTS.md:19`, `AGENTS.md:33`.
10. **The repository is public: no internal names, hosts or local paths anywhere.** `AGENTS.md:38`, `CONTRIBUTING.md:23`.
11. **The tool is small and language-neutral: plain bash and git.** `README.md:3`.

## Metrics

Units: seconds, counts, and permille (thousandths). Run every command from the repository root. "Run" means the one `tests/run.sh` run of 2026-11-18, whose output the three `tests/run.sh` rows share.

| metric | direction | goal it serves | how to measure | now | floor (= now) | target |
|---|---|---|---|---|---|---|
| `tier1-seconds` | lower | 2 | `s=$(date +%s); tests/run.sh >/dev/null 2>&1; echo $(( $(date +%s)-s ))` (not cheap: over 5 minutes) | 339 s (2026-11-18, one run; the lints take under 1 s, the rest is the slowest script) | 339 | |
| `slowest-test-script-seconds` | lower | 2, 5 | `tests/run.sh 2>&1 \| awk '/^ok   tests\//{gsub(/\(/,""); if ($3+0>m) m=$3+0} END{print m}'` (same run as above) | 339 (`tests/test_lean_recheck.sh`; next: `test_lean_ledger.sh` 120, `test_land_direct.sh` 52) | 339 | |
| `failing-test-scripts` | lower | 2, 7, 8 | `tests/run.sh 2>&1 \| grep -c '^FAIL tests/'` (same run) | 1 (`tests/test_no_crash_record.sh`, case "a crash in the landing's session whose parent is gone: wanted own, rc=0"; probably this sandbox, which has no systemd user manager, but not confirmed elsewhere) | 1 | |
| `test-cases` | higher | 7, 8 | `tests/run.sh 2>&1 \| awk '/^ok   tests\//{gsub(/\(/,""); s+=$5} /^== .* passed/{s+=$3} END{print s}'` (same run) | 1524 (24 scripts; counts the 45 passing cases of the failed script) | 1524 | |
| `test-scripts` | higher | 5, 7 | `ls tests/test_*.sh \| wc -l` | 24 (2026-11-18) | 24 | |
| `mutation-guards-covered` | higher | 7 | `awk '/^done <<.LIST/{f=1;next}/^LIST/{f=0}f' tests/test_mutations.sh \| wc -l` | 14 (2026-11-18) | 14 | |
| `public-lint-violations` | lower | 10 | `tests/lint.sh 2>&1 \| grep -c '^lint:'` | 0 (2026-11-18) | 0 | |
| `stale-manifest-files` | lower | 9 | `bin/land-manifest --check >/dev/null 2>&1; echo $?` (0 = fresh, 1 = stale) | 0 (2026-11-18) | 0 | |
| `unverified-signed-tags` | lower | 9 | `n=0; for t in $(git tag --list \| grep -v '^v0\.1\.0$'); do git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=.land/land.signers verify-tag $t >/dev/null 2>&1 \|\| n=$((n+1)); done; echo $n` (v0.1.0 is excluded: it predates signing, `README.md:342`) | 0 of 44 tags (2026-11-18; latest v0.21.0, signature good) | 0 | |
| `tool-code-lines` | lower | 11, 4 | `wc -l bin/* lib/*.sh install \| tail -1` (the gate-defining code: `bin/`, `lib/`, `install`; `scripts/bootstrap-land` is not counted) | 1591 (2026-11-18) | 1591 | |
| `files-per-landing-permille` | lower | 4, 5 | `git log -50 --name-only --pretty=format:@@ \| awk '/^@@/{n++;next} NF{f++} END{print int(f*1000/n)}'` (files written per commit over the last 50 commits, times 1000) | 6500 (6.5 files a commit, 2026-11-18) | 6500 | |
| `landings-touching-shared-files-of-50` | lower | 5 | `git log -50 --name-only --pretty=format:@@ \| awk '/^@@/{if(n&&h)c++;h=0;n++;next} $0=="MANIFEST.sha256"\|\|$0=="VERSION"\|\|$0=="CHANGELOG.md"{h=1} END{if(h)c++;print c}'` (of the last 50 commits, how many wrote `MANIFEST.sha256`, `VERSION` or `CHANGELOG.md`) | 39 (2026-11-18) | 39 | |
| `p90-commit-to-main-seconds` | lower | 1, 6 | `jq -s '[.[]\|select(.result=="landed")\|.total_s]\|sort\|.[(length*9/10\|floor)]' "$(git rev-parse --git-common-dir)/vbm-land/metrics.jsonl"` (`total_s` is the lander's run time, which leaves out the wait before the lander starts) | unmeasured: needs the lander's metrics log of the owner's real landings (`bin/land-direct:28`); this checkout has none | unmeasured | |
| `landings-per-hour` | higher | 6 | same log: `jq -s '[.[]\|select(.result=="landed")\|.ts]\|(max-min)' ...` gives the span in seconds; landings divided by hours of that span | unmeasured: same log | unmeasured | |
| `red-minutes-per-week` | lower | 6 | no command in the repository: needs the log of Tier 1 runs on `main`'s own tip, or a count of the `Revert` commits and the time between each red commit and its revert (`git log --grep '^Revert' --format=%cI`) | unmeasured: needs a record of when `main` was red | unmeasured | |
| `release-candidate-escapes` | lower | 3 | no command: needs a record, per release, of the failures `LAND_RC_CMD` found that Tier 1 had passed (`README.md:141`) | unmeasured: no record in the repository | unmeasured | |
| `release-candidate-seconds` | lower | 3 | `s=$(date +%s); tests/acceptance.sh --soak >/dev/null 2>&1; echo $(( $(date +%s)-s ))` (runs Tier 1 on a scratch clone, then 20 landers at once; the soak is "by hand, on a machine with room", `docs/gate-mechanism-acceptance.md`; `LAND_RC_TIMEOUT` is 3600) | unmeasured: not cheap, and it needs a machine with room | unmeasured | |

## Health today

- **The fast gate is not fast.** Tier 1 took 339 s against a stated "under 60 s" and "about half a minute". One script, `tests/test_lean_recheck.sh`, accounts for all of it (339 s; its own comment says "about 5 minutes under this load"). Without it the next script is 120 s, which is still over the target. The goal is regressed, or the docs are stale; this is the largest gap.
- **Tier 1 is red here.** One test script fails, `tests/test_no_crash_record.sh`. It may be this sandbox (no systemd user manager) and not the repository, but it is not confirmed. The lander's own rule is that a landing must not add a failure.
- **The fix-by-design goal is not met.** 39 of the last 50 commits wrote a file every release touches (`MANIFEST.sha256`, `VERSION`, `CHANGELOG.md`), and a commit writes 6.5 files on average. `README.md:63` calls a committed generated file "a conflict by construction", and `MANIFEST.sha256` is committed and generated. `LAND_REGEN_CMD` softens the cost but does not remove the shared file.
- **The three headline metrics and the escape count are unmeasured.** The repository states them (`README.md:146`-`README.md:152`, `README.md:141`) and keeps no record of landing time, red time or escapes, so its own health claims cannot be checked. Neither the release-candidate time nor the soak was run here.
- **Healthy where it is measured:** no lint violations, a fresh manifest, every tag since v0.2.0 signed and verifying, 14 guards covered by mutants, 1524 cases counted. These are the floors that must not move back.
- **The tool is 1591 lines of gate-defining shell and has no target for its size.**

## What a steward would do first

1. Bring `tier1-seconds` (and `slowest-test-script-seconds`) down toward the 60 s the README promises: move the 339 s Lean proof replay of `tests/test_lean_recheck.sh` to `LAND_RC_CMD`, where the README puts slow checks, or state the real Tier 1 time in the README and `CONTRIBUTING.md`.
2. Get `failing-test-scripts` to 0 by finding out whether `tests/test_no_crash_record.sh` fails on a machine with a systemd user manager; if it does, fix it, and if it does not, make it say so rather than fail.
3. Start measuring `p90-commit-to-main-seconds`, `red-minutes-per-week` and `release-candidate-escapes`, with a command or a log kept in the repository, so that the goals behind `README.md:146`-`README.md:152` and `README.md:141` have a number; then work on `landings-touching-shared-files-of-50`.

## Questions for the owner

- What is Tier 1's real target for this repository: the README's "under 60 s" and "about half a minute", or what it is now (339 s, mostly the Lean proof replay)? Is `tests/test_lean_recheck.sh` meant to be in Tier 1?
- Targets for every row are blank. In particular: a ceiling for `tool-code-lines`, a target for `files-per-landing-permille` and `landings-touching-shared-files-of-50` (should `MANIFEST.sha256` stay committed, or be generated at release?), and the p90 and red-minute aims, which the README gives only as "a few minutes" and "near zero".
- Is a "landing" the lander's `total_s` or the time from "ready" to "on main" (`README.md:151`)? Where should that data live, since a lander's metrics log sits in a clone's git directory and is lost with the clone?
- Is `tests/test_no_crash_record.sh` known to fail without a systemd user manager?
- Should the scorecard count release-candidate escapes from a ledger file in the repository, and where?
- The goals are read from the README, `AGENTS.md` and `CONTRIBUTING.md`. Is there a goal they leave out (adoption by other repositories, the interface's stability, "Group landing" not yet built, `README.md:172`)?
