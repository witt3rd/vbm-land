# The family repository: many libraries, one repository

Status: the contract, written before the code (documents only: no tool, test or lint is built by this page). It is normative: every "must" below is something a test of the implementing item has to check, and section 11 lists the refusals each of those tests has to see fail. It builds on `docs/pin.md` (the tree hash, the lock, `land-pin`), `docs/areas.md` (areas; overlap is the declared dependency; the concurrency model) and `docs/signing.md` (the release key). Where this page and those differ, this page governs only the *family repository* described here; every other repository keeps them as they are.

## 0. The decision, and what it buys

The owner decided: the family's libraries are no longer one repository each. Each becomes a **directory `lib/<name>/` of ONE public repository** (called here **the family repository**), which has its own registry and is validated by areas. Separate repositories multiplied scaffolding, vendored lander copies, rulesets, nested vendored copies of each other (the same library vendored two and three levels deep, kept equal by `land-pin verify` rule 3) and release chores, and a change that spans libraries needed coordinated releases. Inside one repository there is **one version of everything: the commit**.

The family repository is laid out as any consumer of this tool is: it vendors the lander at `.land/tool/`, lands with `.land/land-direct`, and keeps its settings in `.land/` (`land.conf`, `land.signers`, `areas.json`). It is **not** this repository: this repository keeps the lander and the release and pin tools (section 7), and this page lives here because those tools implement it. In this page "the lander's `lib/`" never means `lib/<name>/` of the family repository.

## 1. Layout

```
lib/<name>/
  <sources>             whatever the library is written in, its tests included
  VERSION               plain X.Y.Z, this library's own
  CHANGELOG.md          this library's own
  README.md             this library's own
  deps                  its in-repo dependencies (section 2); present even when empty
  <package file>        its own lakefile package (lakefile.toml, lean-toolchain, lake-manifest.json)
                        or the equivalent of its language; it names the in-repo libraries it
                        requires ONLY as the relative path ../<dep>
registry/<name>.json    one entry per library (section 1.2)
.land/areas.json        one area per library, and areas for the registry, the documents and the tooling
docs/  scripts/  tests/ the repository's own documents, helpers and lints (the tooling area)
```

A library directory is **self-contained**: its toolchain pin and package file are inside it, so that the directory alone, exported, is a buildable library. A path dependency `../<dep>` resolves the same way in the family repository (`lib/<dep>`) and in a consumer (`vendor/<dep>`, section 4): that is why the form is fixed. A library name is `[a-z0-9][a-z0-9_-]*`, unique, and is never `registry`, `docs`, `tooling` or `inert` (area names, section 1.3). The directory name, the registry file name, the area name and the tag prefix are the same string.

### 1.1 One file per library, nothing every change must edit

There is no root `VERSION`, no root list of libraries, no root changelog of releases: a list that every change edits is a conflict by construction (README 2b). The registry is a directory of files, the version and the changelog live in the library, and any index is generated, never committed.

### 1.2 The registry: `registry/<name>.json`

One JSON object, strict like `.land/areas.json`: an unknown or missing key, a bad value or a duplicate is refused (exit 2) by name.

```json
{
  "v": 1,
  "name": "gamma",
  "kind": "library",
  "status": "experimental",
  "version": "0.4.0",
  "path": "lib/gamma",
  "deps": ["beta"],
  "consumers": ["https://example.org/acme/consumer-one"]
}
```

| key | meaning |
|---|---|
| `v` | exactly `1` |
| `name` | the library's name; equals the file name |
| `kind` | `library` (vendored by consumers, section 4), `spec` (a specification other libraries build on) or `tool` (an executable library). The set is closed |
| `status` | `experimental`, `stable` or `deprecated` (section 8, mixed maturity) |
| `version` | equals `lib/<name>/VERSION` at the same commit (a release bumps both in one landing) |
| `path` | exactly `lib/<name>` (data, so that a reader and a tool never compose it) |
| `deps` | equals `lib/<name>/deps` (a mirror, for a reader of the registry alone: the lint refuses a difference) |
| `consumers` | the PUBLIC repositories that vendor it, as `https` URLs, sorted. Information for the migration and for release notes; never a gate. A private consumer is not named here (section 8, leaks) |

### 1.3 The areas file: one area per library

`.land/areas.json` (`docs/areas.md` section 1) has, in this order: one area per library, `registry`, `docs`, `tooling`.

- **Area `<name>`** owns `lib/<name>/*` **and `lib/<d>/*` for every `d` in the transitive closure of `<name>`'s `deps`** (section 2), sorted, nothing else except root files its steps read (a toolchain manager file, say: shared files are listed in every area that reads them, `docs/areas.md` 3.3). Its steps build and test the library with `cwd` `lib/<name>`, and include the repository's lint (below). **Overlap is the declared dependency:** a change to `lib/alpha/` touches `alpha` and every area that lists `lib/alpha/*`, which are exactly the libraries that depend on it, directly or not. The lint (section 2) refuses an areas file whose library areas are not exactly this; a hand-edited path list is not a declaration the tool trusts.
- **Area `registry`** owns `registry/*`. **Area `docs`** owns `docs/*`, `README.md`, `CHANGELOG.md` (the repository's own, not a library's). **Area `tooling`** owns `scripts/*` and `tests/*`.
- **The public lint is a step of every area** (the same `cwd` and `run` in each, so it runs once per landing, `docs/areas.md` rule 3). It runs on the WHOLE tree and holds the family checks of sections 2 and 3 and the leak check of section 8. No area is stepless: a document can leak a name as well as a source file can.
- A path no area owns (a root file) runs everything (rule 5); the first change to it is judged by every area. `.land/` is gate-defining and runs everything.
- The release candidate of the whole repository (`land-release --rc`, no `--area`) runs every area (rule 7).

