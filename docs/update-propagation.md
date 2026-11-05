# Update propagation: how a repository that vendored vbm-land gets the next release

Status: built (U1 to U4): `land-update --check`, the scheduled workflow, signed releases and verification, `--diff`, `--land`, `LAND_AUTO_UPDATE` with `--auto`. U5 (skill and conventions) remains.

## The rule: pull only

Dependencies point one way: **a repository depends on vbm-land; vbm-land does not know what depends on it.** So vbm-land carries into every vendored
copy two capabilities, a **check** and an **update**, that run in and are owned by the consumer. There is no list of consumers in this repository, no tool
that reaches into other repositories, no canary order, no rollout, and no version table fed from here. A consumer's pin (`scripts/land/PIN`, a documented
`key=value` file) is a public, stable interface: anyone who wants a fleet view (a registry, a dashboard) **reads the pins itself**.

## 1. The check (a scheduled workflow in the consumer)

`install` adds `.github/workflows/vbm-land-update.yml` (from `templates/vbm-land-update.yml`) **only if absent**; it is the consumer's own file afterwards, landed
and gated like any other. Weekly, and on dispatch, on the consumer's own runner or a hosted one, it runs:

1. `scripts/land/bin/land-check` (offline drift: the vendored copy is exactly its pin), and
2. `scripts/land/bin/land-update --check`: reads the **release tags** of the source (read-only; public, or token-authenticated for a private source) and prints one line,
   `vbm-land: pinned v0.1.0, latest v0.3.2: behind 4 releases (minor)`. The class is the semver distance (patch / minor / major).

When behind, it is **visible, not blocking**: the line goes to the run summary and a warning annotation, the job exits non-zero for "behind" (a red check on the
workflow, no more), and, if the consumer opts in (`LAND_UPDATE_ISSUE=1`, needs `issues: write`), one tracking issue is opened and kept current. It is a separate
workflow from the gate (`LAND_CI_WORKFLOW`), so its result can never make main "red" and block landing. Unreachable source: a distinct exit code and message, never a silent pass.

## 2. The update (the consumer's own act: `land-update`)

`scripts/land/bin/land-update <tag>` is a command **inside the vendored copy**. It:

1. fetches the tag from the pinned source and **verifies the signed tag** against the consumer's allowed signers (`scripts/land.signers`, consumer-owned and reviewed;
   the first install takes the signer's fingerprint out of band: `install --signers FILE`; without a signers file it says "unverified" loudly);
2. verifies that the **manifest hash recorded in the signed tag message** equals the hash of `MANIFEST.sha256` at that commit, and every file against the manifest
   (the installer already refuses a release whose files do not match);
3. **shows the diff**: the changed vendored files, the manifest diff, and the CHANGELOG entries between the two pins (`--diff` shows it without changing anything);
4. stages the new tree and PIN (today's behaviour), and, with `--land`, goes on: a fresh branch, one commit `chore(land): vbm-land vX.Y.Z`, the **consumer's Tier 1 and the
   consumer's own lander**, run from a pristine checkout of main so the lander that lands the new copy is the old one already on main (the old lands the new). The update
   passes through everything any change passes through: `scripts/land/` is in the consumer's protected, gate-defining set, so its attack suite or gate-diff judge runs on it.
   It stops on the first red and lands nothing; it never forces.

## 3. Policy in the consumer's `scripts/land.conf`

`LAND_AUTO_UPDATE=none|patch|minor`, default **none**. When set, the scheduled workflow performs `land-update --land` itself for a release of that class or below, with
the token that **that repository** holds (a push by the default workflow token does not trigger the push CI that defines red, so an auto-updating repository
needs a deploy key or a token; the settings checklist says so). A **major** release is never automatic. On red it stops, leaves the report, and the workflow shows it.
Auto-update only makes sense where the runner has the toolchain of the consumer's Tier 1; elsewhere leave it `none` and update by hand.

## 4. Updating by hand, and outside consumers

Same mechanism, no special case. An agent or person who sees the "behind" line runs the `update-vbm-land` skill (`land-update --diff <tag>`, read it, `land-update --land <tag>`).
Outside consumers (when this repository is public) do exactly the same; what makes it reviewable is the CHANGELOG (one line per interface change, an "Upgrade notes"
paragraph for any minor or major), the manifest diff, and the signed tag. A fleet owner who wants a reminder builds it on their own side, from the pins and the tags.

## 5. Trust: the lander pushes to main

An update replaces code that pushes to the base branch and reverts commits, so: (a) release tags are **signed** by the maintainer's key (`bin/land-release` makes the annotated,
signed tag with `manifest_sha256=` in its message; key custody and rotation are the maintainer's, and a rotation is a signers-file change the consumer reviews); (b) the
consumer verifies signature, manifest-in-tag and file hashes before touching its tree; (c) the update lands through the consumer's own gates and attack suite; (d) the
upstream drift check (`land-check --upstream`) keeps confirming the manifest at the pinned commit; (e) nothing is fetched or run at landing time.

## Slices (in this order; each lands through a lander)

| # | Slice | Done when |
|---|---|---|
| U1 | `land-update --check` (semver class, exit codes) and `templates/vbm-land-update.yml`, written by `install` when absent; tests with scratch consumers and a source with several tags | a consumer behind by a patch, a minor and a major each reports the right class; unreachable source is distinct; the workflow lints |
| U2 | `bin/land-release` (signed tag with the manifest hash), signature and manifest-in-tag verification in `install` and `land-update`, `--diff`, `scripts/land.signers`; tests with throwaway ssh keys | a tag with a bad signature, an unknown signer, or a wrong manifest hash is refused and nothing is written |
| U3 | `land-update --land`: branch, commit, the consumer's Tier 1 and own lander from a pristine main; stops on red | a scratch consumer lands an update; a red Tier 1 lands nothing |
| U4 | `LAND_AUTO_UPDATE` and the workflow's auto mode (patch/minor; major never) | minor lands itself, major only reports, red stops |
| U5 | The `update-vbm-land` skill, README and CHANGELOG "Upgrade notes" convention | docs match the commands |

## Not in vbm-land, by design

A consumers file, `land-rollout`, a canary order, an owner-lane field, a registry column maintained here. (`bin/land-audit DIR...` stays what it is: a local, read-only report on directories
you hand it; it does not know any repository and gains no list.)

## Open questions for the owner

- Who holds the release-signing key, and is an ssh signing key (simple, no gpg) acceptable? 
- Is a failing-but-non-blocking workflow plus the run summary enough for the "no silent staleness" rule, or is the opt-in tracking issue wanted by default?
- Which repositories, if any, should set `LAND_AUTO_UPDATE` (those whose runner has the Tier 1 toolchain), and where does each keep its push token?
