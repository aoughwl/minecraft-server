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
| Everything else | not started |

The state slots are `World.trigState`, `World.bodyState`, `World.fireState` (`nil RootRef`, typed by the owning module because serverbase sits below it). Nothing here is checked from other threads yet: with `threads = 1` it is the same single-owner code, and no owner-thread assert exists until the phase 2 gate item is done. The server wiring (`servermod`) was not changed; a full server build and the scenario suite have not been run for these three changes.

## Phase 4 status (what is implemented, what refuses, what is left)

**Shape.** `sim/dimtick.aowl` knows nothing of `World`: a dimension is an index and the tick body a closure. `servermod.tickWorlds` calls `dimGateNow` every tick (plugins can be loaded and players can move at run time). Only when it answers `dgOn` does it run `tickWorldsThreaded`: one `worldmod.tick` per world as a job on the shared pool (`jobpool.sharedJobPool`, owner id from `allocOwner`, Urgent lane; no second pool is ever created), the tick thread waits at a barrier (a `drainDone` loop that yields), applies the queued messages, then runs the server-level ticks (bodies, create, triggers, fluids, climate, fire, erosion, body sync, lod sync, player data) as before. Anything else runs today's loop unchanged.

**The gate refuses (stays sequential, prints the reason once per change) when:** `MC_DIM_THREADS` is not `1`; the thread plan has no workers (or the shared pool has none); fewer than two worlds; a hook consumer registered with `registerHookConsumer(name, queueable = false)`; any plugin is loaded (`loadedPluginCount() > 0`: every plugin is a consumer of cancellable events such as BlockChangeEvent, which cannot be deferred); players are in more than one world (see the shared state below).

**Messages and their order.** `postCross(kind, closure)` / `postHookEvent(closure)`: outside a dimension job the closure runs at once (so with the gate off nothing changes); inside one it goes to that world's outbox and the join phase runs the outboxes world ascending, post order within a world. The order depends only on the world index and the code path, never on which thread ran which world, so 1 worker and N workers agree (tested). It is not the sequential order in general: a message acts at the end of the world phase instead of in the middle of the world's tick (the synthetic test is written so that this does not show; a real portal transfer happens one phase later than it did).

**Converted to messages:** portal transfer (`portal/portalmod.tickPortal`: destination search/build, `teleport`, passengers), player dimension change (`worldmod.teleportWorld` and `respawnPlayer` defer themselves when called from a dimension job), the death message broadcast over all worlds (`entitymod.broadcastDeathMessage`), the advancement broadcast over all worlds (`advancementglue`, `broadcastSystemMessage`), the block log record (`blocklogcore.blockLogRecordChange`, with the thread's cause/actor context captured; the actor name is interned at the join so actor indices come out in world order) and the replay tap that rides on it, and the trigger notification of `setBlockState` (`gTrigChange`).

**Shared state, fixed:** the entity id allocator is atomic (`entitymod.reserveIds`, `servermod.addPlayer`; which id a world gets depends on timing when two worlds spawn at once, ids are never compared across runs); `gPortalManagers` is behind a lock (never iterated); the profiler scope stack is not touched from dimension threads (`profIgnoreThisThread`: worker time shows up inside the tick thread's `ScTickWorld` barrier scope, there are no per-thread profiler buffers); the block log context is a threadvar; the owner guard has `enterDimJob`, `assertWorldThread`, and `assertOwner` now flags tick-thread state touched from a dimension job (`MC_THREAD_ASSERT=1`), plus `dimtick.assertWorldOwned` (per-world `Owned` token claimed by the job). The entity/block/explosion/durability RNG streams are thread-local and clock seeded: they were never reproducible, so which worker runs a world changes nothing that was deterministic before.

**Shared state, NOT fixed (the reason for the player rule):** the id-keyed per-player tables `entitymod.gPlayerBases`, `gExperienceDelays`, `player.gPlayerStats`, `gPlayerPoses`, `gPlayerDisplayNames` are plain tables mutated from player ticks; they are only safe while one world at a time has players, which is what `dgPlayers` enforces (a world with players next to empty worlds is allowed). Not audited at all: every other module-level `var` reachable from entity AI, block behaviours, mob spawning and the loot bridge (about 600 module vars exist, section 2). The way to find them is to run with the gate on and `MC_THREAD_ASSERT=1`, which has not been done. `levelsync` and `climatewire` read `worlds[0]` but run on the tick thread after the barrier, so they need no change; reads of `server.worlds[0]` from inside a world job (for example `tickEnvironment`) were not checked. The tick thread is idle while worlds run (it does not tick a world itself), and if all pool workers are held by long generation jobs the barrier waits for them (dimension jobs go on the Urgent lane but do not preempt).

**Cross-world sites NOT converted** (still reach another world directly; each is reached from the tick thread today, or only on paths the gate refuses): `commandbridge` command execution and `/tp` into another world (network pump, tick thread); `command/execute` with `gSourceOverride`; the Jester `bodysync`/`lodsync`/`windsync` loops over `worlds` (server level, after the barrier); `respawn.calculateRespawnPoint` reading another world's block (called from `respawnPlayer`, which is deferred as a whole); `worldedit/weworld` and `bulkedit.aowl:293` (BlockChangeEvent hook of bulk edits: the chunk-system owner's file, tick thread only); `bodymanager` and `trigger` loops over all worlds (after the barrier); `pregen`, `replay`, `player_server` save loops; the plugin host calls that reach into a named world (tick thread, and loaded plugins keep the gate shut); Bedrock play paths.

**Hook sites that can still fire from a world thread:** with the gate on there is no plugin loaded, so the plugin event hooks reachable from block/entity code (cropmod BlockGrowEvent, pressure plate BlockRedstoneEvent, `setBlockState` BlockChangeEvent, entity event hooks) are the do-nothing defaults or `pluginBlockChangeListened()` is false; WorldEdit's and the datapack tick hooks only fire from the network pump or the tick start. Loading a plugin at run time makes the next tick fall back to the sequential loop. `setBlockState` asserts (guards on) if the cancellable hook is reached from a dimension job. Hot sites converted to `postHookEvent`-style queueing: the block log and trigger notifications of `setBlockState`. Other hook sites (crops, hoppers, furnaces, pistons) were not converted: their events are cancellable or return a value, so they are covered by the plugin rule only.

**Verification still owed:** a full server build; the scenario suite with `MC_DIM_THREADS=1 MC_THREADS=4` on an overworld+nether world including a portal scenario and `MC_THREAD_ASSERT=1`; a state-hash comparison of saved worlds between the sequential and the threaded loop; behaviour when pool workers are busy with generation; measured MSPT (with one idle nether the gate may well be slower than the sequential loop).

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