## 2. In-repo dependencies: `lib/<name>/deps`

One data file per library: **the direct in-repo dependencies, one name per line, sorted bytewise (C locale), no duplicates, no blank line, no comment, no version, a final newline; empty (zero bytes) when there are none.** Inside the repository there is one version of everything, the commit, so a version here would be a second truth. The closure of a library is its deps, their deps, and so on, computed from these files only; it is a set, with no order.

The lint (`tests/lint.sh` of the family repository; it is a step of every area) refuses:

1. a `deps` file that is missing, unsorted, with a duplicate, a blank or comment line, a name that is not a directory of `lib/` and a registry entry, or the library's own name;
2. **a cycle** in the graph of the `deps` files, naming the cycle's libraries in order;
3. **an undeclared use of another library's files.** The check is mechanical and has two parts, and no part reads prose or guesses an import:
   - the library's package file names in-repo requirements only by the relative path `../<dep>`; the set of names so required must equal `deps` exactly (a required path that is not in `deps`, or a `deps` name no package file requires, is refused). A language-level `import` of a library that the package does not require cannot resolve: the area's own build refuses it, which is why the steps of an area run the real build and not a stand-in;
   - no tracked file under `lib/<a>/` may contain the byte string `../<b>/` or `lib/<b>/` where `<b>` is a library that is not in the closure of `<a>` (a literal match of names the registry lists; a file that has to speak of another library writes its name without a path);
4. a library area whose `paths` differ from `lib/<name>/*` plus `lib/<d>/*` for each `d` of the closure (an area that does not list a dependency would not run when the dependency changes: an escape by construction, `docs/areas.md` 3.3);
5. a registry entry that disagrees with the library (`version` against `VERSION`, `deps` against the file, `path`), a library with no registry entry or no area, and an entry or area with no library;
6. maturity (section 8): a `stable` library whose closure holds an `experimental` one.

## 3. Tags: one signed tag per library release

A release of ONE library is an annotated, ssh-signed tag **`<name>/vX.Y.Z`** (the same key as every release, `docs/signing.md`) on a commit that

1. **landed on `main`** (HEAD is `origin/main`, or the declared candidate `rc/<name>/vX.Y.Z` whose changes are all on main, as `land-release` already requires), and
2. **passed the steps of the library's area AND of every area that depends on it** (every area whose `paths` hold the string `lib/<name>/*`, which by section 1.3 are the dependents, transitively), run as a release candidate with `LAND_RC=1`: nothing cached, selected or skipped.

**The tag's meaning:** "the subtree `lib/<name>/` and the subtrees of its in-repo dependency closure, at this commit." Nothing else in the repository is promised: a sibling library, the registry, the documents and the tooling can be in any state. The tag says nothing about libraries that depend on `<name>`: they are not released by this tag, each takes the next release of its own, and their areas have been run on `<name>`'s commit (point 2) so that a break would have stopped this release.

`VERSION` and `CHANGELOG.md` are **per library**. A change to one library bumps only its own `VERSION`, its own `CHANGELOG.md` and its own registry `version`; no dependency and no dependent is bumped for it. The release refuses (section 5) unless `lib/<name>/VERSION` is the plain `X.Y.Z` of the tag, is greater (by number, never by string) than every existing `<name>/v*` tag, and `lib/<name>/CHANGELOG.md` has a heading line that begins `## X.Y.Z`.

**The message** (the annotation is what the signature covers):

```
<repository> <name>/vX.Y.Z
tree_sha256=<tree hash of lib/<name>/ at the commit>
dep_tree_sha256=<dep>:<tree hash of lib/<dep>/ at the commit>
dep_tree_sha256=<dep2>:<tree hash of lib/<dep2>/ at the commit>
```

`tree_sha256` is the tree hash of `docs/pin.md` section 1 of exactly the directory `lib/<name>/` (the files inside it, paths relative to it; the `.lake` and `.git` exclusions at any depth as there). There is one `dep_tree_sha256=` line for every library of the closure, sorted by name, and none for a library with no deps. So the signature binds the library AND each dependency subtree it vendors with it, and a consumer verifies every vendored directory against a signed value (section 4). **The tag name is the name, the path is `lib/<name>`: the pair is never composed from the message.** A tag that is not annotated and signed by a key in the consumer's `.land/land.signers`, whose `VERSION` or `deps`-derived closure differs from what the message says, or whose message has two `tree_sha256=` or a `dep_tree_sha256=` line out of the closure, is refused by `land-pin vendor`.

