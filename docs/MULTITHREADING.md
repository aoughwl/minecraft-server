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
| Phase 1 (a) chunk save compress job (`ChunkSerializer.compressionHint/compress/applyPrepared` split of `update_chunk`; `sim/savepool`, MC_SAVE_WORKERS=1 and workers>0, default off): `saveGeneric` serialises on the caller, compresses one region file's chunks on the pool, joins, applies in chunk order, then `writeOf` on the caller | savejobtest: region files byte-identical (timestamp page masked) vs inline at 0 and 3 workers, in-place and whole-file configs, first write and rewrite with changing sector counts; chunk io/anvil tests rerun. `writeOf` stays on the caller (no per-region write lane yet, so no write overlap), only the compress overlaps; only the anvil serializer has the split (linear/pump formats stay inline); no server build, no load test, no speedup measured; exclusive with MC_NET_WORKERS/MC_PATH_WORKERS/MC_PLUGIN_JOBS in one process (jobpool allows one worker pool) |
| Phase 1 (b) chunk packet compress job (`packet_encoder.compressFrame`/`appendFrame` split, `sim/pktslots` ordered per-client slot list on the shared net pool, MC_CHUNKPKT_WORKERS=1 and workers>0, default off) | pktslotstest: bytes equal the inline encoder at 3 workers for 3 connections with compression and encryption switched on mid-stream (see test results in the commit). NOT wired into JavaClient (`sendPacketNowData` does not know which packets are chunk packets; the MC_NET_WORKERS lane already compresses every packet off-thread and takes precedence); no server build |
| Phases 1 to 4 change lists | written (docs/MULTITHREADING_PHASES.md) |
| Worker count from the thread plan + never-raise workers | prepared on top of the chunk chain (branch mt-items-1-3), not pushed |
| Phase 1 (f): `generation_executor` on `sim/jobpool` (branch mt-gen) | `jobpool` has lanes (`lnUrgent`/`lnNormal`/`lnBackground`, per-lane FIFO, a worker takes the lowest non-empty lane; `submitLane`, `laneDepth`; `submit` = Normal). Generation and decode batches are Normal jobs, LOD summaries Background (taken only when Urgent+Normal are empty), per-handle done lists kept, job bodies never raise (generation failure -> `GenerationFailure`). Worker count from `planThreads(...).chunkWorkers` when MC_CHUNK_WORKERS or MC_THREADS is set (unset stays 0 = inline). **Pool decision: one shared pool per process**; generation claims it via `sharedJobPool`/`allocOwner`; a later `newJobPool` with workers while one is live is refused (inline pool, printed, counted in `refusedPools()`); after integration every user takes the pool from `jobpool.sharedJobPool` and an owner id from `allocOwner` (path, erosion, light, save, net encode/decode/packet slots, plugin jobs per plugin handle; no fixed owner ids remain), so all gates can be on together; whoever creates the pool first sets its size (`liveWorkerPool()` only queries). jobpooltest (lane order, refusal, shared pool, owners) and generationexecutortest (inline vs 4 workers, block-for-block) pass; genhash itself is inline-only and does not exercise the executor. Not verified: full server build, scenarios with MC_CHUNK_WORKERS=0 and 4, lod lane under load, throughput vs the old executor (extra task-table lock per job), `MC_GEN_STATS` idle time is gone |
| Wiring jobpool into phases 2 to 6 | other items still waiting |
| Wiring jobpool into generation_executor, phases 1 to 6 | waiting on the chunk-system owner's branches reaching main |
| Phase 1 (c) relight: step 1 snapshot-backed `LightLevelAccess` (`world/lightsnapshot`: copy of the loaded chunk columns of box + shell + one chunk margin, closures over the copies, cell diff, apply refuses a stale snapshot); step 2 region relight as a pool job (`sim/lightjob`: `submitRelight`/`pollRelights`/`drainRelights`/`relightPending`; applied by the poll after next in every mode, overlapping regions held in order, a stale or failed result is dropped and relit live; MC_LIGHT_WORKERS=1 and workers>0, default off, reuses the path pool when live; wired into `bulkUpdateLighting` and the start of `flushBlockUpdates`) | lightingruntimetest: snapshot relight equals live relight on 18 random edits (7123 changed cells) and a stale snapshot is refused; lightjobtest: job light equals inline light for 8 non-overlapping edits (0 conflicts) and 10 overlapping ones (6 applied, 4 conflicts relit live, 9 held), per-tick light hashes identical at 0 and 3 workers; bulkedittest builds with the wiring (gate off). NOT shown: the gate on in a real server or scenario (no full build), speedup (snapshot copies whole columns of up to (w+4)^2 chunks per region, unmeasured), mob-spawn/other readers do not yet consult `relightPending`, single-cell `updateLighting0` calls stay inline (a job result they invalidate is dropped, not merged), chunk save and shutdown do not yet call `drainRelights`, the net/plugin pools are not shared with it |
| Phase 5 (generic part): footprint scheduler `sim/regionsched` (`runRegionTasks`: tasks with a home chunk and margin, `planPhases` 4-colour phases, one pool job per tile, join between phases, results merged in task-id order, inline at threads<=1, sized by `planThreads`) | regionschedtest passes (300 synthetic overlapping-footprint tasks: identical world hash and results at threads 1, 2 and 4 over 5 reps each, atomic per-chunk occupancy check saw no concurrent overlap, same-tile tasks serial, raising bodies contained, unsafe tile size refused); jobpooltest still passes. Not wired to anything: running real tick work through it needs phase 2 steps 4-6 (per-world state) and phase 4, plus the footprint-declaration audit per system (fluids/redstone margin 1, mob AI radius) and a border phase for explosions/pistons/mobs crossing; the occupancy check is a test helper, not a runtime debug assertion that a body stayed inside its footprint; no soak test, no speedup measured (the test body is synthetic) |
| Phase 6 (server side + plugin wiring): plugin job primitive `sim/plugjob` and its plugin glue `plugin/engine/enginejobs` (host calls `job_submit`/`job_status`/`job_pending`/`job_abi_version`, `on_job` entry, JS and aowlmony SDK helpers, `examples/jobs-js`, `docs/PLUGIN_JOBS.md`) | plugjobtest passes (300 jobs equal at threads=1 and 4, ticket order, nothing before poll, two plugins isolated, failed jobs, guard flags a world touch in both modes); enginejobstest passes (34 checks at threads=1 and 4, also with MC_THREAD_ASSERT=1: kernels, delivery only after poll, per-plugin order, unload drops, shutdown); host calls and `on_job` through a real JS plugin on aoe_engine.dll pass (enginejobhosttest; engineplugintest still passes); `stopPluginManager` is not called by the server's stop path yet (servermod is outside this lane); the aowlmony SDK `runJob` only compiles (no native plugin image built or run); off by default (`MC_PLUGIN_JOBS=1` for workers), not part of the full server build, no load test, cannot share a worker pool with path jobs or net encode |
| Phase 2: collapse trigger queue per world (`trigStateOf(world)`, `body/trigger.aowl`) | done, `worldstatetest` passes. Queue, rate buckets, scan budget and starts per tick are per dimension. Built cells, block log tiles, cracks, wind timers and stats are still module wide (keyed by dimension) |
| Phase 2: bodies per world (`bodiesOf(world)`, `body/bodymanager.aowl`) | done, `worldstatetest`, `bodytest`, `createworldtest`, `replaytest` pass. Body ids and uuids are global and atomic (`atomicFetchAdd`). `gBodies` is gone. `maxAwake`/`maxCells` and the round robin cursor now apply per world (same with one world). Still module wide: event and fx feeds, stats, collapse jobs, the one collision provider (answers for all worlds), journal replay list |
| Phase 2: fire regions per world (`physwire/firewire.aowl`, `fireRegions(world)`) | done, `worldstatetest` passes. `gStats` (and the region seed counter) stays module wide; climatewire still samples worlds[0], erosionwire is still one job |
| Phase 2: the other items (entity lists, fluids, climate, erosion, fight/map managers, ambient parameters, per thread profiler/replay/log buffers, the plugin hook serial lane, owner-thread asserts) | not started |
| Phase 4: per-dimension tick on the shared pool with a join phase (`sim/dimtick`, wired in `servermod.tickWorlds`; `MC_DIM_THREADS=1` AND `planThreads` workers > 0, default off = the sequential per-world loop exactly) | See "Phase 4 status" below. dimticktest: a synthetic 3-world scripted workload (per-world state, a portal message every 5th tick, a second message every 7th, one hook event per world per tick) gives identical state digests after every one of 120 ticks with the gate off, on with 1 worker, on with 4 workers and on an inline pool; the gate refuses a non-queueable hook consumer; the owner guard flags a hook fired from, and a wrong-world touch inside, a dimension job. blocklogdimtest: the block log written from 3 worlds on 4 workers equals the sequential log. `servermod` and the changed modules pass `aowlmony check` (semantic check only, no code generation). NOT done: a full server build, a scenario run, any run with a real world tick on worker threads, any speedup measurement |
| Phase 5 wiring: random-tick scan on the region scheduler (`sim/regionphase`, `level.drawRandomRolls`/`scanRolls`, `worldmod.tickChunks`, `MC_REGION_THREADS=1`, default off) | See "Phase 5 status". regionphasetest passes: identical digests and world hash gate off, 0, 1 and 4 workers; footprint guard in `ownerguard`. Other per-chunk systems audited and refused. No speedup expected, no server build run |
| Multi-gate stress test (`sim/multigatetest`) | passes (built on its own nimcache; 100 rounds seed 20260101, 150 rounds seeds 1 and 2, 100 rounds seeds 3 to 5; about 160k pool jobs per 100 rounds). On ONE shared pool with 4 workers the tick thread steps a seeded random interleaving of: generation-style Normal jobs, a Background (LOD-like) stream, Urgent jobs, lane-priority probes, 3 net encode lanes (real `netencode`, bytes compared with the inline encoder, compression and encryption switched on mid-stream), save compress batches (real `savepool` on the real Anvil `compressChunkBytes`, compared with inline `compressOf`), 3 plugin handles (real `plugjob`: ticket order, values, raising jobs flagged failed), region scheduler runs under a fresh owner each (real `regionsched`, equal to the threads=1 world hash and results), an erosion run every other round (real `erosionjob`, digest equal to the stepwise loop), a light relight scenario every 10th round (real `lightjob`, final light equal to the inline relight, 8 applied, 0 conflicts) and path-like jobs (a synthetic BFS body submitted on `pathpool`'s pool: the real search needs the entity stack). Asserted per round: each user equals its single-user/inline result, `liveWorkerPool()` is the one pool with 4 workers and `refusedPools() == 0`, `completed == submitted`, failed jobs == the raisers submitted, lanes empty. Lane priority: a deterministic test (all 4 workers held, 120 jobs submitted scrambled, start ranks checked against the lane order within a worker's slack) and about 1600 probes per 100 rounds that jump a Background backlog (only about 20 of them meet 40 or more queued Background jobs; worst observed: 6 Background starts between probe submit and probe start, bound 2W = 8). Also: three helper threads submitting to and draining their own owners while the tick thread works (the pool lock holds; the "owner thread only" note in jobpool is a convention, not a requirement), shutdown of the shared pool with 800 queued jobs and 3 net lanes with queued packets (all finish, results intact), 40 fresh pools shut down with random queued jobs (workers joined, `liveWorkerPool()` cleared, a later `submit` runs inline), and a deliberate second `newJobPool` is refused and counted. Mutation check: reversing the lane order in `nextLane` makes the gate test and the probes fail. No bug was found in `sim/*`. NOT covered: the real pathing search (synthetic body), `pktslots`, `netdecode`, `dimtick`, `regionphase` and the generation executor on the same pool; one tick thread is the only submitter for the real modules (the helper threads use synthetic bodies); a full server was not run |
| Pool speedup, measured (`sim/poolbench`, synthetic, not a gate) | Machine: 20 logical processors (a desktop part, SMT on; the benchmark does not know the physical core count), Windows, gcc build, one run (best of 5 per point, medians within 5 to 35 percent of the best, so treat figures as +-10 percent). The submitting thread only submits and drains (it spins with Sleep(0)), so it also occupies a core. **zlib level 6 of a 64 KiB buffer** (847 us per job in a plain loop): inline 1.03x, 1 worker 1.03x, 2 workers 1.99x (1 211 -> 2 351 jobs/s), 4 workers 3.79x (4 467 jobs/s), 8 workers 5.87x (6 926 jobs/s, 71 percent efficiency). **Light-like flood fill, 48x48x24** (177 us per job): 1 worker 1.02x, 2 1.87x, 4 3.84x, 8 5.84x (32 981 jobs/s). **Pool overhead per job**, an empty job through submit/take/finish/drain: 0.08 us inline, 0.24 us at 1 worker, 0.38 at 2, 0.49 at 4, 1.89 at 8 (the one pool lock is contended at 8); for jobs of 100 us and more that is below 2 percent at 4 workers, and the 1-worker pool matches the plain loop within 3 percent. Reading: scaling is near linear to 4 workers, sub-linear at 8 (memory allocation and the single task-table lock, plus the tick thread's own core). NOT measured: jobs of a few microseconds (the lock cost dominates there, do not submit those individually), the server under load, the effect on tick time, and a machine without SMT. `drainDone` is O(finished results) under the lock, so one huge undrained backlog (the bench drains 20 000 at once) costs more than the same number drained every tick |
| Everything else | not started |

The state slots are `World.trigState`, `World.bodyState`, `World.fireState` (`nil RootRef`, typed by the owning module because serverbase sits below it). Nothing here is checked from other threads yet: with `threads = 1` it is the same single-owner code, and no owner-thread assert exists until the phase 2 gate item is done. The server wiring (`servermod`) was not changed; a full server build and the scenario suite have not been run for these three changes.

## Phase 4 status (what is implemented, what refuses, what is left)

**Shape.** `sim/dimtick.aowl` knows nothing of `World`: a dimension is an index and the tick body a closure. `servermod.tickWorlds` calls `dimGateNow` every tick (plugins can be loaded and players can move at run time). Only when it answers `dgOn` does it run `tickWorldsThreaded`: one `worldmod.tick` per world as a job on the shared pool (`jobpool.sharedJobPool`, owner id from `allocOwner`, Urgent lane; no second pool is ever created), the tick thread waits at a barrier (a `drainDone` loop that yields), applies the queued messages, then runs the server-level ticks (bodies, create, triggers, fluids, climate, fire, erosion, body sync, lod sync, player data) as before. Anything else runs today's loop unchanged.

**The gate refuses (stays sequential, prints the reason once per change) when:** `MC_DIM_THREADS` is not `1`; the thread plan has no workers (or the shared pool has none); fewer than two worlds; a hook consumer registered with `registerHookConsumer(name, queueable = false)`; any plugin is loaded (`loadedPluginCount() > 0`: every plugin is a consumer of cancellable events such as BlockChangeEvent, which cannot be deferred); players are in more than one world (see the shared state below).

**Messages and their order.** `postCross(kind, closure)` / `postHookEvent(closure)`: outside a dimension job the closure runs at once (so with the gate off nothing changes); inside one it goes to that world's outbox and the join phase runs the outboxes world ascending, post order within a world. The order depends only on the world index and the code path, never on which thread ran which world, so 1 worker and N workers agree (tested). It is not the sequential order in general: a message acts at the end of the world phase instead of in the middle of the world's tick (the synthetic test is written so that this does not show; a real portal transfer happens one phase later than it did).

**Converted to messages:** portal transfer (`portal/portalmod.tickPortal`: destination search/build, `teleport`, passengers), player dimension change (`worldmod.teleportWorld` and `respawnPlayer` defer themselves when called from a dimension job), the death message broadcast over all worlds (`entitymod.broadcastDeathMessage`), the advancement broadcast over all worlds (`advancementglue`, `broadcastSystemMessage`), the block log record (`blocklogcore.blockLogRecordChange`, with the thread's cause/actor context captured; the actor name is interned at the join so actor indices come out in world order) and the replay tap that rides on it, and the trigger notification of `setBlockState` (`gTrigChange`).

**Shared state, fixed:** the entity id allocator is atomic (`entitymod.reserveIds`, `servermod.addPlayer`; which id a world gets depends on timing when two worlds spawn at once, ids are never compared across runs); the profiler scope stack is not touched from dimension threads (`profIgnoreThisThread`: worker time shows up inside the tick thread's `ScTickWorld` barrier scope, there are no per-thread profiler buffers); the block log keeps its plain global context for the tick thread and uses a separate thread-local one only inside dimension jobs (gate off touches only the plain one); `gPortalManagers` takes its lock only inside a dimension job; the owner guard has `enterDimJob`, `assertWorldThread`, and `assertOwner` now flags tick-thread state touched from a dimension job (`MC_THREAD_ASSERT=1`), plus `dimtick.assertWorldOwned` (per-world `Owned` token claimed by the job). The entity/block/explosion/durability RNG streams are thread-local and clock seeded: they were never reproducible, so which worker runs a world changes nothing that was deterministic before.

**Shared state, NOT fixed (the reason for the player rule):** the id-keyed per-player tables `entitymod.gPlayerBases`, `gExperienceDelays`, `player.gPlayerStats`, `gPlayerPoses`, `gPlayerDisplayNames` are plain tables mutated from player ticks; they are only safe while one world at a time has players, which is what `dgPlayers` enforces (a world with players next to empty worlds is allowed). Not audited at all: every other module-level `var` reachable from entity AI, block behaviours, mob spawning and the loot bridge (about 600 module vars exist, section 2). The way to find them is to run with the gate on and `MC_THREAD_ASSERT=1`, which has not been done. `levelsync` and `climatewire` read `worlds[0]` but run on the tick thread after the barrier, so they need no change; reads of `server.worlds[0]` from inside a world job (for example `tickEnvironment`) were not checked. The tick thread is idle while worlds run (it does not tick a world itself), and if all pool workers are held by long generation jobs the barrier waits for them (dimension jobs go on the Urgent lane but do not preempt).

**Cross-world sites NOT converted** (still reach another world directly; each is reached from the tick thread today, or only on paths the gate refuses): `commandbridge` command execution and `/tp` into another world (network pump, tick thread); `command/execute` with `gSourceOverride`; the Jester `bodysync`/`lodsync`/`windsync` loops over `worlds` (server level, after the barrier); `respawn.calculateRespawnPoint` reading another world's block (called from `respawnPlayer`, which is deferred as a whole); `worldedit/weworld` and `bulkedit.aowl:293` (BlockChangeEvent hook of bulk edits: the chunk-system owner's file, tick thread only); `bodymanager` and `trigger` loops over all worlds (after the barrier); `pregen`, `replay`, `player_server` save loops; the plugin host calls that reach into a named world (tick thread, and loaded plugins keep the gate shut); Bedrock play paths.

**Hook sites that can still fire from a world thread:** with the gate on there is no plugin loaded, so the plugin event hooks reachable from block/entity code (cropmod BlockGrowEvent, pressure plate BlockRedstoneEvent, `setBlockState` BlockChangeEvent, entity event hooks) are the do-nothing defaults or `pluginBlockChangeListened()` is false; WorldEdit's and the datapack tick hooks only fire from the network pump or the tick start. Loading a plugin at run time makes the next tick fall back to the sequential loop. `setBlockState` asserts (guards on) if the cancellable hook is reached from a dimension job. Hot sites converted to `postHookEvent`-style queueing: the block log and trigger notifications of `setBlockState`. Other hook sites (crops, hoppers, furnaces, pistons) were not converted: their events are cancellable or return a value, so they are covered by the plugin rule only.

**Verification still owed:** a full server build; the scenario suite with `MC_DIM_THREADS=1 MC_THREADS=4` on an overworld+nether world including a portal scenario and `MC_THREAD_ASSERT=1`; a state-hash comparison of saved worlds between the sequential and the threaded loop; behaviour when pool workers are busy with generation; measured MSPT (with one idle nether the gate may well be slower than the sequential loop).

### Phase 4 scenario evidence (full build of mt-int, honest)

With every gate off, `worldedit_more` and `fluids_finite` failed solo on the phase 4 build, and also on a build of aeeeaa7 (the same tree without phase 4), with varying failure messages: so the phase 4 commit is not their cause; they are timing-sensitive (`worldedit_more` hits the once-per-tick tool guard in `wecmd.useTool` when the bot clicks within one tick) and passed in other full runs. With `MC_DIM_THREADS=1 MC_THREAD_ASSERT=1 MC_THREADS=4` a full scenario run gave 14 pass, 5 fail (`fluids_finite`, `create_live`, `lod_summaries`, and the two by-design pack scenarios); `create_live` and `lod_summaries` passed solo with the gate off; final build of mt-int (with phase 5): default settings 15 pass / 4 fail (`worldedit_more`, `fluids_finite`, and the two by-design pack scenarios); `worldedit_more` then passed and failed on the identical configuration minutes apart, so it is a flake in this environment (not attributable to any gate); with `MC_DIM_THREADS=1 MC_REGION_THREADS=1 MC_THREAD_ASSERT=1 MC_THREADS=4` a full run gave 14 pass / 5 fail (`fluids_finite`, `create_live`, `lod_summaries`, the two pack scenarios), and `lod_summaries` passed solo with threads only and with both gates on. `fluids_finite` fails with and without every gate and also on the build without phase 4. No thread-assert violation line was printed in the gate-on run. Still not shown: that `create_live`/`fluids_finite` are stable at baseline on this machine, a speedup, or a run with players in more than one world. A real world tick on worker threads has therefore run only inside that one full run, with players in one world, and no speedup was measured.

### Final build of mt-int at 2e1c89b (scenario evidence)

Defaults (every opt-in gate off): 15 pass / 4 fail (`fluids_finite`, `lod_summaries`, and the two by-design pack scenarios). With `MC_THREADS=4 MC_DIM_THREADS=1 MC_REGION_THREADS=1 MC_SOLVER_WORKERS=1 MC_THREAD_ASSERT=1`: the same 15 pass / 4 fail (`phys_fell` and `worldedit_more` pass in both runs; no thread-assert violation was printed). `lod_summaries` fails differently each time (timeout waiting for a chunk / `water agrees for only 46 of 64 samples`) and passes solo: load- or timing-sensitive. `fluids_finite` failed every time on builds that contain the chunk-system chain (also with every gate off and without phase 4) while the origin/main build passed it: it is not attributable to the multithreading work and needs the chunk-chain owner. Not run: `bodytest` against the solver job (its build did not finish in time), anything with a real player in two worlds, the solver job's worker path in a live server.

### Phase 4 with real players in two worlds (live, mt-int)

`sh tools/run_dim_threads.sh <exe>` (scenario `dim_threads_two_worlds`: two operator bots, one in the overworld, one sent to the nether, 40-60 block edits each at the same coordinates, cross-world `execute in <dim> if block` queries, a repeating command block, keep-alives, a fresh login at the end). On the final build with `MC_DIM_THREADS=1 MC_DIM_PLAYERS_MULTI_WORLD=1 MC_THREAD_ASSERT=1 MC_THREADS=4 MC_CHUNK_WORKERS=4`: both bots passed all stages, the log printed `dimtick: dimension threads on` once, no `world tick(s) raised` line and no `owner guard:` line (the server now prints guard violations from the tick, `reportGuardViolations`, only when the count changes, so silence means zero; the reporter itself was not shown firing in a live run, only in `dimticktest`). Gate off also passes; without `MC_DIM_PLAYERS_MULTI_WORLD` the gate closes with players in two worlds. Not covered: portal entry, saved-world hash comparison, any speedup, long soak (each run is under a minute), runs with the pool busy generating chunks.

### Phase 4: portal entry, saved-world comparison, soak (live, mt-s1, prebuilt exe, no server build)

Tools: `tools/run_dim_portal.sh` (scenario `dim_portal`: build an obsidian frame with `nether_portal[axis=x]` blocks by `/fill`, WALK into it with real position packets, arrive in the nether through `portalmod.tickPortal`, check the destination portal, walk into it, arrive back; a second bot sits in the nether and edits), `tools/run_world_hash.sh` + scenario `det_world` + `tools/hash_world.py` (saved-world comparison), `tools/run_dim_soak.sh` (`DIM_SOAK_SECS`, working-set sampling). All with `MC_DIM_THREADS=1 MC_DIM_PLAYERS_MULTI_WORLD=1 MC_THREAD_ASSERT=1 MC_THREADS=4 MC_CHUNK_WORKERS=4` for "on".

**Portal entry, gate on:** works. Overworld to nether in 0.8 to 2.6 s per walk, nether to overworld in 1.4 to 2.6 s (11 s once with the gate off while the destination chunks generated), the destination portal is built in the nether (6 portal blocks seen by the client, and the server's `execute in the_nether if block` agrees), the return builds a NEW overworld portal (the `/fill`-built frame was not found as the return target in either mode, gate on or off; not investigated) and later trips reuse both. 3 round trips passed twice, 2 round trips twice, 55 round trips in the 19 minute soak; no `world tick(s) raised` and no `owner guard:` line in any gate-on run. Gate off: the same scenario passes (2 round trips). Not clean: one gate-on run timed out waiting for the return (40 s) once, with an earlier version of the bot walk (the walk target was a cell-border centroid); it did not repeat in about 70 later gate-on round trips and was not explained. One run died on a bot limit (the bot cannot parse a set-slot with item components). Do not use `/tp` to enter a portal: the client's confirmation of the `/tp` then races the portal's own teleport and the server kicks with "Wrong teleport id" (gate off too).

**"Wrong teleport id" kicks in the soak, NOT caused by the gate:** the long loop gets kicked from time to time right after the bot is `/tp`'d out of the return portal (the next `/tp` confirm arrives while another teleport id is awaited). It happened with the gate on (trip 13 of run 1, trip 43 of run 2), with everything off (trips 16 and 5, 10 minute run) and with workers on / gate off (trip 10). Cause not found (a second server-side teleport, or the confirm handler's strict id check, `play.aowl handleConfirmTeleport`); `run_dim_soak.sh` reconnects the bot and counts it.

**Saved-world comparison:** same scripted single-bot workload (seed 424242, fills, setblocks, stairs/slab, chest, furnace, `/clone`, a hollow shell, nether edits through `execute in`, `/save-all`, `/stop`), 1 world occupied, 2 loaded: gate off, workers on / gate off (twice), gate on. In every edited volume that does not depend on terrain (the bedrock deck, stone box, clone destination, cobblestone slab, glowstone/diamond tower, the carve + gold floor: 8000+ cells) all runs are cell-for-cell identical, and the nether deck/markers are identical gate on vs workers on / gate off. What differs and is NOT attributable to the gate: (a) the `/fill ... replace stone` ore volume differs between two runs with the SAME settings (1116 cells), so it is noise from the chunk's generation state when the command ran; (b) 76 grass/dirt cells (random ticks); (c) the gate-off run (no workers) missed the last nether `setblock` (chest) and generated 406 instead of about 1200 chunks, so the saved chunk SET differs with the worker count, not with the gate; (d) most saved chunks are proto chunks (`Status` carvers/features/light), whose contents differ between any two runs, so a whole-region or whole-chunk hash is meaningless here (raw region bytes with timestamps masked never matched, including for identical settings); level.dat differs in `LastPlayed` and `Time` only. The gate-on run has an `aowlmony/bodies/*.nbt` file, and so does the workers-on / gate-off run (a solver body, from `MC_THREADS`).

**Soak (gate on, 1166 s, two bots):** server alive at the end (a fresh login worked), the nether companion stayed connected the whole time (4584 edits, 73 keep-alives), 55 portal round trips, one bot kick (above), the log shows `dimtick: dimension threads on` once and nothing else. Server working set: 439 MB at the start, 2.4 GB at 6 min, 3.8 GB at 11 min, 5.7 GB at 19 min (about +270 MB/min, no plateau). Controls of 10 minutes: everything off 515 MB to 1.6 GB (plateau at the end), workers on / gate off 398 MB to 3.2 GB. So the growth follows the chunk workers (far more chunks generated and kept), not visibly the gate; a leak is neither shown nor excluded (no run was long enough to see a plateau with workers on, and the bot's far portal destinations load new areas all the time).

Not verified: any speedup, entities and mobs in the nether during the soak, Bedrock clients, a soak with a pool busy for hours, the cause of the soak kicks.

## Phase 5 status (region phase wiring, audit)

**Wired (default off):** `sim/regionphase.aowl` + `worldmod.tickChunks`. The random block ticks are split in `world/level.aowl` into three steps that `getTickData` still composes in the same order (so with the gate off the result is what it always was): `drawRandomRolls` (tick thread: the Level's single xorshift stream and `loadedChunks`; draws in active-chunk order, ticking section ascending, draw ascending), `scanRolls` (turns draws into `RandomTickSample`s: reads one chunk's block sections and constant block-state tables, writes only its own slot), `collectScheduledTicks` (mutates the chunk tick schedulers: tick thread). `worldmod.tickChunks` now runs draw, then `scanChunksOnPool` (the `regionPhase` stage), then `getTickDataWith`, then `runTickData` as before. The region phase is one `runRegionTasks` call: one task per active chunk with a ticking section, home = that chunk, margin 0, tile size 4 (one pool job per 4x4 tile, 4 colour phases, join before the apply). Samples are concatenated in task-id order, so the output is the one-pass loop's for any worker count. Apply (`runTickData`: block behaviours, `setBlockState`, hooks, block log) never leaves the tick thread, which keeps the hook lane rule.

**Gate:** `MC_REGION_THREADS=1` AND `planThreads` workers > 0, decided once, on the process's shared pool (`allocOwner` id, no second pool). Off by default: `scanChunksOnPool` answers false and the caller scans inline. Also refused from inside a pool or dimension job (it would block a worker on its own pool): with `MC_DIM_THREADS=1` the per-world `tickChunks` therefore scans inline; the two gates do not combine. A failed or unplanned run is redone inline.

**Footprint guard:** `ownerguard.enterRegionTask(homeX, homeZ, margin)` / `leaveRegionTask` / `assertInFootprint(cx, cz, what)` (`MC_THREAD_ASSERT=1`): a region task body declares its footprint and every chunk it reads/writes is checked; a task also counts as a job body, so `assertOwner` flags tick-thread state touched from it (inline runs included). Only checkable where the body calls it (the scan calls it for its home chunk); it cannot see an access that does not go through a call.

**Honest cost:** a scan is a few table reads per ticking section (`randomTickSpeed` 3 draws), cheaper than a job. Expect no speedup, possibly a small slowdown, from this workload; no measurement was made. It is the proven first user of the footprint scheduler and of the draw / scan / ordered-apply split, not a performance win.

**Audit: which per-chunk systems can have a provable footprint** (from reading `worldmod.tick`, `worldadapter.runTickData`, `level.getTickData`, `natural_spawner`, `cropmod`; not every behaviour body was read):

| System | Verdict | Why |
|---|---|---|
| Random tick sampling (scan) | SAFE, wired | home chunk only, constant tables, own slot; RNG draws kept on the tick thread |
| Scheduled block/fluid tick collection (`collectScheduledTicks`) | not safe to split | pops from chunk schedulers and edits `chunksWithScheduledTicks`; cheap; stays on the tick thread |
| Random tick bodies (`b.randomTick`: crops, grass spread, leaves decay, fire, lava, vines, ...) | NOT safe | each reads neighbours (crops: 3x3 farmland moisture, light, neighbours; spread: blocks within a few cells, possibly across chunks) and calls `setBlockState`, which fires the cancellable BlockChangeEvent hook, block log, trigger and light updates, and may schedule ticks in other chunks; the order of these effects between neighbouring chunks is part of the sequential result. Needs a read-only decision phase per behaviour (decide, return "set X to Y") plus an ordered apply: a per-behaviour rewrite, and still the footprint is per block (margin 1 chunk at borders) |
| Fluid per-chunk ticks | NOT safe | `fluidhost` finite-fluid host has module-level per-dimension state (phase 2 item 3 not done), spreads across chunk borders |
| Fire (`physwire/firewire`) | NOT safe yet | per-world regions exist (phase 2) but ticks mutate blocks across borders and spawn tick work |
| Mob spawn scan (`natural_spawner`) | NOT safe as is | reads `entitiesOf(world)` (module-level `gWorlds`, phase 2 item 2 not done), `World.spawnRand`/`getSeed()` RNG state, and spawns entities (mutating the entity list) in the same pass; a pure "candidate" split would need per-chunk derived RNG, which changes the sequences (not determinism-preserving against today's stream) |
| Light and heightmap upkeep | already off-thread by a different mechanism | `sim/lightjob` snapshot jobs (MC_LIGHT_WORKERS); heightmap updates are inside `setRelativeBlock` on the tick thread |
| Per-chunk entity AI that only reads | NOT safe | AI ticks write the entity (goals, navigation) and read live World through closures and gCollisionProviders (global mutable); pathfinding has a snapshot path (phase 1 e) but no job yet |

The next candidate with real work in it, once phase 2 steps 2 to 4 land: a per-behaviour "decide" scan for the hottest random-tick blocks (crop growth, grass/mycelium spread) returning a requested state change per sample, margin 1, applied in sample order on the tick thread. Until then phase 5 stays at this one wired workload.

**Verified:** `regionphasetest` (built and run on its own nimcache): a 10x10-chunk scripted world over 30 ticks with the gate off, on with 0 workers (inline pool), 1 worker and 4 workers (3 reps) gives identical per-tick sample digests and final world hashes; 7200 tasks, widest phase 4 shards, 0 failed, 0 guard violations; a margin-1 workload on overlapping 3x3 footprints gives identical slots at 1 and 4 workers; the footprint guard flags a deliberate out-of-footprint read. `leveltest` (getTickData unchanged results), `ownerguardtest` and `regionschedtest` re-run.
**Not verified:** a full server build or any scenario with `MC_REGION_THREADS=1`; `servermod`/`worldmod` were only semantic-checked (`aowlmony check` of servermod passes, no code generation); any speedup; behaviour under `MC_THREAD_ASSERT=1` with a live server.
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
| Phase 1 (d) erosion as one pool job (`physwire/erosionjob`, wired in erosionwire; MC_EROSION_WORKERS=1 and workers>0, default off, shares the pool via `jobpool.sharedJobPool` (own owner id from `allocOwner`), applied on the tick the stepwise run would finish, applyJob + stale guard on the tick thread) | erosionjobtest: 6 seeds, digest of changes/bodies/steps/ops equal for the stepwise loop, inline job and a 2-worker pool; erosiontest/scenetest still pass. The erosionwire wiring and `/erosion run` with the flag on were only compiled, not run against a live server; no Background lane (shared FIFO with path jobs); a worker slower than `steps` ticks applies later (timing, not content); the solver job is a separate row below |
| Phase 1 (d) solver as one pool job (`physwire/solverjob`, wired in `body/bodymanager.stepCollapseJobs`; MC_SOLVER_WORKERS=1 and planThreads workers>0, default off, shared pool + `allocOwner`) | **Audit.** `solve`/`newSolverJob` callers in the server: only `bodymanager` (`collapseStart` -> `collapseStep` -> `collapseApply`). Interactive `collapseCheck` on a small box (<= `collapseInline` cells) returns its report in the same call (bodytest, `/body collapse`): NOT wired, a one-tick delay would change its contract. The queued path (`collapseEnqueue`, used by `trigger.aowl`, and `collapseCheck` on big boxes) already spreads the solve over many ticks (`collapseOps` per tick) and applies later: WIRED, a tick of extra delay is safe. `fell*` and `trigger*` only consume the report. Other callers (`scenes`, `solveradapter`, `create/kinetic`, tests) are offline/tests or a different solver (create kinetics). **Worker mode:** the front queued job's `solve` runs as one job on a copy of its SolverInput, applied on the tick thread exactly `SolveDelayTicks` (1) ticks after the submit in every mode (inline at 0 workers also next tick; if the worker is not done the tick waits, never a different tick), then the next queued job is submitted that same tick (one in flight). `collapseStale` re-reads the box and drops the result (report reason "result dropped") if any block differs from the snapshot (section versions fast path); the change's own trigger queues a fresh check. The gate-on schedule differs from the sliced default (one tick per job instead of ceil(ops/collapseOps)), by design; threads=1 vs N are identical. | solverjobtest: 60 generated inputs, `solve` result `==` for direct, inline, 1 worker and 4 workers; ordered pipeline (12 jobs, one in flight) applied in submit order at the same tick cadence in every mode; 56 checks. bodytest (imports the changed bodymanager) see commit message. Not verified: bodymanager worker path against a live server or with the flag on (no test drives `enableSolverJobs`); stale drop is untested end to end; a slow solve stalls the tick thread at the due tick (determinism over latency); full server build |
| Phase 1 (a) chunk save compress job (`ChunkSerializer.compressionHint/compress/applyPrepared` split of `update_chunk`; `sim/savepool`, MC_SAVE_WORKERS=1 and workers>0, default off): `saveGeneric` serialises on the caller, compresses one region file's chunks on the pool, joins, applies in chunk order, then `writeOf` on the caller | savejobtest: region files byte-identical (timestamp page masked) vs inline at 0 and 3 workers, in-place and whole-file configs, first write and rewrite with changing sector counts; chunk io/anvil tests rerun. `writeOf` stays on the caller (no per-region write lane yet, so no write overlap), only the compress overlaps; only the anvil serializer has the split (linear/pump formats stay inline); no server build, no load test, no speedup measured; exclusive with MC_NET_WORKERS/MC_PATH_WORKERS/MC_PLUGIN_JOBS in one process (jobpool allows one worker pool) |
| Phase 1 (b) chunk packet compress job (`packet_encoder.compressFrame`/`appendFrame` split, `sim/pktslots` ordered per-client slot list on the shared net pool, MC_CHUNKPKT_WORKERS=1 and workers>0, default off) | pktslotstest: bytes equal the inline encoder at 3 workers for 3 connections with compression and encryption switched on mid-stream (see test results in the commit). NOT wired into JavaClient (`sendPacketNowData` does not know which packets are chunk packets; the MC_NET_WORKERS lane already compresses every packet off-thread and takes precedence); no server build |
| Phases 1 to 4 change lists | written (docs/MULTITHREADING_PHASES.md) |
| Worker count from the thread plan + never-raise workers | prepared on top of the chunk chain (branch mt-items-1-3), not pushed |
| Phase 1 (f): `generation_executor` on `sim/jobpool` (branch mt-gen) | `jobpool` has lanes (`lnUrgent`/`lnNormal`/`lnBackground`, per-lane FIFO, a worker takes the lowest non-empty lane; `submitLane`, `laneDepth`; `submit` = Normal). Generation and decode batches are Normal jobs, LOD summaries Background (taken only when Urgent+Normal are empty), per-handle done lists kept, job bodies never raise (generation failure -> `GenerationFailure`). Worker count from `planThreads(...).chunkWorkers` when MC_CHUNK_WORKERS or MC_THREADS is set (unset stays 0 = inline). **Pool decision: one shared pool per process**; generation claims it via `sharedJobPool`/`allocOwner`; a later `newJobPool` with workers while one is live is refused (inline pool, printed, counted in `refusedPools()`); after integration every user takes the pool from `jobpool.sharedJobPool` and an owner id from `allocOwner` (path, erosion, light, save, net encode/decode/packet slots, plugin jobs per plugin handle; no fixed owner ids remain), so all gates can be on together; whoever creates the pool first sets its size (`liveWorkerPool()` only queries). jobpooltest (lane order, refusal, shared pool, owners) and generationexecutortest (inline vs 4 workers, block-for-block) pass; genhash itself is inline-only and does not exercise the executor. Not verified: full server build, scenarios with MC_CHUNK_WORKERS=0 and 4, lod lane under load, throughput vs the old executor (extra task-table lock per job), `MC_GEN_STATS` idle time is gone |
| Wiring jobpool into phases 2 to 6 | other items still waiting |
| Wiring jobpool into generation_executor, phases 1 to 6 | waiting on the chunk-system owner's branches reaching main |
| Phase 1 (c) relight: step 1 snapshot-backed `LightLevelAccess` (`world/lightsnapshot`: copy of the loaded chunk columns of box + shell + one chunk margin, closures over the copies, cell diff, apply refuses a stale snapshot); step 2 region relight as a pool job (`sim/lightjob`: `submitRelight`/`pollRelights`/`drainRelights`/`relightPending`; applied by the poll after next in every mode, overlapping regions held in order, a stale or failed result is dropped and relit live; MC_LIGHT_WORKERS=1 and workers>0, default off, reuses the path pool when live; wired into `bulkUpdateLighting` and the start of `flushBlockUpdates`) | lightingruntimetest: snapshot relight equals live relight on 18 random edits (7123 changed cells) and a stale snapshot is refused; lightjobtest: job light equals inline light for 8 non-overlapping edits (0 conflicts) and 10 overlapping ones (6 applied, 4 conflicts relit live, 9 held), per-tick light hashes identical at 0 and 3 workers; bulkedittest builds with the wiring (gate off). NOT shown: the gate on in a real server or scenario (no full build), speedup (snapshot copies whole columns of up to (w+4)^2 chunks per region, unmeasured), mob-spawn/other readers do not yet consult `relightPending`, single-cell `updateLighting0` calls stay inline (a job result they invalidate is dropped, not merged), chunk save and shutdown do not yet call `drainRelights`, the net/plugin pools are not shared with it |
| Phase 5 (generic part): footprint scheduler `sim/regionsched` (`runRegionTasks`: tasks with a home chunk and margin, `planPhases` 4-colour phases, one pool job per tile, join between phases, results merged in task-id order, inline at threads<=1, sized by `planThreads`) | regionschedtest passes (300 synthetic overlapping-footprint tasks: identical world hash and results at threads 1, 2 and 4 over 5 reps each, atomic per-chunk occupancy check saw no concurrent overlap, same-tile tasks serial, raising bodies contained, unsafe tile size refused); jobpooltest still passes. Not wired to anything: running real tick work through it needs phase 2 steps 4-6 (per-world state) and phase 4, plus the footprint-declaration audit per system (fluids/redstone margin 1, mob AI radius) and a border phase for explosions/pistons/mobs crossing; the occupancy check is a test helper, not a runtime debug assertion that a body stayed inside its footprint; no soak test, no speedup measured (the test body is synthetic) |
| Phase 6 (server side + plugin wiring): plugin job primitive `sim/plugjob` and its plugin glue `plugin/engine/enginejobs` (host calls `job_submit`/`job_status`/`job_pending`/`job_abi_version`, `on_job` entry, JS and aowlmony SDK helpers, `examples/jobs-js`, `docs/PLUGIN_JOBS.md`) | plugjobtest passes (300 jobs equal at threads=1 and 4, ticket order, nothing before poll, two plugins isolated, failed jobs, guard flags a world touch in both modes); enginejobstest passes (34 checks at threads=1 and 4, also with MC_THREAD_ASSERT=1: kernels, delivery only after poll, per-plugin order, unload drops, shutdown); host calls and `on_job` through a real JS plugin on aoe_engine.dll pass (enginejobhosttest; engineplugintest still passes); `stopPluginManager` is not called by the server's stop path yet (servermod is outside this lane); the aowlmony SDK `runJob` only compiles (no native plugin image built or run); off by default (`MC_PLUGIN_JOBS=1` for workers), not part of the full server build, no load test, cannot share a worker pool with path jobs or net encode |
| Phase 2: collapse trigger queue per world (`trigStateOf(world)`, `body/trigger.aowl`) | done, `worldstatetest` passes. Queue, rate buckets, scan budget and starts per tick are per dimension. Built cells, block log tiles, cracks, wind timers and stats are still module wide (keyed by dimension) |
| Phase 2: bodies per world (`bodiesOf(world)`, `body/bodymanager.aowl`) | done, `worldstatetest`, `bodytest`, `createworldtest`, `replaytest` pass. Body ids and uuids are global and atomic (`atomicFetchAdd`). `gBodies` is gone. `maxAwake`/`maxCells` and the round robin cursor now apply per world (same with one world). Still module wide: event and fx feeds, stats, collapse jobs, the one collision provider (answers for all worlds), journal replay list |
| Phase 2: fire regions per world (`physwire/firewire.aowl`, `fireRegions(world)`) | done, `worldstatetest` passes. `gStats` (and the region seed counter) stays module wide; climatewire still samples worlds[0], erosionwire is still one job |
| Phase 2: the other items (entity lists, fluids, climate, erosion, fight/map managers, ambient parameters, per thread profiler/replay/log buffers, the plugin hook serial lane, owner-thread asserts) | not started |
| Phase 4: per-dimension tick on the shared pool with a join phase (`sim/dimtick`, wired in `servermod.tickWorlds`; `MC_DIM_THREADS=1` AND `planThreads` workers > 0, default off = the sequential per-world loop exactly) | See "Phase 4 status" below. dimticktest: a synthetic 3-world scripted workload (per-world state, a portal message every 5th tick, a second message every 7th, one hook event per world per tick) gives identical state digests after every one of 120 ticks with the gate off, on with 1 worker, on with 4 workers and on an inline pool; the gate refuses a non-queueable hook consumer; the owner guard flags a hook fired from, and a wrong-world touch inside, a dimension job. blocklogdimtest: the block log written from 3 worlds on 4 workers equals the sequential log. `servermod` and the changed modules pass `aowlmony check` (semantic check only, no code generation). NOT done: a full server build, a scenario run, any run with a real world tick on worker threads, any speedup measurement |
| Phase 5 wiring: random-tick scan on the region scheduler (`sim/regionphase`, `level.drawRandomRolls`/`scanRolls`, `worldmod.tickChunks`, `MC_REGION_THREADS=1`, default off) | See "Phase 5 status". regionphasetest passes: identical digests and world hash gate off, 0, 1 and 4 workers; footprint guard in `ownerguard`. Other per-chunk systems audited and refused. No speedup expected, no server build run |
| Everything else | not started |

The state slots are `World.trigState`, `World.bodyState`, `World.fireState` (`nil RootRef`, typed by the owning module because serverbase sits below it). Nothing here is checked from other threads yet: with `threads = 1` it is the same single-owner code, and no owner-thread assert exists until the phase 2 gate item is done. The server wiring (`servermod`) was not changed; a full server build and the scenario suite have not been run for these three changes.

## Phase 4 status (what is implemented, what refuses, what is left)

**Shape.** `sim/dimtick.aowl` knows nothing of `World`: a dimension is an index and the tick body a closure. `servermod.tickWorlds` calls `dimGateNow` every tick (plugins can be loaded and players can move at run time). Only when it answers `dgOn` does it run `tickWorldsThreaded`: one `worldmod.tick` per world as a job on the shared pool (`jobpool.sharedJobPool`, owner id from `allocOwner`, Urgent lane; no second pool is ever created), the tick thread waits at a barrier (a `drainDone` loop that yields), applies the queued messages, then runs the server-level ticks (bodies, create, triggers, fluids, climate, fire, erosion, body sync, lod sync, player data) as before. Anything else runs today's loop unchanged.

**The gate refuses (stays sequential, prints the reason once per change) when:** `MC_DIM_THREADS` is not `1`; the thread plan has no workers (or the shared pool has none); fewer than two worlds; a hook consumer registered with `registerHookConsumer(name, queueable = false)`; any plugin is loaded (`loadedPluginCount() > 0`: every plugin is a consumer of cancellable events such as BlockChangeEvent, which cannot be deferred); players are in more than one world UNLESS `MC_DIM_PLAYERS_MULTI_WORLD=1` (the id-keyed player tables are locked inside dimension jobs, see below, but only those tables are audited, so allowing players in several worlds is opt-in and unverified with a real player in two worlds).

**Messages and their order.** `postCross(kind, closure)` / `postHookEvent(closure)`: outside a dimension job the closure runs at once (so with the gate off nothing changes); inside one it goes to that world's outbox and the join phase runs the outboxes world ascending, post order within a world. The order depends only on the world index and the code path, never on which thread ran which world, so 1 worker and N workers agree (tested). It is not the sequential order in general: a message acts at the end of the world phase instead of in the middle of the world's tick (the synthetic test is written so that this does not show; a real portal transfer happens one phase later than it did).

**Converted to messages:** portal transfer (`portal/portalmod.tickPortal`: destination search/build, `teleport`, passengers), player dimension change (`worldmod.teleportWorld` and `respawnPlayer` defer themselves when called from a dimension job), the death message broadcast over all worlds (`entitymod.broadcastDeathMessage`), the advancement broadcast over all worlds (`advancementglue`, `broadcastSystemMessage`), the block log record (`blocklogcore.blockLogRecordChange`, with the thread's cause/actor context captured; the actor name is interned at the join so actor indices come out in world order) and the replay tap that rides on it, and the trigger notification of `setBlockState` (`gTrigChange`).

**Shared state, fixed:** the entity id allocator is atomic (`entitymod.reserveIds`, `servermod.addPlayer`; which id a world gets depends on timing when two worlds spawn at once, ids are never compared across runs); the profiler scope stack is not touched from dimension threads (`profIgnoreThisThread`: worker time shows up inside the tick thread's `ScTickWorld` barrier scope, there are no per-thread profiler buffers); the block log keeps its plain global context for the tick thread and uses a separate thread-local one only inside dimension jobs (gate off touches only the plain one); `gPortalManagers` takes its lock only inside a dimension job; the owner guard has `enterDimJob`, `assertWorldThread`, and `assertOwner` now flags tick-thread state touched from a dimension job (`MC_THREAD_ASSERT=1`), plus `dimtick.assertWorldOwned` (per-world `Owned` token claimed by the job). The entity/block/explosion/durability RNG streams are thread-local and clock seeded: they were never reproducible, so which worker runs a world changes nothing that was deterministic before.

**Per-player id-keyed tables, now locked (this replaces the player rule):** `entitymod.gPlayerBases`/`gExperienceDelays`, `player.gPlayerStats`/`gPlayerPoses`/`gPlayerDisplayNames`, `playerextras.gTabListHeaders`/`gTabListFooters`/`gLastSentXp` and `breath.gBreaths` take `sim/playerlock` (`ptLock`/`ptUnlock`) around each table operation, only inside a dimension job (tick-thread access is never concurrent with one, so the gate-off path is the plain table access as before). The lock is held only around the table op itself (never across a call into another locked table, never while iterating; read-modify-write such as `incrementStat` is under one hold). Ids are per player and a player ticks in exactly one world's job, so there is no key contention, only table-structure contention. With this the gate no longer refuses players in more than one world. UNVERIFIED: only a synthetic test (below) ran with two "players" per world in three worlds on 4 workers; no real server with players in two worlds was run, and other player-reachable module vars (net writes per client are per connection; chat/tab-list broadcast over worlds is queued) were not audited beyond these tables. Not audited at all: every other module-level `var` reachable from entity AI, block behaviours, mob spawning and the loot bridge (about 600 module vars exist, section 2); the way to find them is a gate-on run with `MC_THREAD_ASSERT=1` on a real server, which has not been done. `levelsync` and `climatewire` read `worlds[0]` but run on the tick thread after the barrier; reads of `server.worlds[0]` from inside a world job (for example `tickEnvironment`) were not checked. The tick thread is idle while worlds run, and if all pool workers are held by long generation jobs the barrier waits for them.

**Cross-world sites (audit result, per site).**
* CONVERTED to a message: command blocks (`commandbridge` `server.runCommandBlock`, reached from the block tick = a dimension job): from a dimension job the whole command (execute-in, `/tp`, setblock in another world, ...) is posted as `CrossCommand` and runs in the join phase on the tick thread; outside one it runs at once (gate off = the original call). Effect: a command block's command acts at the end of the world phase, not in the middle of its block tick, and `successCount`/`lastOutput` are written then.
* `/tp` into another world: reaches `worldmod.teleportWorld`, which already defers itself from a dimension job; commands now only run on the tick thread anyway. `command/execute` `gSourceOverride` is a `threadvar` and `runFallback` sets and restores it on one thread; it is only reached from the tick thread (command blocks deferred, chat/console/RCON/plugin commands come from the network pump or the plugin tick), asserted in `runFallback`.
* PROVEN tick-thread-only and ASSERTED (`dimtick.assertTickThread`, a bool check with guards off, a recorded violation under `MC_THREAD_ASSERT=1` if reached from a dimension job or a pool job): Jester `tickBodySync`, `tickLodSync`, `tickWindSync` (called from `tickPluginManager`, itself asserted); `bodymanager.tickBodies` and `worldByDim`; `trigger.tickTriggers` and `setWorldMode`; `pregen.tickPregen`; `replay.recTick`/`recordCommand`/`replayTick`; `player_server.saveAllPlayers`; WorldEdit `tickWorldEdit`, `findPlayer`, `worldByDimName` (the `weworld` edit operations are only called from the `wecmd` command handlers, i.e. commands, which are on the tick thread); `commandbridge.runConsoleCommand`; the plugin host `tickPluginManager`; Bedrock `pumpBedrockPlay` (Bedrock packet handling, including its command requests, runs inside that pump on the tick thread).
* NOT touched: `bulkedit.aowl` (chunk/physics owner's file; its only cross-world-looking part is the cancellable `BlockChangeEvent` loop that is reached only when `pluginBlockChangeListened()`, and plugins keep the gate shut; no assert added there). Also not asserted: `respawn.calculateRespawnPoint` (called from `respawnPlayer`, which is deferred as a whole), other `for w in server.worlds` loops in code reached from world code that were not in the original list (`block/worldhooks.aowl:240`, `entitymod.aowl:2904`, `fluidhost.aowl:372`, `net/java/play.aowl:1299`, `physwire/firewire.aowl`): not audited in this pass.
* Plugin host calls that reach into a named world: plugins loaded keep the gate shut, so nothing to convert while the gate is on.

**Hook sites that can still fire from a world thread:** with the gate on there is no plugin loaded, so the plugin event hooks reachable from block/entity code (cropmod BlockGrowEvent, pressure plate BlockRedstoneEvent, `setBlockState` BlockChangeEvent, entity event hooks) are the do-nothing defaults or `pluginBlockChangeListened()` is false; WorldEdit's and the datapack tick hooks only fire from the network pump or the tick start. Loading a plugin at run time makes the next tick fall back to the sequential loop. `setBlockState` asserts (guards on) if the cancellable hook is reached from a dimension job. Hot sites converted to `postHookEvent`-style queueing: the block log and trigger notifications of `setBlockState`. Other hook sites (crops, hoppers, furnaces, pistons) were not converted: their events are cancellable or return a value, so they are covered by the plugin rule only.

**Verified (this pass):** `dimticktest` (built and run on its own nimcache) now also runs, in the same three-world workload, two id-keyed per-player table updates per world per tick through `ptLock`/`ptUnlock` and a cross-world "command block" posted as `CrossCommand` from the dimension job: identical digests after every one of 120 ticks with the gate off, 1 worker and 4 workers (and an inline pool), 0 failed messages, the commands counted as deferred in the threaded runs, no owner violation; `ownerguardtest` and `blocklogdimtest` re-run; `servermod`, `commandbridge`, `entitymod`, `player`, bedrockplay, replayplay, windsync, trigger, pumpkinlib pass `aowlmony check` through `sim/dimservercheck` (semantic check only). **Verification still owed:** a full server build; the scenario suite with `MC_DIM_THREADS=1 MC_THREAD_ASSERT=1 MC_THREADS=4` on overworld+nether with a player in each and a command block that targets the other world; a state-hash comparison of saved worlds between the sequential and the threaded loop; measured MSPT.

### Phase 4 scenario evidence (full build of mt-int, honest)

With every gate off, `worldedit_more` and `fluids_finite` failed solo on the phase 4 build, and also on a build of aeeeaa7 (the same tree without phase 4), with varying failure messages: so the phase 4 commit is not their cause; they are timing-sensitive (`worldedit_more` hits the once-per-tick tool guard in `wecmd.useTool` when the bot clicks within one tick) and passed in other full runs. With `MC_DIM_THREADS=1 MC_THREAD_ASSERT=1 MC_THREADS=4` a full scenario run gave 14 pass, 5 fail (`fluids_finite`, `create_live`, `lod_summaries`, and the two by-design pack scenarios); `create_live` and `lod_summaries` passed solo with the gate off; final build of mt-int (with phase 5): default settings 15 pass / 4 fail (`worldedit_more`, `fluids_finite`, and the two by-design pack scenarios); `worldedit_more` then passed and failed on the identical configuration minutes apart, so it is a flake in this environment (not attributable to any gate); with `MC_DIM_THREADS=1 MC_REGION_THREADS=1 MC_THREAD_ASSERT=1 MC_THREADS=4` a full run gave 14 pass / 5 fail (`fluids_finite`, `create_live`, `lod_summaries`, the two pack scenarios), and `lod_summaries` passed solo with threads only and with both gates on. `fluids_finite` fails with and without every gate and also on the build without phase 4. No thread-assert violation line was printed in the gate-on run. Still not shown: that `create_live`/`fluids_finite` are stable at baseline on this machine, a speedup, or a run with players in more than one world. A real world tick on worker threads has therefore run only inside that one full run, with players in one world, and no speedup was measured.

## Phase 5 status (region phase wiring, audit)

**Wired (default off):** `sim/regionphase.aowl` + `worldmod.tickChunks`. The random block ticks are split in `world/level.aowl` into three steps that `getTickData` still composes in the same order (so with the gate off the result is what it always was): `drawRandomRolls` (tick thread: the Level's single xorshift stream and `loadedChunks`; draws in active-chunk order, ticking section ascending, draw ascending), `scanRolls` (turns draws into `RandomTickSample`s: reads one chunk's block sections and constant block-state tables, writes only its own slot), `collectScheduledTicks` (mutates the chunk tick schedulers: tick thread). `worldmod.tickChunks` now runs draw, then `scanChunksOnPool` (the `regionPhase` stage), then `getTickDataWith`, then `runTickData` as before. The region phase is one `runRegionTasks` call: one task per active chunk with a ticking section, home = that chunk, margin 0, tile size 4 (one pool job per 4x4 tile, 4 colour phases, join before the apply). Samples are concatenated in task-id order, so the output is the one-pass loop's for any worker count. Apply (`runTickData`: block behaviours, `setBlockState`, hooks, block log) never leaves the tick thread, which keeps the hook lane rule.

**Gate:** `MC_REGION_THREADS=1` AND `planThreads` workers > 0, decided once, on the process's shared pool (`allocOwner` id, no second pool). Off by default: `scanChunksOnPool` answers false and the caller scans inline. Also refused from inside a pool or dimension job (it would block a worker on its own pool): with `MC_DIM_THREADS=1` the per-world `tickChunks` therefore scans inline; the two gates do not combine. A failed or unplanned run is redone inline.

**Footprint guard:** `ownerguard.enterRegionTask(homeX, homeZ, margin)` / `leaveRegionTask` / `assertInFootprint(cx, cz, what)` (`MC_THREAD_ASSERT=1`): a region task body declares its footprint and every chunk it reads/writes is checked; a task also counts as a job body, so `assertOwner` flags tick-thread state touched from it (inline runs included). Only checkable where the body calls it (the scan calls it for its home chunk); it cannot see an access that does not go through a call.

**Honest cost:** a scan is a few table reads per ticking section (`randomTickSpeed` 3 draws), cheaper than a job. Expect no speedup, possibly a small slowdown, from this workload; no measurement was made. It is the proven first user of the footprint scheduler and of the draw / scan / ordered-apply split, not a performance win.

**Audit: which per-chunk systems can have a provable footprint** (from reading `worldmod.tick`, `worldadapter.runTickData`, `level.getTickData`, `natural_spawner`, `cropmod`; not every behaviour body was read):

| System | Verdict | Why |
|---|---|---|
| Random tick sampling (scan) | SAFE, wired | home chunk only, constant tables, own slot; RNG draws kept on the tick thread |
| Scheduled block/fluid tick collection (`collectScheduledTicks`) | not safe to split | pops from chunk schedulers and edits `chunksWithScheduledTicks`; cheap; stays on the tick thread |
| Random tick bodies (`b.randomTick`: crops, grass spread, leaves decay, fire, lava, vines, ...) | NOT safe | each reads neighbours (crops: 3x3 farmland moisture, light, neighbours; spread: blocks within a few cells, possibly across chunks) and calls `setBlockState`, which fires the cancellable BlockChangeEvent hook, block log, trigger and light updates, and may schedule ticks in other chunks; the order of these effects between neighbouring chunks is part of the sequential result. Needs a read-only decision phase per behaviour (decide, return "set X to Y") plus an ordered apply: a per-behaviour rewrite, and still the footprint is per block (margin 1 chunk at borders) |
| Fluid per-chunk ticks | NOT safe | `fluidhost` finite-fluid host has module-level per-dimension state (phase 2 item 3 not done), spreads across chunk borders |
| Fire (`physwire/firewire`) | NOT safe yet | per-world regions exist (phase 2) but ticks mutate blocks across borders and spawn tick work |
| Mob spawn scan (`natural_spawner`) | NOT safe as is | reads `entitiesOf(world)` (module-level `gWorlds`, phase 2 item 2 not done), `World.spawnRand`/`getSeed()` RNG state, and spawns entities (mutating the entity list) in the same pass; a pure "candidate" split would need per-chunk derived RNG, which changes the sequences (not determinism-preserving against today's stream) |
| Light and heightmap upkeep | already off-thread by a different mechanism | `sim/lightjob` snapshot jobs (MC_LIGHT_WORKERS); heightmap updates are inside `setRelativeBlock` on the tick thread |
| Per-chunk entity AI that only reads | NOT safe | AI ticks write the entity (goals, navigation) and read live World through closures and gCollisionProviders (global mutable); pathfinding has a snapshot path (phase 1 e) but no job yet |

The next candidate with real work in it, once phase 2 steps 2 to 4 land: a per-behaviour "decide" scan for the hottest random-tick blocks (crop growth, grass/mycelium spread) returning a requested state change per sample, margin 1, applied in sample order on the tick thread. Until then phase 5 stays at this one wired workload.

**Verified:** `regionphasetest` (built and run on its own nimcache): a 10x10-chunk scripted world over 30 ticks with the gate off, on with 0 workers (inline pool), 1 worker and 4 workers (3 reps) gives identical per-tick sample digests and final world hashes; 7200 tasks, widest phase 4 shards, 0 failed, 0 guard violations; a margin-1 workload on overlapping 3x3 footprints gives identical slots at 1 and 4 workers; the footprint guard flags a deliberate out-of-footprint read. `leveltest` (getTickData unchanged results), `ownerguardtest` and `regionschedtest` re-run.
**Not verified:** a full server build or any scenario with `MC_REGION_THREADS=1`; `servermod`/`worldmod` were only semantic-checked (`aowlmony check` of servermod passes, no code generation); any speedup; behaviour under `MC_THREAD_ASSERT=1` with a live server.

## Measured on a real server

What this measures: whether the opt-in thread gates speed up or slow down a real server process. One workload, one machine, one prebuilt
executable; read "What is NOT shown" before quoting any number.

**Machine and build.** Windows 11, 20 logical processors (desktop part, SMT on), `C:/m/int_final.exe` (prebuilt integration build of this
tree, not rebuilt for this test). The machine was shared: other agents were building and running their own servers during the runs, so the
CPU was never idle. Each run records the machine CPU percentage (2 s sample after boot, before the load): 23 to 66 percent across runs, with
no pattern by configuration (`cpu_before_pct` in the raw file). Absolute numbers are therefore pessimistic; the comparison relies on the
round-robin order (A B C ... A B C ...) so that drift hits all configs alike.

**Commands.** `sh tools/bench_server.sh C:/m/int_final.exe 3` runs the matrix below round-robin, 3 rounds; `python tools/bench_server.py
<exe> <label> [MC_*=v ...]` runs one configuration (env `BENCH_PORT` 26010, `BENCH_RADIUS` 8, `BENCH_FILLS` 12, `BENCH_RESULTS` jsonl file).
Per run: a fresh world with seed 123456789, `view_distance` 6, `simulation_distance` 4, offline mode; RCON is the control channel. All `MC_*`
variables are cleared, then set per configuration. Three phases, the first two each under its own `/profile start`/`stop`/`export` session
(MSPT numbers are the profiler's per-tick session stats):

1. **gen**: `/setworldspawn 0 80 0`, `/pregen start 8c` = 17 x 17 = 289 chunks. Wall time from the command until `/pregen status` reports done.
2. **fill**: one idle bot (`tools/mcbot.py`, no scenario) joins at spawn so the chunks near it are loaded; then 12 `/fill` commands of 8192
   blocks (32 x 8 x 32, stone/air alternating) around spawn: block updates, relight and chunk resends to that player. The commands go one
   after another over RCON, so the phase wall time (about 20 s) is bounded by that and is not a throughput figure.
3. **save**: `save-all` round trip right after the fill phase (`save_all_flush_s`), and a second one (`save_all_flush2_s`).

Raw results: `docs/bench_server_results.jsonl`, 28 lines (the 24 matrix runs, then 4 extra `cw4_save` runs). One `base` run of round 2 lost its
RCON connection (ConnectionResetError, cause not found) and was replaced by an extra `base` run at the end, so that one is not in round-robin
position. Each line holds all phases, the profiler scopes and the environment.

**Results** (mean of 3 runs, min-max in parentheses where useful; MSPT in ms):

| config (env) | gen wall s | chunks/s | gen MSPT mean | gen MSPT p95 | gen MSPT max | tick-thread chunk-system ms during gen | fill MSPT mean | fill MSPT p95 | fill MSPT max | save-all s |
|---|---|---|---|---|---|---|---|---|---|---|
| base (`MC_CHUNK_WORKERS=0`) | 45.0 (44.0-46.8) | 6.4 | 0.13 | 0.29 | 1.5 | 44135 | 25.6 (23.2-28.5) | 57.5 | 152 (145-165) | 0.084 |
| `MC_CHUNK_WORKERS=4` | 19.8 (18.8-20.9) | 14.6 | 0.18 | 0.61 | 3.8 (2.7-5.1) | 2506 | 24.4 (21.8-26.2) | 54.7 | 121 (99-149) | 0.067 |
| `MC_CHUNK_WORKERS=8` | 15.2 (14.6-16.0) | 19.0 | 0.23 | 0.95 | 4.0 (3.6-4.4) | 2471 | 26.0 (24.4-28.5) | 58.1 | 122 (115-127) | 0.077 |
| `MC_THREADS=0` (automatic) | 15.5 (14.8-16.6) | 18.7 | 0.24 | 0.90 | 3.7 (3.4-4.1) | 2422 | 25.2 (21.8-29.3) | 55.3 | 179 (153-214) | 0.078 |
| `MC_THREADS=1` | 46.3 (45.1-47.5) | 6.2 | 0.14 | 0.31 | 4.9 (1.5-10.9) | 45324 | 26.1 (24.2-29.1) | 58.7 | 179 (164-197) | 0.072 |
| workers 4 + `MC_SAVE_WORKERS=1` | 19.8 (18.5-20.9) | 14.6 | 0.18 | 0.54 | 5.9 (3.7-8.2) | 2363 | 24.6 / 1123.8 / 21.3 (3 runs) | 56 | 197 / 254351 / 126 (3 runs) | 0.073 |
| workers 4 + `MC_LIGHT_WORKERS=1` | 18.9 (18.1-19.6) | 15.3 | 0.17 | 0.59 | 3.2 (2.1-4.6) | 2078 | 23.9 (23.2-24.9) | 54.1 | 131 (121-140) | 0.078 |
| workers 4 + `MC_DIM_THREADS=1` | 20.5 (19.6-21.4) | 14.1 | **22.5 (21.6-24.1)** | **30.4** | **2986 (2505-3291)** | 2482 | 25.0 (24.5-25.6) | 53.9 | 133 (120-151) | 0.068 |

The gates that need workers (`SAVE`, `LIGHT`, `DIM`) were run on top of `MC_CHUNK_WORKERS=4` (the pool is shared and sized by its first user, and a
gate with 0 workers stays off); compare them with the `MC_CHUNK_WORKERS=4` row. The server printed no gate, refusal or pool line in any
configuration (`gate_lines` is empty in all 28 runs), so "the gate engaged" is NOT confirmed by a log line, only suggested by behaviour
(for `DIM`, clearly; for `LIGHT` and `SAVE` not at all).

**What the data shows**

* **Generation workers speed up pregen a lot.** 45.0 s with no workers, 19.8 s with 4 (2.3x), 15.2 s with 8 (3.0x), 15.5 s with `MC_THREADS=0`
  (automatic; 3.0x). Runs of one config agree within about 7 percent; every worker config is far outside the baseline range. 8 workers beat 4 by
  1.3x, not 2x.
* **The tick thread's chunk-system time during generation falls from about 44 s (the whole run: generation ran on the tick thread) to about
  2.5 s** with workers. It does not show as tick MSPT: that scope runs outside the profiled tick in this build, and MSPT stayed at 0.13 ms in
  the baseline gen phase (20 tps). No player was online during gen, so whether the inline generation would stall a player's view was NOT
  measured.
* **Worker configs raise gen-phase MSPT a little** (mean 0.13 to 0.18 to 0.24 ms, p95 0.29 to 0.6 to 0.9 ms; max a few ms): still tiny.
* **`MC_THREADS=1` equals the baseline** (46.3 s vs 45.0 s).
* **Fill phase (block updates, relight, player resend): no gate changed it.** Mean MSPT 24 to 26 ms, p95 54 to 59 ms, max 120 to 180 ms in every
  config, `MC_LIGHT_WORKERS=1` included (23.9 ms, inside the others' range). With 3 runs per config and 20-30 percent spread, the max
  differences (e.g. 179 for `MC_THREADS=0/1` vs 152 for base) are not distinguishable from noise. So no speedup of the tick-bound part of this
  workload is shown. For `MC_LIGHT_WORKERS=1` either relight is not the dominant cost of this fill or the job path was not taken (no counter
  is exposed, not checked).
* **`save-all`** took 0.06 to 0.09 s in every config: the world was nearly all saved already (pregen unloading writes the chunks), so it is a
  near-empty flush. `MC_SAVE_WORKERS=1` is NOT shown to help or hurt a save of a large dirty world.

**Slowdowns and anomalies (as found)**

* **`MC_DIM_THREADS=1` slows the tick during generation: mean MSPT 22.5 ms vs 0.18 ms for the same workers without it, p95 30 ms, and single
  ticks of 2.5 to 3.3 s in all 3 runs.** The profiler puts 9 s of the 20 s gen phase in the "tick world" scope. Reading (hypothesis, not
  tested): the dimension jobs queue on the same pool as the generation batches and the tick thread waits at the join behind generation
  work. Generation itself was not slower (20.5 s vs 19.8 s). In the fill phase, with no generation load, it is neutral (25.0 ms vs 24.4 ms).
  Do not enable it with heavy generation on the shared pool. Nothing here tests it with several busy dimensions, where it could help.
* **`MC_SAVE_WORKERS=1` (with 4 workers): 2 of 7 runs stalled 236 to 254 s in the fill phase** (one tick of 236 or 254 s; the phase took 256 or
  275 s instead of 19 s). The other 5 runs were normal. The server printed no error and recovered; generation and `save-all` were normal in the
  stalled runs. Cause unknown (the stall is inside a tick but outside any profiler scope; no thread dump was taken). It did not occur in
  the 21 matrix runs of the other configs. Treat `MC_SAVE_WORKERS=1` as unsafe on a live server until this is understood. The `cw4_save`
  table row's mean fill MSPT hides this; use the three listed values.
* One `base` run (round 2) lost its RCON connection (`ConnectionResetError`); reason unknown, not seen again in the later 27 runs (it could
  be a server crash or a script problem, not distinguished).

**What is NOT shown**

* One workload, one machine: a fresh seed, one idle player, an almost empty tick (0.1 to 0.2 ms) outside the fill phase. No mobs, redstone,
  fluids, several players flying into new terrain, no real pathing mob (so `MC_PATH_WORKERS` was not run), no net load (`MC_NET_WORKERS`
  not run: one bot is no net load), no `MC_EROSION_WORKERS`, `MC_SOLVER_WORKERS` or `MC_REGION_THREADS` runs (no matching load).
* No benefit of `SAVE`, `LIGHT` or `DIM` is shown (one harm, one unexplained stall, two neutral results); no save of a large dirty world;
  no relight of a big edit (the 12 fills are about 100k blocks); no player-driven generation; only 4 and 8 workers (and automatic) as points.
* Generation speed is the server's own throttled pregen of radius 8 chunks (up to 256 tickets in flight), not view-distance generation by a
  player, and one radius.
* Noise: gen wall within about 7 percent between runs of a config; fill MSPT mean +-15 percent and max much more. 3 runs per config (7 for
  `cw4_save`) are too few for p99 or max statements except the large effects above. The machine was shared and busy (23-66 percent CPU before
  each run, other servers running).
* The "chunk system / IO" 44 s is a profiler scope outside the tick that sums to about the run wall time because generation ran inline on the tick thread; it is not a per-tick cost.

### Memory growth with chunk workers: leak, or not? (mt-m1, prebuilt exe C:/m/int_final.exe, no build)

Tools: `tools/mem_soak.py` (fresh world, RCON only; `/pregen start <R>c` for PASSES passes, or an operator bot that teleports around, scenario `mem_wander` in `tools/mcbot_scenarios.py`; samples the server's working set / private bytes from a thread into a csv; `tools/mem_soak_results/*.csv` are the raw samples), prior evidence is the 19 minute dimension soak above (439 MB -> 5.7 GB, +270 MB/min).

**Code read (generation_executor.aowl, jobpool.aowl, schedule.aowl unload path), no retained-reference bug found in the executor/pool:** the per-handle `done`/`lodDone` lists are emptied by every poll (`setLen(0)`), the pool's own `done` list is drained per owner (`dropPoolResults`), the task table `gTasks` reuses freed slots (`gFreeTasks`; it only grows to the peak number of in-flight jobs, and a taken slot is overwritten with an empty `GenTask`), and job bodies clear their local `t`. `pendOwner/pendCount` grow by one entry per `allocOwner` handle (one per level), not per job. The one place that could keep memory is not in these files: `schedule.processUnloadQueue` only drops a holder whose `occupied` is null and then writes its proto/dirty chunks; a chunk that is mid-generation is retried next second.

**Measurements (radius 20 chunks = 1681 chunks, fresh world seed 123456789, view 6, no players):**

| run | pregen wall | working set during | after pregen, idle 4 to 6 min |
|---|---|---|---|
| workers 0 | 342 s | 94 -> 644 MB peak, 581 MB at the end | flat 580 MB (no growth, no fall) |
| workers 1 | 410 s | peak 676 MB | flat 580 MB |
| workers 4 | 114 s | peak 751 MB | flat 687 MB |
| workers 4, 4 passes over fresh disjoint areas (shift 2000 blocks) | 81, 63, 53 s | 747, 716, 748 MB after each pass | flat 748 MB; no per-pass growth |
| workers 4, 6 passes over the SAME area (loaded back from disk) | 82 s, then 12 s each | 739, 797, 1155, 1123, 1187 MB | flat 1187 MB (one 400 MB step in passes 3 to 4, then no more) |

So a bounded pregen does not leak per pass and does not grow in the idle tail; the plateau is higher with workers (687 vs 581 MB: allocator high-water mark from parallel generation; the same-area passes show a one-off +400 MB step that did not repeat in passes 5 and 6). Memory is NOT returned to the OS after the work finishes (flat, not falling) in any run: this is the allocator keeping its pages (working set and private bytes move together), not distinguishable from a leak by these numbers alone, but also not growing.

**What does grow: a player that has been around (the real finding).** An operator bot in spectator mode teleports every 6 s along a square spiral (500-block pitch) for 200 s, then leaves (here kicked by the known "Wrong teleport id", or ends). Working set stays 300 to 700 MB while it walks, and 4 to 40 s after the player is gone it jumps to 3.5 GB (workers 4, t=248 s, 3576 MB) and 3.9 GB (workers 0, t=310 s, 3840 MB), then stays flat for the following 7 minutes (3552 and 3867 MB at the end): not freed by idle, not freed by `save-all`. `MC_GEN_STATS=1` shows the burst: the count of chunks started at the first stages goes from about 4 900 to 12 500 (Biomes 12493, StructureStart 12352) at once while only 2 400 reach Full. Workers do not cause it (workers 0 does the same, later because inline generation is slower); they only make it faster and bigger in the time given. Two more runs of the same walk with workers 4 reproduced it (`save4`: 1.1 GB -> 7.4 GB in under 4 s, cut off by the abort cap; `blow4`: 650 MB -> 4.0 GB, flat afterwards); runs on the wrong ports are not counted, so a long-lived server whose players keep visiting new areas (portal destinations, the soak's far bots) will climb like the 19 minute soak did. Thread dump at the jump (`tools/mem_soak_results/leave*_threads_at_blowup.txt`): all four workers running (130 s CPU each) with workers 4; the single tick thread running with workers 0.

**Verdict: a leak in the generation executor / job pool is not shown (by reading and by the bounded runs); memory growth under player movement is shown, is independent of the worker count (it also happens with workers 0), and consists of tens of thousands of partially generated proto chunks (about 300 KB each) that are requested at once when a player's position changes/ends and are never unloaded again within 7 minutes.** Whether they would ever be released (eventually, or only by restart) is UNKNOWN: no run was longer than about 7 minutes after the jump. The trigger (what asks for about 7 600 extra chunks right after the player left, the lod summaries radius 64, the player's chunk tickets, or the spawn/forceload area) was not identified. Proposed, in peer-owned files, NOT done: (1) log the schedule's holder count by target stage every 10 s (`chunkMap.len`, holders with `targetStage == None` and a chunk still set, `unloadChunks.len`) next to the `MC_GEN_STATS` line, to see whether the proto chunks are still in `chunkMap`; (2) check that `processUnloadQueue`'s `holder.occupied` retry cannot spin forever for a chunk whose generation was never submitted (a stage dependency of a request that was cancelled); (3) check what a player disconnect or a teleport requests at level `lod` radius.

**Caveats:** (a) two of my intermediate runs were started on ports 26040/26044 by mistake, outside the allowed range, where another agent's bench servers listen (`bench_run_26041`, `bench_run_26045`): their numbers are discarded (not in the table) and my port cleanup may have killed those servers, which I report to the owner; (b) Windows working set and private bytes are the only metrics (no heap profile; mimalloc statistics were not available from outside); (c) one single seed and one machine (20 logical processors); (d) the `mem_wander` bot is kicked by the known teleport-id race, so "player leaves" and "kicked" are the same event here; (e) the first `winpid` of the tool misdetected the server (the RCON listener disappears after the first connection), fixed in the committed version.
