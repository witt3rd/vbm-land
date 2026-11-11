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
| the Lean gates | `AxiomGate.lean`, `LedgerGate.lean`, `ClosureGate.lean`, `trust_ledger.py`, `trust-ledger-check.sh` | a LIBRARY of the family (its own contract: it is Lean, vbm-land is not) | to specify |
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

## 5. The check that keeps it so

The payload carries a list of RETIRED PATHS (the repository-level paths of every file that moved into it). A
repository's fast gate runs `land-check`, which fails when a retired path exists in the repository: a copy can
never come back unseen. `land-check` already fails on an edited vendored tool file.

## 6. Versioning

Adding payload files is additive (a minor release). The retired-path check REFUSES something that was accepted, so
it is introduced as a refusal only for a repository that has taken the release that carries the file it retires:
`land-update` adds the new retired paths to the repository's check in the same commit that moves the file.

## 7. Build order

1. This contract lands. 2. The runtime files (merged), with their tests, join the payload; `land-check` gains the
retired-path list; a release. 3. Each repository, ONCE, takes the release and, in the same change, deletes its
pin script and lock and its copies of the runtime, vendors what it depends on, and runs `land-pin verify` in its
fast gate. 4. The remaining groups of section 3 are inventoried and specified, then moved the same way.
