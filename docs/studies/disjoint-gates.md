# Study: gates that find modules by directory, and ledgers kept in fragments

Status: a STUDY (no code changes; nothing here is built). Written 2026-11-19 against vbm-land 0.21.0. Principle: the hub guideline `factor-for-disjointness` and README section 2b: **no file every change must edit; register by ADDING a file that is found by name or generated at build; validation follows the factoring.**

## 0. The problem, measured

On 2026-11-19 every family library built overnight by parallel agents shared four files that EVERY slice edited:

| file | why every slice edits it |
|---|---|
| `VbmX.lean` | the root module: one `import` line per module |
| `VbmXProofs.lean` | the proof library's root: one `import` line per proof module |
| `VbmXProofs/Ledger.lean` | one `def ledger : List Obligation` that every slice appends to |
| `docs/proof-ledger.md` | rendered by `land-lean ledger` and committed |

Six slices were blocked with `conflictUnresolved` (the scheduler's result for a rebase it could not resolve); the work had to be serialised. Git cannot merge two additions into the same gap of a file. Checked here on a scratch repository: two branches that each insert a line in DIFFERENT gaps of one file merge cleanly; two that insert in the SAME gap conflict. A list that every slice appends to is the same gap by construction.

The cause is partly in this tool, partly in the libraries it is configured for:

* (a) the axiom audit and the proof recheck take their modules from `.land/lean.conf` (`LAND_LEAN_AXIOM_IMPORTS`, `LAND_LEAN_AXIOM_ROOTS`, `LAND_LEAN_RECHECK_MODULES`), and the audit program imports exactly those modules. A short, stable list can only cover a growing library through ONE module that imports everything. That module is the first two files above.
* (b) `LAND_LEAN_LEDGER_MODULE` names ONE module holding ONE list: the third file.
* (c) the gate writes `docs/proof-ledger.md` on every green run (`lean/LedgerGate.lean:128`) and the repositories commit it: the fourth file. A committed generated file is a conflict by construction (README 2b).

A fifth file is hidden in the same shape: the ratchet baseline `LAND_LEAN_LEDGER_BASELINE` is three lines (`proved N`, `open N`, `total N`) that any slice that adds a claim and runs `--write` rewrites (`LedgerGate.lean:136-138`). It is part of this study (section 3.3).

What this study does NOT claim: that the tool alone removes the conflicts. The libraries' own lakefile and downstream importers of the root module are part of the cause too (sections 2.5 and 6).

What was checked in this sandbox (Lake 5.0.0, Lean 4.35.0, toy projects, removed afterwards), marked "checked" below: `lake build +A.B +C.D` builds modules by name and names the failing one; a module outside every `lean_lib` glob is reported as `unknown module`; `leanchecker --fresh` on a generated module that only imports the others replays the whole closure and rejects a planted false theorem. What was NOT checked is marked **[verify]**.

## 1. Inventory: every place the tool needs a list of modules or one aggregate

Line numbers are those of 0.21.0.

### 1.1 Module lists (the root-module cause)

| # | where | what it holds | feeds |
|---|---|---|---|
| 1 | `lib/conf.sh:17` `lean_conf_keys`; `:19-25` `lean_conf_defaults` | the key names and defaults of `.land/lean.conf`. ONE long line lists every key: adding a key edits the same line as any other key (this repository has the problem it studies) | every gate |
| 2 | `lib/conf.sh:80-82` `lean_conf_validate` | module-name keys are `^[A-Za-z0-9_.]+( ...)*$`, path keys are one path, pattern keys are patterns | `land-lean`, `land-check` (`bin/land-check:53`: a typo in `lean.conf` is drift) |
| 3 | `bin/land-lean:21-23` | `LAND_LEAN_AXIOM_IMPORTS` and `LAND_LEAN_AXIOM_ROOTS`, both required (exit 2 if empty), passed as `--imports A,B --roots X,Y` | `lean/AxiomGate.lean` |
| 4 | `lean/AxiomGate.lean:118-123` | the `--imports` list becomes the argument of `importModules`: the audited environment is exactly the closure of the listed modules | the audit |
| 5 | `lean/AxiomGate.lean:107,124-128,144` | the ROOTS are matched by `moduleName.getRoot`, the FIRST component. A root is already a prefix rule: `VbmXProofs` covers every `VbmXProofs.*` module. Only a module that is not in the closure of the imports escapes the audit, silently. A root that matches no constant at all is an error (`:128`) | the audit |
| 6 | `bin/land-lean:25-34` | `LAND_LEAN_RECHECK_MODULES`: one `leanchecker --fresh MODULE` per listed module, side by side (`:30-33`), each replaying that module's whole import closure | the recheck |
| 7 | `lean/recheck-selftest.sh` | its own two fixture modules | not an aggregate; nothing to change |
| 8 | `bin/land-lean:36-38`, `lean/LedgerGate.lean:49,54` | `LAND_LEAN_LEDGER_MODULE` (one module), `LAND_LEAN_LEDGER_IMPORTS` (the code the claims are about, a list), `LAND_LEAN_LEDGER_SUBJECT` (module roots that count as that code). The gate imports `[ledger module] ++ imports` | the ledger gate |
| 9 | `lean/lakefile.toml:8` | `roots = ["LandLedger", "LandWalk"]`: the tool's own package; a new tool module edits this line | the tool |
| 10 | `bin/land-manifest:9` | the payload is one `payload=(...)` line: a new payload file edits the same line | this repository's release |
| 11 | consumer side, `LAND_LEAN_TRUST_KEYS_CMD` (`lean/trust-keys.sh:28`) | a command that prints the closure modules the trust ledger must cover **[verify: which repositories use it that way]** | the trust ledger |

Already by discovery (the precedent to follow): `LAND_LEAN_TRUST_FILES` and `LAND_LEAN_TRUST_EXTERN_DIRS` are path patterns and directories; `lean/trust-keys.sh:5` lists files with `git ls-files --cached --others --exclude-standard` and `:12-13` greps the configured directories. The tool already derives requirements from the tree for the trust gate.

### 1.2 Single aggregates (the ledger cause)

| # | where | what it holds |
|---|---|---|
| 12 | `lean/LedgerGate.lean:55` | `env.evalConst (List Obligation) {} constName`: ONE constant of ONE module is the whole ledger |
| 13 | `lean/LandLedger.lean:8-10` | the convention: "a repository's `Ledger.lean` ... holds only its data, `def ledger : List Obligation`" |
| 14 | `lean/LedgerGate.lean:90-116` | every claim of the list is checked and rendered in one loop; no uniqueness check on the slug exists at all (two claims with one slug render as two rows) |
| 15 | `lean/LedgerGate.lean:40-44,133-140` and `:136-138` | the ratchet: aggregate counts `proved/open/total`, one file, rewritten whole by `--write` |
| 16 | `lean/LedgerGate.lean:128` | `docs/proof-ledger.md` written on every green run, at a literal path |
| 17 | `lean/LedgerGate.lean:60,68,77` (`LAND_LEAN_LEDGER_ENTRIES`, `_BRIDGES`, `_CLAUSES`) | three more single files (entry points, `spec-def theorem reached-def` lines, the clause index). A slice edits them only when it adds an entry point, a bridge or a clause: fewer slices than the four above, but the same shape **[verify: how often]** |
| 18 | `docs/trust-ledger.md` (`lean/trust_ledger.py:19`) | one document of entries numbered `### T<n>`: two slices that each add a trusted item both write the next number |

Rows 3-6 and 8 are fixed by section 2; 12-16 by section 3; 9-10 and 1-2 are this repository's own overlap, handled in the slice plan (section 7); 17-18 are named in section 6 as not covered.

## 2. Design for discovery

### 2.1 The keys

Two new keys in `.land/lean.conf` (same grammar, same parser; unknown keys stay errors; `land-check` validates them through the same `lean_conf_validate`):

```
LAND_LEAN_MODULES_DIRS="VbmX VbmXProofs"     # directories (relative to the repository root); each is a module prefix
LAND_LEAN_MODULES_EXCLUDE="VbmX/Scratch/*"   # optional path patterns that are not modules of the library
```

Rule: for each directory `D`, every tracked or untracked-not-ignored `*.lean` file under `D/` is the module `D.<path without .lean, `/` replaced by `.`>`, and `D.lean` itself, if it exists, is the module `D` (the root is just a module, section 2.6). The file list comes from `git ls-files --cached --others --exclude-standard` (the precedent in `lean/trust-keys.sh:5`), not from `find`: ignored build output, `.lake/`, `vendor/` and a generated-and-ignored file are never seen, and the answer is what the commit would contain. The key holds directories relative to the repository root; a library whose `lean_lib` has a `srcDir` needs a third key or a rule **[verify: does any family library use `srcDir`]**.

New subcommand `land-lean modules`: prints the module list, one per line, sorted, and nothing else. It is the one place discovery lives (`lib/lean-modules.sh`); every gate calls it, and a human can read what a gate will audit.

### 2.2 Determinism

`LC_ALL=C` is already exported by `bin/land-lean:11`. The list is sorted bytewise by module name, de-duplicated, and passed to Lean through a FILE (`--imports-file PATH`, one module per line) instead of a comma list: a library of a thousand modules is 40 KB, over any sane argument. Same tree, same list, same order, on any host. The list is printed (counted) at the head of each gate's output so a log shows what was audited.

### 2.3 Errors are typed, never skips

| situation | behaviour |
|---|---|
| a configured directory does not exist | exit 2 (a refused configuration: a typo must not turn the gate off) |
| the directories hold no module | exit 1 (a gate that audited nothing proves nothing: the same rule as `AxiomGate.lean:128`) |
| a file name that is not a module name (`foo-bar.lean`) | exit 1, names the file: it could be imported only with guillemets, and silently dropping it would leave it unaudited |
| a module that does not build | exit 1, names the module (below) |
| a module no `lean_lib` of the lakefile covers | exit 1, names the module and says to add the glob (checked: Lake says ``unknown module `X.Y` ``) |
| a symlink | not followed; named in a warning line |

**Build step.** When discovery is on, `land-lean axiom` and `recheck` first run `lake build +M1 +M2 ...` over the discovered modules (checked: this builds exactly those modules, a cached no-op when current, and on failure Lake prints `Some required targets logged failures:` and `- MODULE` per failing module, which the tool re-prints as `land-lean: MODULE does not compile`). Reason: today the gates read whatever `.olean` is on disk. With a configured list that is the repository's own build line's job; with a discovered list the tool is the only one that knows which modules exist, and a module that fails to build must be REPORTED, not left out, and must never be replaced by a stale `.olean` from an earlier green build **[verify: whether Lake keeps the old `.olean` when a rebuild fails; if it does, the build step is what protects against replaying it]**. `--no-build` skips the step for a repository that builds itself and then relies on the preflight below.

**Preflight.** After the build step, before any audit or replay, the tool checks that every discovered module has an `.olean` on the Lake search path and prints each missing one (`land-lean: MODULE has no .olean`). Exit 1. A list with one hole is not audited at all.

### 2.4 The axiom audit

`land-lean axiom` with `LAND_LEAN_MODULES_DIRS` set: imports = the discovered modules (plus anything in `LAND_LEAN_AXIOM_IMPORTS`, section 2.6); roots = `LAND_LEAN_AXIOM_ROOTS` if set, else the distinct first components of the discovered modules (here `VbmX`, `VbmXProofs`). `lean/AxiomGate.lean` changes in one place: `--imports-file` read beside `--imports` (`:120`). Roots are already a prefix rule (`:127`), so the audit logic and its differential self-test do not change.

Effect: a module that no root file imports is audited. Today it is not (row 5): the root is a coverage list kept by hand, and forgetting a line leaves a module out without a message. This is a finding about the status quo, not only a convenience: the first run after migration may count MORE constants than before, and that is the point (section 5, step 2).

### 2.5 The recheck

`leanchecker --fresh` takes one module per run and replays that module's whole closure (`bin/land-lean:29`). One run per discovered module would replay the shared closure a thousand times (the largest consumer: 22,000 constants, about 2 minutes per closure). So the tool generates ONE aggregate module at gate time, in a temporary directory, never in the repository:

1. write `$tmp/LandRecheckAll.lean`: `import M` for each discovered module, in sorted order;
2. `lake env lean -o $tmp/LandRecheckAll.olean $tmp/LandRecheckAll.lean`;
3. `LEAN_PATH=$tmp:$LEAN_PATH lake env leanchecker --fresh LandRecheckAll`.

(Checked: this replays every module of the list and the closure, and the run rejects a planted false theorem that was added with the kernel check skipped; the generated module compiles in well under a second. `lean/recheck-selftest.sh` already uses the same `LEAN_PATH` technique.) The generated root is exactly what the one consumer's temporary script generates, moved into the tool, where it needs no `.gitignore` line and cannot be committed. The tool needs no root file; the repository's own `VbmX.lean`, if it has one, is one more discovered module.

Output: `recheck: N modules (and what they import) in one fresh process`, then one verdict. What is lost: with one run, a rejection names the DECLARATION (checked: `while replaying declaration 'lie'`) but not the module. The tool maps the declaration to its module with the same `getModuleIdxFor?` lookup `LandWalk.lean:43` uses, in a second small Lean call on failure only **[verify: leanchecker's exit and message when several declarations are rejected]**. `--selftest` is unchanged.

**The lakefile.** The library's own `lean_lib` must also cover the modules, or Lake never builds a module that nothing imports: `lean_lib VbmX where globs := #[.submodules `VbmX]` (a one-time edit of a file slices do not touch). Checked: a module outside every glob is reported by name (table above), so a repository that forgot is told, not skipped.

### 2.6 Compatibility: the root is just a module

* Neither new key set: behaviour is byte for byte today's. Nothing changes for a repository that does not opt in.
* Both set: the lists are UNIONED (discovered modules, then the configured ones). A repository can adopt discovery before it deletes anything.
* A library that keeps a root (because downstream code writes `import VbmX`): the root is discovered like any module, imports whatever it imports, and nothing requires it to be complete. Hand-maintained or generated at build, it is a PUBLISHING concern of the library, no longer a gate input. A library whose root must exist for downstream users and must not be a conflict point generates it from the lakefile or a script and ignores it in git. The tool does not generate roots for publication **[verify: whether any family library is imported through its root by another repository]**.
* `LAND_LEAN_AXIOM_IMPORTS`, `LAND_LEAN_AXIOM_ROOTS`, `LAND_LEAN_RECHECK_MODULES` stay valid keys and keep working; the docs call them "explicit additions". A major release may retire them later (not proposed here).
* `LAND_LEAN_LEDGER_IMPORTS` and `_SUBJECT`: the roots in SUBJECT are already a per-library constant. With discovery on, the modules the reach walk needs (those whose first component is in SUBJECT) are taken from the discovered list; the key stays for anything else.

## 3. Design for ledger fragments

### 3.1 The layout

One file per module of claims, found by name:

```
VbmXProofs/Ledger/Parse.lean        -- module VbmXProofs.Ledger.Parse
VbmXProofs/Ledger/Escape.lean
```

```lean
import LandLedger
import VbmXProofs.Parse            -- only what its claims cite
open Land.Ledger
namespace VbmXProofs.Ledger.Parse
def ledger : List Obligation := [
  O "parse-roundtrip" (.proved [``VbmXProofs.Parse.roundtrip]),
  OC "parse-limits" ["c:7.1"] (.partly [``VbmXProofs.Parse.limit_ok] "the 2 GiB case")
]
end VbmXProofs.Ledger.Parse
```

New key `LAND_LEAN_LEDGER_DIR="VbmXProofs/Ledger"`. The gate reads the constant `<fragment module>.<LAND_LEAN_LEDGER_CONSTANT>` of every `*.lean` file DIRECTLY in that directory (not below it), sorted bytewise by module name, concatenated. A fragment imports only what it cites, so it can be built and checked alone: validation follows the factoring. The fragments are also ordinary discovered modules (section 2), so they are built, audited and replayed; no second list.

### 3.2 Concatenation and the checks that follow it

* **Order**: by module name (`LC_ALL=C`), then list order inside a fragment. A slice that renames a fragment reorders the rendered document, and nothing else.
* **A fragment without the constant**: exit 1, `ledger: FILE has no constant NAME.ledger` (today a missing constant is the same refusal at `LedgerGate.lean:57`, naming the module).
* **A fragment that forgot its namespace** defines the root constant `ledger`, which would collide with another fragment's at import time (Lean refuses to import two modules that declare the same constant) **[verify: that the import error names the module]**. A source lint before the import, `namespace <its module name>` must occur in the file, turns that into a typed refusal naming the file. It is a text check and says so.
* **Slug uniqueness across fragments** (new; today there is none, row 14): after concatenation, a slug that occurs twice is `ledger: duplicate slug S in A.lean and B.lean` (both files named; the same file twice names it twice and the two positions). Exit 1. Since one claim in two fragments is the usual way two slices step on each other, the error is the right one for them to see in their own landing.
* **Single-module mode** (compatible): the duplicate check also runs, as a WARNING in the release that introduces it and an error from the next minor, because it refuses something that was accepted (docs/payload.md section 6 sets the same rule for retired paths). **[verify: whether any of the 14 repositories has a duplicate today]**
* **Both set** (`LAND_LEAN_LEDGER_MODULE` and `LAND_LEAN_LEDGER_DIR`): the module's list first, then the fragments. A repository can move claims out of the old list one at a time.

The reach, clause and theorem checks (`LedgerGate.lean:61-100`) see one list and are unchanged.

### 3.3 The ratchet baseline

Today: `proved N / open N / total N` in one file; any slice that adds a claim and runs `--write` rewrites it. Three proposals, in the order of how far they go:

1. **One sorted per-slug file**: `slug status` per line (`status` one of `proved`, `partial`, `open`, `limit`; the status AFTER the reach rule, as the counts are today). Two slices adding different slugs merge cleanly IF they land in different gaps of the sorted order; two that land in the same gap conflict (checked on git, section 0). Much better than one counter line that every slice changes, not disjoint.
2. **One baseline file per fragment, next to it**: `VbmXProofs/Ledger/Parse.ratchet`, same line format. A slice edits only the baselines of the fragments it edits, which are the fragments it already owns. Two slices conflict only if they edit the same fragment, which is real overlap. **Recommended.** `LAND_LEAN_LEDGER_BASELINE` names a directory in this mode; the file format is detected (the old three-line aggregate is still read, section 5).
3. **No committed baseline: compare with the base commit's ledger** (the lander exports `LAND_BASE_REF`, `bin/land-direct:161`). No file at all; needs the base built, which doubles the gate's work, and fails outside a landing. Not proposed now.

The rule, per slug (stricter than the aggregate, and written so that the first `--write` accepts today's state): a slug recorded as `proved` must still be `proved`; a slug's rank may not fall (`proved` 3, `partial` 2, `open` and `limit` 1); a recorded slug may not disappear unless it was `open` or `limit` (removing a proved claim would lower `proved`, which the aggregate refuses today). A slug not in the baseline is new and is accepted: "open may rise only by the claims newly written down" holds by construction. `--write` rewrites only the baseline files whose content changed (a slice that did not change a claim writes nothing) and keeps comment lines as today (`LedgerGate.lean:137`).

**A consequence worth stating**: with this rule, no slice NEEDS to edit a baseline: a new claim is accepted without one. The baseline only locks in gains, and it is only as tight as its last `--write`. Run `--write` at release (in `LAND_RC_CMD`) or by a steward, and a slice's own `--write` (recording its gain) touches only its fragment's file. What this does not catch: a proved claim added AFTER the last `--write` and then deleted before the next one (section 6).

### 3.4 The rendered `docs/proof-ledger.md`: choose

Options:

* **A. Not committed.** The gate renders into the run directory (`$LAND_RUN_DIR`, exported by `bin/land-direct:130`, else a temporary directory), prints the path and the counts, and `land-lean ledger --render PATH` writes it where asked (a release step).
* **B. One rendered file per fragment**, `docs/proof-ledger/Parse.md`. Each slice edits only its own file.
* **C. Keep one committed file, regenerated by `LAND_GEN_CMD`.** The lander regenerates it on the rebased tree (`bin/land-direct:304`).

**Choose A.** B has no shared file, but the header the document needs (`N proved, M partial ... of T`, the reach totals, the clause coverage) is an aggregate, so an index file reappears, or the totals live nowhere; B also doubles the number of files and needs a second check that each rendered file matches its fragment (a new gate, and a way to be stale). C is the status quo with a softer failure: `LAND_REGEN_CMD` resolves a conflict confined to generated files, but every landing still changes the file, so base moves for everyone and Tier 1 runs again (`docs/scorecard.md` records exactly this for `MANIFEST.sha256`). A removes the file from every slice, needs no new check (nothing can be stale that is not stored), and loses only what readers outside the repository use: a browsable document. That is produced when it is wanted: `land-lean ledger --render docs/proof-ledger.md` runs at release, in `LAND_RC_CMD`, whose output is committed by the single release commit, a serial act. The document is then touched by one writer at a time, not by every change.

Compatibility: single-module mode keeps writing `docs/proof-ledger.md` on every run, as today; the new key `LAND_LEAN_LEDGER_DOC` (default that path in module mode, empty in fragment mode) names the target, and empty means "run directory only". Consumers that cite the document elsewhere: see step 5 of the migration.

### 3.5 The gate's own shape

`lean/LedgerGate.lean` is one 158-line `run` function that loads, checks, renders, ratchets and self-tests. Every change in section 3 would edit it. The first slice of the ledger part therefore splits it into modules by responsibility (load, check, render, ratchet), without a behaviour change, so the following slices touch different files (section 7).

## 4. What each design decides, in one table

| old | new, when opted in | stays |
|---|---|---|
| `VbmX.lean`, `VbmXProofs.lean` list every module | `land-lean modules` walks the directories | roots are a module like any other |
| `RECHECK_MODULES`: one run per listed module | one generated aggregate module, one run | `--selftest`, `LEANCHECKER`, exit codes |
| `AXIOM_IMPORTS/ROOTS` | derived from the same list (roots from the first components) | both keys still work, unioned |
| `Ledger.lean`: one list | `Ledger/<Mod>.lean`: one fragment per module, concatenated sorted | `LEDGER_MODULE` still read |
| three counters | per-slug status, one file per fragment | the old file is read and replaced on `--write` |
| `docs/proof-ledger.md` committed on every run | rendered to the run directory; `--render` at release | module mode still writes it |

## 5. Migration

### 5.1 Who

The task counts 14 repositories that use the old shape. I could not list them from this repository, which sees only itself. By kind, with what this repository's own documents show; every count and name is **[verify]** against each repository's `.land/lean.conf`, which a one-line loop answers (`grep -l LAND_LEAN_ .land/lean.conf` and the keys it sets):

| kind | what it looks like | known from here | migration |
|---|---|---|---|
| the first consumer | the repository that adopted the Lean gates first and whose conf the documents quote (the pinned-dependency example of `docs/lean-gates.md` is `vbm-json`'s: imports `LeanJson LeanJsonProofs LeanJsonSimd.ParseSimd`) | one **[verify which]**; it vendors another library (`vbm-simd`), so also a ROOT-IMPORT case | steps 1-6 by hand, first, as the pilot |
| libraries built from the factory template | `VbmX.lean`, `VbmXProofs.lean`, `VbmXProofs/Ledger.lean`, committed `docs/proof-ledger.md`: the shape measured on 2026-11-19 | the bulk of the 14 **[verify the count]** | change the TEMPLATE first (slice T1), then steps 1-6 per library, mechanically |
| the one that generates its root at gate time | the root generated by a temporary script and git-ignored | one **[verify which]** | steps 1-6, and delete the temporary script and its ignore line |
| libraries with the axiom gate only (no ledger, no proofs library) | `lean.conf` with IMPORTS and ROOTS | **[verify whether any]** | steps 1-2 only |

### 5.2 Mechanical steps per library (one landing each, in this order)

1. **Take the release** that carries the keys: `land-update --land vX.Y.Z` (minor, additive). Nothing changes for the repository: no key set, the old behaviour byte for byte. Its fast gate (`land-check`) accepts the new keys.
2. **Discovery for the gates.** Set `LAND_LEAN_MODULES_DIRS` (the library and the proof library), keep the old keys. Run `land-lean axiom` and compare `N constants checked` with the number before. Equal: the root was complete. Higher: the root had forgotten modules, which are now audited; read them before landing. The same for `recheck`. Then delete `AXIOM_IMPORTS` (and `AXIOM_ROOTS`, if derived roots are right) and `RECHECK_MODULES`.
3. **The lakefile** gets `globs := #[.submodules `VbmX]` for each library, so Lake builds what nothing imports. Delete the root files that only listed modules (`git rm`); keep, or generate and ignore, a root that downstream code imports (section 2.6).
4. **Split the ledger.** `land-lean ledger --split DIR` (slice S8, one time) reads the single list by value and writes one fragment per proof module of the FIRST theorem each claim cites (claims with none go to `Misc`); the reviewer compares the rendered documents before and after: same rows, only the order differs. Set `LAND_LEAN_LEDGER_DIR`, remove `LAND_LEAN_LEDGER_MODULE`, `git rm` the old `Ledger.lean`. Comments in the old list are lost (the splitter works from values): carry the ones that matter by hand.
5. **Stop committing the rendered ledger.** `git rm docs/proof-ledger.md`; set `LAND_LEAN_LEDGER_DOC=` (empty). Remove it from `LAND_GENERATED_LIST` and from `LAND_GEN_CMD`/`LAND_REGEN_CMD` if listed there. Fix what cites it: a trust-ledger entry whose `Test` or `Enters` names `docs/proof-ledger.md` would fail `land-lean trust` (every cited file must exist, `lean/trust_ledger.py:44`); a README link. Add `land-lean ledger --render docs/proof-ledger.md` to the release command (`LAND_RC_CMD`) if a browsable document is wanted.
6. **The ratchet.** `land-lean ledger --write` with the baseline pointing at the fragment directory writes one `.ratchet` per fragment from the CURRENT ledger (nothing is refused: the first write records today's state). `git rm` the old three-line file. The per-slug rule is stricter than the counters: run it once and read the result before landing.
7. In the pilot only: delete the temporary root-generating script.

### 5.3 What `land-update` does

`land-update` replaces `.land/tool/` and the skills and applies retired paths (`docs/pin.md`, `lib/retired-paths.txt`). It does not edit the repository's own `.land/lean.conf` or its Lean sources, and this change does not make it. So an update ALONE changes nothing; the repository opts in by step 2. Optionally (slice S9) `land-update`, like its 0.8.0 migration, PRINTS a notice for a repository whose `lean.conf` sets `LAND_LEAN_LEDGER_MODULE` or lists modules and none of the new keys: information only, no edit. That is a gate-defining file (`bin/land-update`) and the owner decides.

### 5.4 What stays backward compatible

* Every existing key, with its meaning and defaults; the exit codes (0 ok, 1 gate failed, 2 refused configuration) and the output lines `axiom gate: N constants checked, M offending`, `ledger: P proved, ... of T`, `recheck: ... ok`.
* The three-line baseline format, read as today and replaced only on `--write`.
* A repository that does nothing keeps its four shared files and its conflicts; the tool does not force it.
* Versioning: additive keys and flags are a minor release (0.22.0); making duplicate slugs an error in module mode is the one refusal, scheduled a minor later. A major release is not needed unless the old keys are retired (not proposed).

## 6. Risks, and what each design does not cover

| risk or limit | where | what to do |
|---|---|---|
| A file dropped into a discovered directory is audited at once, including scratch work | discovery | `LAND_LEAN_MODULES_EXCLUDE`; the listing is printed in every run |
| A stale `.olean` replayed in place of a module that no longer builds | recheck, audit | the build step and the preflight (2.3); **[verify]** Lake's behaviour on a failed rebuild |
| One replay process: a rejection names a declaration, the module needs a lookup | recheck | the failure-only lookup of 2.5 **[verify]** |
| Discovery needs the lakefile to cover the modules | all | the tool names the module (checked) but cannot fix the lakefile; the edit is one-time |
| A library is imported through its root by another repository | root deletion | keep or generate the root for them; not a gate concern **[verify]** |
| A fragment with no namespace, or a slug repeated across fragments | ledger | the source lint and the duplicate check (3.2); the lint is a text match |
| Two slices that edit the SAME fragment still conflict | ledger | that is real overlap, and the factoring (small fragments by module) is what keeps it rare; nothing here removes it |
| The ratchet is only as tight as its last `--write`; a proved claim added and deleted between two writes is not seen | ratchet | `--write` at release; the base-commit comparison (3.3, option 3) is the stronger design and is not proposed now |
| Slugs with whitespace cannot be written to the per-slug baseline | ratchet | refuse them in `--write` with a named error **[verify: whether any exists]** |
| The reach entries, bridges and clause index are still one file each (inventory 17) | ledger | the same fragment treatment fits (`<Mod>.bridges` beside the fragment); a later slice, wanted only if the measure (section 8) shows them |
| `docs/trust-ledger.md` numbers its entries `T<n>` (inventory 18) | trust | not covered; the same cure (one file per entry, the number a derived id) is its own study |
| This repository's own shared lines: `lean_conf_keys` (`lib/conf.sh:17`), the `payload=(...)` line, `CHANGELOG.md`, `docs/lean-gates.md`, `MANIFEST.sha256` (generated; `LAND_REGEN_CMD` resolves it) | the slice plan | section 7 factors them first or serialises |
| Test cost: every Lean test of this repository needs a toolchain and is slow (`tests/test_lean_recheck.sh` is the slowest script of Tier 1, `docs/scorecard.md`) | the slice plan | each slice's own test is the fastest that can fail; discovery and module-list logic is tested in pure bash and git, without Lean |
| Not verified here at all | | the 14 repositories and their shapes; the real size of a library's closure under the aggregate replay; how often reach inputs change |

## 7. Slice plan

Each slice is about 150 lines with its own test, lands through `.land/land-direct` (gate-defining paths under `bin/` and `lib/` are judged by the owner). The study applies its own rule: the table says which files each slice writes; slices with no common file run in parallel, and where a file is shared the plan says so and orders it.

The shared lines of THIS repository come first, because every later slice would otherwise write them:

| slice | what | files it writes | test |
|---|---|---|---|
| **P1** | `lib/conf.sh`: one key per line (each key registered and defaulted on its own line, not in one 17-key line); no behaviour change | `lib/conf.sh` | the four `tests/test_lean_*.sh` and `tests/test_retired.sh`, unchanged |
| **P2** | `bin/land-lean` becomes a dispatcher; one file per subcommand (`lean/cmd/axiom.sh`, `recheck.sh`, `ledger.sh`, `trust.sh`); no behaviour change | `bin/land-lean`, new `lean/cmd/*.sh` | the same four tests |
| **P3** | `lean/LedgerGate.lean` split by responsibility (`LedgerLoad`, `LedgerCheck`, `LedgerRender`, `LedgerRatchet` modules, `run` calls them); no behaviour change | `lean/LedgerGate.lean`, new `lean/Ledger*.lean`, `lean/lakefile.toml` | `tests/test_lean_ledger.sh` unchanged |
| **P0** | `bin/land-manifest` takes `lean/*`, `lib/*.sh` and `docs/` payload files by directory instead of by one line (AGENTS.md already says "all of `lib/`" and "every file in `templates/`"); owner decision, gate-defining | `bin/land-manifest` | `land-manifest --check` and a test that a new file in `lib/` is in the manifest |
| **M0** | the measure of section 8: `scripts/overlap.sh` (pure git), run on this repository's history to record the "before" | `scripts/overlap.sh` (new), `tests/test_overlap.sh` (new) | a scratch repository with known overlap |

P0-P3 and M0 share no file except `bin/land-manifest`'s line, which P2 and P3 edit when they add payload files: **land P0 first**, or serialise P2 and P3. With P0 first, P1, P2, P3 and M0 run in parallel.

Then, after P1-P3 (the part that opts in), two lanes that touch different files:

| slice | what | files it writes | depends on | test |
|---|---|---|---|---|
| **D1** | `lib/lean-modules.sh`, `land-lean modules`, keys `LAND_LEAN_MODULES_DIRS` and `_EXCLUDE`, validation, typed errors | `lib/lean-modules.sh` (new), `lib/conf.sh` (the key lines), `lean/cmd/modules.sh` (new) | P1, P2 | `tests/test_lean_modules.sh`: pure bash and git; sorted, excluded, untracked-but-not-ignored, bad name, empty, missing directory |
| **D2** | the axiom audit from the list: `--imports-file`, derived roots, build step, preflight naming each missing module | `lean/AxiomGate.lean`, `lean/cmd/axiom.sh` | D1 | `tests/test_lean_axiom_discover.sh`: a module no root imports with a planted axiom is found; a module that does not build is named |
| **D3** | the recheck from the list: generated aggregate module, one run, failure lookup of the module | `lean/cmd/recheck.sh`, `lean/recheck-aggregate.sh` (new) | D1 | `tests/test_lean_recheck_discover.sh`: a planted false theorem in an unimported module is rejected; a missing `.olean` is named |
| **L1** | `LAND_LEAN_LEDGER_DIR`: load, concatenate sorted, per-fragment constant, namespace lint | `lean/LedgerLoad.lean`, `lean/cmd/ledger.sh`, `lib/conf.sh` (one key line) | P1, P2, P3 | `tests/test_lean_ledger_fragments.sh`: two fragments, one without the constant, one without a namespace |
| **L2** | duplicate slug across fragments, typed, both files named; the module-mode warning | `lean/LedgerCheck.lean` | L1 | the same new test file extended in its own cases, or a second file `test_lean_ledger_dup.sh` (no shared test file) |
| **L3** | per-slug and per-fragment baseline; the old format read; `--write` writes only changed files | `lean/LedgerRatchet.lean` | L1 | `tests/test_lean_ledger_ratchet.sh`: every rule of 3.3 can fail, including a mutant that drops the "rank may not fall" check |
| **L4** | `LAND_LEAN_LEDGER_DOC`, `--render PATH`, default run directory in fragment mode | `lean/LedgerRender.lean`, `lib/conf.sh` (one key line) | L1 | `tests/test_lean_ledger_doc.sh`: nothing is written to `docs/` in fragment mode; `--render` writes it |
| **L5** | `land-lean ledger --split DIR` (one time, step 4) | `lean/LedgerSplit.lean` (new), `lean/cmd/ledger.sh` | L1 | split a toy ledger, re-render both ways, same rows |

Parallelism: **D2 and D3 are parallel** (different files, both after D1). **D-lane and L-lane are parallel** after P1-P3. **L2, L3, L4 are parallel** after L1 (each its own Lean module and its own test). Still shared: `lib/conf.sh` (the key lines of D1, L1, L4: three slices append a line to one block; P1 makes it one key per line, which keeps the hunks apart unless two insert in the same gap, so queue D1, then L1, then L4, or accept one trivial conflict) and `lean/cmd/ledger.sh` (L1 and L5: L5 after L1).

Finally, once, at the end (serial; these are the shared documents, written by ONE slice so that no other slice has to):

| slice | what | files |
|---|---|---|
| **R1** | the user-facing text: keys in `docs/lean-gates.md`, README "The Lean gates", `docs/payload.md` 4a, the CHANGELOG entry (the keys and flags are an interface change: minor release 0.22.0), `VERSION`, the release (`land-release`) | `docs/lean-gates.md`, `README.md`, `docs/payload.md`, `CHANGELOG.md` (inert path), `VERSION` |
| **S9** | optional: the `land-update` notice (5.3) | `bin/land-update` |

Each earlier slice describes itself in its commit message and in a NEW file (`docs/lean-discovery.md` may be created by D1 and extended only by the slices of its lane) instead of editing `lean-gates.md` and `CHANGELOG.md`, which R1 owns. Outside this repository: **T1** the factory template ships the new shape (fragments directory, globs lakefile, discovery keys; after D3 and L4), then one migration slice per library (5.2), each in its own repository and so parallel with every other. The pilot (the first consumer, 5.1) goes first, after R1's release.

## 8. How it would be measured

Before any slice lands, and after each migration, on each library:

* **Aggregate count** = the number of files written by more than half of the last N slice commits of the library (N = 20, merges excluded):

  ```
  git log --no-merges -n 20 --name-only --pretty=format:%x00 \
    | awk 'BEGIN{RS="\0"} NF{n++; delete s; for(i=1;i<=NF;i++) if(!s[$i]++) c[$i]++} END{for(f in c) if(c[f]*2>n) print f}' | sort | wc -l
  ```
  (a sketch **[verify]**: it counts a path once per commit; it is what `scripts/overlap.sh`, slice M0, would do properly.) Measured 2026-11-19 on the libraries built overnight: **4** (the four files of section 0; the ratchet baseline of section 3.3 is a fifth candidate that was not measured **[verify]**). The target after migration is **0**; a nonzero count lists the files that remain (a changelog, a lakefile) and is the work list.
* **Overlap** = over all pairs of the last N commits, the share of pairs that write a common file. It must fall and never rise (README 2b).
* **Conflicts** = the landings of the period whose `result` is `conflict` in `landings.jsonl` (`docs/landings.md`, the lander's exit 11), and the scheduler's `conflictUnresolved` count (six on 2026-11-19).
* **A deterministic test** of the layout: `tests/test_lean_disjoint.sh` builds a scratch repository with N fragment-adding slices, each its own branch, merges them all with git and requires no conflict; the same test on the old shape (each appends to one list) requires a conflict, so the test can fail.
* **Cost**: the seconds of `land-lean axiom` and `recheck` before and after on one library, to confirm that one aggregate replay is not slower than the listed one (expected faster for any library that listed more than one module) **[verify]**.

Not measured here, because the 14 repositories are not visible from this one: the starting aggregate count per library, the number of modules, the closure sizes. The slice M0 records them the first time it runs on each.
