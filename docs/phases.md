# Per-phase inert lists: the contract

Status: **specification** (nothing here is built yet). It is written so that a worker can implement it and a test can check it; section 10 lists what a test checks.

A repository's gate has **phases**: independent units of Tier 1, each reading its own inputs (a Lean build, a web build, a document check). `LAND_INERT` (README 6.3, "Inert paths") knows two cases only: a change is wholly inert (Tier 1 is skipped) or every phase runs. So a change to a document, a skill or a web file runs the Lean build. The family rule is that validation follows the factoring: **a change runs what it can affect, and the release candidate runs everything.** This page extends the inert declaration from "no phase reads this path" to "this phase does not read this path".

## 1. Conf: `LAND_INERT_<PHASE>`

`.land/land.conf` accepts, besides `LAND_INERT`, any key `LAND_INERT_<PHASE>` where `<PHASE>` is one or more upper-case letters, digits and underscores (`LAND_INERT_LEAN`, `LAND_INERT_WEB`, `LAND_INERT_DOCS`, `LAND_INERT_E2E_SLOW`). Any other key (`LAND_INERT_` with nothing after it, a lower-case or other character in the suffix) is an unknown key and refused as every unknown key is (exit 2).

- **The value** has the syntax of `LAND_INERT`: space-separated shell patterns, `*` matches `/`, matched against the path as the repository's top-level lists it. It names the paths that phase does **not** read.
- **The phase name** the gate uses is the suffix in lower case: `LAND_INERT_E2E_SLOW` is the phase `e2e_slow`. The mapping is one to one (names are `[a-z0-9_]+`).
- **`LAND_INERT` keeps its meaning** (paths no phase reads) and is **implied in every phase's list**: the effective list of a phase is `LAND_INERT_<PHASE>` followed by `LAND_INERT`. A path in `LAND_INERT` is never repeated per phase.
- **An empty or absent `LAND_INERT_<PHASE>` is no list**: the phase always runs (section 2).
- There is no negation and no pattern language beyond the shell patterns: a phase that reads `spec/schema/x.json` but not the rest of `spec/` lists the directories it does not read, one pattern each (section 9). A pattern is a declaration about every path it matches, today and later: keep patterns specific.

## 2. The rule

For one landing, with *changed paths* = the paths the rebased combination changes against the base (`git diff --name-status --no-renames`: a rename is a deletion of the old path and an addition of the new one; statuses `A`, `M`, `D`, `T`), a phase **P is skipped if and only if all of these hold**:

1. P has a list (`LAND_INERT_<P>` is set and non-empty);
2. the landing changes at least one path;
3. no changed path is in `LAND_PROTECTED` (a protected path **forces every phase**);
4. **every** changed path has status other than `D` and matches the effective list of P.

Consequences, each of them a decision and not a heuristic:

- **A deleted or renamed-away path is never skippable** for any phase: a check can read that a file exists (a ledger entry that cites it, a link to it) and nothing can tell that from its content. Editing or adding a listed path is exactly what the declaration covers.
- **A phase with no list always runs.** An unknown path, an unknown phase and a misspelled key all fail toward running. **Fail-safe: when in doubt, everything runs.**
- **One path outside the list runs the phase.** There is no "mostly": the first path that is not skippable decides.
- **A change whose every path matches `LAND_INERT`** is wholly inert as today (README 6.3): Tier 1 and the `post-tier1` hook are not run, the summary says `"validation":"inert"`, and no phase is asked, so `skipped_phases` is absent (the whole of Tier 1 was skipped, not phases of it).
- **No phase is ever skipped on the release candidate** (section 3).

The decision is made once per attempt, after the rebase, on the combination that would land, next to the existing inert decision, and is made again on every attempt (the base moved: section 6).

## 3. How the gate asks

