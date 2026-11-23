# Areas: validate exactly what a change can affect

Status: the contract. Documentation and data only: `vectors/areas/areas.json` is its conformance suite and the implementation (the next item) must pass every case. This page replaces the per-phase inert lists that were specified earlier the same day (they were never built or released); `LAND_INERT` keeps its meaning as the **area with no steps** (rule 6).

## 0. The problem, in one paragraph

Hundreds or thousands of agents change one repository at once, in any language, and land directly on one trunk. Today a change either skips Tier 1 (`LAND_INERT`) or runs the whole of it, and every landing moves the trunk, so every landing still in flight must rebase and run the whole gate again. The cost of that grows with the number of agents (section 3). The cure is a **factoring the project declares**: named **areas**, each owning paths and carrying the commands that test them. A change then validates exactly the areas it touches, a landing is disturbed only by landings that touch one of its areas, and the release candidate still runs everything.

The model is adopted from a sibling tool that has run it in production. Its rules are kept as they are: they are the result of experience, and each one is there because a smarter rule was tried and failed.

## 1. The areas file

`.land/areas.json`, JSON, read from `origin/<base>` exactly like `land.conf` (a commit cannot loosen the rules it is judged by). When the base has no such file yet, the working tree's copy is **validated** (a malformed one refuses) and is **not applied**: that landing is judged by the base's own rules (section 7, theorem). **The presence of the file turns areas on** (as `.land/lean.conf` turns the Lean gates on); no `land.conf` key is added. Everything under `.land/` is in the protected set (section 2, rule 5), so this file is.

```json
{
  "version": 1,
  "areas": [
    {
      "name": "lib",
      "paths": ["src/lib/*", "tests/lib/*"],
      "exclude": ["src/lib/generated/*"],
      "steps": [
        {"run": "make fmt-check"},
        {"run": "make test-lib"},
        {"run": "npm test", "cwd": "src/lib/web"}
      ]
    }
  ]
}
```

| key | meaning |
|---|---|
| `version` | exactly `1` |
| `areas` | a non-empty list; **the order is significant**: it is the order steps run in |
| `name` | `[a-z0-9][a-z0-9_-]*`, unique. `inert` is reserved (rule 6) |
| `paths` | a non-empty list of globs the area **owns** |
| `exclude` | optional list of globs: a path that matches one is not the area's, however many `paths` it matches |
| `steps` | **required**; the commands that run this area's tests, lint, type check, format check. `[]` is an area with no steps (rule 6) |
| step `run` | a command line, run with `bash -c`; non-zero is failure |
| step `cwd` | optional literal directory, relative to the repository's top level; default `.` |

**The glob language** is the one `LAND_INERT` and `LAND_PROTECTED` already use, and nothing else: `*` matches any run of characters **including `/`**, `?` matches one character, everything else is literal. Case-sensitive. Matched against the whole path as git lists it (relative to the top level, no leading `./`). There are no brackets, braces, `**` (it is two stars, the same as one), negation or escapes: a pattern that contains `[`, `]`, `\`, `{` or `}` is refused, so that every implementation, in any language, agrees. A pattern is also refused when it is empty, starts with `/` or `./`, ends with `/`, contains `//`, or has a `..` segment. A `cwd` must be a literal directory (no `*`, `?`, and the same shape rules).

**The file is DATA and strict.** An unknown key, a missing `steps`, a duplicate name, a bad glob or `cwd`, a `version` other than `1`, an empty `paths`, or a step with no `run`: the file is refused (exit 2) by name and area, never half read. `land-check` refuses it too (offline), so a malformed file cannot land. The vectors `invalid-*` fix this.

## 2. The rules (normative)

Numbers 1 to 7 are the model; the vectors cite them.

1. **Declare.** A repository declares named areas in the file above: `name`, `paths`, optional `exclude`, `steps`.
2. **Touch.** A change **touches** an area when a changed path matches one of the area's `paths` and none of its `exclude`. The changed paths are those of the net change being validated (the rebased tree against the base): added, modified, deleted, and renamed, where **a rename is a deletion of the old path plus an addition of the new one** (both ends are matched). A deleted path matches like any other.
3. **Run everything of what is touched.** A change runs **every step of every area it touches**: nothing narrower. There is **no selection** by import graph, by what a test read, by coverage, by test name or by size cap, and **no flag that skips a step**. Predictability is the point: the same paths always run the same steps. Steps run in the order of the areas in the file, then of their steps; a step that two touched areas both declare (same `cwd` and same `run`) runs once. A failing step stops the landing (exit 13) and names its area and step.
4. **There are no dependency edges between areas.** Shared code is listed in the `paths` of **every area that depends on it**, and a path that matches two areas touches **both**. **Overlap is the declared dependency**: it is how coupling is paid for, and the project minimizes it by factoring (section 4 measures it).
5. **What no area owns.** A path that no area owns (no `paths` glob matches it, or an `exclude` removes it) runs **everything of the closest enclosing area**. The *directory a glob starts in* is the glob's segments before the first segment that contains `*` or `?`, the last segment (the file part) never counting: `src/lib/*` starts in `src/lib`, `core/*.py` in `core`, `docs/*/index.md` in `docs`, `README.md` and `*.md` in the root. A glob that starts in the root **encloses nothing**. An area *encloses* a path when the path is not excluded by the area and lies under (a path prefix, by whole segments: `core/io` does not enclose `core/iodata.json`) the directory of some glob of the area. The **closest** is the area with the longest such directory; **areas that tie all run**. A path **no area encloses is UNMAPPED and runs the FULL suite** (every area, every step), and the lander names it: never a silent skip.
   **Gate-defining paths** also run the full suite: everything under `.land/` (the areas file, `land.conf`, hooks, the vendored tool) and every path in `LAND_PROTECTED`. They are never "unmapped" (they are named *gate-defining*), and an area that owns one does not narrow the run: the files that judge changes are judged by everything. **A repository may declare otherwise:** the areas file may carry a top-level `"gate_areas": ["NAME", ...]` (a non-empty list of distinct area names that exist). A gate-defining change then runs THOSE areas (added to the areas it touches) instead of everything, and still says which path made it gate-defining. Use it when the full suite is too expensive to run for every change to the judge (a family repository of many libraries): the trade is that an area outside the list is not re-judged until a change touches it or the release candidate runs it, and rule 7 is unchanged: the release candidate runs EVERY area, `gate_areas` or not. A path no area owns or encloses still runs the full suite. Without the key nothing changes.
