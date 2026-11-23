# Study: why a full-suite landing takes an hour, and how to make it minutes

Status: a STUDY (documents only; no code, test, or config is changed here). Written against `vbm-land` 0.26.0, `docs/areas.md`, and `docs/family-repo.md`.

In a family repository of seventeen libraries, any change to `.land/` (everything under it: the vendored lander, `.land/areas.json`, `.land/land.conf`, hooks) or any other gate-defining path, as well as every release candidate (`land-release`), runs every step of every area. Run sequentially in a fresh scratch worktree, seventeen Lean libraries at roughly three minutes each take ~51 minutes — and the default 30-minute bound on Tier 1 (`LAND_TIER1_TIMEOUT=1800` in `lib/conf.sh:41`) kills the landing at around library ten.

This study answers four questions: (1) where the hour goes, (2) three remedies with their soundness arguments, costs, and requirements, (3) a recommended order with expected wall times on one host and on four hosts, and (4) the decisions the owner must make.

---

## 1. Where the time goes

The lander's own per-run logs (`<git common dir>/vbm-land/metrics.jsonl` and `landings.jsonl`) in this repository record only `tier1_s` and `total_s` for the whole run (on `vbm-land` itself, 236–315 s), not per-step timings of a family repository. The hour is therefore accounted for from the structure of `bin/land-direct`, `lib/areas.sh`, `lib/areas.py`, `bin/land-release`, and `docs/family-repo.md`.

### 1.1 Cold Lake builds in a fresh scratch worktree

`bin/land-direct:286` creates a fresh detached worktree at `$run/wt` (`git worktree add -q -f --detach "$wt" "$remote/$base"`) for every run. Because `.lake/` is gitignored, `$wt` starts with zero compiled `.olean` or C build artifacts.

Every `lib/<name>/` in a family repository is a self-contained Lake package (`docs/family-repo.md` section 1) with its own `lakefile.toml`, `lean-toolchain`, and `lake-manifest.json`, naming its in-repo dependencies as relative paths `../<dep>`. Consequently, running `lake build` in `lib/<name>/` compiles not only `<name>`'s own modules, but also **every in-repo dependency in `<name>`'s closure from scratch**, because Lake writes build products into each package's `.lake/` inside `$wt` (or `lib/<name>/.lake/`) and no prior landing's `.lake/` exists in `$wt`.

- A shared foundation library `alpha` (for example, a low-level parsing or SIMD-style primitive library) is compiled when `alpha`'s own area runs, and **compiled again** inside the fresh worktree whenever a downstream library (`beta`, `gamma`, `delta`, ...) runs `lake build` in its own `cwd` — unless Lake shares a `.lake/` across `../<dep>` paths inside the same `$wt`, in which case it is still compiled cold at least once per landing, and **re-compiled from cold on every subsequent landing** because `$wt` is destroyed on exit (`bin/land-direct:92-96`).
- Even when `../<dep>/.lake/` is populated in `$wt` by an earlier area in the same run, downstream `lake build` steps still re-link, re-check, and run their own `lake test` / `land-lean` gates sequentially.
- Seventeen libraries × ~3 minutes each ≈ **51 minutes** (up to ~1 hour with `git worktree add`, `land-check`, `tests/lint.sh`, and `lake test` / Lean gates).

### 1.2 The repeated whole-repository gate (confirmed: runs once)

In `docs/family-repo.md` section 1.3, the whole-repository public lint (`tests/lint.sh`) is prepended as a step of every area with the exact same `cwd` (`.`) and `run`.

**Confirmed in code:** `lib/areas.py:169-174` (`outcome()`) deduplicates `(cwd, r)` across all areas in `run` using `seen = set()`, attributing the shared step to the first area in file order that declares it and emitting it **once** in `steps0`. `docs/areas.md` rule 3 specifies this exact behaviour. Thus `tests/lint.sh` does **not** run seventeen times; it runs once per landing. The hour is not spent in the shared lint — it is spent in the seventeen distinct per-library build/test steps.

