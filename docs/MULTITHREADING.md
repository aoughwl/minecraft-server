# Multithreading plan

Status: **plan** (phase 0 partly started, see section 9). Written from four read-only investigations of the tree at e7c443c: the global-state
audit, the tick structure, the thread primitives of the compiler, and the upstream (Rust) concurrency model. Where a claim was not checked it says so.

## 1. Goals

1. The server uses more than one core for real work, and the user can say how many threads it may use.
2. It runs well as a **singleplayer / LAN server inside the game**: the game itself needs cores for rendering, so the server must leave some free.
3. **Same results with any thread count.** `threads = 1` (everything inline) and `threads = N` must produce the same world: chunk generation is already
   checked byte for byte (`genhash`); the same bar applies to every phase below.
4. No big-bang rewrite. Every phase ships on its own, is off or harmless by default until proven, and can be switched back to the single-threaded path.

Non-goals: lock-free everything; making plugin code thread-aware (plugins keep running on one thread and see a serial server).

## 2. Where we are (facts)

* One thread runs the whole server: accept, every connection's packet handling, the 20 Hz tick, RCON, query, Bedrock, console (`pumpkinlib.aowl serverLoop`).
  Play packets are handled in the network pump, outside the tick, and mutate the world directly.
* Upstream (Rust) is concurrent by design, on three axes: a tokio task per connection, rayon `par_iter` over worlds, players and entities (plus a
  `simulation_pool` of one thread per CPU and a `compute_pool` of `cpus/2` clamped to 2..8), and dedicated chunk generation / IO threads. Our port flattened
  all three into the polled loop; the locks became plain fields (`chunkdata.aowl`, `netbase.aowl`, `chunk_system/channel.aowl`).
* The only worker threads we have: chunk generation (`world/chunk_system/generation_executor.aowl`, `MC_CHUNK_WORKERS`, default 0, the launcher sets 4), the
  Bedrock crypto, online-mode HTTP auth. Generation hands a whole `Cache` of chunk protos to a worker and does not touch it until it comes back.
* **Refcounts are atomic and the allocator (mimalloc) is thread-safe.** `pumpkinlib.aowl`'s header and `DESIGN_16`/`17` still say the opposite: stale, fix them.
  Atomic refcounts make the count safe, not the contents: two threads on one object is still a race.
* Primitives available to native programs (`std/rawthreads`, `locks` with `Lock`/`Cond`, `atomics`, `ticketlocks`, `cpuinfo.countProcessors`): thread
  create/join with optional CPU pinning, mutex, condition variable (no timeout), gcc atomics. **No channel, semaphore or lock-free queue**: a job queue is a
  seq under a Lock. Exceptions do not cross threads: a job body must catch everything. Windows `countProcessors` covers one processor group (max 64).
* About 600 module-level `var`s (about 130 in the plugin layer, 320 in `server`). Roughly: 95 are write-once vtable singletons, about 170 are hook slots
  installed at start-up, the rest is per-world, per-player, caches, counters and the genuinely shared state in section 3.

## 3. The shared state that decides everything

Ranked by how much it blocks parallel ticking (from the audit):

| Group | Examples | Rule needed |
|---|---|---|
| Per-world state held in globals | `entitymod.gWorlds` (entities are *not* on `World`), `body/bodymanager` (`gBodies`, `gJobs`, 72 refs), `body/trigger`, `fluids/fluidhost.gDims`, `physwire/*`, `physics/windfield` | move into `World` (one owner per world) |
| Global RNGs | `gLootRand`, `gSpawnRand`, `gEntityRandomState`, `weatherRandomState`, `explosionRandomState`, `gRngState` (block prelude), item-stack RNGs | one stream per world (also needed for determinism) |
| Ambient "current X" parameters | `gMetaTarget`, `gSourceOverride`, plugin `gCurPlayer`/`gEvName`/`gScope` | thread-local or passed explicitly |
| Lazy tables with no lock | `generated/registry`, `generated/tag`, `block_properties` lookups, loot caches, `physics/materials.gInit`, `chunk_data.biomeRemaps` | prewarm at start-up (generation already does this for its own) |
| Hook slots | about 58 `gPlugin*Hook`, 75 `gPrev*` chains, entity hooks | read-only while ticking; hot reload applies between ticks |
| Profiler / replay / logger | one global scope stack, `gRec`, `logger` | per-thread buffers merged at tick end |
| Plain-field "locks" | `ChunkData`, tick schedulers | real ownership rules (phase 4/5) |
| Datapack and recipes | `datapack.gBase*`, mutable `generated/recipes` | `/reload` only between ticks |

