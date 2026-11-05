# Going public: the record

This repository started private and was made public by its owner. This page records what was checked, what the published history carries, and the order of the flip, so that a reader can see what "public-ready" meant here.

## History published as is

The history was **not** re-written or re-rooted. Every commit, signed tag and commit hash is the one consumers already pin (a pin records the 40-hex commit, and `land-check --upstream` reads the manifest at that commit), so a rewrite would have broken every pinned consumer and every release signature. The owner accepted the following exposure on 2026-11-05:

- **The author identity.** The owner's name and e-mail appear as author and committer of 35 of the 36 commits and as the tagger of all 7 signed release tags (the same identity is already public in the owner's other repositories).
- **One infrastructure word.** A word for the private build machines appears in the subject of one early commit (a CI runner change), in the patches of three early commits (two sentences in documents, later reworded; the runner label) and in nothing else. The public-readiness lint of the VBM standard refuses it; the current tree no longer carries it (the last line is the runner label that the flip-day change removes).
- **Internal task identifiers.** A few commits carry `Task`/`Task-ID` trailers naming internal work items; one trailer names a private project that was the first consumer.
- Nothing else: no secret, no host name, no address, no local path, no other person's data.

## What was checked

| Check | Result |
|---|---|
| gitleaks 8.30.1, full history of every ref of a fresh mirror of the remote (`main` and 7 tags, 36 commits), and the working tree | 0 findings |
| trufflehog 3.99.8, same scope | 0 verified, 0 unverified |
| the VBM public-readiness lint (hash list of private names, path patterns) over the tree | clean after the tree fixes; before them 2 hits (the runner label, one CHANGELOG sentence) |
| a scan of every commit message, tag message, path, author line and changed line of all refs for the same hashes plus plain patterns (host names, home paths, e-mails, addresses) | only the accepted items above |
| `tests/lint.sh` (this repository's own lint, now with the two additional words) | clean |
| Tier 1 (`tests/run.sh`) in a fresh `ubuntu:24.04` container after dependencies were fetched, with the network disconnected | passes |
| in that container: install a signed release into a scratch repository, land a change with the vendored lander, the drift check, `land-update --check` against a tag, `git verify-tag` with `scripts/land.signers` | passes |

## The flip, in order

The runner label cannot be removed before the repository is public: until then CI runs on the owner's self-hosted runner (the hosted runners are unavailable to this private repository), and `tests/lint.sh` allows that label only while `.github/visibility` says `private`. So the change that returns CI to hosted runners is prepared as a patch (`runs-on: ubuntu-latest`, `.github/visibility` set to `public`) and lands right after the visibility change:

1. The owner changes the visibility and checks that an anonymous `git clone` works.
2. At once, the settings below (the API refuses the fork-pull-request policy on a private repository, so it can only be set now). While the runner is still registered, CI has no `pull_request` trigger, so no outside code reaches it.
3. Land the flip-day change with `scripts/land-direct` (local Tier 1 runs the lint on the patched tree) and read the push CI on a hosted runner: it must be green.
4. Deregister the runner (`gh api repos/witt3rd/vbm-land/actions/runners` lists none).
5. Tell the consumers (below) and update the registry entry of the VBM standard.

## Settings at the flip (replace nothing; each has a read-back)

1. Fork pull-request workflows need approval for **all outside collaborators**: `gh api -X PUT repos/witt3rd/vbm-land/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors`.
2. Read-only workflow token that cannot approve pull requests: `gh api -X PUT repos/witt3rd/vbm-land/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false`.
3. Private vulnerability reporting: `gh api -X PUT repos/witt3rd/vbm-land/private-vulnerability-reporting`.
4. Secret scanning and push protection: `gh api -X PATCH repos/witt3rd/vbm-land -F 'security_and_analysis[secret_scanning][status]=enabled' -F 'security_and_analysis[secret_scanning_push_protection][status]=enabled'`.
5. Delete head branches on merge: `gh api -X PATCH repos/witt3rd/vbm-land -F delete_branch_on_merge=true`.
6. Protect `main` from deletion and non-fast-forward updates (no required pull request, no bypass list, so landing still works): `gh api repos/witt3rd/vbm-land/rulesets --input templates/ruleset-protect-main.json`; read back `gh api repos/witt3rd/vbm-land/rules/branches/main --jq '.[].type'`; then one real landing.
7. Protect release tags (`v*`) from deletion and update: `gh api repos/witt3rd/vbm-land/rulesets --input templates/ruleset-protect-release-tags.json`. Do this once the flip-day landing is done and no release is in flight.
8. No workflow uses `pull_request_target`, every workflow declares read-only `permissions:`, no deploy key or stale secret exists.

## Consumers

Repositories that vendor this tool read it without a secret once it is public. Each consumer should enable the weekly schedule of `.github/workflows/vbm-land-update.yml` (the two lines `schedule:` and `- cron: '23 6 * * 1'`), landed through its own lander, and may drop the read token it needed while this repository was private. Consumers' pins and tags are unchanged: nothing is re-pinned.