**A legacy tag** is a tag `<name>/vX.Y.Z` whose commit has no `lib/<name>/deps` (made by the migration, section 6, from a release of the old repository): its closure is empty, it has `tree_sha256=` only, and the libraries the old repository vendored inside itself stay inside its subtree. It verifies as any tag does.

**Tags are never moved or deleted** (`docs/pin.md` section 2). The tag ruleset (`templates/ruleset-protect-release-tags.json`) of the family repository must cover `refs/tags/*/v*`, which the default pattern of that template does not; this is a checklist item of the repository's creation, and `land-audit` warns when it is missing.

## 4. Pins: a consumer vendors a library as a subtree

A consumer vendors library `NAME` at `vendor/NAME/` (as today) and lists it in `.land/pins.lock`. **One line per vendored library, seven fields:**

```
NAME SOURCE_URL TAG COMMIT PATH TREE_SHA256 ROLE
```

`NAME` is `[a-z0-9][a-z0-9_-]*` and unique; `SOURCE_URL` is the public https URL of the family repository; `TAG` is `<root>/vX.Y.Z` (the tag the vendoring was made from); `COMMIT` is 40 hex, the commit that tag points at; `PATH` is exactly `lib/NAME`; `TREE_SHA256` is 64 hex and is **the tree hash of exactly `PATH` at `COMMIT`**; `ROLE` is `root` (the consumer asked for it) or `dep` (it is there because a root's closure names it). The lock is read strictly as before (a wrong field count, a bad hex string, a bad name, a duplicate, a `PATH` that is not `lib/NAME`, a `TAG` whose prefix is not a name in the lock, exit 2). The old five-field line `NAME URL TAG REV TREE_SHA256` (a whole repository at `vX.Y.Z`) is still read, for one purpose: the consumers that have not yet been re-pointed (section 6). The release that deletes its reader is a major release, made when the registry lists no consumer still on it.

**Why a subtree hash.** The hash changes **only when that directory changes**. A landing in a sibling library moves the commit and moves nothing of this library's `TREE_SHA256`, so unrelated libraries never move a consumer's pin and `land-pin outdated` has nothing to say about them.

**Vendoring vendors the closure, flat, from the same commit.** `land-pin vendor NAME URL TAG`:

1. fetches the tag, refuses unless it is signed by a key of `.land/land.signers`, and checks that `TAG` is `NAME/vX.Y.Z`;
2. exports `PATH` of the tagged commit (the files of `lib/NAME/` with the prefix removed) and recomputes the tree hash; it must equal the message's `tree_sha256=`;
3. reads the `deps` files of that commit, computes the closure, and refuses unless the message has exactly one `dep_tree_sha256=` line for each member and the recomputed hash of each `lib/<dep>/` equals it;
4. writes `vendor/NAME/` and `vendor/<dep>/` for every member, **one copy of each, side by side (flat)**, so `../<dep>` resolves as it does in the repository; and one lock line each: `NAME` as `root`, each member as `dep`, all with `SOURCE_URL`, `PATH`, and the tree hash recomputed;
5. a `dep` line carries the `TAG` and `COMMIT` of **the first root, by name, whose closure holds it**; the line is rewritten under that rule whenever the set of roots changes, so it is derived data and `verify` can check it.

Nothing vendors from two commits at once: a library and the dependencies it brings are always from the one commit its tag names. If another root already vendors a closure member and the recomputed hash **differs**, the vendoring is refused, naming both roots and the member (`land-pin verify` rule 3 of `docs/pin.md`, one version of each library in the closure, unchanged): the consumer takes a tag of one of them whose member matches, or moves both (`update --all` does). If it is equal, the existing line stays: that sharing is exactly what a subtree hash allows when a dependency did not change between two commits.

**`land-pin verify` (offline)** checks, each naming the library and the reason:

1. every lock line has `vendor/NAME/` and its tree hash equals `TREE_SHA256`;
2. every directory directly under `vendor/` has a lock line (an unlocked library is refused);
3. every copy of a library found at any depth has the same tree hash as every other copy and as the lock;
4. **the closure is complete:** every name in the `deps` file of each vendored library is itself a locked, vendored library, and every `dep` line is named in the `deps` file of a vendored library (a stale dependency left by an update is refused);
5. every `dep` line has the `TAG` and `COMMIT` of its first root by name (the derived rule above);
6. the old rules for skills (`docs/pin.md` section 8) and for malformed locks.

It cannot check offline that a tag still points at its commit, nor that the hashes equal the signed message: that was checked when the line was written (`vendor` refuses otherwise), and `land-pin online` repeats it for every root (each `TAG` must still point at `COMMIT`, each hash is recomputed from the fetched commit and compared with the tag's message; a moved or deleted tag is a finding).

**`land-pin outdated` and `update --all` compare per library**, over the roots only (a `dep` line is reported with its root, never alone):

- the **newer tags** are those of the same prefix, `NAME/vX.Y.Z`, compared numerically by their three numbers (`docs/pin.md` 9.1); a tag of another library is never a candidate;
- a root is `behind` exactly when there is a newer tag of **that library**. The report has, for it, `closure_changed`: the sorted names, from the closure at the pinned commit and at the newer tag's commit, whose subtree hash differs between the two (`null` when nothing is newer). A newer tag whose closure did not change says so: it is a change of the library's own subtree alone. Main having moved in some other library is not a finding; main having moved in this library's closure without a tag is not a finding either (no tag, nothing to take), and the report does not guess;
- `update --all` takes each behind root with `vendor` (section 4 above: the whole closure again, from the new commit, replacing the old closure whole: a member the new closure dropped and no other root names is removed with its lock line) and leaves every library that is not behind alone, whatever main did. Everything else of `docs/pin.md` 9.2 (a clean tree, atomic, never a commit, a dry run) is unchanged.
- the JSON of `outdated` gains the key `closure_changed` for kind `library` (a key added is the same `v`).

**The signature of each vendored dependency** is the signature of its root's tag: the dependency's own hash is a line of the root's signed message. A dependency does not need a tag of its own at that commit.

## 5. Release: `land-release --area NAME`

`bin/land-release` is the command that exists. Added, for the family repository:

```
land-release --area NAME [--declare] [--rc] [--push]
```

With `--area NAME`:

1. NAME must be a library with an area in `origin/<base>`'s `.land/areas.json`; `VERSION`, `CHANGELOG.md` and `registry/NAME.json` are read from `lib/NAME/` and `registry/` at HEAD, and the checks of section 3 (the plain `X.Y.Z`, greater than every existing `NAME/v*` tag, a `## X.Y.Z` heading, registry `version` equal) must pass, or no tag (exit 1 or 2 as the tool already uses them);
2. the clean tree, `HEAD == origin/<base>` and the candidate branch rules are as today; the candidate branch is `rc/NAME/vX.Y.Z` (one per library and version);
3. **`RC` runs the area and its dependents:** every step of area NAME and of every area whose `paths` hold `lib/NAME/*`, in file order, with `LAND_RC=1`, nothing cached, selected or skipped (`docs/areas.md` rule 7, restricted to these areas). The areas it does not run are named in the output. **`LAND_RC_CMD` is not run:** it is the repository-wide candidate, and a library's own extra checks are steps of its area; `land-release --rc` with no `--area` runs every area and then `LAND_RC_CMD`, and tags nothing;
4. the tag is made as in section 3, signed by `LAND_SIGNING_KEY` (the same key and the same `.land/land.signers` principal as every release: custody and rotation as in `docs/signing.md`), with `tree_sha256=` and the `dep_tree_sha256=` lines;
5. `--push` pushes the tag, never a branch.

Without `--area`, a repository that has `registry/` refuses to tag (exit 2): a tag of the whole repository has no meaning there. Every other repository keeps `v<VERSION>` exactly as today.

The one verifier (`lib/verify.sh`) gains the subtree form (export a path of a commit, hash it, and check a message's `dep_tree_sha256=` lines against the closure of that commit); `land-release`, `land-pin` and `install` use that one function, and `tests/test_verifier_one.sh` keeps a second one out.

## 6. Migration of an existing library repository into `lib/<name>/`

**Preconditions, checked before anything is written** (a refusal changes nothing): every release tag of the old repository is annotated and its commit is an ancestor of the old `main`; the old repository's tree hash at each tag equals the `tree_sha256=` of that tag's message where it has one; the old `main` is green; the public lint of the family repository, run over the old repository's WHOLE HISTORY (section 8), finds nothing.

**Order: leaves first.** A library migrates after every family library it vendors (nested or direct) has migrated, so that its adaptation can name `../<dep>` and a real `lib/<dep>/`. Libraries with no family dependency go first, in any order; then those whose dependencies are all in; and so on (a topological order of the old vendoring, which has no cycle, since a cycle of vendored copies cannot exist). One library is migrated at a time, under a hold of the family repository (`land-direct --hold "migrating NAME"`, then `--release`), so that the trunk is quiet while the merge lands.

**The operations, per library `NAME`, from a scratch clone of the old repository** (made with `mktemp -d`, removed at the end; nothing is done in the old working copy):

1. `git clone --no-local OLD scratch && cd scratch`; check out its `main`; remove every ref but `main` and the tags (no other branch is migrated; an unmerged branch is archived as a diff and a reason first, README 4.6).
2. **Move the whole tree under `lib/NAME/`, rewriting history:** `git filter-repo --to-subdirectory-filter lib/NAME --force`. Every commit is kept, with its author, dates and message; only its tree is re-rooted. The tool writes `.git/filter-repo/commit-map` (old hash, new hash, one pair per line) and rewrites the old tags onto the new commits; these tag objects are discarded in step 5 (their signatures covered the old hashes and no longer verify). Because the whole tree is moved and nothing else changes, **the tree hash of `lib/NAME/` at a migrated commit equals the old tree hash at the old commit** (the hash is of the directory's files with paths relative to it): the migration checks this equality for every old tag and refuses on any difference.
3. In a clone of the family repository, with `main` at its head: `git fetch ../scratch main:refs/heads/migrate/NAME` then `git merge --allow-unrelated-histories --no-ff -m "chore(NAME): migrate the library, with its history, into lib/NAME" migrate/NAME`. The first parent is the family `main`, so the push is a plain fast-forward of the trunk; the old history is the second parent and `git log lib/NAME` and `git blame` follow it. This merge is the **one commit of the repository not made by the lander** (the lander rebases and flattens, and cannot carry a second parent); it is the owner's act, under the hold, never forced, and nothing it touches lies outside `lib/NAME/`.
4. **The adaptation** is a second ordinary commit on top of the merge, in the same push: add `lib/NAME/deps` (the sorted family libraries the old repository vendored), replace the old repository's vendored family copies (`vendor/<dep>/`, nested ones too) by the path requirement `../<dep>`, remove their lock lines, add `registry/NAME.json` and the area `NAME` to `.land/areas.json` (section 1.3, with its closure), and delete what the repository needed only for being a repository (its own vendored lander, rulesets, workflows and scripts, which the family repository already has once). A library that vendors a dependency that is not in the family is a point this page leaves open (section 12).
5. **Before the push,** in a scratch worktree of the merge result, the owner runs the family repository's `land-release --rc` (every area, every step) and the public lint: a red result is fixed in the adaptation commit, never pushed. Then `git push origin HEAD:main` (a fast-forward), then `land-direct --release`. From the next landing on, the base has the area, and the library is judged by it (`docs/areas.md` section 7: the base judges; this is the additive landing).
6. **The old tags are re-created under the new names, on the migrated commits.** For each old tag `vX.Y.Z` with old commit `C`, `C' = commit-map(C)` (the commit of the migrated history, **before** the adaptation): `land-release --area NAME --retag vX.Y.Z --commit C'` (a flag of the implementing item), which refuses unless `C'` is an ancestor of `origin/main`, `lib/NAME/VERSION` at `C'` is `X.Y.Z`, the tree hash of `lib/NAME/` at `C'` equals the old tag's `tree_sha256=` (or, for a pre-signing old tag with none, the old tree hash), and `NAME/vX.Y.Z` does not exist. It runs no candidate (the old repository already passed it; these are legacy tags, section 3) and makes the annotated tag `NAME/vX.Y.Z` on `C'` with the message `tree_sha256=` and one line `retagged_from=<old URL> <old tag> <old commit>`.
7. **The signature is re-issued, not moved.** The new tag is a NEW tag object, signed by the same release key (`LAND_SIGNING_KEY`, on the maintainer's host), verified against `.land/land.signers` of the family repository (the same public key line, its fingerprint checked out of band as in `docs/signing.md`). The old tag's signature stays valid for the old object in the old repository, which is archived and never deleted; it is not edited and no tag there is moved.
8. **What a consumer's pin does.** A lock line for `NAME` at the old tag keeps verifying offline: `vendor/NAME/` is unchanged and its hash is what the line says, and the old repository's tags are still served while it is archived. Re-pointing is `land-pin vendor NAME <family URL> NAME/vX.Y.Z` with the SAME version: the signed new tag's `tree_sha256=` equals the old hash by step 2, so `vendor/NAME/` comes out **byte for byte as it was** and the change is the lock line alone (a diff of `vendor/` that is not empty is a refusal to commit it). A consumer is then on a family pin, and `land-pin outdated` looks at the family repository. Until it is re-pointed `outdated` looks at an archived repository that has no newer tag and says "current": the registry's `consumers` list is the checklist, and the archive (step 9) waits for it.
9. **Consumers are re-pointed, then the old repository is archived.** For each consumer in `registry/NAME.json`'s `consumers` (and the owner's private consumers, listed outside this repository): one change per consumer, `land-pin vendor` as above, landed through that consumer's own lander. When every one is landed, the old repository gets a last landing that replaces its `README.md` with a notice (the library moved to `lib/NAME/` of the family repository at the URL, the last version released there, the tags that stay here, and that new releases are tagged `NAME/vX.Y.Z` over there), and is **archived** (read-only; never deleted, and no tag removed). The notice and the archive are the owner's act (publishing).
10. **The scratch clone, the temporary branch `migrate/NAME` and every temporary directory are removed** at the end, in a trap, whether the migration succeeded or not; a migration that stopped leaves the family repository as it was (the merge is pushed last, everything before is local).

**A consumer that vendored two old repositories now has one family pin** only if it vendors them through one family tag: it does not need to: each library stays a `root` at its own tag, and a library that is the dependency of another comes as its `dep` line when the second root is re-pointed to its family tag; until then the old copies stay nested inside the old vendored directories and `verify` rule 3 keeps them equal, as today.

## 7. What stays separate, and why

- **The lander (this repository).** It bootstraps every repository, the family repository included, and is vendored by all of them: a repository cannot depend on itself for its own first landing, and `scripts/bootstrap-land` is its recovery path. Its release must not depend on any library: `land-release` of this repository runs this repository's own steps and signs with the key; if the lander lived in the family repository, a red area of an unrelated library (experimental, say) would hold back a lander release that every repository, family and products, needs to take. A change to the tools of this page (`land-pin`, `land-release`, `lib/verify.sh`) is a release of this repository, taken into the family repository by `land-update` like any other consumer's.
- **The products.** A product is a consumer: it vendors libraries and is vendored by nobody, it has its own deploy and release cadence, it may be private, and its main may carry names, hosts and settings that this public repository must never hold (section 8). Putting products in the family repository would make the trunk's gate depend on them and the public lint refuse them.
- **Third-party skills** stay pinned by source URL and commit (`docs/pin.md` section 8), unchanged.

## 8. Risks, stated plainly, each with how it is bounded

**One trunk for all agents.** Every landing, of any library, pushes the same ref. Area-disjoint landings do not disturb each other's validation (`docs/areas.md` 3.2: each area is its own instance of the model, and with `LAND_REUSE=1` a verdict whose area the trunk's move did not touch is reused), **but they still race for the fast-forward**: the push is the only arbiter (3.4), so a lander of area `a` can lose it to a landing of area `b`. What that costs is bounded: the race window is the lander's rebase-and-decide time, not the validation time `T`; a lost race costs **a rebase and a decision, not a re-test** (3.2, last paragraph), because the areas it touches did not move; and it is retried with jittered waits up to `LAND_ATTEMPTS` (30) within `LAND_DEADLINE` (900 s), after which it stops with exit 16 and nothing lost. `LAND_REUSE=1` is therefore **required** in the family repository (`docs/areas.md` section 7 step 5, once the candidate has been green with the factoring). What areas cannot cure: a hot dependency, since a landing in a leaf touches every dependent (the price of the declared overlap). It is measured with `land-check --areas` and `land-metrics` (landings and exit-16 stops per area) and cured by splitting the leaf along the seam its dependents use, and by keeping its steps short (3.4). The public lint, being a step of every area, runs once per landing and must stay fast; a slow lint is a defect of the repository, since it is on every landing's path.

**A leak into a public repository.** The family repository is public (`.github/visibility`), and a library repository that was private brings its history. Bounded by: (a) the public lint (`tests/lint.sh`, names of products, people, machines and companies, local paths) runs on the WHOLE tree and is a step of every area, so no landing is exempt, and an unmapped or gate-defining path runs everything; (b) the migration refuses unless the same lint finds nothing in the old repository's whole history: every commit's tree (`git grep` over `git rev-list --all`), every commit message and every tag message; history that fails is rewritten in the scratch clone (`git filter-repo --replace-text`) **before** step 3, never after, because nothing public can be taken back; (c) the registry's `consumers` names only public repositories, so a private product is not named in a public file; (d) the tag messages are text of the repository and are covered by the same lint before a tag is pushed. A leak found after the push is rotated and reported, not hidden.

**Mixed maturity.** One repository holds a stable library and an experiment. Bounded by the registry's `status`: `experimental` (any version), `stable` (version at least 1.0.0, enforced by the lint), `deprecated` (no new dependents: the lint refuses a new `deps` line naming it, judged against the base). A `stable` library may not depend on an `experimental` one (lint, section 2 point 6), so the maturity of a closure is its weakest member and is visible. Because every library has its own area, an experiment that is red blocks only its own landings and those of its dependents: a stable library outside its overlap lands and releases without it (`land-release --area` runs the area and its dependents only). `land-release --rc` with no `--area` is the whole-repository audit and reports every red area by name.

**Smaller ones.**
- **One key signs every library's tag.** As today (one key across the repositories), so the custody and rotation rules of `docs/signing.md` are unchanged; a compromise is no wider than it was. The tags are verified per library against the consumer's own signers file.
- **A diamond across two roots** (two libraries, one dependency, the dependency changed between their tags) is refused by `vendor` and by `verify` rule 3, never merged silently; the remedy is a newer tag of the older root.
- **A larger clone.** Every consumer fetch gets the whole repository (`vendor` uses a depth-1 fetch of the tag); a partial clone (`--filter=blob:none`) is an optimization the implementation may make and the contract does not require.

## 9. A worked example

Generic names. A family repository with four libraries: `alpha` (no dependencies), `beta` (depends on `alpha`), `gamma` (depends on `beta`; so its closure is `beta` and `alpha`) and `delta` (independent, still an experiment).

```
lib/alpha/deps   (empty)
lib/beta/deps    alpha
lib/gamma/deps   beta
lib/delta/deps   (empty)
```

`registry/gamma.json` is the entry of section 1.2 (`"deps": ["beta"]`). The areas file, complete and valid (`docs/areas.md` section 1), is:

```json
{
  "version": 1,
  "areas": [
    {
      "name": "alpha",
      "paths": ["lib/alpha/*"],
      "steps": [
        {"run": "tests/lint.sh"},
        {"run": "lake build", "cwd": "lib/alpha"},
        {"run": "lake test", "cwd": "lib/alpha"}
      ]
    },
    {
      "name": "beta",
      "paths": ["lib/alpha/*", "lib/beta/*"],
      "steps": [
        {"run": "tests/lint.sh"},
        {"run": "lake build", "cwd": "lib/beta"},
        {"run": "lake test", "cwd": "lib/beta"}
      ]
    },
    {
      "name": "gamma",
      "paths": ["lib/alpha/*", "lib/beta/*", "lib/gamma/*"],
      "steps": [
        {"run": "tests/lint.sh"},
        {"run": "lake build", "cwd": "lib/gamma"},
        {"run": "lake test", "cwd": "lib/gamma"}
      ]
    },
    {
      "name": "delta",
      "paths": ["lib/delta/*"],
      "steps": [
        {"run": "tests/lint.sh"},
        {"run": "lake build", "cwd": "lib/delta"},
        {"run": "lake test", "cwd": "lib/delta"}
      ]
    },
    {"name": "registry", "paths": ["registry/*"], "steps": [{"run": "tests/lint.sh"}]},
    {"name": "docs", "paths": ["docs/*", "README.md", "CHANGELOG.md"], "steps": [{"run": "tests/lint.sh"}]},
    {"name": "tooling", "paths": ["scripts/*", "tests/*"], "steps": [{"run": "tests/lint.sh"}]}
  ]
}
```

What follows from it:

- A change to `lib/alpha/` touches `alpha`, `beta` and `gamma` (and not `delta`): the lint runs once, then the three builds and tests. A change to `lib/gamma/` touches `gamma` only. A change to `lib/delta/` touches `delta` only, and is never disturbed by, nor disturbs, the others (`delta`'s overlap with anything is empty). A change to `registry/gamma.json` touches `registry` and runs the lint. A path no area owns (`LICENSE`) runs every area.
- **Releasing `alpha` 1.3.0.** The landing that bumps `lib/alpha/VERSION`, its `CHANGELOG.md` (a `## 1.3.0` heading) and `registry/alpha.json` `version` changes nothing of `beta` or `gamma`. Then `land-release --area alpha --push` runs the steps of `alpha`, `beta` and `gamma` (the three areas that hold `lib/alpha/*`; `delta`, `registry`, `docs` and `tooling` are named as not run), and only if all pass signs `alpha/v1.3.0`. Had `beta` been red against the new `alpha`, there would be no tag, and the red area names where to look. `beta` and `gamma` are not released by it.
- **Releasing `gamma` 0.4.0** makes `gamma/v0.4.0`, whose message is:

```
family gamma/v0.4.0
tree_sha256=3b1f6c0a9e2d47855a0c1e6b7d93f2480ae1c5d7b6f90324e8a1d5c7f0b29e64
dep_tree_sha256=alpha:9d41c7e0b5a3826f1e07d4c9b2a85630f7e1d2c4a9b0583e6f41d7c2a8b3e015
dep_tree_sha256=beta:5e7a0c93d1b4682f0a9e3c7d51b8f2046c1a7e9d3b50f8246a1c0e7d93b5f812
```

- **A consumer vendors it:** `land-pin vendor gamma https://example.org/acme/family gamma/v0.4.0` writes `vendor/alpha/`, `vendor/beta/` and `vendor/gamma/` side by side from the one commit, so `../beta` and `../alpha` resolve, and the lock:

```
# .land/pins.lock
alpha https://example.org/acme/family gamma/v0.4.0 0123456789abcdef0123456789abcdef01234567 lib/alpha 9d41c7e0b5a3826f1e07d4c9b2a85630f7e1d2c4a9b0583e6f41d7c2a8b3e015 dep
beta https://example.org/acme/family gamma/v0.4.0 0123456789abcdef0123456789abcdef01234567 lib/beta 5e7a0c93d1b4682f0a9e3c7d51b8f2046c1a7e9d3b50f8246a1c0e7d93b5f812 dep
gamma https://example.org/acme/family gamma/v0.4.0 0123456789abcdef0123456789abcdef01234567 lib/gamma 3b1f6c0a9e2d47855a0c1e6b7d93f2480ae1c5d7b6f90324e8a1d5c7f0b29e64 root
```

- **Unrelated landings do not move it.** Fifty landings in `lib/delta/` later, the consumer's three hashes are what they were and `land-pin outdated` reports nothing. Then `alpha/v1.3.0` is tagged and `gamma` is untouched: the consumer's root is `gamma`, there is no newer `gamma/v*` tag, and nothing is reported (a newer `alpha` tag is not a candidate for a `dep` line). When `gamma/v0.5.0` exists, `outdated` reports `gamma gamma/v0.4.0 -> gamma/v0.5.0` with `"closure_changed":["alpha","gamma"]` (if `beta` did not change between the two commits) and `update --all` re-vendors the three directories from the new commit and rewrites the three lines.
- **A diamond.** The consumer also vendors `epsilon` (a library that depends on `alpha`) at a tag whose `lib/alpha/` hash differs from the one `gamma/v0.4.0` carries: `vendor epsilon ...` is refused, naming `alpha`, `gamma` and `epsilon`; the consumer takes `gamma/v0.5.0` or an older `epsilon` whose `alpha` matches.
- **Migration of `beta`** (old repository `beta-old`, which vendored `alpha`): `alpha` goes first (a leaf). Then, from a scratch clone of `beta-old`, `git filter-repo --to-subdirectory-filter lib/beta --force`; the merge with unrelated histories into the family repository's `main` under a hold; the adaptation commit that adds `lib/beta/deps` (`alpha`), drops `beta-old`'s `vendor/alpha`, requires `../alpha` and adds `registry/beta.json` and the area `beta`; `land-release --rc` in a scratch worktree; the push; `land-release --area beta --retag v0.2.0 --commit C'` for each old tag (`beta/v0.2.0` ...), each recording `retagged_from=`; the consumers re-pointed with `land-pin vendor beta ... beta/v0.2.0` (the `vendor/beta/` diff empty); the old repository's README replaced by the notice, then archived.

## 10. What this page does not do

- It does not build anything: no lint, no `land-pin` change, no `--area` or `--retag`, no migration. Section 11 is what the implementing items must test; each of their negative tests is **watched to fail** (a deliberately wrong tool or tree, shown red, as `docs/areas.md` 10 and `docs/pin.md` 9.6 do), and is kept only then.
- It does not select inside an area, infer a dependency from source, or read prose: the dependency graph is the `deps` files, the closure is computed from them, the overlap is the areas file, and every check above compares data.
- It does not change the lander, the push, holds and freezes, the commit rules, the signing key, or any repository that is not the family repository, until a consumer is re-pointed.
- It does not decide for the owner: which libraries migrate and when, what a `stable` library is beyond the rule above, and who is a public consumer.

## 11. What the tests must refuse (each WATCHED to fail)

Every fixture is a local git repository: no network.

- **The lint:** a `deps` file unsorted, with a duplicate, a blank line, a comment, a version, a missing file, a name that is not a library, and its own name; a two-library cycle and a three-library cycle (the cycle named); a package file that requires `../<b>` with `b` not in `deps`; a `deps` name no package requires; a tracked file naming `lib/<b>/` or `../<b>/` for a library outside the closure (and the same text for a library inside the closure, which must be ACCEPTED); a library area whose paths miss a closure member or list a library outside it; a library with no area, no registry entry, or a registry entry with another `version`, `deps` or `path`; a library area named `registry`; a `stable` library with an `experimental` dependency, and a `stable` library with version 0.x; a new `deps` line naming a `deprecated` library.
- **The tag and the release:** `land-release --area` with `VERSION` not equal to the tag, not greater than an existing `NAME/v*` (and `v1.10.0` after `v1.9.0` ACCEPTED), no `## X.Y.Z` heading, a registry mismatch, a dirty tree, HEAD not `origin/main`, a missing key; a **red dependent area** (a change in `alpha` that breaks `gamma`'s build: no tag, and the area is named); a red area that is NOT a dependent (`delta`) which must NOT stop the release (ACCEPTED); `LAND_RC_CMD` not run with `--area`; no `--area` in a repository with `registry/`. The message has the `tree_sha256=` of `lib/NAME/` and exactly one `dep_tree_sha256=` per closure member, sorted.
- **`--retag`:** a commit that is not an ancestor of `origin/main`, whose `VERSION` differs, whose subtree hash differs from the old tag's `tree_sha256=`, an existing tag; the migrated history whose subtree hash at a tag differs from the old tree (the migration is refused); a history with a leak (refused before step 3).
- **`vendor`:** an unsigned tag, an unknown signer, a tag whose prefix is not `NAME`, a message with no `tree_sha256=`, with two, with a `dep_tree_sha256=` missing, extra, or disagreeing with the exported directory, a closure whose `deps` file at the commit differs from the message's list, a diamond (a member already vendored with another hash); and ACCEPTED: a shared dependency with an equal hash from two roots at two commits.
- **`verify`:** an edited, added, deleted vendored file; an unlocked directory; a lock line with no directory; a `dep` line no vendored `deps` names; a name in a vendored `deps` that is not locked; a `dep` line whose `TAG` or `COMMIT` is not its first root's; a flipped hash; a malformed line (each of the seven fields, a duplicate, a `PATH` that is not `lib/NAME`); the five-field line ACCEPTED while the legacy reader exists; a nested copy that differs.
- **`outdated` and `update --all`:** a newer tag of ANOTHER library is not a finding; `v1.10.0` against `v1.9.0` is; `closure_changed` names exactly the members whose hash differs; a library that did not change is not touched when main moved elsewhere; an update that drops a closure member removes it and its line, and keeps one another root still names; the whole run atomic as in `docs/pin.md` 9.6.

## 12. Open points (named, not decided here)

- **A library that vendors a non-family dependency** (a third-party package, say). The tree hash of `lib/NAME/` would carry it, and a consumer that vendors `NAME` gets it inside the subtree; whether such pins move to one root-level lock of the family repository, or the library keeps them inside its directory as today, is the owner's decision before the first such library migrates. Until then it is not migrated.
- **The registry's `consumers` for private products** are recorded outside this repository; how the owner's private list reaches the migration checklist is the owner's.
- **Partial clones** for `vendor` are an optimization and not part of this contract.