## 4. The design

Two kinds of parallelism, deliberately kept separate:

**A. Offload (job pool).** Pure compute: input is a snapshot, output is a result, the tick thread applies it. No shared mutable state, so no locking
inside the job and no change in behaviour. This is what generation already does. Applies to: chunk serialisation and compression, saving, chunk
packet build and compression, region relighting, physics solver and erosion runs, pathfinding queries, mob-awareness scans.

**B. Simulate in parallel (ownership).** Several parts of the world tick at once. Safe only when each thread owns the data it writes:
1. **per dimension** (overworld, nether, end): independent except portals;
2. **per region inside a dimension**, with declared footprints: a tick job says "I touch chunk (x, z) and a margin"; the scheduler runs disjoint
   footprints together (`sim/regions.aowl planPhases` already computes the 4-colour tile plan), and anything that crosses a border is a queued message
   handled in a border phase. Code inside a job stays ordinary single-threaded code.

One pool, not several: the existing generation pool is generalised into the job pool (agreed with the chunk-system owner), and `threads` feeds it.

## 5. Thread configuration (including singleplayer)

```
threads = 0          # in minecraft-server.toml: 0 automatic, 1 everything on the tick thread (today's behaviour), N = the tick thread plus N - 1 workers
reserved_cores = 2   # automatic leaves this many cores to the rest of the machine (the game's renderer, in singleplayer)
```

* Automatic = `cores - reserved_cores`, at least 1, at most 16 for now (chunk generation workers: at most 8, measured: 8 vs 4 gives about 10 % at 65x65 because the tick thread is the limit); `cores` from `countProcessors()`. A dedicated server sets `reserved_cores = 0`. `threads` counts the tick thread too, so `threads = 1` is the inline configuration the determinism tests compare against.
* Precedence: env `MC_CHUNK_WORKERS` (kept; counts workers) > env `MC_THREADS` (counts threads, 0 = automatic) > config. The launcher keeps working unchanged.
* One resolved number feeds the pool; per-phase shares (generation, io, sim) are derived from it, not separate knobs, until measurement says they need to be.
* Optional later: `pin_threads`, worker priority below normal in singleplayer.

## 6. Phases

Each phase lists what changes, who owns the files, how it is verified. "Gate" = must hold before the next phase.

**Phase 0: measure and make safe (no behaviour change)**
* `threads`/`reserved_cores` config and the pure resolver (`src/server/sim/threadcfg.aowl`), with tests. **Done in this change.**
* `profScope` around the unscoped tick parts (bodies, fluids, fire, erosion, climate, body sync) and ScLighting/ScGeneration; capture a `/profile export` baseline on a busy world. *(server/ticker and physwire files: coordinate.)*
* Fix the stale "refcounts are not atomic" comments. Make `stopFlag` atomic.
* Prewarm the lazy tables at start-up (registry, tags, loot, block properties, materials, biome remaps) before any worker starts.
* Per-world RNG streams (loot, spawn, entity, weather, explosion, block prelude): same seeds, one per world.
* Gate: baseline numbers recorded; scenario suite identical.