### 1.3 Strictly sequential execution

Both `areas_steps` (`lib/areas.sh:36-48`, used by `bin/land-direct`) and `areas_candidate` (`lib/areas.sh:80-98`, used by `bin/land-release`) iterate over `$run/areas.d/steps0` in a single `while IFS= read ...` loop, running one step to completion before starting the next:

- `areas_steps` runs each step via `t1stage`, updating `left=$(( $3 - ($(date +%s) - ts) ))` before each step (`lib/areas.sh:40`). With `LAND_TIER1_TIMEOUT=1800` (30 minutes), the eleventh ~3-minute library is never even started: the lander aborts with exit 13 (`Tier 1 ran past its bound`).
- `areas_candidate` runs each step sequentially under `LAND_RC_TIMEOUT` (default `7200` s in `bin/land-release:73`), so a full release candidate survives the timeout only by taking ~51–60 minutes of wall time.

### 1.4 Summary of where the hour goes

| source | today's cost (17 libraries) | why |
|---|---|---|
| Fresh scratch worktree per landing | 100% cold Lake builds on every full-suite landing | `$run/wt` has no `.lake/`; `run_cleanup` deletes it |
| Repeated dependency builds | `alpha` built in every dependent or once per `$wt` | each `lib/<name>/` has its own package and `../<dep>` |
| Sequential `steps0` loop | sum of all 17 libraries (~51 min) > `LAND_TIER1_TIMEOUT` (30 min) | `areas_steps` and `areas_candidate` run 1 step at a time |
| Shared whole-repo lint (`tests/lint.sh`) | runs **once** (confirmed, `lib/areas.py:169-174`) | deduplicated by `(cwd, run)` |

---

## 2. Three remedies

### 2.1 Remedy (a): Run independent areas concurrently

#### Design

By `docs/areas.md` rule 4, **areas have no dependency edges**: overlap in `paths` is the declared dependency, and `docs/areas.md` section 9 explicitly allows a lander to run areas concurrently when the verdict is the same.