The lander decides; the gate (the repository's own Tier 1 command) asks. Three things, and nothing else, cross that boundary.

- **`LAND_TOUCHED`**: a file the lander writes (in its run directory) and whose absolute path it exports to the Tier 1 commands (`LAND_GATES_CMD`, `LAND_TEST_CMD`) and the `post-tier1` hook. One line per changed path, `STATUS<TAB>PATH`, the output of `git diff --name-status --no-renames` against the base, in that command's order. It is for a gate that wants to choose WITHIN a phase; the phase decision never needs it. (`LAND_TOUCHED_FILE`, the existing names-only list the hooks read, is unchanged.)
- **`LAND_PHASES_SKIP`**: exported to the same commands, always, whenever Tier 1 runs: the **space-separated lower-case names of the skipped phases**, sorted (C locale), **empty when none is skipped**. Set-but-empty means "a landing; skip nothing".
- **`bin/land-phase NAME`**, a published tool (payload, executable), the one way a gate reads the above:

| Exit | Meaning | When |
|---|---|---|
| 0 | run the phase | `NAME` is not in `LAND_PHASES_SKIP`; or this is the release candidate; or there is no base (below) |
| 1 | skip the phase | `NAME` is in `LAND_PHASES_SKIP` as a whole word |
| 2 | misuse | no or several arguments, `NAME` not `[a-z0-9_]+` (an upper-case name is misuse, never folded), or `LAND_TOUCHED` set while `LAND_PHASES_SKIP` is unset (the two travel together) |

It reads only its argument and the environment. It reads no conf file, matches no pattern and runs no git: the lander already decided. It prints one line on stderr, `land-phase: NAME: runs` or `land-phase: NAME: skipped`, so a gate's log says what was asked.

**The release candidate always runs every phase, and signals it in this way.** `land-release` runs `LAND_RC_CMD` with `LAND_RC=1` and with **`LAND_PHASES_SKIP` and `LAND_TOUCHED` removed from its environment** (a candidate started from inside a landing never inherits a skip). `land-phase` then finds neither variable: that is "a run with no base", and it prints `land-phase: NAME: runs (no base: every phase runs)` and exits 0. If `LAND_RC=1` is set it **wins over everything**: exit 0, the same line, even if a skip list leaked in. A gate that never calls `land-phase` runs everything, as before.

## 4. Visibility

- **The lander prints, for each phase that has a list, one line**, phases in name order, before Tier 1 starts:
  - `land-direct: phase lean: skipped (every changed path is in LAND_INERT_LEAN or LAND_INERT)`
  - `land-direct: phase web: runs (web/src/a.ts is not in LAND_INERT_WEB or LAND_INERT)`
  - `land-direct: phase docs: runs (docs/old.md is deleted: a deletion is never skippable)`
  - `land-direct: phase lean: runs (.land/land.conf is in LAND_PROTECTED: a protected path runs every phase)`

  The path named is **the first path that was not skippable** for that phase, in the order of `LAND_TOUCHED`; for a protected hit it is the first protected path. A phase without a list is not known to the lander and gets no line (it runs).
- **The summary JSON gains `"skipped_phases":["docs","web"]`** (sorted, lower-case), **only when non-empty**: a landing that skipped no phase, and a wholly inert or reused one, print the line they print today. Additive: the interface section of `CHANGELOG.md` makes it a minor release. The landings record (`docs/landings.md`) is not changed by this item.
- **A skipped phase never lets a gate report zero cases as success.** `docs/ran-evidence.md` makes a script that evaluated nothing fail; a skip must not be able to turn that into a pass, nor a pass into silence. So a gate that asks `land-phase`:
  1. prints, **before its `ran:` line**, one line `phases skipped: NAME NAME` (the phases it did not run, in the order it asked; `phases skipped: none` when it skipped none), in lower case: it must not contain the word `SKIPPED`, which `bin/ran-evidence` rejects, and it is not a `ran:` line;
  2. prints `ran: NAME: N cases` where **N counts only the checks it executed**: a skipped phase adds nothing, never a case.

  If every phase a change reaches was skipped the gate has executed nothing and `ran-evidence` fails it. **That failure is the intended outcome**: it says the change reached no check. The repair is a declaration, never an exemption: put the path in `LAND_INERT` if no phase reads it, or give it a phase that does (section 9: `docs`).
- The summary reports the lander's decision; the `phases skipped:` line reports what the gate did. A list naming a phase the gate never asks has no effect and no check would notice: the repository's own test lints that every `LAND_INERT_<PHASE>` has a `land-phase <phase>` in its gate (the tool does not read the gate).

## 5. Audit

A per-phase list is a **declaration**, audited exactly as `LAND_INERT` is (README 4.8): the lander never reads a file's content to check it, and a wrong entry skips a check that should have judged the change. A project proves each entry by experiment, in a scratch worktree of the current tree, **for each concrete path that matches the entry** (not for the pattern):

1. **Baseline.** Run THAT phase alone, in full: every other phase skipped, no cache, no selection, no shortening (the release candidate's mode for one phase), and require green.
2. **Overwrite.** Replace the path's content with different content (an empty file; then text that is not valid in its format) and run that phase again. **A verdict that differs from the baseline is a wrong entry: remove the pattern or narrow it.**
3. **Delete.** Remove the path and run that phase again. A phase that fails here **reads the path's existence**: that does not make the entry wrong (a deletion is never skippable), but record it, because the same path may be read in other ways.

An entry is established when every path it matches passes 1 and 2 for that phase. A pattern that matches a path that does not exist yet is not established for it: keep the patterns specific.

**A wrong entry is an ESCAPE.** The release candidate runs every phase (section 3), so a break a skipped phase should have caught fails there (README 4.8: count escapes). Each escape names the phase that failed and the path that was changed without it: the repair is to remove that path from that phase's list. A repository that never sees an escape can widen its lists; one that sees many should narrow them.

## 6. Interplay with reuse and with `--group`

- **Reuse (`LAND_REUSE=1`, README 6.3).** The per-phase skip set is a function of the landing's own changed paths, so it is recomputed on every attempt, after the rebase. A reused landing runs no Tier 1 and so no phase: `"validation":"reused"` is printed, `skipped_phases` is not (an earlier attempt's skip set describes that attempt). **Reuse is allowed only when the set of phases this attempt would run is contained in the set that the passing attempt ran**; otherwise the earlier verdict does not cover this combination and Tier 1 runs. A phase a landing skipped is judged on nothing by the change, and the paths that moved under it are not the landing's to validate: the existing reuse test (nothing moved is a path the change touches or affects) is unchanged.
- **Inert and protected first.** The order is: protected paths (all phases run), then the whole-inert test (`LAND_INERT` alone), then reuse, then the per-phase decision for what remains.
- **`--validate` then `--push SHA`.** `--validate` prints the summary with its `skipped_phases`; `--push SHA` pushes that exact verdict and refuses a moved base, so no decision is made again between them.
- **`--group`.** A group landing is one landing: base..rev, the net change of all its commits, and the decision is made once on that net change (a path added by one commit and removed by a later one is not changed and is not listed). A phase is skipped only when **every** path of **every** entry is skippable, so the phases the batch runs are exactly the union of the phases its entries would run alone; the coordinator's by-one checks are unaffected. `--group` waives the size budget and nothing else: no phase and no list is waived by it.

## 7. Worked example

A repository (generic names) with a Lean tree `spec/`, a web application `web/`, documents `docs/`, agent files `.agents/`. Tier 1 has three phases:

- `lean`: builds `spec/`, runs the axiom and ledger gates (`.land/lean.conf`) and the trust gate, which reads `docs/trust-ledger.md`. It reads `spec/`, `.land/lean.conf`, `docs/trust-ledger.md`.
- `web`: builds and tests `web/`. It reads `web/` and `spec/schema/*.json`, the schemas generated from the Lean tree (so also what they are generated from: `spec/Core/`), but none of `spec/Proofs/`.
- `docs`: checks documents only (links, spelling, the front matter of `.agents/skills/*/SKILL.md`); it reads `docs/`, `README.md` and `.agents/`, never code.

```
LAND_PROTECTED="scripts/tier1.sh .land/*"
LAND_INERT="CHANGELOG.md LICENSE"
LAND_INERT_LEAN="web/* .agents/* docs/guide/* README.md"
LAND_INERT_WEB="spec/Proofs/* spec/lakefile.toml spec/lean-toolchain docs/* .agents/* README.md"
LAND_INERT_DOCS="spec/* web/*"
```

Why each entry (a pattern is there because the phase demonstrably does not read it, per section 5; the reason is the one a reviewer can check):

| List | Entry | Reason |
|---|---|---|
| all | `CHANGELOG.md`, `LICENSE` in `LAND_INERT` | no phase reads them |
| `lean` | `web/*`, `.agents/*`, `README.md` | the Lean build has no input outside `spec/`, `.land/lean.conf` and the trust ledger |
| `lean` | `docs/guide/*`, **not** `docs/*` | `docs/trust-ledger.md` is read by the trust gate; the prose guide is not. No negation exists, so the safe directory is named |
| `web` | `spec/Proofs/*` | proofs generate nothing the web reads |
| `web` | **not** `spec/Core/*`, **not** `spec/*` | the schemas the web phase reads are generated from `spec/Core/`: a path a phase's input is generated from is read by that phase |
| `web` | `spec/lakefile.toml`, `spec/lean-toolchain` | build pins of the Lean tree; the web build has its own |
| `web` | `docs/*`, `.agents/*`, `README.md` | no web check reads them |
| `docs` | `spec/*`, `web/*` | the document check reads no code content |
| none | `.land/*`, `scripts/tier1.sh` | protected: every phase runs on a change to the gate itself |

What a landing then runs (a phase not listed is skipped):

| Change | `lean` | `web` | `docs` | Why |
|---|---|---|---|---|
| `CHANGELOG.md` | | | | wholly inert: `"validation":"inert"`, no phase asked |
| `docs/guide/intro.md` | skipped | skipped | runs | `docs/guide/intro.md` is in the lean and web lists, not in the docs list (none matches it) |
| `docs/trust-ledger.md` | runs | skipped | runs | the lean list names only `docs/guide/*` |
| `.agents/skills/x/SKILL.md` | skipped | skipped | runs | docs reads it |
| `spec/Proofs/A.lean` | runs | skipped | skipped | |
| `spec/Core/B.lean` | runs | runs | skipped | web's input is generated from it |
| `web/src/a.ts` | skipped | runs | skipped | |
| `web/src/a.ts` and `docs/guide/intro.md` | skipped | runs | runs | one path outside a list runs the phase |
| delete `docs/guide/old.md` | runs | runs | runs | a deletion is never skippable, so even the phases that list it run |
| `.land/land.conf` | runs | runs | runs | protected |
| `LAND_RC=1` (the release candidate) | runs | runs | runs | no base: `land-phase` always exits 0 |

The summary of the second row carries `"skipped_phases":["lean","web"]`. The gate (`scripts/tier1.sh`, protected):

```sh
skipped=
for p in lean web docs; do
  if .land/tool/bin/land-phase "$p"; then "run_$p"; else skipped="$skipped $p"; fi
done
echo "phases skipped: ${skipped# }"   # prints "none" when empty in the real script
echo "ran: tier1: $n cases"           # n counts executed checks only
```

## 8. Non-goals

- **No content reading.** The lander does not parse a build graph, an import list or a diff to learn what a phase reads; the repository declares it, and section 5 audits it.
- **No guessing.** No inference of phases from directory names, no default lists, no "obviously inert" paths. A phase without a list runs.
- **No numeric thresholds.** No "small change", no line counts, no percentages: a path is on a list or it is not.
- No negation, no globbing beyond the shell patterns, no per-phase protected set, no per-commit decision (the decision is on the net change that would land).
- Phases are not ordered or made to depend on each other by the lander; the gate runs them in its own order. Skipping within a phase (selecting tests) stays the gate's business (`LAND_TOUCHED`) and is also not allowed on the release candidate.

## 9. What a worker implements (and where)

`lib/conf.sh` (accept the key family and parse it; one place), `bin/land-direct` (the decision next to the inert decision; the printed lines; `LAND_TOUCHED`, `LAND_PHASES_SKIP`; the summary key; the reuse containment test), `bin/land-release` (clear the two variables for `LAND_RC_CMD`), `bin/land-phase` (new, executable, in the payload of `bin/land-manifest` with `MANIFEST.sha256` rewritten, not edited), `README.md` 6.3 and the key table, and this page in the payload docs. Gate-defining files: judged by the owner.

## 10. What a test checks

Each case builds a repository with lists and landings, and asserts the decision, the printed line and the exit code:

1. **Key grammar**: `LAND_INERT_LEAN`, `LAND_INERT_E2E_SLOW` accepted; `LAND_INERT_`, `LAND_INERT_lean` refused (exit 2).
2. **Skip**: every changed path (added or modified) matches the phase's list: `land-phase` exits 1 and `LAND_PHASES_SKIP` holds the name.
3. **Run on one outsider**: one path outside the list: exit 0; the lander prints that path, and it is the first such path.
4. **`LAND_INERT` implied**: a path only in `LAND_INERT` counts as matching for every phase that has a list; a change wholly in `LAND_INERT` is `"validation":"inert"` and has no `skipped_phases`.
5. **Deletion and rename**: a deleted path that matches runs the phase; a path renamed into a listed path from an unlisted one runs it; the printed reason says deleted.
6. **Protected**: a protected path runs every phase, including those whose list matches it.
7. **Fail-safe**: a phase with no list, an empty list or a misspelled key runs; a landing with no changed path skips nothing.
8. **Summary**: `"skipped_phases":["docs","web"]` sorted, present only when non-empty; an ordinary landing's line is byte-identical to today's.
9. **`land-phase` exits**: 0, 1, and 2 for no argument, two arguments, an upper-case name, `LAND_TOUCHED` set without `LAND_PHASES_SKIP`; no `LAND_PHASES_SKIP` and no `LAND_TOUCHED`: prints the "no base" line and exits 0; `LAND_RC=1` with a leaked skip list: exit 0.
10. **Release candidate**: `land-release --rc` runs `LAND_RC_CMD` with neither variable in its environment, even when started from inside a landing.
11. **Accounting**: a gate that skips a phase prints `phases skipped: ...` before its `ran:` line, the line passes `bin/ran-evidence`, and a gate whose every phase was skipped, with no other check, fails it.
12. **Reuse**: a landing whose skip set shrank (it would now run a phase the passing attempt skipped) is not reused; one whose run set is contained in the earlier one is; a reused landing has no `skipped_phases`.
13. **`--group`**: the decision is on the union: one entry reaching a phase runs it for the batch; a path added and removed within the batch is not listed.
14. **Gate lint** (the repository's own): every `LAND_INERT_<PHASE>` has a `land-phase <phase>` in the gate.