**Phase 1: one job pool (offload)**
* Generalise `generation_executor` into `sim/jobpool`: typed jobs with an owner handle, result queue per owner, never-raise job bodies, a stop/drain protocol, stats (`MC_GEN_STATS` becomes pool stats), `threads` from section 5. Generation keeps its API.
* Move onto it, one at a time, each behind the same `threads = 1` inline fallback: chunk save serialise+compress; outgoing chunk packet build+compress; region relight (snapshot of the lit volume); `physics` solver/erosion runs (already pure); pathfinding (snapshot of nearby blocks).
* Gate per item: bit-identical result for threads 1 vs N (generation `genhash`, world save hash, packet bytes), scenario suite with `MC_CHUNK_WORKERS=0` and `4`.

**Phase 2: state ownership**
* Move `gWorlds` entity lists, body/trigger/fluid/fire/climate/erosion state, fight and map managers into `World`.
* Replace ambient parameters with explicit arguments or thread-locals; per-thread profiler/replay/logger buffers.
* Plugin hooks: one serial lane. Hooks fire on the tick thread only; code running on other threads queues events.
* Gate: no behaviour change at threads = 1; a debug build that asserts "this global is only touched from its owner thread".

**Phase 3: network off the tick thread**
* Per-connection read/decode and encode/compress/encrypt on pool workers (upstream does this on its `compute_pool`); packet handlers still run on the tick thread so world code stays single-owner.
* Gate: ping/latency scenario, 50-bot join test, byte-identical streams for a fixed input.

**Phase 4: one thread per dimension**
* Each `World` ticks on its own thread with a barrier at tick end; portal / teleport / cross-world entity moves become messages applied in a join phase.
* Gate: determinism (nether + overworld ticking together gives the same state as sequential), portal scenarios, no data race flagged by the owner-thread asserts.

**Phase 5: regions (footprint scheduler), opt-in**
* Tick jobs per tile with declared footprint and margin (1 chunk for fluids/redstone/fire, mob-AI radius for entities); 4-phase colouring from `planPhases`; border operations (explosions, pistons across a boundary, mobs crossing) deferred to a border phase or run with a widened footprint.
* Debug mode checks that a job only touched what it declared.
* Gate: soak test with redstone, fluids, TNT and mobs across region borders, state hash equal to the sequential run.

**Phase 6: plugins on other cores (optional)**
* After native plugin images exist, an engine job primitive (`aoe_job_*`, proposed by the ENGINE side) for compute-only plugin work. Not needed for the server itself.
* Server side done as `sim/plugjob.aowl` (on `sim/jobpool`): per-plugin owner handle, `submitPlugJob` / `pollPlugJobs` on the tick thread, results applied only in the poll and strictly in ticket order, in every mode (threads = 1 runs the job inline but still delivers on the next poll). Sized by `planThreads`. Job bodies must not call setBlockState, run hooks or touch World/Entity; under `MC_THREAD_ASSERT=1` `assertOwner` now also flags calls made from inside a job body (inline included). The plugin-facing ABI is defined in `docs/PLUGIN_JOBS.md`: because plugin code cannot run off the engine's thread, the "engine ABI" is the host calls `job_submit` / `job_status` / `job_pending` / `job_abi_version` and the `on_job` entry (names follow the existing `schedule_*` / `event_*` host calls rather than a new C export), over server-owned kernels (`fnv1a`, `primes`, `sort`); `enginejobs.aowl` registers each plugin, `tickPluginManager` polls once per tick, unload and `stopPluginManager` drain.

## 7. Verification strategy

* **Determinism harness**: run the same scripted session (bots, commands, a fixed seed) with `threads = 1`, `2`, `8` and compare a hash of the saved world and of the packet stream. Any difference blocks the phase.
* **Debug assertions**: owner-thread checks on per-world state, lock-order assertions, footprint checker (phase 5), "no job touches the world" check in the pool.
* **Stress**: many bots, many chunks, repeated start/stop with workers (shutdown drains, no stuck `inFlight`), and a TNT/redstone soak.
* **Profile before and after** each phase on the same world (`/profile export`); a phase that does not improve MSPT or is not neutral in correctness is reverted.