1. **Per-area step lists, not one flat `steps0`.** `lib/areas.py` emits steps grouped by area (preserving each area's internal step order). A shared `(cwd, run)` step that appears in multiple areas (such as `tests/lint.sh` at `cwd=.`) is deduplicated as today: run **once** in a pre-phase before parallel area workers start (or attributed to a single barrier step), so two workers never run the same command in the same `cwd` at the same time.
2. **Intra-area sequential, inter-area concurrent.** Each area `A` runs its own steps in declaration order (`step 1`, then `step 2`, ...). Distinct areas `A` and `B` run in parallel worker subshells, each in its own process group (`set -m`, matching `bin/run-tests-parallel:29`) with its own `TMPDIR` and its own per-step log file (`$run/area.<A>.<i_step>.log`).
3. **Shared `../<dep>` write hazard in Lake.** Inside one `$wt`, if area `beta` (`cwd=lib/beta`) and area `gamma` (`cwd=lib/gamma`) both depend on `../alpha` and run `lake build` simultaneously, both Lake processes may attempt to build and write into `lib/alpha/.lake/` at the same time — racing on `.olean` / `.trace` / lock files. Two ways to make concurrent `lake build` sound inside `$wt`:
   - **Option a1 (topological / pre-build shared deps, or Lake's own locking):** pre-build shared `deps` closure once, or rely on Lake's file lock (if Lake serialises writes to `../alpha/.lake/`, `beta` and `gamma` stall on `alpha` rather than corrupting it, though they still contend).
   - **Option a2 (isolated per-area worktrees or `LAKE_BUILD_DIR`):** each area worker runs in a lightweight read-only/copy-on-write clone or `git worktree` (or sets its own build directory), eliminating cross-area `.lake/` races completely at the cost of extra disk/rebuilds of shared deps — which Remedy (b) eliminates anyway.

#### Concurrency bound: derived from the machine, never a hard-coded number

How many areas run at once is a **machine fact** (CPU cores and available RAM), never a constant in `vbm-land`:

- Let $C = 	ext{nproc}$ (available logical CPUs).
- Let $M_{	ext{avail}}$ be available memory (`MemAvailable` from `/proc/meminfo`, or cgroup memory limit if running inside a container) and $M_{	ext{area}}$ be the peak RSS of one `lake build` + `lean` worker (for Lean 4 libraries, typically 1.5–4 GiB per parallel build; Lake itself spawns internal threads up to `nproc` unless constrained).
- **Avoid nested oversubscription:** if $J$ areas run concurrently and each `lake build` spawns $C$ Lean workers, total threads become $J 	imes C$, thrashing memory and CPU. Therefore, when running $J$ areas concurrently, each area's Lake invocation must be capped at $t = \max(1, \lfloor C / J floor)$ threads (or `LAKE_JOBS` / `-j` / `LEAN_NUM_THREADS` passed to the step environment), and:
  $$J = \max\Bigl(1,\; \minigl(\lfloor C / t_{\min} floor,\; \lfloor M_{	ext{avail}} / M_{	ext{area}} floorigr)\Bigr)$$
  where $t_{\min}$ is the minimum threads per area (e.g., 1 or 2) and $M_{	ext{area}}$ is a host/repo setting (or measured/configured via an operator knob akin to `TEST_JOBS` in `bin/run-tests-parallel:30`, defaulting to `min(nproc, floor(MemAvailable / M_area))`).
- On a host with 16 cores and 64 GiB RAM (with $M_{	ext{area}} pprox 4$ GiB, $t=1$–$2$), $J pprox 8$–$16$; on a smaller 8-core / 16 GiB host, $J = 4$.

#### Fail-fast vs. run-all, per-step logs, and timeouts

- **Fail-fast vs. run-all:**
  - For **`land-direct` (Tier 1)**: **fail-fast** is preferable once any area fails (kill remaining area process groups via `lib/reap.sh`, as `bin/run-tests-parallel:21` does on abort), because a landing with one red area cannot land anyway and freeing the machine immediately helps concurrent landers. *Exception:* if `inherited_red` is enabled (`bin/land-direct:256-264`), only the failing area's step needs to be re-run on `$bsha`, not the whole suite.
  - For **`land-release --rc` (release candidate)**: **run-all and report every failure** (matching `bin/run-tests-parallel:39-50`), because the release operator needs the complete list of red areas in one pass (`docs/family-repo.md` section 8: "reports every red area by name").
- **Per-step logs:** Every step writes to `$run/area.<name>.<step_idx>.log` (and `$run/area.<name>.rc`). On failure, the lander prints the failing area name, step command, and log path (`logfile`), and `run_cleanup` (`bin/land-direct:92-96`) already preserves `*.log` on non-zero exit.
- **Timeouts under concurrency:** `LAND_TIER1_TIMEOUT` (`lib/conf.sh:41`) is a **wall-clock** bound on the entire Tier 1 phase (`left=$(( $3 - ($(date +%s) - ts) ))` in `lib/areas.sh:40`), not a CPU-time sum. Running $J$ areas concurrently reduces wall-clock time by roughly $\min(J, N_{	ext{areas}})$ (subject to the longest single area, stragglers, and shared-dependency contention), so a 51-minute sequential run drops to ~6–15 minutes under $J=4$–$8$ **without** raising `LAND_TIER1_TIMEOUT=1800`. Each area worker passes the remaining wall-clock `left` to `bounded` (`timeout --kill-after=30`).

#### Soundness, cost, and what it needs

- **Soundness:** Sound provided (1) no two concurrently running areas write to the same working-tree path (requires isolating `.lake/` or pre-building/locking shared `../<dep>` directories, and running shared steps like `tests/lint.sh` once before workers start), and (2) no step mutates tracked files in `$wt` (in `bin/land-direct:387-388`, Tier 1 leaving changes outside `LAND_GENERATED_LIST` is already an error; if any area regenerates generated files, that step must run in a serial pre/post phase). Under these conditions, the verdict is identical to sequential execution (`docs/areas.md` section 9).
- **Cost:** Medium. Pure shell/process-management change in `lib/areas.sh` and `lib/areas.py`, reusing the `set -m` + `lib/reap.sh` + per-job `TMPDIR`/log pattern already proven in `bin/run-tests-parallel`.
- **What it needs:**
  1. `lib/areas.py`: group `steps0` by area (after a deduplicated shared-steps pre-phase) instead of flattening into one list.
  2. `lib/areas.sh`: parallel worker loop in `areas_steps` and `areas_candidate`, bounded by machine-derived $J$, using `lib/reap.sh` for clean process-group teardown, per-area/per-step logs, and `inherited_red` scoped to the failing area+step.
  3. Resolution of the shared `../<dep>/.lake/` write hazard (either per-area `wt` / `LAKE_BUILD_DIR` isolation, or pre-building shared deps, or verified Lake locking).
  4. `tests/test_areas.sh`: tests for concurrent execution, deduplicated shared step running once, fail-fast reaping, and run-all reporting in `land-release`.

---

### 2.2 Remedy (b): A shared build cache for Lean build products

#### Design

Instead of rebuilding every unchanged library from scratch in every fresh `$run/wt`, maintain a **content-addressed artifact cache** (on the host, outside `$run/wt`, e.g., under `<git common dir>/vbm-land/cache/` or a configured machine cache directory) storing each library's compiled `.lake/build/` artifacts keyed by a strict cryptographic digest of all inputs that affect its compilation.

When `lake build` is about to run for `lib/<name>/`:

1. **Compute the input key `K(name)`:**
   $$K(	ext{name}) = 	ext{SHA256}\Bigl(	ext{toolchain},\; 	ext{lake\_files},\; 	ext{tree\_hash}(	ext{lib/}\langle	ext{name}angle),\; igl[	ext{dep}: K(	ext{dep}) 	ext{ for } 	ext{dep} \in 	ext{sorted}(	ext{deps}(	ext{name}))igr],\; 	ext{build\_env}\Bigr)$$
   Specifically:
   - **`toolchain`**: exact contents of `lib/<name>/lean-toolchain` (and `lake --version` / `lean --version` output, in case the host toolchain binary changed without the pin changing).
   - **`lake_files`**: `lib/<name>/lakefile.toml` (or `.lean`) and `lib/<name>/lake-manifest.json` (already inside `tree_hash(lib/<name>)`, listed explicitly for clarity).
   - **`tree_hash(lib/<name>)`**: the deterministic content hash of all tracked (and unignored) files under `lib/<name>/`, excluding `.lake/` and `.git/` (the exact `st_hash_at` / `tree_hash` already implemented in `lib/verify.sh` and `lib/subtree.sh`!).
   - **Recursive dependency keys `K(dep)`**: for every `dep` in `lib/<name>/deps` (which `docs/family-repo.md` section 2 guarantees is a DAG with no cycles and matches `../<dep>` in `lakefile.toml`), include `dep:K(dep)`. Because `K(dep)` already hashes `dep`'s toolchain, sources, and transitive deps, `K(name)` changes whenever anything in `name`'s transitive build closure changes.
   - **`build_env`**: any compiler/Lake flags or environment variables that affect `.olean` / C output (e.g., `CFLAGS`, `LEAN_ABORT_ON_PANIC`, build profile).
2. **Cache lookup (before running `lake build`):**
   - If `$CACHE_DIR/$K(name)` exists and passes integrity verification (e.g., manifest/checksum of cached `.lake/build/`), populate `lib/<name>/.lake/build/` (via hardlinks, reflinks on copy-on-write filesystems, or fast extract) **with timestamps preserved or set consistently** so Lake sees every target as up-to-date.
   - Note: `lake build` itself still runs on cache hit — as a ~0.5 s no-op check — or, if the cache stores only `.olean`/C build products, `lake test` and `land-lean` still run against the restored build products unless their verdicts are also gated (see Soundness below).
3. **Cache store (after a green `lake build`):**
   - Atomically stage `.lake/build/` to a temporary directory on the same filesystem and `mv` (atomic rename) into `$CACHE_DIR/$K(name)` so concurrent landers never observe a half-written cache entry.
   - Bounded size: LRU / age eviction (e.g., sweep entries unused for $N$ days or above a size cap, never inside a running build).
4. **Release candidate (`LAND_RC=1`):**
   - `docs/areas.md` rule 7 requires `LAND_RC=1`: *"nothing cached, selected or skipped."* Therefore, when `LAND_RC=1` is set (every `land-release`), **the build cache MUST be bypassed on read** (every library compiles cold from source). A green `LAND_RC=1` run may still populate the cache for subsequent Tier 1 landings, or bypass both read and write.

#### Soundness: what makes a cached result unsound, and how the key excludes it

A cached build product or cached test/gate verdict is **unsound** if it returns green when a cold build/run on the current tree would fail. Five failure modes and how the key/design excludes each:

| unsoundness hazard | why it happens | how the design excludes it |
|---|---|---|
| **1. Changed toolchain** | `lean-toolchain` edited, or host `lean`/`lake`/`leanc`/C compiler upgraded | Include `lean-toolchain` content + `lean --version` + `cc --version` in `K(name)` |
| **2. Changed transitive dependency** | `lib/<dep>/` changed, changing `.olean` ABI or definitions | Include `dep:K(dep)` recursively for all `deps` in `K(name)` |
| **3. Changed lander tool or gate** | `.land/tool/` (`land-lean`), `.land/lean.conf`, or `.land/areas.json` changed | **Cache only `.lake/build/` (build products), NOT gate verdicts**, OR include `sha256(.land/tool/MANIFEST.sha256)` + `sha256(.land/lean.conf)` in any gate-verdict key. Caching only `.lake/build/` means `land-lean` and `lake test` **always run** on the current lander tool |
| **4. Gate or build reads the environment / outside `lib/<name>/`** | A build script reads an env var, clock, network, or file outside `lib/<name>/` and `deps` | `docs/family-repo.md` section 2 forbids undeclared cross-library reads; `build_env` pins known build vars; `LAND_RC=1` runs cold on every release candidate to catch any escape |
| **5. Concurrent cache corruption / dirty `.lake/`** | Two landers write `$CACHE_DIR/$K` at once, or a lander mutates hardlinked `.olean`s | Write to temp dir + atomic `rename`; restore via copy/reflink (never mutable shared hardlinks to `.trace` files that Lake rewrites) |

**Key distinction:** Caching **build artifacts (`.lake/build/`)** is far safer than caching **test/gate verdicts**. If `.lake/build/` is cached by `K(name)`, a change to `.land/` (say, a stricter `land-lean` check or a new `tests/lint.sh` rule) still **executes every gate and test** against the restored `.olean`s — it just skips recompiling unchanged Lean modules (~80–90% of the 3-minute per-library time).

#### Cost and what it needs

- **Cost:** High (the most moving parts, though self-contained). Requires a cache wrapper or Lake-aware step helper, atomic staging, eviction, and careful timestamp/reflink handling so Lake does not decide to rebuild anyway due to mtime skew.
- **What it needs:**
  1. A cache helper (e.g., `bin/land-cache` or Lake wrapper in `vbm-land`, or a repository-level wrapper in the family repo's step commands) that computes `K(name)` from `st_hash_at` + `deps` + toolchain version, restores `.lake/build/`, runs `lake build`, and atomically stores `.lake/build/`.
  2. Respect for `LAND_RC=1`: when `LAND_RC=1`, skip cache read (`docs/areas.md` rule 7).
  3. Cache eviction/GC policy (disk bound) and flock-free atomic publish (`mktemp -d` + `mv -T` / `ln`).
  4. Tests: cache hit skips recompilation, source edit invalidates `K(name)` and all dependents `K(downstream)`, toolchain version change invalidates `K(name)`, `LAND_RC=1` bypasses cache read.

---

### 2.3 Remedy (c): Area-level reuse for a gate-defining change

#### What happens today

In `lib/areas.py:144-163`:

```python
gd = is_gate(p, prot)   # p.startswith(".land/") or matches LAND_PROTECTED
if gd:
    full = True
    gate.add(p)
```

Whenever a landing touches **any** path under `.land/` or in `LAND_PROTECTED` (including `lib/*/areas.json` per `docs/family-repo.md` section 1.3), `full := true`: **every area runs**, and in `outcome()` / `main()` (`lib/areas.py:308`):

```python
reused = [n for n in mine if not d["full"] and not moved["full"] and n not in moved["touched"] and ...]
```

Both `d["full"]` and `moved["full"]` disable reuse completely.

#### When area-level reuse is sound — and when it is NOT

Be honest about what `.land/` contains (`lib/paths.sh`):

1. **`.land/tool/` (the vendored lander, `land-update`)**: **Reuse is NOT sound.**
   The vendored lander *is* the judge: `land-lean` (`AxiomGate.lean`, `LedgerGate.lean`, `trust_ledger.py`), `land-check`, `land-direct`, `lib/areas.py`, `lib/conf.sh` all live in `.land/tool/`. Even if a library's own source files did not change, a new `land-lean` rule or bugfix in `.land/tool/` can turn a previously green library red. Reusing an old verdict from an older `.land/tool/` would let a broken gate pass.

2. **`.land/land.conf` and `.land/land.d/*` (settings and hooks)**: **Reuse is NOT sound.**
   `land.conf` sets timeouts, `LAND_PROTECTED`, `LAND_GENERATED_LIST`, etc., and `land.d/` hooks (`post-rebase`, `post-tier1`) judge the whole tree. A change to settings or hooks can reject a library that previously passed.

3. **`.land/areas.json` and `lib/<name>/areas.json` (when only ONE library's area changed)**: **Partial reuse *could* be sound only in narrow cases, and even then is fragile:**
   - Suppose `lib/delta/areas.json` adds a new step to `delta` (and `compose --write` updates `.land/areas.json` accordingly). Areas `alpha`, `beta`, `gamma` have the exact same `paths`, `exclude`, `steps`, and `uses` as on `origin/main`.
   - **However:**
     - `docs/areas.md` rule 5 deliberately makes `.land/` gate-defining: *"the files that judge changes are judged by everything."*
     - Checking that an edit to `.land/areas.json` only modified area `delta` (and did not change `alpha`'s `paths`, `exclude`, or `steps`, nor introduce a syntactic/semantic change affecting `enclosing` or `unmapped` paths for `alpha`) requires **diffing the parsed AST of `areas.json`**, not just checking file paths.
     - And for **inter-landing reuse** (`LAND_REUSE=1`): `LAND_REUSE` only reuses verdicts from an *earlier attempt of the same landing* (`$prev` → `$bsha`, `lib/areas.sh:55-58`) — it does **not** reuse verdicts across different landings from `main`! So even if `alpha` was green on `main` an hour ago, a new landing touching `.land/areas.json` has no `$prev` attempt of its own.

4. **`.land/PIN` or `.land/land.signers`**:
   - `.land/PIN` changes together with `.land/tool/` on `land-update`.
   - `.land/land.signers` is read-only unless `LAND_OWNER=1` (`bin/land-direct:352-353`); it does not affect library builds, but changes so rarely (key rotation) that optimizing for it saves nothing.

#### What the areas contract (rule 7) requires

`docs/areas.md` rule 7 is explicit:

> **The release candidate runs EVERY area.** `land-release` runs every step of every area (with `LAND_RC=1`: nothing cached, selected or skipped)...

And for landings, `docs/areas.md` rule 5 is equally explicit:

> **Gate-defining paths** also run the full suite: everything under `.land/` (the areas file, `land.conf`, hooks, the vendored tool) and every path in `LAND_PROTECTED`.

**Conclusion for Remedy (c):** Area-level reuse for `.land/` changes is **not a general solution**. For `.land/tool/`, `.land/land.conf`, and `.land/land.d/`, reuse is **unsound** because the judge itself changed. For `lib/<name>/areas.json` + `.land/areas.json`, narrow AST-diffing reuse would only ever help if `land-direct` cached verdicts across *unrelated* landings on `main` (which it does not do today, and which would duplicate the build-cache problem with worse soundness hazards), and it would **never** help `land-release --rc` (rule 7).

---

## 3. Recommendation

### 3.1 Recommended order

1. **First: Remedy (a) — Concurrent independent areas** (`lib/areas.py`, `lib/areas.sh`, `tests/test_areas.sh`).
   - **Why first:** Immediate 4×–8× wall-clock speedup on **every** full-suite run — both `.land/` gate-defining landings **and** `land-release --rc` (where caching is forbidden by rule 7). Drops a 51-minute run under `LAND_TIER1_TIMEOUT=1800` without weakening any gate or introducing cache-invalidation risk.
2. **Second: Remedy (b) — Content-addressed `.lake/build/` cache** (build products only, bypassed when `LAND_RC=1`).
   - **Why second:** Eliminates the ~2–2.5 minutes of cold Lean compilation per unchanged library on `.land/` landings and on cross-library dependency changes (`alpha` rebuilt for `beta`, `gamma`, ...). Combined with (a), a `.land/` landing (e.g. `land-update` or adding a new library's `areas.json`) drops from ~51 minutes to **1–3 minutes**.
3. **Do NOT build Remedy (c)** for `.land/` changes.
   - **Why:** Unsound for `.land/tool/`, `land.conf`, and hooks; saves nothing for `land-release --rc` (rule 7); and once (a) + (b) are in place, a full-suite `.land/` landing already takes ~1–3 minutes while actually running every gate on the new tool.

### 3.2 Expected wall-clock time for the hub today (17 libraries, ~3 min each cold)

Assumptions: 17 libraries averaging ~3 min each cold (~2.2 min `lake build` + ~0.8 min `lake test` / `land-lean` gates), ~0.2 min shared `tests/lint.sh`, and cache hit reduces `lake build` to ~0.1 min (leaving ~0.9 min for no-op build check + `lake test` + `land-lean` per library).

| scenario | today (sequential, cold) | + (a) concurrent areas | + (a) + (b) build cache |
|---|---|---|---|
| **Single host** ($J = 4$–$8$, 17 libs) | ~51 min (**killed** at 30 min by `LAND_TIER1_TIMEOUT`) | **~7–14 min** (passes `LAND_TIER1_TIMEOUT=1800`) | **~2–4 min** for `.land/` landing; **~7–14 min** for `land-release --rc` (`LAND_RC=1`) |
| **Four hosts** (distributed / sharded areas, $4 	imes J$) | N/A (single-host loop) | **~3–5 min** (bounded by slowest single library + shared-dep barrier + git/sync overhead) | **~1–2 min** for `.land/` landing; **~3–5 min** for `land-release --rc` |

*(Note: "four hosts" requires either a remote coordinator/runner dispatching areas across hosts, or sharded CI/worker runners; `bin/land-direct` and `bin/land-release` today are single-host scripts. See risks below.)*

### 3.3 Risks

| risk | impact | mitigation |
|---|---|---|
| **Shared `../<dep>/.lake/` write race** under Remedy (a) | Two concurrent areas (`beta`, `gamma`) write to `lib/alpha/.lake/` simultaneously and corrupt `.olean`/`.trace` files | Pre-build shared `deps` closure before parallel workers, or isolate per-area build dirs / worktrees |
| **Memory exhaustion / OOM** under Remedy (a) | 8–16 concurrent `lake build` + `lean` processes exceed host RAM | Derive $J$ from `MemAvailable / M_area` and cap per-area Lake/Lean threads ($t = \max(1, \lfloor C/J floor)$) |
| **Stale or corrupted build cache** under Remedy (b) | False green if toolchain, `deps`, or compiler flags are omitted from `K(name)` | Include `lean-toolchain` + `lean --version` + `cc --version` + recursive `K(dep)` in `K(name)`; cache `.lake/build/` only (always run `land-lean` and `lake test`); atomic temp+rename publish; `LAND_RC=1` bypasses cache read |
| **mtime skew on cache restore** under Remedy (b) | Lake ignores restored `.olean`s and rebuilds anyway | Store and restore `.lake/build/` with consistent timestamps or Lake's own trace/input-hash expectations verified in tests |
| **Multi-host complexity** (4 hosts) | Adds network transport, host clock/toolchain drift, and remote reaping | Keep single-host concurrency (a) + local/shared cache (b) first; only add multi-host dispatch if single-host ~2–4 min is still too slow |

### 3.4 Code classification (protected vs. unprotected)

Per `CONTRIBUTING.md` and `AGENTS.md`:

- **Lander code (protected — owner lands them):**
  - `lib/areas.py` (emit per-area step groups beside/instead of flat `steps0`; keep shared `(cwd, run)` deduplicated)
  - `lib/areas.sh` (`areas_steps` and `areas_candidate` concurrent runner, `lib/reap.sh` process-group cleanup, machine-derived $J$, `inherited_red` scoped to failing area/step)
  - `bin/land-direct` (if `LAND_TIER1_TIMEOUT` / logging / `metrics.jsonl` per-area timing fields are updated)
  - `bin/land-release` (if `areas_candidate` signature or run-all reporting flags change)
  - `lib/conf.sh` (only if a new `land.conf` key or operator knob is added)
  - `bin/land-cache` or cache helper in `bin/` / `lib/` (if Remedy (b) is shipped in `vbm-land` rather than as a family-repo script)
- **Documents and tests (unprotected — agents may land):**
  - `docs/areas-parallel.md` (this study)
  - `docs/areas.md` (if documentation of concurrent area execution or `LAND_RC=1` cache rules is expanded)
  - `tests/test_areas.sh` and `tests/test_release_candidate_area.sh` (new tests for concurrent areas, shared-step deduplication, fail-fast vs. run-all, and cache invalidation)

---

## 4. What the owner must decide

1. **Approve Remedy (a) first** (concurrent independent areas in `lib/areas.py` and `lib/areas.sh`) as the next protected lander slice.
2. **Choose the `../<dep>/.lake/` isolation strategy for Remedy (a):**
   - Option 1: pre-build shared dependency libraries once in `$wt` before launching parallel dependent areas, or
   - Option 2: give each area worker an isolated build directory / worktree (trades extra disk/build time until Remedy (b) lands, with zero lock contention).
3. **Set the failure policy per mode:** confirm **fail-fast** (kill remaining areas on first failure, except `inherited_red` check on the failing step) for `land-direct`, and **run-all** (report every failing area) for `land-release --rc`.
4. **Approve Remedy (b) (`.lake/build/` content-addressed cache) and where it lives:** inside `vbm-land` (e.g., a generic cache helper or `LAND_CACHE_DIR` knob, bypassed when `LAND_RC=1`) vs. inside the family repository's own build wrapper.
5. **Confirm rejecting Remedy (c):** accept that `.land/` changes continue to run every area (now ~2–4 min with (a)+(b), and ~7–14 min with (a) alone) rather than adding fragile AST-diff reuse over `areas.json`.
6. **Decide whether four-host distribution is needed at all** once single-host (a) + (b) brings `.land/` landings to ~2–4 minutes and `land-release --rc` to ~7–14 minutes.