6. **Inert is an area with no steps.** An area whose `steps` is `[]` is a documented area whose changes run nothing. A landing whose touched areas have no steps runs nothing, says `"validation":"inert"` and lists those areas (section 5): never a bare green. `LAND_INERT` keeps working (expand and contract): its patterns are the reserved pseudo-area `inert`, which owns them, has no steps, and **does not own a deleted path** (a check can read that a file exists, and nothing can tell that from its content; this is the rule `LAND_INERT` already has). With **no areas file**, the repository has one implicit area `all` that owns every path and whose steps are `LAND_GATES_CMD` then `LAND_TEST_CMD`; the inert patterns carve non-deleted paths out of `all`, so a change whose every path is inert touches only `inert`, as today. **With an areas file**, an inert pattern carves nothing out: a path that matches `inert` and an area touches both, and `land-check` reports the overlap. `LAND_INERT` is the older spelling and is retired in the next major release; a stepless area is the way to say it now.
7. **The release candidate runs EVERY area.** `land-release` runs every step of every area (with `LAND_RC=1`: nothing cached, selected or skipped), then `LAND_RC_CMD` if the repository sets one (the extra checks areas do not carry: a soak, a long suite), and makes no tag unless all pass. A candidate is the audit of the factoring (section 3.3).

**The decision**, as a function (the reference the vectors were produced with, `tests` of the next item must agree with it case by case):

```
decide(areas, inert, protected, changes, release_candidate):
  changes := split every rename into (D old, A new)
  full := release_candidate
  for (status, p) in changes:
    if p under .land/ or p matches a protected glob:  mark p gate-defining;  if the file declares gate_areas: touched += gate_areas  else: full := true
    owners := every area that owns p
           + [inert]  if p matches an inert glob and status != D
    if owners non-empty:  touched += owners;  continue
    if p is gate-defining: continue
    enc := the areas that enclose p, with the longest directory (all that tie)
    if enc non-empty:  touched += enc
    else:  unmapped += p;  full := true
  run     := every area (and inert, if declared)   if full   else touched
  steps   := the steps of the areas in `run`, in file order, a repeated (cwd, run) once
  skipped := every area not in run
```

The vectors are the specification where this text is short.

## 3. Concurrency