## 8. Risks and decisions needed

* **Hidden shared state.** The audit counted globals, not every access path; the first threads will find more. The owner-thread assertions are there for that.
* **Plugins and hooks fire inside block and entity code.** Until phase 2 gives them a serial lane, nothing that runs a hook may leave the tick thread.
* **Lighting and block-update chains cross chunk borders**; relighting as a job needs a snapshot with a margin, and a job that falls behind must not let the world read stale light.
* **Windows**: one processor group (64 logical CPUs) is the limit of `countProcessors`; fine for now.
* **Ownership of the code**: `world/chunk_system`, `world/generation`, `physics`, `server/world/bulkedit` belong to the chunk-system/physics owner. Phases 1 to 5 touch them; the change lists go to that owner first and land after their open branches.
* **Decision for the user**: how many cores the singleplayer server may take by default (this plan says leave 2), and whether region sharding (phase 5) is wanted at all or phases 1 to 4 are enough.

## 9. Status

| Item | State |
|---|---|
| This plan | written |
| `threads` / `reserved_cores` config + resolver (`sim/threadcfg.aowl`) + tests | done, tests pass (threadcfgtest, libtest) |
| Wiring the resolved count into `generation_executor` | needs the chunk-system owner (change list sent) |
| Stale "refcounts are not atomic" comments in docs and sim/regions | fixed (pumpkinlib header: with the chunk-system owner's batch) |
| Phase 0: atomic stopFlag, prewarmAll, weather RNG per world, thread-local entity/block/durability RNGs, atomic item-stack ids; job pool and owner guard modules (sim/jobpool, sim/ownerguard) | done, built and scenario-run (worldedit_wand and create_live failed once in the full run and passed on rerun; no baseline to prove flaky) |
| Loot and spawner RNG per World | done (full build, scenarios 14 pass); explosion RNG thread-local (explosiontest passes); materials prewarm after reload: `prewarmMaterials()` in physics/materials, rerun by loadMaterialOverrides/clearMaterialOverrides (materialstest: 3 concurrent readers do no fill, 42 checks pass; not exercised through a real pack reload in a running server) |
| Phase 2 steps 1-3: thread-local ambient params, entities stored on World, worldFluids accessor | done (full build, scenarios 14 pass) |
| Phase 3 step 1: optional Java encode worker (sim/netencode, MC_NET_WORKERS=1 and workers>0; default off) | byte-identical encode test passes; scenarios equal baseline off, flaky worldedit/create_live with it on (pass on rerun); not load-tested; playtest signature assertion fails on origin/main too |
| Phase 3 step 2: optional decode worker (sim/netdecode, armed at Play, same gate, default off) | equivalence test passes (17 checks); scenarios equal baseline off; not shown armed in scenarios, not load-tested |
| Phase 1 (e) step 1: snapshot-backed PathfindingContext + computePathWith (live path unchanged) | 320 snapshot-vs-live path comparisons identical; scenarios equal baseline except flaky worldedit_wand (pass/fail across reruns); no job yet |
| Phase 1 (e) step 2: path search as a pool job (MC_PATH_WORKERS=1 and workers>0, default off, applied next tick in every mode, stale results dropped) | 96 identical-path cases at 0 and 3 workers, stale-drop test; no scenario spawns a pathing mob so the live job path is unexercised; create_live is timing-flaky with and without the flag; snapshot cost (about 105k cells per submit) unmeasured |
| Phase 1 (d) erosion as one pool job (`physwire/erosionjob`, wired in erosionwire; MC_EROSION_WORKERS=1 and workers>0, default off, shares the pool via `jobpool.sharedJobPool` (own owner id from `allocOwner`), applied on the tick the stepwise run would finish, applyJob + stale guard on the tick thread) | erosionjobtest: 6 seeds, digest of changes/bodies/steps/ops equal for the stepwise loop, inline job and a 2-worker pool; erosiontest/scenetest still pass. The erosionwire wiring and `/erosion run` with the flag on were only compiled, not run against a live server; no Background lane (shared FIFO with path jobs); a worker slower than `steps` ticks applies later (timing, not content); the solver job is not done |
| Phases 1 to 4 change lists | written (docs/MULTITHREADING_PHASES.md) |
| Worker count from the thread plan + never-raise workers | prepared on top of the chunk chain (branch mt-items-1-3), not pushed |
| Phase 1 (f): `generation_executor` on `sim/jobpool` (branch mt-gen) | `jobpool` has lanes (`lnUrgent`/`lnNormal`/`lnBackground`, per-lane FIFO, a worker takes the lowest non-empty lane; `submitLane`, `laneDepth`; `submit` = Normal). Generation and decode batches are Normal jobs, LOD summaries Background (taken only when Urgent+Normal are empty), per-handle done lists kept, job bodies never raise (generation failure -> `GenerationFailure`). Worker count from `planThreads(...).chunkWorkers` when MC_CHUNK_WORKERS or MC_THREADS is set (unset stays 0 = inline). **Pool decision: one shared pool per process**; generation claims it via `sharedJobPool`/`allocOwner`; a later `newJobPool` with workers while one is live is refused (inline pool, printed, counted in `refusedPools()`); path/net/plugin users were not converted to `sharedJobPool`, so with those gates on and generation on they run inline. If one of them wins the race to create the pool, generation joins it and gets its (smaller) size. jobpooltest (lane order, refusal, shared pool, owners) and generationexecutortest (inline vs 4 workers, block-for-block) pass; genhash itself is inline-only and does not exercise the executor. Not verified: full server build, scenarios with MC_CHUNK_WORKERS=0 and 4, lod lane under load, throughput vs the old executor (extra task-table lock per job), `MC_GEN_STATS` idle time is gone |
| Wiring jobpool into phases 2 to 6 | other items still waiting |
| Phase 5 (generic part): footprint scheduler `sim/regionsched` (`runRegionTasks`: tasks with a home chunk and margin, `planPhases` 4-colour phases, one pool job per tile, join between phases, results merged in task-id order, inline at threads<=1, sized by `planThreads`) | regionschedtest passes (300 synthetic overlapping-footprint tasks: identical world hash and results at threads 1, 2 and 4 over 5 reps each, atomic per-chunk occupancy check saw no concurrent overlap, same-tile tasks serial, raising bodies contained, unsafe tile size refused); jobpooltest still passes. Not wired to anything: running real tick work through it needs phase 2 steps 4-6 (per-world state) and phase 4, plus the footprint-declaration audit per system (fluids/redstone margin 1, mob AI radius) and a border phase for explosions/pistons/mobs crossing; the occupancy check is a test helper, not a runtime debug assertion that a body stayed inside its footprint; no soak test, no speedup measured (the test body is synthetic) |
| Phase 6 (server side + plugin wiring): plugin job primitive `sim/plugjob` and its plugin glue `plugin/engine/enginejobs` (host calls `job_submit`/`job_status`/`job_pending`/`job_abi_version`, `on_job` entry, JS and aowlmony SDK helpers, `examples/jobs-js`, `docs/PLUGIN_JOBS.md`) | plugjobtest passes (300 jobs equal at threads=1 and 4, ticket order, nothing before poll, two plugins isolated, failed jobs, guard flags a world touch in both modes); enginejobstest passes (34 checks at threads=1 and 4, also with MC_THREAD_ASSERT=1: kernels, delivery only after poll, per-plugin order, unload drops, shutdown); host calls and `on_job` through a real JS plugin on aoe_engine.dll pass (enginejobhosttest; engineplugintest still passes); `stopPluginManager` is not called by the server's stop path yet (servermod is outside this lane); the aowlmony SDK `runJob` only compiles (no native plugin image built or run); off by default (`MC_PLUGIN_JOBS=1` for workers), not part of the full server build, no load test, cannot share a worker pool with path jobs or net encode |
