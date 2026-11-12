# What the tool ships, and what a repository may not copy

Status: accepted 2026-11-11. With `docs/pin.md` this makes the family take everything it shares from one place by one
mechanism. The end state it defines, checkable on every repository:

> Vendoring, releasing, versioning, pinning and taking dependencies are done the same way in every vbm repository.

## 1. The rule

Anything a repository uses that is not its own arrives by exactly one of two mechanisms, and the repository carries
no other copy:
- a LIBRARY (a package with its own releases): `land-pin vendor`, into `vendor/NAME/`, locked in `.land/pins.lock`
  (docs/pin.md);
- a TOOL FILE (a script, a library of shell, a skill): the vbm-land payload, into `.land/tool/` and
  `.agents/skills/`, pinned by `.land/PIN` (`land-update`).
A file is one or the other, decided here. Its version is the version of the package that ships it.

## 1a. Where things live (the layout convention)

One rule, borrowed from how other ecosystems do it: a tool keeps what belongs to it in ONE hidden folder (`.github/`,
`.cargo/`, `.vscode/`, `.husky/`), pins what it depends on in a lock file (`Cargo.lock`, `go.sum`), vendors third-party
source in `vendor/` (Go, Ruby, PHP), turns itself on by the PRESENCE of its configuration file (`.eslintrc`,
`vite.config.ts`, `rustfmt.toml`) and versions with `vX.Y.Z` tags, a version file and a `CHANGELOG.md`.

| what | where | the habit it follows |
|---|---|---|
| the tool, vendored, read-only | `.land/tool/`, its skills in `.agents/skills/` | a vendored toolchain |
| which release of it | `.land/PIN` | `rust-toolchain.toml` |
| the repository's settings for the lander | `.land/land.conf` | `.cargo/config.toml` |
| the repository's settings for a language's gates | `.land/<language>.conf` (`.land/lean.conf`) | `rustfmt.toml`, `clippy.toml`: one file per tool |
| hooks | `.land/land.d/` | `.husky/` |
| who may sign releases | `.land/land.signers` | `allowed_signers`, `cosign.pub` |
| the libraries the repository vendors | `.land/pins.lock`, and the source in `vendor/NAME/` | `Cargo.lock` + `vendor/`, `go.sum` + `vendor/` |
| the repository's own gate and its own tests | `scripts/tier1.sh`, `scripts/test_*.sh` | a `Makefile` or `justfile` |
| the version | `VERSION`, tag `vX.Y.Z`, `CHANGELOG.md` | |

Rules:
1. A file the TOOL reads lives in `.land/`, its name defined once in `lib/paths.sh`. A new tool or check never invents a
   location (no new dotfile or top-level folder, no data file dropped in `scripts/` for the tool to find).
2. A configuration file's presence turns its feature on. There is no separate switch to keep in step with it.
3. The format of a configuration file is the format `land.conf` already has (`lib/conf.sh`: strict, known keys only,
   one parser). Not a second format.
4. A repository's OWN scripts and the data only they read stay where they are: nothing moves for tidiness.
   Disturbing a repository needs a reason that a tool or a check requires.
5. Where an existing file the tool reads sits elsewhere (`scripts/long-runners.txt` for the guard lint,
   `scripts/pin-roots.txt` in two repositories), it moves to `.land/` when that tool or check next changes, in the same
   commit that changes its reader.

## 2. Why (the inventory of 2026-11-11, ten repositories)

The same files appear in several repositories as hand-edited copies. Of the files present in three or more
repositories: `lib-ran.sh` (7 copies, 5 variants), `ran-evidence.sh` (7 copies, 7 variants), `run-scoped.sh` (6, 4),
`run-tests-parallel.sh` (6, 6), `git-hermetic.sh` (5, 5), `check-zero-warning.sh` (6, 4), `AxiomGate.lean` (6, 6),
`pinned-lib.py` and its lock (3, 3 each). The differences found in the first four are drift, not need: a documentation
path, an old directory layout, a word in a comment, a few lines of local commentary. One canonical version serves all.

## 3. The decisions