**The judge is the base.** A landing is judged by the areas file and the steps **on `origin/<base>`**, never by the ones its own commits carry: a commit that changes the areas file, or deletes what a step runs, is decided and run by the base's file, so a commit cannot loosen the rules it is judged by. The consequence for a change that moves the factoring is an order of landings (section 7, "The migration order"); a landing that deletes a script the base's steps run fails its own gate (exit 13, and the message says the steps are the base's).

### 3.1 Why whole-gate validation does not scale

A model, simple enough to hold in the head and honest about being a mean-field one. `N` agents each loop: validate (time `T`: the whole gate, on the exact combination), then try to push. The push is a fast-forward, so it succeeds only if the trunk did not move since the attempt's base. Let landings arrive at rate `L` (all agents together).

- **The chance the trunk moves during one validation** is `p = 1 - e^(-L·T)`. An attempt succeeds with probability `e^(-L·T)`; a landing therefore costs `e^(L·T)` attempts, **`e^(L·T) - 1` re-validations**, each a full `T`.
- `L` is not a given: it is produced by the agents. Each of the `N` agents makes an attempt every `T`, so `L = (N/T)·e^(-L·T)`. With `s = L·T` (landings per validation time): `s·e^s = N`, so `s = W(N)` (Lambert W), about `ln N`.

| agents `N` | landings per `T` (`s`) | an attempt succeeds | attempts per landing | a lander still not landed after 30 attempts |
|---|---|---|---|---|
| 2 | 0.85 | 43% | 2.3 | under 0.1% |
| 10 | 1.75 | 17% | 5.7 | 0.3% |
| 20 | 2.2 | 11% | 9.1 | 3% |
| 50 | 2.9 | 5.7% | 17.5 | 17% |
| 100 | 3.4 | 3.4% | 29.5 | 36% |
| 1000 | 5.3 | 0.5% | 190 | 85% |

Read it twice. **Throughput grows like `ln N`**: a thousand agents land fewer than six changes per validation time, and 99.5% of the compute they burn is thrown away. The cost per landing grows linearly with `N`. And the wasted attempts are not harmless: they are the same machine's cores, so `T` itself grows with `N`, which lowers `s`. With the lander's bound of 30 attempts (`LAND_ATTEMPTS`), a third of the landers of a 100-agent whole-gate repository give up (exit 16), and `LAND_DEADLINE` (900 s) cuts a slow gate off sooner. The model is approximate (arrivals are not exactly Poisson, agents are not saturated), and its shape is what matters: **retests per landing proportional to the number of agents, throughput logarithmic**.

**Livelock.** The push is the only arbiter and it is lock-free: *some* lander always lands (the system progresses), but nothing bounds how long a particular lander loses. That is livelock for the individual: it keeps rebasing and re-validating, exactly as the model says, and its bound is the one the lander already has (section 3.4).

### 3.2 What areas change

A landing's verdict depends only on the areas it touches. Two consequences:

1. **Disturbed only by overlap.** Split the agents over `k` disjoint areas (`N/k` each) and each area is its own instance of the model: the landing rate that disturbs an agent is that of its own area, and the area's validation is the area's steps, `T_a ≤ T`. Throughput becomes `k·W(N/k)`:

   | `N` | `k` areas | landings per `T` | (one area: `W(N)`) |
   |---|---|---|---|
   | 100 | 10 | 17.5 | 3.4 |
   | 100 | 20 | 26.5 | 3.4 |
   | 1000 | 20 | 57.2 | 5.3 |
   | 1000 | 100 | 174.6 | 5.3 |

   and each of those `T_a` is shorter than `T`.

2. **Reuse becomes area-level and language-neutral.** A lander that passed on base `B1` and finds the trunk at `B2` takes the paths that moved (`B1..B2`) and runs them through **the same matcher** (rules 2, 4 and 5). If the areas the move touches are disjoint from the areas of mine that ran, **my verdict is still valid** for those areas and they are not run again. **A move that touches an area of mine re-validates only that area**, not the others I touch. The decision, with `mine` and `moved` both decided by rule 2 to 5:

   - my change is *full-suite* (an unmapped or gate-defining path of mine): nothing is reused;
   - an area of mine that ran and **passed** in the attempt validated against `B1`, has steps, and is **not** in the areas of `moved` is **reused**; every other area of mine with steps runs again;
   - `moved` is full-suite (it holds an unmapped or gate-defining path: the areas file, `land.conf`, a hook, the vendored tool, `LAND_PROTECTED`) touches every area, so everything of mine runs again;
   - an area with no steps ran nothing: it is neither re-run nor reused;
   - all the refusals `LAND_REUSE` already has stand (the base is not a descendant, the settings or hooks moved, a regenerated file, a provider that fails): reuse only ever fails toward running.

   `LAND_REUSE=1` turns reuse on, as today. `LAND_AFFECTS_CMD` is **not** consulted with an areas file, and the two together are refused (exit 2): the overlap *is* the declared dependency, and a second, undeclared one would be a guess. Without an areas file `LAND_AFFECTS_CMD` is unchanged. It is retired with `LAND_INERT`.

   The consequence for the retest storm: the re-validations of a landing are now caused only by landings that touch **its areas**, not by every landing; and a lost race on the push (a fast-forward that failed because the trunk moved elsewhere) costs a rebase and a decision, not a validation.

### 3.3 The soundness condition

Reuse, and equally the very idea of validating only the touched areas, is valid **exactly when each area's steps read nothing outside the paths the area owns.** If the steps of `app` read `src/lib/x.c` and `src/lib/*` is not in `app`'s `paths`, a change to `x.c` that breaks `app` validates nothing of `app`, and a reused verdict is wrong in the same way. That is an **escape**.

- **Who finds it:** the release candidate (rule 7). It runs every step of every area on the exact head; a break the factoring let through fails there, and it fails *by area*, so the failure names the area whose `paths` were too narrow.
- **How it is fixed:** by **widening that area's `paths`** (listing the shared path in the area that reads it), never by a tool guessing. The tool does not trace reads, does not read the steps and does not infer imports: any such inference is a heuristic, and a heuristic here is a silent skip.
- **What counts as a read:** a source file; a configuration, lock or toolchain file (`pyproject.toml`, `lakefile.toml`, `cabal.project`); a test fixture; a script a step calls; a path the step *lists* (a step that enumerates a directory reads its names, and a deletion in it matters). Not paths: the network, the clock, the environment. A step that reads those is flaky, and no factoring cures flakiness.
- **How a project audits it, before it trusts the file** (one experiment per area, in a scratch worktree of the current tree, never in the working copy): for the area, take every tracked path **outside** its `paths` (or a representative sample per directory: the project's choice, and the report of section 4 lists the candidates), **delete it, run the area's steps, and see them pass**; then **overwrite it** with unrelated content (empty, or garbage) and run the steps again. A step that fails reads that path: widen `paths`, repeat. An area is sound when no deletion and no overwrite outside its paths changes its verdict. It is the same experiment that audits `LAND_INERT`, now applied per area, and a project keeps it as a script of its own, run when the factoring changes and before a release.
- **What the audit cannot give:** a step that reads a path only on some runs (a test that opens a file under one condition). The candidate finds it when it happens; the discipline is the one of the whole family: fast gate, best effort; the release candidate is the proof; escapes are counted and each one narrows the factoring's error.

Two landings in disjoint areas are validated on trunks that do not contain each other, and the trunk after both holds both. That is the same soundness condition at work: `b`'s steps read nothing in `a`'s paths, so `b`'s verdict is the verdict on the combination too.

### 3.4 Fairness and livelock under many landers

- **The push is the arbiter.** A plain fast-forward, no lock, no queue, no lease (`tests/lint.sh` keeps them out). Whoever pushes first lands; the others rebase.
- **What bounds retries.** `LAND_ATTEMPTS` (30) and `LAND_DEADLINE` (900 s): past either, the lander stops with exit 16, *nothing pushed, nothing lost*, and the agent runs it again. Between attempts it waits a jittered, growing time, so losers do not collide again. Areas do not change these bounds. They change how often they are reached: an attempt is lost only to a landing that touches one of *its* areas (and, with reuse, a lost race does not even cost a validation).
- **A hot area that everyone edits** is the case areas cannot cure by themselves: all the landings of that area are one instance of the model, `W(n)`, and its throughput is logarithmic in the number of agents *in that area*. What the project and the tool do about it, in order of cost:
  1. **Split the area** (the factoring is the cure). A hot area is a measurement, not an opinion: the landings record will carry the areas of each landing (with the implementation), and `land-metrics` will report landings and exit-16 stops per area. One area that gets half the landings is one to split along the seam the changes actually use.
  2. **Shorten its steps.** `T_a` multiplies the cost of every retest: a hot area should hold the fast checks and the slow ones should be a different area (or the candidate's).
  3. **Batch with `--group`.** `--group` lands a **stack of commits as one landing**: the base-to-revision net change of all of them (a path added by one commit and removed by a later one is not changed), decided and validated **once**. The areas it runs are the union of the areas its entries would run alone, and no area and no step is waived by `--group` (it waives nothing but what it waives today: the size budget). `K` entries of one hot area cost one validation and one trunk move instead of `K` of each, so the hot area's landing rate falls by `K` and the retests with it. A coordinator (not built: the lander has its half) forms the batch from the ready changes of one area, checks them one by one as it does today, and falls back to one by one, bisecting, if the batch fails.
  4. **Do not put too many agents in one area.** From the table: at 5 concurrent landers in an area an attempt succeeds 27% of the time, at 2 it succeeds 43%. A scheduler that holds an area at 4 or 5 concurrent items keeps a lander's expected attempts near 4.
- **No area starves another.** A disjoint area's landings do not disturb a hot area's, nor the other way round: that is rule 4 working in the direction that helps.

### 3.5 What the work queue should learn from areas

The queue schedules agents by disjoint files. Disjoint files are not enough: two changes to different files of the same area still disturb each other (rule 3 runs the area on both, and a move in the area invalidates the other's verdict). **Schedule by disjoint areas**: two items conflict when the *sets of areas their expected paths touch* intersect, computed by the same matcher (a path that touches two areas conflicts with both). Specifically:

- an item that touches **one** area is cheaper than one that touches several: prefer to split a task into one item per area, and let a task that must span areas (a change to shared code, which touches every dependent) wait until the dependents are quiet;
- an item with an **unmapped** or gate-defining path conflicts with everything (it runs everything): schedule it alone, and treat the count of such items as a defect of the factoring to remove (section 4);
- the **hot areas** (most landings, most exit-16 stops) get a concurrency limit (3.4), and the items that touch only a cool area run first;
- **the overlap list is the dependency graph the queue needs**: it is exactly the set of areas that a change to shared code drags in. The queue reads `land-check --areas --json` (section 4); it never reads source.

## 4. Tooling: measuring overlap and unmapped paths

`land-check --areas` reports, from `origin/<base>`'s areas file and the tracked paths (`git ls-files`), exactly:

- **(a) every pair of overlapping areas and the paths in the overlap** (`inert`, if declared, counts as an area); a path in three areas is listed under each of the three pairs;
- **(b) every tracked path no area owns**, each with the areas that enclose it (rule 5), or none: an empty list says that path is UNMAPPED and every change to it runs the full suite. Paths under `.land/` and in `LAND_PROTECTED` are gate-defining, not unowned, and are not listed;
- **(c) the areas with no steps** (documented areas that run nothing).

`--json` prints the same as one object, the format the `report` vectors fix:

```json
{"overlap":[{"areas":["app","lib"],"paths":["src/lib/x.c"]}],
 "unowned":[{"path":"Makefile","enclosed_by":[]},{"path":"core/io/data.json","enclosed_by":["core-io"]}],
 "no_steps":["docs"]}
```

Pairs are in name order, paths sorted. The text form ends with three counts (areas in overlap, paths in overlap, unmapped paths) so the numbers can be tracked. The report is **information, not a gate**: it exits 0 on a well-formed file; the offline drift check still refuses a malformed one. A project that wants a ratchet (the unmapped count may not rise) writes it in its own Tier 1 from the JSON; the tool sets no threshold, since a threshold is a heuristic about someone else's repository. The point is that overlap and unmapped paths are **measured** and so can shrink over time: every unowned path is a decision (own it, or accept that it runs everything), and every path in an overlap is a cost that a better factoring removes.

## 5. The summary

The landing's JSON last line (`README` 6.2) gains, **only when the repository has an areas file** (the usual line keeps its shape otherwise):

- `"areas":["app","lib"]`: the areas the validation **ran**, names sorted: every touched area whose verdict was not reused, a stepless one included (it ran, with nothing in it), and every area when the suite is full; `inert` is among them when the pseudo-area was touched;
- `"skipped_areas":["docs","tools"]`: every declared area **not** run and not reused, names sorted;
- `"reused_areas":["lib"]`: present only when non-empty: touched areas whose verdict was **reused** (section 3.2). `areas`, `reused_areas` and `skipped_areas` partition the areas.

**A gate that runs fewer than all areas says which.** `"validation"` keeps its three values and gets precise meanings: absent, at least one step ran; `"inert"`, zero steps ran **because every touched area has no steps** (the list says which; this is the documented-area case, and the only green with nothing run); `"reused"`, every touched area with steps was reused and nothing ran. A net change with no path (a group whose commits cancel) says so in a printed line, has `"areas":[]` and `"validation":"inert"`. **Zero steps run for any other reason is not a green**: it cannot happen, since a path that touches no area is UNMAPPED and runs everything. The `post-tier1` hook runs exactly when a step ran. The lander also prints, before the steps, one line per area it runs or skips (the first path that touched it), and names every unmapped path and every gate-defining one.

The landings record (`docs/landings.md`) carries the same keys in the same way, so hot areas are measured; that edit is made with the implementation, not here.

## 6. How it interacts with what exists

| exists | with an areas file |
|---|---|
| `LAND_TEST_CMD`, `LAND_GATES_CMD` | **refused together** with the file **on the base** (exit 2): Tier 1 is the steps. `land.conf`'s rule "at least one command is set" reads "or an areas file on the base". A commit that adds the file and removes the keys is not refused: the base has no file yet (section 7, theorem) |
| `LAND_INERT` | works (rule 6); its patterns are the area `inert`; retired in the next major release |
| `LAND_PROTECTED` | its paths run every area; they are not unmapped |
| `LAND_REUSE` | `1` turns on area-level reuse (3.2); `LAND_AFFECTS_CMD` refused with the file |
| `LAND_RC_CMD` | runs **after** every step of every area, as the extra of the candidate (rule 7); without it the candidate is the areas' steps |
| `--validate`, `--push SHA` | `--validate` prints the summary with its areas; `--push SHA` pushes that exact verdict and decides nothing again |
| `--group` | one decision on the net change (3.4) |
| hooks | `post-rebase` unchanged; `post-tier1` runs when a step ran |
| `LAND_TIER1_TIMEOUT` | bounds the sum of the steps; inherited-red handling is unchanged and applies per step |

## 7. How a project migrates

A repository with only `LAND_TEST_CMD` **keeps working**: with no areas file it has one implicit area `all` that owns everything (rule 6), so nothing changes until it chooses to.

**The adoption theorem.** Let `B` be the base a landing is judged on and `C` the commit's net change.
1. If `B` has **no** areas file, the landing is judged by `B`'s rules entirely: `B`'s `land.conf` (`LAND_GATES_CMD`, `LAND_TEST_CMD`, its Tier 1, its hooks). `C`'s `.land/areas.json`, if any, is only **validated** (`land-areas validate`; a malformed file refuses, exit 2) and is not what judges. `C` may add the file and remove `LAND_GATES_CMD` and `LAND_TEST_CMD` in the same landing: no key of `C` is read, so nothing is refused beside the file. No override is needed or used.
2. If `B` has an areas file, the landing is judged by `B`'s file and `B`'s steps, whatever `C` changes in it (a change to the file touches `.land/`, so it runs the full suite of `B`'s areas), and `LAND_GATES_CMD`/`LAND_TEST_CMD` in `B`'s `land.conf` are refused (exit 2).
3. Hence the first areas landing is the last one judged by the old rules, and the **next landing** is the first one judged by the areas. `tests/test_areas.sh` checks (1) and (2) on fixture repositories, with the negative of each watched to fail.

The `LAND_CONF` environment variable (a configuration file on disk, the owner's recovery override) is **not** a step of this migration; `--conf PATH` is a path **in the base** (default `.land/land.conf`), another thing.

**The migration order.** Because the base judges, a change that moves the factoring lands in two kinds of landing, additions first:

1. **Additive landing.** Land what only adds: the new step scripts, the new areas file (and, while the base has none, the removal of `LAND_GATES_CMD`/`LAND_TEST_CMD`). Everything the base's steps run still exists, so the base's gate passes.
2. **Deleting landing.** Only now, with the new file on the base, land the deletions of what the old areas (or the old commands) ran: a script, a Makefile target, a test file. Landed in step 1 they would fail the base's gate, which still runs them (exit 13, naming the area and step).
3. A rename of a script is both: add the new name in step 1, point the areas at it, delete the old name in step 2.

It adopts areas by *splitting* that one area:

1. **Start with one area that is the whole gate.** Write `.land/areas.json` with one area `all`, `paths: ["*"]`, whose steps are the commands of `LAND_GATES_CMD` and `LAND_TEST_CMD`, and delete those two keys, in **one** landing. It is judged by the base's rules (theorem, 1): the old Tier 1 runs, and the new file is validated. The verdicts from the next landing on are the same as before.
2. **Peel the documents.** A stepless area for what no check reads (`docs/*`, `CHANGELOG.md`): this replaces `LAND_INERT`, which can then be deleted. Remove those paths from `all`'s `paths` as you split, or keep `*` and let overlap show you what is left.
3. **Split by seam**, the one the changes actually follow. Run `land-check --areas` after each step: the overlap is the price of the split, the unmapped list is what the split has not yet placed. The first goal is *no unmapped path that is not on purpose*; the second is shrinking the overlap.
4. **Audit each new area** (3.3) before trusting it, and run the release candidate after the split lands. Count escapes: an escape is an area whose `paths` need widening. A repository that sees many escapes should hold the split where it is.
5. **Turn on `LAND_REUSE=1`** once the candidate has been green with the factoring for a release.

Every one of these is a landing like any other, judged by the base (section 3): a change to the areas file runs the full suite of the base's areas, so a bad split is caught by the file it replaces. Each step of the split that moves a script goes in the order above.

## 8. Worked examples

Generic names throughout. In each, shared code is listed in every area that depends on it: that is the overlap, and the paragraph says where it is and why. Every file below is a **complete, valid areas file**; `vectors/areas/areas.json` has them and the cases that follow from them. Paths not listed (a root `.gitignore`, `.agents/`) are unmapped on purpose in these files: the first change to one runs everything, and `land-check --areas` lists them so that the project decides.

### 8.1 A Python package with a services layer and a shared library

```json
{
  "version": 1,
  "areas": [
    {
      "name": "lib",
      "paths": ["src/acme/lib/*", "tests/lib/*", "tests/conftest.py", "pyproject.toml", "uv.lock"],
      "steps": [
        {"run": "ruff check src/acme/lib tests/lib"},
        {"run": "mypy src/acme/lib"},
        {"run": "pytest tests/lib -q"}
      ]
    },
    {
      "name": "orders",
      "paths": ["src/acme/services/orders/*", "tests/services/orders/*", "src/acme/lib/*", "tests/conftest.py", "pyproject.toml", "uv.lock"],
      "steps": [
        {"run": "ruff check src/acme/services/orders tests/services/orders"},
        {"run": "mypy src/acme/services/orders"},
        {"run": "pytest tests/services/orders -q"}
      ]
    },
    {
      "name": "billing",
      "paths": ["src/acme/services/billing/*", "tests/services/billing/*", "src/acme/lib/*", "tests/conftest.py", "pyproject.toml", "uv.lock"],
      "steps": [
        {"run": "ruff check src/acme/services/billing tests/services/billing"},
        {"run": "mypy src/acme/services/billing"},
        {"run": "pytest tests/services/billing -q"}
      ]
    },
    {
      "name": "docs",
      "paths": ["docs/*", "README.md", "LICENSE", "CHANGELOG.md"],
      "steps": []
    }
  ]
}
```

`lib` is the shared library; `orders` and `billing` are services that import it, so **`src/acme/lib/*` is in all three areas**: a change to the library touches the library and both services, a change to a service touches only that service (the library does not list the services, which it does not read). `tests/conftest.py`, `pyproject.toml` and `uv.lock` are read by every pytest, ruff and mypy run, so they are in all three: that is the whole overlap besides the library. `docs` has no steps (rule 6) and replaces `LAND_INERT`. The cost to pay down is the library: splitting it into the part each service really uses shrinks the overlap.

### 8.2 A TypeScript monorepo (web, api, shared)

```json
{
  "version": 1,
  "areas": [
    {
      "name": "shared",
      "paths": ["packages/shared/*", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "tsconfig.base.json"],
      "steps": [
        {"run": "pnpm lint", "cwd": "packages/shared"},
        {"run": "pnpm typecheck", "cwd": "packages/shared"},
        {"run": "pnpm test", "cwd": "packages/shared"}
      ]
    },
    {
      "name": "web",
      "paths": ["packages/web/*", "packages/shared/*", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "tsconfig.base.json"],
      "steps": [
        {"run": "pnpm lint", "cwd": "packages/web"},
        {"run": "pnpm typecheck", "cwd": "packages/web"},
        {"run": "pnpm test", "cwd": "packages/web"},
        {"run": "pnpm build", "cwd": "packages/web"}
      ]
    },
    {
      "name": "api",
      "paths": ["packages/api/*", "packages/shared/*", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "tsconfig.base.json"],
      "steps": [
        {"run": "pnpm lint", "cwd": "packages/api"},
        {"run": "pnpm typecheck", "cwd": "packages/api"},
        {"run": "pnpm test", "cwd": "packages/api"}
      ]
    },
    {
      "name": "docs",
      "paths": ["docs/*", "README.md", "LICENSE"],
      "steps": []
    }
  ]
}
```

`web` and `api` list `packages/shared/*`; `shared` lists neither (it imports neither), so a change to `shared` runs all three and a change to `web` runs only `web`. The workspace files (`package.json`, the lockfile, the workspace and base tsconfig) are read by every package's lint, type check and build: they are in the three code areas. `web` carries `pnpm build` because a bundler failure is a failure of `web` and of nothing else.

### 8.3 A Haskell project (library, executable, tests)

```json
{
  "version": 1,
  "areas": [
    {
      "name": "library",
      "paths": ["src/*", "acme.cabal", "cabal.project", "cabal.project.freeze", "hlint.yaml", ".fourmolu.yaml"],
      "steps": [
        {"run": "cabal build lib:acme --ghc-options=-Werror"},
        {"run": "hlint src"},
        {"run": "fourmolu --mode check src"}
      ]
    },
    {
      "name": "executable",
      "paths": ["app/*", "src/*", "acme.cabal", "cabal.project", "cabal.project.freeze", "hlint.yaml", ".fourmolu.yaml"],
      "steps": [
        {"run": "cabal build exe:acme-cli --ghc-options=-Werror"},
        {"run": "hlint app"},
        {"run": "fourmolu --mode check app"}
      ]
    },
    {
      "name": "tests",
      "paths": ["test/*", "src/*", "app/*", "acme.cabal", "cabal.project", "cabal.project.freeze", "hlint.yaml", ".fourmolu.yaml"],
      "steps": [
        {"run": "cabal test --test-show-details=failures"},
        {"run": "hlint test"},
        {"run": "fourmolu --mode check test"}
      ]
    },
    {
      "name": "docs",
      "paths": ["docs/*", "README.md", "LICENSE", "CHANGELOG.md"],
      "steps": []
    }
  ]
}
```

Three areas over one cabal project. `src/*` is the library and is read by the executable and the tests (they link it); `app/*` is read by the tests too (they exercise the command line); `test/*` is read by no one. So `src/*` is in three areas, `app/*` in two, `test/*` in one. The cabal file, the project file and the freeze file are read by every build, as are the lint and formatter configurations: they are in the three. This is the dependency-heavy shape: a change to the library touches everything, and the only way to shrink it is to split the library into sub-libraries with their own directories (`src/core/*` read by one area, `src/cli/*` by another).

### 8.4 A C project with a library and tools

```json
{
  "version": 1,
  "areas": [
    {
      "name": "libacme",
      "paths": ["include/*", "src/*", "tests/lib/*", "third_party/*", "Makefile"],
      "steps": [
        {"run": "make lib CFLAGS='-Wall -Wextra -Werror'"},
        {"run": "make test-lib"},
        {"run": "make format-check"}
      ]
    },
    {
      "name": "tools",
      "paths": ["tools/*", "tests/tools/*", "include/*", "src/*", "third_party/*", "Makefile"],
      "steps": [
        {"run": "make tools CFLAGS='-Wall -Wextra -Werror'"},
        {"run": "make test-tools"},
        {"run": "make format-check"}
      ]
    },
    {
      "name": "docs",
      "paths": ["docs/*", "man/*", "README.md", "LICENSE", "CHANGELOG.md", "Makefile"],
      "steps": [
        {"run": "make check-man"}
      ]
    }
  ]
}
```

`include/*` and `src/*` are the library and are compiled into the tools, so both areas own them. The `Makefile` is read by every step (each one is a `make` target), so it is in all three areas; the documentation area owns it for the same reason (`make check-man` reads it) and still has a step: an area with steps is not inert. `third_party/*` is vendored code that both build. `tests/lib/*` and `tests/tools/*` are each read by one area only. The cost here is the header: any change to a public header runs everything, which is the truth of C.

### 8.5 A Lean project (spec, implementation, proofs, a web console)

```json
{
  "version": 1,
  "areas": [
    {
      "name": "spec",
      "paths": ["spec/*", "lakefile.toml", "lean-toolchain", "lake-manifest.json"],
      "steps": [
        {"run": "lake build Spec"}
      ]
    },
    {
      "name": "impl",
      "paths": ["impl/*", "spec/*", "lakefile.toml", "lean-toolchain", "lake-manifest.json"],
      "steps": [
        {"run": "lake build Impl"}
      ]
    },
    {
      "name": "proofs",
      "paths": ["proofs/*", "impl/*", "spec/*", "docs/trust-ledger.md", "lakefile.toml", "lean-toolchain", "lake-manifest.json"],
      "steps": [
        {"run": "lake build Proofs"},
        {"run": ".land/tool/bin/land-lean axiom"},
        {"run": ".land/tool/bin/land-lean trust"}
      ]
    },
    {
      "name": "console",
      "paths": ["console/*"],
      "steps": [
        {"run": "npm ci", "cwd": "console"},
        {"run": "npm run lint", "cwd": "console"},
        {"run": "npm test", "cwd": "console"},
        {"run": "npm run build", "cwd": "console"}
      ]
    },
    {
      "name": "docs",
      "paths": ["docs/*", "README.md", "LICENSE", "CHANGELOG.md"],
      "exclude": ["docs/trust-ledger.md"],
      "steps": []
    }
  ]
}
```

The Lean tree is a chain: `impl` imports `spec`, `proofs` imports both, so `spec/*` is in three areas, `impl/*` in two, `proofs/*` in one; the Lake files and the toolchain pin are read by every build and are in all three. `docs/trust-ledger.md` is *excluded* from `docs` and owned by `proofs`: `land-lean trust` derives what the ledger must say from the tree, so the proofs area reads it. (The `exclude` is what keeps the stepless `docs` area from also touching it.) The web console is independent of the Lean tree: **`console/*` overlaps nothing**, and the console's agents never disturb, and are never disturbed by, a proof landing. That is the factoring doing its job. The Lean gates (`docs/lean-gates.md`) are steps of `proofs`.

### 8.6 A documents-only repository

```json
{
  "version": 1,
  "areas": [
    {
      "name": "guide",
      "paths": ["guide/*.md", "glossary.md", ".wordlist.txt"],
      "steps": [
        {"run": "markdownlint guide glossary.md"},
        {"run": "codespell --ignore-words .wordlist.txt guide glossary.md"},
        {"run": "lychee --offline guide"}
      ]
    },
    {
      "name": "policies",
      "paths": ["policies/*", "glossary.md", ".wordlist.txt"],
      "steps": [
        {"run": "markdownlint policies"},
        {"run": "codespell --ignore-words .wordlist.txt policies"},
        {"run": "scripts/check-policy-ids policies"}
      ]
    },
    {
      "name": "scripts",
      "paths": ["scripts/*"],
      "steps": [
        {"run": "shellcheck scripts/*"}
      ]
    },
    {
      "name": "front-matter",
      "paths": ["README.md", "LICENSE", "CHANGELOG.md", "CONTRIBUTING.md"],
      "steps": []
    }
  ]
}
```

No code, still areas. `guide` and `policies` are checked separately, and both read the glossary and the word list, so those two files are in both. `scripts` is the tooling the checks use. `front-matter` has no steps: the readme, licence, changelog and contributing guide are read by no check (the audit of 3.3 says so), so a change that touches only them runs nothing and says `"validation":"inert"`. A document change that touches the guide runs the guide's three checks and not the policies'. The repository that sets `LAND_INERT=CHANGELOG.md` today is this one with the area made explicit.

### 8.7 A family repository with per-library areas (leaf, C substrate, split definitions/proofs)

In a family repository (`docs/family-repo.md` section 1.3), each library declares its own `lib/<name>/areas.json` and `.land/areas.json` is composed deterministically from them. Three library shapes illustrate how `uses` and per-library areas compose:

1. **A small leaf library (`leaf`, ~10 Lean modules, `deps` empty)** declares one area named `leaf`:

```json
{
  "version": 1,
  "areas": [
    {
      "name": "leaf",
      "paths": ["*"],
      "steps": [
        {"run": "lake build", "cwd": "lib/leaf"},
        {"run": "lake test", "cwd": "lib/leaf"}
      ]
    }
  ]
}
```

2. **A library with a specification and a C substrate (`kernel`, `deps` empty)** splits into `kernel:spec` (shared Lean specification) and `kernel:c` (the C substrate, which reads the specification's exported layout header and has `"uses": []`):

```json
{
  "version": 1,
  "areas": [
    {
      "name": "kernel:spec",
      "paths": ["Spec/*", "lakefile.toml", "lean-toolchain", "lake-manifest.json"],
      "steps": [{"run": "lake build Spec", "cwd": "lib/kernel"}]
    },
    {
      "name": "kernel:c",
      "paths": ["c/*", "include/*", "Makefile", "Spec/*"],
      "steps": [{"run": "make test", "cwd": "lib/kernel"}],
      "uses": []
    }
  ]
}
```

Here `Spec/*` is listed in both `kernel:spec` and `kernel:c` (intra-library overlap, rule 4) because the C tests check against the spec; a change in `c/*` runs only `kernel:c` and does not rebuild `Spec`.

3. **A library with quick definitions and slow proofs (`core`, `deps`: `["leaf", "kernel"]`)** splits into `core:defs` and `core:proofs`, and a downstream library `app` (`deps`: `["core"]`) declares `uses` only on `core:defs`:

```json
{
  "version": 1,
  "areas": [
    {
      "name": "core:defs",
      "paths": ["Defs/*", "lakefile.toml", "lean-toolchain", "lake-manifest.json"],
      "steps": [{"run": "lake build Defs", "cwd": "lib/core"}],
      "uses": [
        {"lib": "leaf", "area": "leaf"},
        {"lib": "kernel", "area": "spec"}
      ]
    },
    {
      "name": "core:proofs",
      "paths": ["Proofs/*", "Defs/*", "lakefile.toml", "lean-toolchain", "lake-manifest.json"],
      "steps": [{"run": "lake build Proofs", "cwd": "lib/core"}],
      "uses": [
        {"lib": "leaf", "area": "leaf"},
        {"lib": "kernel", "area": "spec"}
      ]
    }
  ]
}
```

When `app/areas.json` declares `"uses": [{"lib": "core", "area": "defs"}]`, the composed `.land/areas.json` expands `app`'s `paths` to include `lib/core/Defs/*` (and transitively `lib/leaf/*` and `lib/kernel/Spec/*`), **excluding `lib/core/Proofs/*` and `lib/kernel/c/*`**:

- A change to `lib/core/Proofs/*` runs only `core:proofs` (slow proofs), without triggering `app` or `core:defs`.
- A change to `lib/core/Defs/*` runs `core:defs`, `core:proofs`, and `app`.
- Releasing `core` (`land-release --area core`) still requires **both** `core:defs` and `core:proofs` plus `app` (every area of `core` and every area that `uses` it) to pass, and tags `core/vX.Y.Z`.

## 9. What this page does not do

- It does not select inside an area. A project that wants a faster area splits it.
- It does not infer. No import graph, no coverage, no learned dependency, no "obviously unrelated" path: a tool that guesses a coupling is a tool that skips a check on a hunch, and the release candidate would find it anyway, after the harm.
- It does not order or parallelize areas for the project: steps run in file order. A lander may run areas concurrently when it can show the verdict is the same; that is an implementation choice and not part of the contract.
- It does not change the push, the holds and freezes, the commit rules, or the signing: those are the lander's and are untouched.

## 10. Conformance vectors

`vectors/areas/areas.json` is the machine-readable contract. One object: `format`, `version`, `spec`, `how_to_read` and `cases`. Each case has:

| key | meaning |
|---|---|
| `id` | unique, kebab-case |
| `rule` | the rule it covers: `1` to `7` (section 2), or `concurrency` (3), `tooling` (4), `examples` (8) |
| `kind` | `validate`, `decide`, `reuse` or `report` |
| `about` | one sentence of why |
| `input` | by kind, below |
| `expect` | the exact expected output |
| `wrong_implementation` | a plausible wrong implementation this case fails; the suite is not a vector set until each one is shown to fail on a deliberately wrong implementation (the next item runs a mutation self-test: the reference with each wrong rule swapped in must fail the case that names it) |

`input` carries the repository's declaration as `areas_file` (the areas file), or `legacy` (the `land.conf` keys of a repository with no areas file: `LAND_TEST_CMD`, `LAND_GATES_CMD`, `LAND_INERT`, `LAND_PROTECTED`), and optionally `land_inert` and `protected` (lists of globs) beside an areas file.

- **`validate`**: `areas_file` → `{"valid": true|false}`.
- **`decide`**: `changes` is a list of `["A"|"M"|"D", path]` and `["R", old, new]`; `release_candidate` (bool, default false). `expect` is `{"areas","skipped_areas","unmapped","gate_defining","full_suite","steps","validation"}`: `areas` and `skipped_areas` are the sorted names that run and do not (`inert` among the names when declared), `unmapped` the sorted unmapped paths, `gate_defining` the sorted gate-defining paths, `steps` the ordered `[cwd, run]` pairs, `validation` `"inert"` when `steps` is empty and `"tier1"` otherwise.
- **`reuse`**: `mine` and `moved` are change lists as above; `expect` is `{"rerun": [...], "reused": [...]}`: of my touched areas with steps, those that run again and those whose verdict stands (both in sorted order).
- **`report`**: `tracked` is the list of tracked paths; `expect` is the object of section 4.

`input.facts`, when present, is **information an implementation must ignore** (what a test "read"; what coverage says): the cases `import-graph-does-not-select` and `coverage-does-not-narrow` fail an implementation that selects by it. The other cases that fail a wrong implementation by construction: a path in two areas (first match wins fails), an exclude (ignored fails), the closest enclosing area with a tie (first enclosing, or all enclosing, fails), a root glob that encloses nothing, a string-prefix directory (`core/iodata.json`), unmapped and gate-defining paths (a silent skip fails), a deleted and a renamed path (matching one end fails), an empty-steps area (treating it as unmapped fails), a trunk move disjoint from mine and one that is not (re-validating on every move, file-level reuse, first-owner attribution all fail), and the reuse cases for a changed areas file.
