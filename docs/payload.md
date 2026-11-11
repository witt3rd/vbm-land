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

## 2. Why (the inventory of 2026-11-11, ten repositories)

The same files appear in several repositories as hand-edited copies. Of the files present in three or more
repositories: `lib-ran.sh` (7 copies, 5 variants), `ran-evidence.sh` (7 copies, 7 variants), `run-scoped.sh` (6, 4),
`run-tests-parallel.sh` (6, 6), `git-hermetic.sh` (5, 5), `check-zero-warning.sh` (6, 4), `AxiomGate.lean` (6, 6),
`pinned-lib.py` and its lock (3, 3 each). The differences found in the first four are drift, not need: a documentation
path, an old directory layout, a word in a comment, a few lines of local commentary. One canonical version serves all.

## 3. The decisions

| group | files | owner | state |
|---|---|---|---|
| the test-running runtime | `lib-ran.sh`, `ran-evidence.sh`, `run-tests-parallel.sh`, `run-scoped.sh`, `lib-reap.sh`, `lib-no-crash-record.sh`, and the tests of these | the vbm-land PAYLOAD (`lib/`, `bin/`) | build next |
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

## 4a. The Lean gates: in the payload, not a separate package

A separate package for them existed (`vbm-gates`, retired 2026-11-09). It was never adopted: every repository kept its
own copies (six variants of the axiom gate remain), and the lander it plugged into later dropped the judge, the
approvals and the protected lists it served. Shared machinery that each repository must opt into separately does not
get adopted; machinery that arrives with the tool every repository already vendors cannot be skipped. So:
- The Lean gates live in this repository under `lean/`, are listed in the payload, and are vendored only by a
  repository that opts in (a `LAND_PROFILES` entry in its `land.conf`); a repository in another language never gets
  them, so the tool stays language-neutral.
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
hash as `land-pin vendor` (`lib/source.sh` and `lib/treehash.sh` become one path). Releases keep recording
`manifest_sha256=` beside `tree_sha256=` until every consumer has taken the release that verifies by the tree hash;
then the manifest line is retired in a major release.

## 7. Build order

1. This contract lands. 2. `land-update` verifies by the tree hash through the shared code (6a). 3. The runtime files
(merged), with their tests, join the payload; `land-check` gains the retired-path list; a release. 4. Each repository, ONCE, takes the release and, in the same change, deletes its
pin script and lock and its copies of the runtime, vendors what it depends on, and runs `land-pin verify` in its
fast gate. 5. The remaining groups of section 3, the Lean gates included, are inventoried, merged and moved the same way.