| group | files | owner | state |
|---|---|---|---|
| the test-running runtime | `lib-ran.sh`, `ran-evidence.sh`, `run-tests-parallel.sh`, `run-scoped.sh`, `lib-reap.sh`, `lib-no-crash-record.sh`, and the tests of these | the vbm-land PAYLOAD (`lib/`, `bin/`): BUILT: the evidence pair, run-scoped and lib-reap (4b), the parallel runner (4c); `lib-no-crash-record.sh` is already here (`lib/no-crash-record.sh`), so a repository only deletes its copy | built; the retired-path check (section 5) is next |
| the pin tool | `pinned-lib.py`, `pinned-libs.lock` | replaced by `land-pin` and `.land/pins.lock` | built (v0.10.0); each repository deletes its copy |
| other process scripts | `git-hermetic.sh`, `check-zero-warning.sh`, `lint-pipefail.sh`, `lint-public`, `public-banned-hashes.txt`, `ran-gates.txt` | decided after the same inventory (each is read, its variants diffed) | to inventory |
| the Lean gates | `AxiomGate.lean`, `LedgerGate.lean`, `ClosureGate.lean`, `trust_ledger.py`, `trust-ledger-check.sh` | the vbm-land PAYLOAD, as an opt-in `lean/` set (section 4a) | to inventory and merge |
| repository-owned | `tier1.sh`, the repository's tests, its build file, `AGENTS.md` | the repository | stays |
| boilerplate at creation | `LICENSE`, `NOTICE`, `SECURITY.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `.gitignore`, `mise.toml` | templates (`new-repo`); `LICENSE` is also checked equal to the standard's | to specify |

## 4. The runtime moves into the payload

The canonical version of each file of the first group is the merge of the variants (the differences resolved to the
generic form: paths from `lib/paths.sh`, no repository-specific commentary), with its self-test moved into this
repository's `tests/`. A repository then:
1. updates its tool (`land-update`), which brings the runtime to `.land/tool/`;
2. points its call sites at the payload paths (a sourced library `.land/tool/lib/NAME.sh`; an executable
   `.land/tool/bin/NAME`);
3. deletes its own copies and the tests of them.

## 4b. run-scoped, lib-reap, and the heavy-host guard

- `bin/run-scoped.sh` joins the payload and replaces `scripts/run-scoped.sh` (every repository's copy) and
  `templates/run-scoped.sh` (the copy-me template that produced the drift: it is deleted). It finds the guard BESIDE
  it (`bin/no-build-guard`), so it works in this repository and in a consumer's `.land/tool/bin/`. The name keeps its
  extension: the guard's lint and its documentation name `run-scoped.sh`.
- `lib/reap.sh` joins the payload and replaces `scripts/lib-reap.sh` (identical in every repository) and the inline
  copy of the same function in `tests/run.sh`.
- `no-build-guard --lint` checks the VENDORED helper (`$LAND_DIR/bin/run-scoped.sh` in a consumer, `bin/run-scoped.sh`
  here) as it checked the repository's copy: it must call the guard before it starts anything, and run with a marker
  present it must refuse and start nothing (the lint executes it). A repository that declares runners and has no
  vendored helper fails. Because the helper is now a tool file, `land-check` also refuses an edited one.
- `scripts/long-runners.txt` and `scripts/heavy-runners.txt` stay repository-owned (they say WHICH runners need
  scoping); callers use `.land/tool/bin/run-scoped.sh NAME MAXSEC CMD...`.

## 4c. The parallel test runner

- `bin/run-tests-parallel` joins the payload: the richest variant of the six copies plus the temporary-space check
  only one of them had; it reads evidence with the reader beside it (`bin/ran-evidence`), takes the repository root
  from git, and has an OPTIONAL per-script bound, `TEST_TIMEOUT` (unset means none, as in the copies: no new limit is
  introduced for a repository).
- This repository's `tests/run.sh` becomes the lint followed by `TEST_TIMEOUT=300 bin/run-tests-parallel
  tests/test_*.sh`: the tool eats its own runner, and its bound stays exactly what it was.
- One failure text for "exit 0 without evidence", the runner's: `FAIL SCRIPT: exit 0 but no ran-evidence (REASON)`.

## 4a. The Lean gates: in the payload, not a separate package

A separate package for them existed (`vbm-gates`, retired 2026-11-09). It was never adopted: every repository kept its
own copies (six variants of the axiom gate remain), and the lander it plugged into later dropped the judge, the
approvals and the protected lists it served. Shared machinery that each repository must opt into separately does not
get adopted; machinery that arrives with the tool every repository already vendors cannot be skipped. So:
- The Lean gates live in this repository under `lean/`, ship to a consumer in `.land/tool/lean/`, and are on for a
  repository that has `.land/lean.conf` (section 1a: the file's presence is the opt-in; a repository in another language
  has none, so the tool stays language-neutral). `.land/lean.conf` says WHICH modules to audit (the axiom gate's imports
  and roots, the Lean module root of each vendored library); the tool owns HOW.
- The base of the merge is the retired package's `lean/` (its own tests were green), reconciled with the variants now
  in use; the differences are resolved the way section 4 resolves them.
- NOT revived: the gate-diff judge, the protected set, the relabel-attack runner and the lander hooks. The lander
  dropped them on purpose (everything runs before the push, once).
- The Lean gates' tests need a Lean toolchain, so they run in a path-scoped tier (when `lean/` changes) and the
  fast gate of this repository stays as fast as it is.

## 5. The check that keeps it so

The payload carries a list of RETIRED PATHS (the repository-level paths of every file that moved into it). A
repository's fast gate runs `land-check`, which fails when a retired path exists in the repository: a copy can
never come back unseen. `land-check` already fails on an edited vendored tool file.

## 6. Versioning

Adding payload files is additive (a minor release). The retired-path check REFUSES something that was accepted, so
it is introduced as a refusal only for a repository that has taken the release that carries the file it retires:
`land-update` adds the new retired paths to the repository's check in the same commit that moves the file.

## 6a. One verifier

Two verifiers exist today: `land-update` checks a manifest hash, `land-pin vendor` a tree hash; both rest on a signed
tag and the signers file. There is to be one: `land-update` verifies a release with the same code and the same tree
hash as `land-pin vendor` (one file, `lib/verify.sh`: `land-update`, `land-pin` and `land-release` use it, and `install`, which must run without a checkout, embeds it verbatim; `tests/test_verifier_one.sh` fails when the copy differs or a second verifier appears). Releases keep recording
`manifest_sha256=` beside `tree_sha256=` until every consumer has taken the release that verifies by the tree hash;
then the manifest line is retired in a major release.

## 7. Build order

1. This contract lands. 2. `land-update` verifies by the tree hash through the shared code (6a). 3. The runtime files
(merged), with their tests, join the payload; `land-check` gains the retired-path list; a release. 4. Each repository, ONCE, takes the release and, in the same change, deletes its
pin script and lock and its copies of the runtime, vendors what it depends on, and runs `land-pin verify` in its
fast gate. 5. The remaining groups of section 3, the Lean gates included, are inventoried, merged and moved the same way.
