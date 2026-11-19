# Multithreading: audit of module-level `var` globals

Companion to `docs/MULTITHREADING.md` (section 2 counted ~600 module vars; the phase 4 status says they are "not audited at all"). Read-only audit of branch `mt-a1`; no build was run and no server was touched. Files outside `src/server/sim` (chunk system, generation, physics, `bulkedit.aowl`, plugin) belong to peers: for those this document only PROPOSES changes. file:line references are at this tip and drift.

## 1. What is covered, and how much the classes can be trusted

**Scope of the list.** Every module-level `var` under `src/` except test files (`*test.aowl`), `data_codegen/`, `generated/`, `tests/`, the JavaScript text embedded in `plugin/engine/jssdk.aowl` (37 `var` lines of JS, not aowl) and the `genhash.aowl` tool script. That is **847 vars**: column-0 `var x` / `var a, b` declarations plus the entries of `var` blocks, threadvars included. They were found with a regex pass over all `.aowl` files (the generator script is not committed).

**Method.** (a) enumerate; (b) for the hot paths trace the writers and the thread that reaches them: `servermod.tickWorlds` -> `worldmod.tick` as a dim job (flushBlockUpdates -> pollRelights, updateActiveChunks, tickChunks, tickPlayers, entity ticks including mob AI and the pathfinder, tickBlockEntities, the chunk schedule pass), `scanRolls` as the only region task today, and the job bodies of solverjob, erosionjob, lightjob, savepool, netencode, pathfinder, plugin kernels and chunk generation; (c) classify the rest by group rule with a sample check. The V/G column says which:

* `V` = **entry-point evidence read**: an `assertTickThread`/`assertOwner` guard, the call chain from the dim or pool body, a lock around every access I saw, or a doc line. It does NOT mean I read every write site of that var.
* `G` = **group rule, sampled**: classified from the file's role (hook proc installed at init, plugin host, network pump, generation table with a documented lock or prewarm). One or two members were read, the rest are inferred. Treat G rows as "probably right", not as proof.

Classes: `IMM` immutable after init (assigned at module init, startup or world creation on the tick thread, only read afterwards); `TICK` tick-thread-only today (evidence in the row); `TV` threadvar; `LOCK` atomic or lock-guarded; `WORLD` per-world slot (a `World` field or an index-by-world slot); `LAZY` a lazily built singleton or lazily taken decision whose first call can land on a worker (init race only, the objects are equivalent: UNSAFE-low); `UNSAFE` mutated from a dim-tick or pool body with no guard; `NA` offline harness, not reachable from the server.

`TICK` is safe today only because the tick thread is idle while dim jobs run (`tickWorldsThreaded` blocks at the barrier) and the server-level ticks run after it. It is NOT automatically safe for phase 5 region tasks that run those systems; rows that a future region task would reach are marked FRAGILE.

## 2. Summary

| class | vars | of which V | of which G |
|---|---|---|---|
| TICK | 475 | 299 | 176 |
| IMM | 68 | 11 | 57 |
| TV | 28 | 28 | 0 |
| LOCK | 86 | 38 | 48 |
| WORLD | 8 | 8 | 0 |
| LAZY | 120 | 15 | 105 |
| UNSAFE | 37 | 27 | 10 |
| NA | 25 | 0 | 25 |
| **total** | **847** | 426 | 421 |

**This is not a full audit.** Every var has a class, but only the 426 `V` rows had their entry points read, the 421 `G` rows are group-rule classifications, and even `V` rows were not checked write by write. Section 6 lists what was not covered.

Real problems (class UNSAFE, 37 vars in 11 groups) are in section 3, plus one related race that is classed TICK in the table (maps). The 120 LAZY vars (init races) are section 4. Rows 1-3 of section 3 can be hit by a plain `MC_DIM_THREADS=1` run; rows 4-9 need an opt-in flag as well (`MC_LIGHT_WORKERS`, `MC_NET_WORKERS`, `MC_PATH_WORKERS`, `physics_triggers=full`, `physics_fire=on`); rows 10-11 are benign statistics counters.

## 3. UNSAFE: mutated from a dim-tick or pool body with no guard

Ordered by how likely a gate-on run is to hit them. The dim gate (`decideGate`) today refuses only for non-queueable hooks, loaded plugins, fewer than two worlds, or players in several worlds without `MC_DIM_PLAYERS_MULTI_WORLD=1`.

| # | vars (file:line) | reached from | why unsafe | proposed fix | owner |
|---|---|---|---|---|---|
| 1 | `logger` (server/logging.aowl:64), `activeEditor` (server/logging.aowl:444) | any `info/warn/error` call, including from dim jobs | file write, flush, `rotateLog` (close and reopen on day change) and the console-editor redraw are unsynchronised; two threads interleave lines and can close the file under each other | one `Lock` taken in `log()` around consolePrint + file write + rotate (logging is rare, cost is nil) | server (sim can do it) |
| 2 | `gRecipeTaggable` (server/block/entities/furnace_like_block_entity.aowl:51) | `tickBlockEntities` -> furnace/smoker/blast furnace -> `cookingRecipeFor` | hidden argument: written by `cookingRecipeFor`, read by the callback `recipeItemIsTaggedWith`; two worlds smelting at once get each other's item | make it a `{.threadvar.}` (same pattern as `entitymod.gMetaTarget`) or capture the item in a closure | server/block |
| 3 | `gItemCooldowns` (server/item/itembehaviour.aowl:70) | `startCooldown` from the `entitymod` shield block (entity damage in a dim job), `isOnCooldown`/`getCooldown` | id-keyed per-player table missed by the `sim/playerlock` pass (gPlayerStats etc. are locked, this one is not); `isOnCooldown` also deletes | wrap each table op in `ptLock/ptUnlock` (3 sites), or keep cooldowns on Player | server/item |
| 4 | `gSink` (server/sim/lightjob.aowl:66), `gFinished` (server/sim/lightjob.aowl:62), `gFailed` (server/sim/lightjob.aowl:63), `gLevelKeys` (server/sim/lightjob.aowl:277), `gLevelJobs` (server/sim/lightjob.aowl:278) | `worldmod.tick` -> `flushBlockUpdates` -> `pollRelights(lightJobsOf(...))`; `worldadapter.bulkUpdateLighting` (MC_LIGHT_WORKERS=1) | `pump()` resets and refills the global `gSink` and writes gFinished/gFailed without `gLock`; `lightJobsOf` appends its per-level table lazily | per-level sink inside `LightJobs`; take `gLock` in `pump`; create the `LightJobs` when the Level is built | sim (a1) |
| 5 | `gSink` (server/sim/netencode.aowl:42) | `lanePush` from `JavaClient.writePacket` (javamod.aowl:163), called by player/world code in dim jobs (MC_NET_WORKERS=1) | `drainDone(..., gSink)` on a shared global from several threads | a local sink variable in `lanePush` | sim (a1) |
| 6 | `gNextPathId` (server/entity/ai/pathfinder/pathfindermod.aowl:240), `gLastOrphanSweep` (server/entity/ai/pathfinder/pathfindermod.aowl:243), `gPathStale` (server/entity/ai/pathfinder/pathfindermod.aowl:241), `gPathApplied` (server/entity/ai/pathfinder/pathfindermod.aowl:242) | `Navigator.tick` / `submitPathJob` / `resolvePathJob` (mob AI, dim job; MC_PATH_WORKERS=1) | unlocked `+=`; `sweepOrphans` walks `gPathJobs` without `gPathJobsLock` while another world submits (seq regrow) and drops other worlds' jobs | atomic id and counters; lock in sweepOrphans or run it on the tick thread only | server/entity/ai |
| 7 | `gBlastLeft` (server/body/trigger.aowl:90), `gCracks` (server/body/trigger.aowl:91), `gCrackDim` (server/body/trigger.aowl:92), `gCrackTick` (server/body/trigger.aowl:93), `gStats` (server/body/trigger.aowl:81), `gMat` (server/body/trigger.aowl:96) | `explosion.explodeBlocks` -> `gTrigExplode` = `explodeSelect` when `gTrigFull` (physics_triggers=full) | explosions run in entity/block ticks (dim job); `explodeSelect` mutates the global blast budget, crack list, material memo and stats; the gate does not refuse physics_triggers=full | a new gate reason (`dgPhysics`) while `gTrigFull`, or post the explosion cell selection through `postCross` and apply it in the join phase | server/body (physics peer) |
| 8 | `gStats` (server/body/bodymanager.aowl:197), `gEvents` (server/body/bodymanager.aowl:206), `gStatePending` (server/body/bodymanager.aowl:209), `gProviderId` (server/body/bodymanager.aowl:202), `gEventsOverflow` (server/body/bodymanager.aowl:210) | same path: `explodeSelect -> spawnDebrisBody -> registerBody -> emitCreate/ensureProvider` | normally tick-only (tickBodies asserted), but `spawnDebrisBody` is called straight from the explosion | same gate or post as the row above | server/body |
| 9 | `gStats` (server/physwire/firewire.aowl:68) | fire block tick -> `gFireSpread` = `fireSpreadImpl` when `physics_fire=on` (fire.aowl:210) | `inc gStats.*` and `worldByDim` from a dim job; zones are per-world (`zonesOf(world)`) but the counters are shared | gate refuses while `gFirePhysOn`, or atomic counters | server/physwire |
| 10 | `unknownPaletteEntries` (world/chunkformat.aowl:28) | chunk decode on chunk IO/generation workers | plain `inc`; benign statistics counter | atomic inc (peer: chunk owner) | peer: world |
| 11 | `gStPasses` (world/chunk_system/schedule.aowl:94), `gStWorkPasses` (world/chunk_system/schedule.aowl:95), `gStSubmitted` (world/chunk_system/schedule.aowl:96), `gStIo` (world/chunk_system/schedule.aowl:97), `gStNotReady` (world/chunk_system/schedule.aowl:98), `gStWaiting` (world/chunk_system/schedule.aowl:99), `gStStale` (world/chunk_system/schedule.aowl:100), `gStWorkUs` (world/chunk_system/schedule.aowl:101), `gStWorkMaxUs` (world/chunk_system/schedule.aowl:102), `gStLast` (world/chunk_system/schedule.aowl:103) | schedule pass from `sendChange(chunkLoading)` at the end of `worldmod.tick`; only with MC_GEN_STATS=1 | non-atomic stat counters, benign data loss; not read in detail | per-schedule counters or atomics (peer) | peer: chunk_system |
| 12 | `gMapManager` (server/world/mapglue.aowl:23) | `worldhooks.tickMaps(player)` in the player tick (dim job) | listed as TICK in the table (the table is only read there), but `mapData.update(player)` mutates the shared `MapData`: two players holding the same map id in two worlds would race | defer map ticks to the join phase, or lock per map | server/world |

None of these has been seen failing: the phase 4 scenario runs reported no owner-guard violation, but the guard only covers code that calls `assert*`, and none of these do. Logging cannot be guarded by an assert (it is legal everywhere), so its fix is the lock.

Related, not a var: the dim gate has no reason for physics_triggers=full or physics_fire=on, and the opt-in pool gates (`lightJobsEnabled`, `pathJobsEnabled`, `netEncodeEnabled`) are not excluded by `MC_DIM_THREADS=1`. A safe stopgap until the rows above are fixed: refuse the dim gate (one more `DimGate` value each) while any of them is on.

## 4. LAZY: first call can land on a worker thread (init race)

120 vars, two shapes.

1. **Lazy block / block-entity / fluid singletons** (105 vars in 96 files under `server/block/{blocks,entities,fluid}`): `proc xAsPlantBlockBase*(): ... = if gX == nil: gX = newPlantBlockBase(); gX`. `prewarmAll` does not touch them, and they are first reached from random ticks and block-entity ticks (a dim job, or a region task once phase 5 runs block code). Two threads racing on the first call each build an object and publish a ref without a barrier; the objects are equivalent, so the visible result is one replaced or leaked object, but the unsynchronised ref store is a real hazard if refs are counted. Proposed fix (mechanical, in the block owner's files): call every accessor once from its module's `registerBlocks*` proc (startup, tick thread), or add one `prewarmBlockSingletons()` to `sim/prewarm.prewarmAll`; a generator pass over the `registerBlocks*` procs can emit it. Sampled: wheat.aowl:40-52 and barrel.aowl:74-85; the other files are the same shape, not each read.
2. **Lazy gate decisions** (`lightJobsEnabled`, `pathJobsEnabled`, `netEncodeEnabled` / `netOwner`, `sharedJobPool`, `ensureJobsLock`, `sharedRegistry`): decided on the first call, which also creates the shared pool. If that first call is a dim job the pool is built from a worker. Fix: decide every gate once in `prewarmAll` on the tick thread (they are env reads).

## 5. Findings that are safe but worth knowing

* `entitymod.gWorlds`, `entitytype.gFactories`, `fluidseam.gFluidTicksSuppressed`, `triggerhook.g*`, `firehook.g*`, `collision_providers.*`, `dragon_fight_world.gFights` are written only on the tick thread (world creation, settings) and read from dim jobs. Safe because worlds are created and settings change between phases; a world created from inside a dim job (none found) would break it.
* `loot.gLootRand` is only the fallback for `LootContextParameters.rng == nil`; every caller in tree passes `addr world.lootRand` (per-world). A new caller that forgets `rng` silently shares one stream across worlds.
* `physics/materials` tables are `IMM` only because `prewarmMaterials()` ran; `/pack reload` re-prewarms on the tick thread, safe only while no erosion job runs (the comment in `sim/prewarm.aowl` says so; it is not enforced).
* The block log, replay tap and the trigger/body change feed reach dim jobs only through `postCross` (verified at `blocklogcore.aowl:520`, `blockbehaviour.aowl:938-949`). `bulkedit.aowl` vars (`gBeMemo`, `gBulkPhaseNs`) are tick-only because every caller is a server-level tick (fluidhost, erosionwire, firewire, bodymanager, worldedit): FRAGILE for phase 5. Proposed (peer file): fill `gBeMemo` for every state in `prewarmAll`.
* Phase 5 today: the only region task body is `scanRolls` (read-only sampling of chunk data); none of the vars here is reachable from it beyond what the chunk/level code reads. Everything in sections 3 and 4 matters the moment block ticks, mob AI or fluids become region tasks.
* There are no module vars in `server/block/blocks/redstone` (only block-behaviour casts), `server/entity/ai/goal`, or `inventory` (one: `gSeedRandom`, packet-handler only). Redstone and goal-AI state lives in objects, so the risk there is shared object state, not vars (not audited, section 6).

## 6. What was NOT covered

* **Not every var was traced.** 421 rows are `G` (group rule); the 426 `V` rows had their entry points checked, not each writer. A `TICK` row means "I found guards or callers on the tick thread", not "I proved no other writer exists".
* **Not module `var`s:** `let`/`const` globals holding mutable refs (found 9 vtable `let`s, all built at init; only a fixed set of constructor shapes was grepped), state captured in closures, fields of long-lived objects (`Server`, `World`, `Level`, `Navigator`, `MapData`) that several worlds share, and native globals. The audit counted module vars as asked, not every shared object reachable from a world tick.
* **Not a dynamic check.** No gate-on run with `MC_THREAD_ASSERT=1`, no race detector, no server build. All of this is reading.
* **Generation (`world/generation/*`, `chunk_system/*`) and `physics/*`** are peer-owned: classified from their own prewarm / `lockGen` comments and spot checks of the lock sites (carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); read paths not re-verified. `physics/scenes.aowl` (25 vars) is an offline harness, marked `NA`.
* **Plugin side** (`plugin/*`, 193 vars) is classified TICK from the gate (`dgPlugins` keeps dim threads off while any plugin is loaded) and `docs/PLUGIN_JOBS.md` (kernels are server code over bytes). I did not read the engine ABI for a path that calls plugin code from a pool thread. Plugin-job pool bodies (`enginejobs.runKernel`) were not read beyond that doc.
* **Network:** `netdecode`/`pktslots` and Bedrock/Jester vars are classified from asserted tick-thread entry points; I did not check which thread calls the write path of Bedrock clients from dim jobs (only the Java `lanePush` path is listed).
* `savepool.gSaveSink` and friends assume one concurrent `compressBatch` caller (`filemanager` region save). I did not prove two worlds never save at once; if saves ever run from dim or region tasks they need per-caller sinks.
* Reads of `server.worlds[*]` from inside world jobs were not audited here either (see the phase 4 notes).

## 7. Table

All 847 vars. Sections 7.2 to 7.4 collapse three groups whose rows would be identical. V/G as in section 1.

### 7.1 Per-var rows (524)

| file:line | name | class | V/G | evidence | proposed fix |
|---|---|---|---|---|---|
| codecs/json_ops.aowl:202 | `theJsonOps` | IMM | G | DynamicOps singletons built at init, stateless |  |
| command/builtinmods.aowl:14 | `gBuiltinMods` | TICK | G | startup registration |  |
| command/cmdsource.aowl:501 | `broadcastConsoleToOps` | TICK | G | console/command output config, set at startup |  |
| command/cmdsource.aowl:502 | `consoleWriter` | TICK | G | console/command output config, set at startup |  |
| command/cmdsource.aowl:624 | `gSourceOverride` | TV | V | threadvar; runFallback asserted tick-thread |  |
| command/cmdtree.aowl:180 | `nextDetachedNodeId` | TICK | G | command tree built on the tick thread |  |
| command/fallbackdispatch.aowl:559 | `gExecutorValue` | TICK | V | execute fallback asserted tick-thread |  |
| data/item_stack/mod.aowl:59 | `ITEM_STACK_ID_GEN` | LOCK | V | `nextId` uses atomicFetchAdd on counter |  |
| data/item_stack/mod.aowl:60 | `gDurabilityRandom` | TV | V | threadvar |  |
| data/item_stack/mod.aowl:61 | `gDurabilityInit` | TV | V | threadvar |  |
| inventory/enchanting_screen_handler.aowl:32 | `gSeedRandom` | TICK | G | enchanting screen handler runs from the window-click packet handler |  |
| mods/create/createworld.aowl:71 | `gSources` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| mods/create/createworld.aowl:72 | `gBearings` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| mods/create/createworld.aowl:73 | `gGraph` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| mods/create/createworld.aowl:74 | `gSol` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| mods/create/createworld.aowl:75 | `gCreateStats` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| mods/create/createworld.aowl:76 | `gCarry` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| mods/create/createworld.aowl:77 | `gLastScanTick` | TICK | G | createTick on the tick thread after the barrier (servermod.tickWorlds); registration procs are called from there and from /create commands |  |
| nbt/nbt_ops.aowl:405 | `theNbtOps` | IMM | G | DynamicOps singletons built at init, stateless |  |
| physics/climate.aowl:104 | `gYearDays` | TICK | G | config set at startup, read-only after |  |
| physics/materials.aowl:86 | `gMat` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:87 | `gHave` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:88 | `gClass` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:89 | `gTagOv` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:90 | `gTagHas` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:91 | `gBlockOv` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:92 | `gBlockHas` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:93 | `gInit` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/materials.aowl:94 | `gFills` | IMM | V | `prewarmMaterials()` (sim/prewarm) fills every state; lazy fill path in `materialOf` then never writes (gFills stays). Reload (`loadMaterialOverrides`) invalidates and re-prewarms: tick thread only, never while erosion jobs run (docs in prewarm.aowl) |  |
| physics/packs.aowl:82 | `gRoot` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/packs.aowl:83 | `gPacks` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/packs.aowl:84 | `gCommands` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/packs.aowl:85 | `gRegistered` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/packs.aowl:86 | `gClimate` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/packs.aowl:87 | `gWorld` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/packs.aowl:88 | `gLastReport` | TICK | G | physics pack list/commands/climate: loaded at startup and by /pack commands (tick thread); a reload calls materials invalidate+prewarm (tick thread, no jobs running) |  |
| physics/windfield.aowl:154 | `gSeed` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:155 | `gHeight` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:156 | `gSolid` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:157 | `gRain` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:158 | `gThunder` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:159 | `gProvider` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:160 | `gHasProvider` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| physics/windfield.aowl:161 | `gParams` | TICK | V | set by climatewire (tick); read by the body integrator and firewire (tick); neither solverjob nor erosionjob imports windfield |  |
| protocol/java/client/play/chunk_data.aowl:76 | `biomeRemaps` | IMM | V | prewarmAll calls remapBiomeForVersion for every version |  |
| protocol/java/server/handshake/handshakemod.aowl:21 | `maxServerAddress` | IMM | G | constant-like |  |
| server/block/blockprelude.aowl:71 | `gRngState` | TV | V | threadvar |  |
| server/block/blockprelude.aowl:72 | `gRngInit` | TV | V | threadvar |  |
| server/block/containers.aowl:27 | `gBlockRecipeProvider` | IMM | V | assigned in installBlockHooks at world creation, same server value |  |
| server/block/entities/furnace_like_block_entity.aowl:51 | `gRecipeTaggable` | UNSAFE | V | `cookingRecipeFor` writes it, then `recipeItemIsTaggedWith` reads it as a hidden argument; furnace/smoker/blast furnace tick in `tickBlockEntities` (dim job): two worlds clobber each other | make it a threadvar (like gMetaTarget) or pass the item through a closure/param |
| server/block/fluidseam.aowl:5 | `gFluidTicksSuppressed` | TICK | V | written by tickFluids/setFluidsEnabled on the tick thread; read by fluid block ticks inside dim jobs (the tick thread is idle then) |  |
| server/block/worldadapter.aowl:33 | `gDefaultRegistry` | LAZY | V | built at first `sharedRegistry()` = first world creation (tick thread) | none needed if first call stays at world creation |
| server/blocklog/blocklogcore.aowl:275 | `gFolder` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:276 | `gRing` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:277 | `gDims` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:278 | `gUsers` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:279 | `gUserIdx` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:280 | `gCtx` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:281 | `gDimCtx` | TV | V | threadvar, used only when inDimJob |  |
| server/blocklog/blocklogcore.aowl:282 | `gDimNames` | TV | V | threadvar, used only when inDimJob |  |
| server/blocklog/blocklogcore.aowl:284 | `gPendingPaths` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:285 | `gPendingData` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:286 | `gLastFlushTick` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:287 | `gClock` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:288 | `gInspect` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:289 | `gStateName` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:290 | `gJob` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:291 | `gApply` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:292 | `gDone` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:293 | `gLater` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:294 | `gLaterAt` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:295 | `gTickNow` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:296 | `gDropped` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:297 | `gWritten` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:298 | `gLastDim` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:299 | `gLastDimIdx` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:500 | `gChangeHookOn` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/blocklog/blocklogcore.aowl:501 | `gChangeHook` | TICK | V | ring/name tables/file are written only by recordChangeNow on the tick thread; from a dim job `blockLogRecordChange` posts via postCross (blocklogcore.aowl:520) |  |
| server/body/bodymanager.aowl:195 | `gCfg` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:197 | `gStats` | UNSAFE | V | normally tick-thread (tickBodies asserted). Also written via `explodeSelect -> spawnDebrisBody -> registerBody -> emitCreate/ensureProvider` from an explosion in a dim job (same gTrigFull path) | same fix as trigger.gBlastLeft |
| server/body/bodymanager.aowl:198 | `gTestCrash` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:199 | `gNextId` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:200 | `gUuidCounter` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:201 | `gBodyStates` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:202 | `gProviderId` | UNSAFE | V | normally tick-thread (tickBodies asserted). Also written via `explodeSelect -> spawnDebrisBody -> registerBody -> emitCreate/ensureProvider` from an explosion in a dim job (same gTrigFull path) | same fix as trigger.gBlastLeft |
| server/body/bodymanager.aowl:203 | `gServers` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:204 | `gReplayed` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:205 | `gLastTick` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:206 | `gEvents` | UNSAFE | V | normally tick-thread (tickBodies asserted). Also written via `explodeSelect -> spawnDebrisBody -> registerBody -> emitCreate/ensureProvider` from an explosion in a dim job (same gTrigFull path) | same fix as trigger.gBlastLeft |
| server/body/bodymanager.aowl:207 | `gFx` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:208 | `gLastImpactFx` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:209 | `gStatePending` | UNSAFE | V | normally tick-thread (tickBodies asserted). Also written via `explodeSelect -> spawnDebrisBody -> registerBody -> emitCreate/ensureProvider` from an explosion in a dim job (same gTrigFull path) | same fix as trigger.gBlastLeft |
| server/body/bodymanager.aowl:210 | `gEventsOverflow` | UNSAFE | V | normally tick-thread (tickBodies asserted). Also written via `explodeSelect -> spawnDebrisBody -> registerBody -> emitCreate/ensureProvider` from an explosion in a dim job (same gTrigFull path) | same fix as trigger.gBlastLeft |
| server/body/bodymanager.aowl:211 | `gDirty` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:212 | `gJobs` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:213 | `gNextJob` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:214 | `gLastSkipLog` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:215 | `gAnchorNx` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:215 | `gAnchorNy` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:215 | `gAnchorNz` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:216 | `gWindBase` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:217 | `gWindTick` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:1354 | `gCollapseResults` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:1362 | `gSolvePool` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodymanager.aowl:1363 | `gSolveDecided` | TICK | V | tickBodies/worldByDim asserted; global views over every world (gBodyStates, gServers): not per-world; see the UNSAFE rows for the explosion path |  |
| server/body/bodyworld.aowl:36 | `gEnvWorlds` | TICK | V | body integrator environment (tickBodies, asserted). `useWorld` mutates a single global world slot: NOT per-world, tick thread only |  |
| server/body/bodyworld.aowl:37 | `gShapeMemo` | TICK | V | body integrator environment (tickBodies, asserted). `useWorld` mutates a single global world slot: NOT per-world, tick thread only |  |
| server/body/bodyworld.aowl:38 | `gRotMemo` | TICK | V | body integrator environment (tickBodies, asserted). `useWorld` mutates a single global world slot: NOT per-world, tick thread only |  |
| server/body/fell.aowl:59 | `gFellStats` | TICK | V | fellNote is reached from trigger.onChange (posted from dim jobs); tickFell on the tick thread |  |
| server/body/fell.aowl:60 | `gQueue` | TICK | V | fellNote is reached from trigger.onChange (posted from dim jobs); tickFell on the tick thread |  |
| server/body/fell.aowl:61 | `gTokens` | TICK | V | fellNote is reached from trigger.onChange (posted from dim jobs); tickFell on the tick thread |  |
| server/body/fell.aowl:62 | `gClass` | TICK | V | fellNote is reached from trigger.onChange (posted from dim jobs); tickFell on the tick thread |  |
| server/body/trigger.aowl:81 | `gStats` | UNSAFE | V | `explodeSelect` (= `gTrigExplode`, called from `explosion.explodeBlocks` when `gTrigFull`, i.e. physics_triggers=full) writes them; explosions run in entity/block ticks = dim job. The dim gate does not refuse physics_triggers=full. Without full: tick-thread only | make `dimGateNow` refuse while gTrigFull (new DimGate), or post the explosion select through postCross and apply in the join phase |
| server/body/trigger.aowl:82 | `gInit` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:83 | `gKnownWorlds` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:84 | `gWorldMode` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:85 | `gWorldSource` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:86 | `gDimMode` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:87 | `gBuilt` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:88 | `gTiles` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:89 | `gStruct` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:90 | `gBlastLeft` | UNSAFE | V | `explodeSelect` (= `gTrigExplode`, called from `explosion.explodeBlocks` when `gTrigFull`, i.e. physics_triggers=full) writes them; explosions run in entity/block ticks = dim job. The dim gate does not refuse physics_triggers=full. Without full: tick-thread only | make `dimGateNow` refuse while gTrigFull (new DimGate), or post the explosion select through postCross and apply in the join phase |
| server/body/trigger.aowl:91 | `gCracks` | UNSAFE | V | `explodeSelect` (= `gTrigExplode`, called from `explosion.explodeBlocks` when `gTrigFull`, i.e. physics_triggers=full) writes them; explosions run in entity/block ticks = dim job. The dim gate does not refuse physics_triggers=full. Without full: tick-thread only | make `dimGateNow` refuse while gTrigFull (new DimGate), or post the explosion select through postCross and apply in the join phase |
| server/body/trigger.aowl:92 | `gCrackDim` | UNSAFE | V | `explodeSelect` (= `gTrigExplode`, called from `explosion.explodeBlocks` when `gTrigFull`, i.e. physics_triggers=full) writes them; explosions run in entity/block ticks = dim job. The dim gate does not refuse physics_triggers=full. Without full: tick-thread only | make `dimGateNow` refuse while gTrigFull (new DimGate), or post the explosion select through postCross and apply in the join phase |
| server/body/trigger.aowl:93 | `gCrackTick` | UNSAFE | V | `explodeSelect` (= `gTrigExplode`, called from `explosion.explodeBlocks` when `gTrigFull`, i.e. physics_triggers=full) writes them; explosions run in entity/block ticks = dim job. The dim gate does not refuse physics_triggers=full. Without full: tick-thread only | make `dimGateNow` refuse while gTrigFull (new DimGate), or post the explosion select through postCross and apply in the join phase |
| server/body/trigger.aowl:94 | `gWindNext` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:95 | `gLastTick` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:96 | `gMat` | UNSAFE | V | `explodeSelect` (= `gTrigExplode`, called from `explosion.explodeBlocks` when `gTrigFull`, i.e. physics_triggers=full) writes them; explosions run in entity/block ticks = dim job. The dim gate does not refuse physics_triggers=full. Without full: tick-thread only | make `dimGateNow` refuse while gTrigFull (new DimGate), or post the explosion select through postCross and apply in the join phase |
| server/body/trigger.aowl:97 | `gLastReport` | TICK | V | tickTriggers/setWorldMode asserted; trigger.onChange arrives posted (blockbehaviour.aowl:947) |  |
| server/body/trigger.aowl:509 | `gBlastWorlds` | TV | V | threadvar |  |
| server/body/trigger.aowl:510 | `gBlastOx` | TV | V | threadvar |  |
| server/body/trigger.aowl:511 | `gBlastOy` | TV | V | threadvar |  |
| server/body/trigger.aowl:512 | `gBlastOz` | TV | V | threadvar |  |
| server/body/triggerhook.aowl:11 | `gTrigOn` | TICK | V | written by trigger.refreshSettings/tickTriggers (asserted); read by dim jobs between phases. gTrigChange from a dim job is posted (`blockbehaviour.aowl:947`) |  |
| server/body/triggerhook.aowl:12 | `gTrigFull` | TICK | V | written by trigger.refreshSettings/tickTriggers (asserted); read by dim jobs between phases. gTrigChange from a dim job is posted (`blockbehaviour.aowl:947`) |  |
| server/body/triggerhook.aowl:17 | `gTrigChange` | TICK | V | written by trigger.refreshSettings/tickTriggers (asserted); read by dim jobs between phases. gTrigChange from a dim job is posted (`blockbehaviour.aowl:947`) |  |
| server/body/triggerhook.aowl:20 | `gTrigExplode` | TICK | V | written by trigger.refreshSettings/tickTriggers (asserted); read by dim jobs between phases. gTrigChange from a dim job is posted (`blockbehaviour.aowl:947`) |  |
| server/commandbridge.aowl:101 | `gScoreboards` | TICK | V | command/console execution (tick thread); command blocks are deferred with CrossCommand |  |
| server/commandbridge.aowl:1485 | `consoleBuffer` | TICK | V | command/console execution (tick thread); command blocks are deferred with CrossCommand |  |
| server/commandbridge.aowl:1486 | `consoleEditor` | TICK | V | command/console execution (tick thread); command blocks are deferred with CrossCommand |  |
| server/commandbridge.aowl:1487 | `consoleEditorShown` | TICK | V | command/console execution (tick thread); command blocks are deferred with CrossCommand |  |
| server/crash.aowl:218 | `handling` | TICK | G | reentrancy flag of the crash handler |  |
| server/data/player_server.aowl:16 | `lastSaveMs` | TICK | V | saveAllPlayers asserted |  |
| server/datapack/datapack.aowl:57 | `gPacks` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:58 | `gFunctions` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:59 | `gFunctionTags` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:60 | `gBaseline` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:61 | `gBaseCrafting` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:62 | `gBaseShaped` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:63 | `gBaseShapeless` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:64 | `gBaseCooking` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/datapack/datapack.aowl:65 | `gUndo` | TICK | G | datapack load/reload commands (tick thread); its tick hook fires at tick start |  |
| server/entity/ai/aibase.aowl:177 | `gEquipMobOnSpawn` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/ai/aibase.aowl:185 | `gGetSkyLightLevel` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/ai/aibase.aowl:192 | `gGetBlockLightLevel` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/ai/pathfinder/pathfindermod.aowl:237 | `gPathJobs` | LOCK | V | gPathJobs under gPathJobsLock in submit/take/pathJobBody (except the sweepOrphans loop, see gLastOrphanSweep); lock created lazily by `ensureJobsLock` (first call may be a dim job) | init lock at enablePathJobs |
| server/entity/ai/pathfinder/pathfindermod.aowl:238 | `gPathJobsLock` | LOCK | V | gPathJobs under gPathJobsLock in submit/take/pathJobBody (except the sweepOrphans loop, see gLastOrphanSweep); lock created lazily by `ensureJobsLock` (first call may be a dim job) | init lock at enablePathJobs |
| server/entity/ai/pathfinder/pathfindermod.aowl:239 | `gPathJobsInit` | LOCK | V | gPathJobs under gPathJobsLock in submit/take/pathJobBody (except the sweepOrphans loop, see gLastOrphanSweep); lock created lazily by `ensureJobsLock` (first call may be a dim job) | init lock at enablePathJobs |
| server/entity/ai/pathfinder/pathfindermod.aowl:240 | `gNextPathId` | UNSAFE | V | `ownerOf` does `gNextPathId += 1` from `Navigator.tick` (mob AI = dim job); duplicate ids merge two navigators on one pool owner | atomicFetchAdd |
| server/entity/ai/pathfinder/pathfindermod.aowl:241 | `gPathStale` | UNSAFE | V | plain counters/flag written from `Navigator.tick`/`resolvePathJob`/`sweepOrphans` (dim job); `sweepOrphans` also walks gPathJobs WITHOUT gPathJobsLock while another world may `submitPathJob` (seq regrow) and drains/drops other worlds' jobs (only with MC_PATH_WORKERS=1) | take gPathJobsLock in sweepOrphans, make counters atomic, sweep on the tick thread only |
| server/entity/ai/pathfinder/pathfindermod.aowl:242 | `gPathApplied` | UNSAFE | V | plain counters/flag written from `Navigator.tick`/`resolvePathJob`/`sweepOrphans` (dim job); `sweepOrphans` also walks gPathJobs WITHOUT gPathJobsLock while another world may `submitPathJob` (seq regrow) and drains/drops other worlds' jobs (only with MC_PATH_WORKERS=1) | take gPathJobsLock in sweepOrphans, make counters atomic, sweep on the tick thread only |
| server/entity/ai/pathfinder/pathfindermod.aowl:243 | `gLastOrphanSweep` | UNSAFE | V | plain counters/flag written from `Navigator.tick`/`resolvePathJob`/`sweepOrphans` (dim job); `sweepOrphans` also walks gPathJobs WITHOUT gPathJobsLock while another world may `submitPathJob` (seq regrow) and drains/drops other worlds' jobs (only with MC_PATH_WORKERS=1) | take gPathJobsLock in sweepOrphans, make counters atomic, sweep on the tick thread only |
| server/entity/ai/pathfinder/pathpool.aowl:13 | `gPathPool` | LAZY | V | `pathJobsEnabled()` decides lazily on first Navigator submit (dim job) and creates the shared pool | call once from prewarmAll |
| server/entity/ai/pathfinder/pathpool.aowl:14 | `gPathDecided` | LAZY | V | `pathJobsEnabled()` decides lazily on first Navigator submit (dim job) and creates the shared pool | call once from prewarmAll |
| server/entity/ai/pathfinder/pathpool.aowl:15 | `gPathOn` | LAZY | V | `pathJobsEnabled()` decides lazily on first Navigator submit (dim job) and creates the shared pool | call once from prewarmAll |
| server/entity/boss/ender_dragon/dragonbase.aowl:106 | `gDragonFightOf` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/breath.aowl:32 | `gBreaths` | LOCK | V | ptLock in dim jobs |  |
| server/entity/collision_providers.aowl:43 | `gCollisionProviders` | TICK | V | registered at startup / `ensureProvider` from bodymanager (tick); see bodymanager.gProviderId for the explosion path |  |
| server/entity/collision_providers.aowl:44 | `gNextProviderId` | TICK | V | registered at startup / `ensureProvider` from bodymanager (tick); see bodymanager.gProviderId for the explosion path |  |
| server/entity/entitymod.aowl:302 | `gBlockHooks` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:303 | `gPlayerHooks` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:306 | `gSignUpdateHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:315 | `gSetCommandBlockHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:323 | `gSetJigsawBlockHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:333 | `gJigsawGenerateRequestHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:342 | `gDropStack` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:350 | `gScatterStack` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:357 | `gSpawnExperienceOrb` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:365 | `gFromType` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:373 | `gTickPortalHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:383 | `gLootHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:391 | `gEatHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:399 | `gDrinkPotionHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/entitymod.aowl:410 | `gEntityRandomState` | TV | V | threadvar |  |
| server/entity/entitymod.aowl:411 | `gEntityRandomInit` | TV | V | threadvar |  |
| server/entity/entitymod.aowl:596 | `gWorlds` | TICK | V | appended in registerWorld (world creation); looked up from dim jobs between phases |  |
| server/entity/entitymod.aowl:616 | `gPlayerBases` | LOCK | V | ptLock in dim jobs (docs phase 4) |  |
| server/entity/entitymod.aowl:617 | `gExperienceDelays` | LOCK | V | ptLock in dim jobs (docs phase 4) |  |
| server/entity/entitymod.aowl:1008 | `gMetaTarget` | TV | V | threadvar |  |
| server/entity/entitytype.aowl:16 | `gFactories` | TICK | V | filled by registerMobs() in installBlockHooks (world creation); read from dim jobs between phases |  |
| server/entity/entitytype.aowl:18 | `gCheckBatSpawnRules` | IMM | G | hook procs assigned at init |  |
| server/entity/entitytype.aowl:26 | `gCheckSlimeSpawnRules` | IMM | G | hook procs assigned at init |  |
| server/entity/mob/mobvts.aowl:50 | `gGetHeightmapHeight` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/mob/mobvts.aowl:62 | `gGetMaxLocalRawBrightness` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/mob/shulker.aowl:43 | `gSpawnShulkerBullet` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/passive/villager/villagermod.aowl:52 | `gOpenHandledScreen` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/passive/villager/villagermod.aowl:60 | `gBedSetOccupied` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:291 | `gDropItemHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:301 | `gPlayerStats` | LOCK | V | ptLock in dim jobs |  |
| server/entity/player.aowl:480 | `gPlayerPoses` | LOCK | V | ptLock in dim jobs |  |
| server/entity/player.aowl:725 | `gWakeUpHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:740 | `gPlayerEffects` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:742 | `gPlayerKillHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:749 | `gPlayerPortalCooldownHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:755 | `gPlayerDamageHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:763 | `gFallHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:803 | `gMiningEffectsHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:965 | `gPlayerDisplayNames` | LOCK | V | ptLock in dim jobs |  |
| server/entity/player.aowl:1121 | `gPlayerLivingWriteHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/player.aowl:1130 | `gPlayerLivingReadHook` | IMM | G | hook procs (`g*Hook`, `g*Fn`) assigned at module init / world install, read by entity code |  |
| server/entity/playerextras.aowl:29 | `gTabListHeaders` | LOCK | V | ptLock in dim jobs |  |
| server/entity/playerextras.aowl:30 | `gTabListFooters` | LOCK | V | ptLock in dim jobs |  |
| server/entity/playerextras.aowl:31 | `gLastSentXp` | LOCK | V | ptLock in dim jobs |  |
| server/fluids/fluidhost.aowl:65 | `gEnabled` | TICK | V | `tickFluids` after the barrier (servermod.tickWorlds); settings by command |  |
| server/fluids/fluidhost.aowl:66 | `gBudget` | TICK | V | `tickFluids` after the barrier (servermod.tickWorlds); settings by command |  |
| server/fluids/fluidhost.aowl:67 | `gStepEvery` | TICK | V | `tickFluids` after the barrier (servermod.tickWorlds); settings by command |  |
| server/fluids/fluidhost.aowl:68 | `gDims` | TICK | V | `tickFluids` after the barrier (servermod.tickWorlds); settings by command |  |
| server/fluids/fluidhost.aowl:69 | `gTick` | TICK | V | `tickFluids` after the barrier (servermod.tickWorlds); settings by command |  |
| server/item/itembehaviour.aowl:70 | `gItemCooldowns` | UNSAFE | V | id-keyed player table NOT under sim/playerlock; `startCooldown` is reached from `entitymod` shield block (`hooks.startCooldown`, entity damage = dim job) as well as from item use (tick thread); `isOnCooldown` deletes | ptLock/ptUnlock around each table op (same as gPlayerStats), or store the cooldown on Player |
| server/item/itembehaviour.aowl:71 | `gFishingBobbers` | TICK | V | written only by the fishing rod `normalUse` (packet handler) |  |
| server/item/itembehaviour.aowl:72 | `gItemHooks` | IMM | G | hook struct assigned at module init (installMapHooks at import) |  |
| server/item/itemsmod.aowl:54 | `gItemRegistry` | IMM | G | registry built at init |  |
| server/logging.aowl:24 | `logDir` | IMM | G | set once at startup |  |
| server/logging.aowl:64 | `logger` | UNSAFE | V | `log()` writes logger.file, flushes, and `rotateLog()` closes/reopens the file on day change, no lock; called from any code (dim jobs log warnings/errors) | one lock around log()/rotateLog |
| server/logging.aowl:444 | `activeEditor` | UNSAFE | V | `consolePrint` (called by log from any thread) reads the editor and writes stdout; editor is mutated by the console on the tick thread | same lock as logger |
| server/net/bedrock/bedrockclient.aowl:195 | `gBedrockSendFilter` | IMM | G | hook procs assigned at init |  |
| server/net/bedrock/bedrockcraft.aowl:12 | `gBedrockRecipes` | TICK | G | bedrock session setup (pump) |  |
| server/net/bedrock/bedrockcraft.aowl:13 | `gBedrockRecipesBuilt` | TICK | G | bedrock session setup (pump) |  |
| server/net/bedrock/bedrockhooks.aowl:10 | `gBedrockPacketReceivedHook` | IMM | G | hook procs assigned at init |  |
| server/net/bedrock/bedrockhooks.aowl:19 | `gBedrockChunkSendHook` | IMM | G | hook procs assigned at init |  |
| server/net/bedrock/bedrockhooks.aowl:28 | `gBedrockPacketSentHook` | IMM | G | hook procs assigned at init |  |
| server/net/bedrock/bedrockplay.aowl:148 | `gSessions` | TICK | V | pumpBedrockPlay asserted |  |
| server/net/bedrock/bedrockplay.aowl:149 | `gServer` | TICK | V | pumpBedrockPlay asserted |  |
| server/net/bedrock/bedrockplay.aowl:159 | `gIds` | TICK | V | pumpBedrockPlay asserted |  |
| server/net/bedrock/bedrockplay.aowl:160 | `gIdsReady` | TICK | V | pumpBedrockPlay asserted |  |
| server/net/bedrock/bedrockskin.aowl:25 | `gJavaSkins` | TICK | G | bedrock session setup (pump) |  |
| server/net/java/javamod.aowl:170 | `gPacketSentHook` | IMM | G | hook procs assigned at init |  |
| server/net/java/javamod.aowl:181 | `gChunkSendHook` | IMM | G | hook procs assigned at init |  |
| server/net/java/play.aowl:88 | `gItemRegistry` | TICK | G | lazy init in the packet handler |  |
| server/net/jester/bodyinbox.aowl:6 | `gBodiesInbox` | TICK | G | network pump |  |
| server/net/jester/bodysync.aowl:66 | `gInit` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:67 | `gSeed` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:68 | `gStarted` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:69 | `gTick` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:70 | `gModel` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:71 | `gViews` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:72 | `gSlots` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:73 | `gFallbackEnabled` | TICK | V | tickBodySync asserted |  |
| server/net/jester/bodysync.aowl:74 | `gSyncStats` | TICK | V | tickBodySync asserted |  |
| server/net/jester/lodmsg.aowl:247 | `gLodInbox` | TICK | G | network pump |  |
| server/net/jester/lodsync.aowl:62 | `gLodInit` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:63 | `gLodRadius` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:64 | `gLodPerTick` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:65 | `gLodInflight` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:66 | `gLodInlineMs` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:67 | `gOffX` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:68 | `gOffZ` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:69 | `gRingStart` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:70 | `gPeers` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:71 | `gCache` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:72 | `gPending` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:73 | `gDims` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:74 | `gOut` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/lodsync.aowl:75 | `gStats` | TICK | V | tickLodSync asserted; its own pool jobs work on copies (gOut counts, tick thread) |  |
| server/net/jester/modsyncstate.aowl:29 | `gPolicy` | TICK | G | join/mod-sync handshake on the network pump |  |
| server/net/jester/modsyncstate.aowl:30 | `gKick` | TICK | G | join/mod-sync handshake on the network pump |  |
| server/net/jester/modsyncstate.aowl:31 | `gMods` | TICK | G | join/mod-sync handshake on the network pump |  |
| server/net/jester/modsyncstate.aowl:32 | `gPending` | TICK | G | join/mod-sync handshake on the network pump |  |
| server/net/jester/modsyncstate.aowl:33 | `gReported` | TICK | G | join/mod-sync handshake on the network pump |  |
| server/net/jester/windsync.aowl:25 | `gWindPeers` | TICK | V | tickWindSync asserted |  |
| server/net/jester/windsync.aowl:26 | `gWindParams` | TICK | V | tickWindSync asserted |  |
| server/net/jester/windsync.aowl:27 | `gWindSent` | TICK | V | tickWindSync asserted |  |
| server/net/jester/windsync.aowl:28 | `gWindLastUpdate` | TICK | V | tickWindSync asserted |  |
| server/net/winsock.aowl:195 | `perfFrequency` | TICK | G | idempotent lazy init of an int; network thread |  |
| server/physwire/climatewire.aowl:26 | `gActive` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:27 | `gOverride` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:28 | `gOvX` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:29 | `gOvZ` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:30 | `gBase` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:31 | `gPublished` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:32 | `gLast` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:33 | `gLastX` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:34 | `gLastZ` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:35 | `gLastTime` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:36 | `gLastRain` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:37 | `gLastThunder` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:38 | `gPublishes` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/climatewire.aowl:39 | `gSamples` | TICK | V | tickClimateFeed after the barrier |  |
| server/physwire/erosionjob.aowl:16 | `gOwnerPool` | TICK | V | set at enable; used from erosionwire.tickErosion (tick thread) |  |
| server/physwire/erosionjob.aowl:17 | `gOwnerId` | TICK | V | set at enable; used from erosionwire.tickErosion (tick thread) |  |
| server/physwire/erosionjob.aowl:36 | `gRuns` | LOCK | V | gRuns under gRunsLock |  |
| server/physwire/erosionjob.aowl:37 | `gRunsLock` | LOCK | V | gRuns under gRunsLock |  |
| server/physwire/erosionjob.aowl:38 | `gRunsInit` | LOCK | V | gRuns under gRunsLock |  |
| server/physwire/erosionwire.aowl:70 | `gErosionPool` | TICK | V | tickErosion on the tick thread; the job body runs on a copy |  |
| server/physwire/erosionwire.aowl:71 | `gErosionDecided` | TICK | V | tickErosion on the tick thread; the job body runs on a copy |  |
| server/physwire/erosionwire.aowl:72 | `gJob` | TICK | V | tickErosion on the tick thread; the job body runs on a copy |  |
| server/physwire/erosionwire.aowl:73 | `gLast` | TICK | V | tickErosion on the tick thread; the job body runs on a copy |  |
| server/physwire/erosionwire.aowl:74 | `gJobsRun` | TICK | V | tickErosion on the tick thread; the job body runs on a copy |  |
| server/physwire/firehook.aowl:7 | `gFirePhysOn` | TICK | V | written by firewire.refreshModes on the tick thread; read by the fire block in dim jobs. See firewire.gStats for what `gFireSpread` then touches |  |
| server/physwire/firehook.aowl:9 | `gFireSpread` | TICK | V | written by firewire.refreshModes on the tick thread; read by the fire block in dim jobs. See firewire.gStats for what `gFireSpread` then touches |  |
| server/physwire/firewire.aowl:65 | `gInstalled` | TICK | V | tickFirePhysics after the barrier (see gStats for the dim-job entry) |  |
| server/physwire/firewire.aowl:66 | `gFireId` | TICK | V | tickFirePhysics after the barrier (see gStats for the dim-job entry) |  |
| server/physwire/firewire.aowl:67 | `gKnown` | TICK | V | tickFirePhysics after the barrier (see gStats for the dim-job entry) |  |
| server/physwire/firewire.aowl:68 | `gStats` | UNSAFE | V | `fireSpreadImpl` (= `gFireSpread`, called from `fire.aowl` fire tick, dim job, when physics_fire=on) does `inc gStats.*`; it also resolves the world by name (`worldByDim`) and mutates `zonesOf(world)`: per-world only if dim == world.dimension (it is), counters shared | gate refuses while gFirePhysOn, or atomic counters |
| server/physwire/physsettings.aowl:12 | `gSettingCache` | TICK | V | see above |  |
| server/physwire/solverjob.aowl:18 | `gOwnerPool` | TICK | V | set at enable; submit/apply only from bodymanager.stepCollapseJobs (tick thread, asserted via tickBodies) |  |
| server/physwire/solverjob.aowl:19 | `gOwnerId` | TICK | V | set at enable; submit/apply only from bodymanager.stepCollapseJobs (tick thread, asserted via tickBodies) |  |
| server/physwire/solverjob.aowl:36 | `gRuns` | LOCK | V | gRuns under gRunsLock (solver job pool body copies its input) |  |
| server/physwire/solverjob.aowl:37 | `gRunsLock` | LOCK | V | gRuns under gRunsLock (solver job pool body copies its input) |  |
| server/physwire/solverjob.aowl:38 | `gRunsInit` | LOCK | V | gRuns under gRunsLock (solver job pool body copies its input) |  |
| server/pregen/pregen.aowl:53 | `gServer` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:54 | `gActive` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:55 | `gLoaded` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:56 | `gGate` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:57 | `gMaxInFlight` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:58 | `gSignalWord` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:59 | `gSignalSerial` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:60 | `gSignalNext` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:61 | `gRemoteWord` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:62 | `gRemoteSerial` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:63 | `gGateOpen` | TICK | V | tickPregen asserted tick-thread |  |
| server/pregen/pregen.aowl:64 | `gLastCheckpoint` | TICK | V | tickPregen asserted tick-thread |  |
| server/profiler/profiler.aowl:155 | `gOn` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:156 | `gInTick` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:157 | `gInited` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:158 | `gNames` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:159 | `gDepth` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:160 | `gStackId` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:161 | `gStackStart` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:162 | `gStackChild` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:164 | `tSelf` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:165 | `tIncl` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:166 | `tCalls` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:168 | `sSelf` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:169 | `sIncl` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:170 | `sCalls` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:171 | `oSelf` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:172 | `oIncl` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:173 | `oCalls` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:174 | `sDom` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:175 | `sTicks` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:176 | `sSumNs` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:177 | `sMaxNs` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:178 | `sDur` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:179 | `sDropped` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:180 | `sSlow` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:181 | `sStartNs` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:182 | `sEndNs` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:183 | `sDeadlineNs` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:184 | `sHasData` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:185 | `gFolder` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:187 | `ring` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:188 | `ringN` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:189 | `win` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:190 | `winCur` | TICK | V | profScope/profEnd are no-ops on dim threads (gIgnoreThread); everything else on the tick thread |  |
| server/profiler/profiler.aowl:231 | `gIgnoreThread` | TV | V | threadvar; dim jobs call profIgnoreThisThread(true) so scope calls do not touch the shared buffers |  |
| server/profiler/profilercmd.aowl:23 | `exportCounter` | TICK | G | command |  |
| server/pumpkinlib.aowl:30 | `stopFlag` | LOCK | G | stop flag (int32), read by workers; set by the host. See phase 0 doc |  |
| server/replay/replay.aowl:73 | `gRec` | TICK | V | recTick/recordCommand asserted; block-change tap goes through postCross |  |
| server/replay/replay.aowl:74 | `gRecOn` | TICK | V | recTick/recordCommand asserted; block-change tap goes through postCross |  |
| server/replay/replay.aowl:75 | `gRecMessages` | TICK | V | recTick/recordCommand asserted; block-change tap goes through postCross |  |
| server/replay/replay.aowl:76 | `gLastFinished` | TICK | V | recTick/recordCommand asserted; block-change tap goes through postCross |  |
| server/replay/replayplay.aowl:78 | `gPlay` | TICK | V | replayTick asserted |  |
| server/serverbase.aowl:331 | `gNewEntitiesBox` | IMM | G | hook set at init |  |
| server/servercore_abi.aowl:15 | `cores` | TICK | G | native ABI registry, tick thread |  |
| server/servermod.aowl:381 | `gGuardReported` | TICK | V | reportGuardViolations, tick thread |  |
| server/sim/dimtick.aowl:63 | `gOutbox` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:64 | `gOwned` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:65 | `gErrors` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:66 | `gBody` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:67 | `gConsumers` | TICK | V | gate decision, tick thread before the barrier |  |
| server/sim/dimtick.aowl:68 | `gPool` | TICK | V | gate decision, tick thread before the barrier |  |
| server/sim/dimtick.aowl:69 | `gOwner` | TICK | V | gate decision, tick thread before the barrier |  |
| server/sim/dimtick.aowl:70 | `gKindCount` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:71 | `gMsgFailed` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:72 | `gWantRead` | TICK | V | gate decision, tick thread before the barrier |  |
| server/sim/dimtick.aowl:73 | `gWant` | TICK | V | gate decision, tick thread before the barrier |  |
| server/sim/dimtick.aowl:74 | `gLastReported` | TICK | V | gate decision, tick thread before the barrier |  |
| server/sim/dimtick.aowl:75 | `gPhaseCount` | WORLD | V | per-world slots (index = world) or tick-thread bookkeeping around the barrier; gBody is read-only while jobs run |  |
| server/sim/dimtick.aowl:76 | `gCur` | TV | V | threadvar |  |
| server/sim/jobpool.aowl:73 | `gJobPool` | LAZY | V | shared pool created by the first `sharedJobPool` caller; gRefused is a counter; the pool itself is locked. The first caller must be the tick thread (all gates above decide lazily, see lightjob/pathpool/netencode) | prewarmAll creates the pool and decides every gate |
| server/sim/jobpool.aowl:74 | `gRefused` | LAZY | V | shared pool created by the first `sharedJobPool` caller; gRefused is a counter; the pool itself is locked. The first caller must be the tick thread (all gates above decide lazily, see lightjob/pathpool/netencode) | prewarmAll creates the pool and decides every gate |
| server/sim/lightjob.aowl:57 | `gPool` | LAZY | V | `lightJobsEnabled()` decides lazily on first call (also builds the shared pool); first call can be from a dim job | call `lightJobsEnabled()` once from sim/prewarm.prewarmAll |
| server/sim/lightjob.aowl:58 | `gOwner` | LAZY | V | `lightJobsEnabled()` decides lazily on first call (also builds the shared pool); first call can be from a dim job | call `lightJobsEnabled()` once from sim/prewarm.prewarmAll |
| server/sim/lightjob.aowl:59 | `gDecided` | LAZY | V | `lightJobsEnabled()` decides lazily on first call (also builds the shared pool); first call can be from a dim job | call `lightJobsEnabled()` once from sim/prewarm.prewarmAll |
| server/sim/lightjob.aowl:60 | `gOn` | LAZY | V | `lightJobsEnabled()` decides lazily on first call (also builds the shared pool); first call can be from a dim job | call `lightJobsEnabled()` once from sim/prewarm.prewarmAll |
| server/sim/lightjob.aowl:61 | `gSlots` | LOCK | V | gSlots under gLock (jobBody/start/applyOne); gLockInit set in ensureLock on the enabling thread |  |
| server/sim/lightjob.aowl:62 | `gFinished` | UNSAFE | V | `pump()` (called from `waitFinished`/`applyOne`/`pollRelights`) does `gSink.setLen(0); drainDone(..., gSink)` and writes gFinished/gFailed without gLock; reached from `worldmod.tick -> flushBlockUpdates -> pollRelights` (dim job) and `worldadapter.bulkUpdateLighting` when MC_LIGHT_WORKERS=1 | move the sink into the per-level `LightJobs`; take gLock in `pump` around gFinished/gFailed |
| server/sim/lightjob.aowl:63 | `gFailed` | UNSAFE | V | `pump()` (called from `waitFinished`/`applyOne`/`pollRelights`) does `gSink.setLen(0); drainDone(..., gSink)` and writes gFinished/gFailed without gLock; reached from `worldmod.tick -> flushBlockUpdates -> pollRelights` (dim job) and `worldadapter.bulkUpdateLighting` when MC_LIGHT_WORKERS=1 | move the sink into the per-level `LightJobs`; take gLock in `pump` around gFinished/gFailed |
| server/sim/lightjob.aowl:64 | `gLock` | LOCK | V | gSlots under gLock (jobBody/start/applyOne); gLockInit set in ensureLock on the enabling thread |  |
| server/sim/lightjob.aowl:65 | `gLockInit` | LOCK | V | gSlots under gLock (jobBody/start/applyOne); gLockInit set in ensureLock on the enabling thread |  |
| server/sim/lightjob.aowl:66 | `gSink` | UNSAFE | V | `pump()` (called from `waitFinished`/`applyOne`/`pollRelights`) does `gSink.setLen(0); drainDone(..., gSink)` and writes gFinished/gFailed without gLock; reached from `worldmod.tick -> flushBlockUpdates -> pollRelights` (dim job) and `worldadapter.bulkUpdateLighting` when MC_LIGHT_WORKERS=1 | move the sink into the per-level `LightJobs`; take gLock in `pump` around gFinished/gFailed |
| server/sim/lightjob.aowl:277 | `gLevelKeys` | UNSAFE | V | `lightJobsOf` appends lazily on first call per level; first call can be a dim job (`worldmod.flushBlockUpdates`) | create the LightJobs when the Level is built (tick thread) or guard with gLock |
| server/sim/lightjob.aowl:278 | `gLevelJobs` | UNSAFE | V | `lightJobsOf` appends lazily on first call per level; first call can be a dim job (`worldmod.flushBlockUpdates`) | create the LightJobs when the Level is built (tick thread) or guard with gLock |
| server/sim/netdecode.aowl:37 | `gDLanes` | LOCK | G | network receive pump (tick thread); gDLanes under gDLock |  |
| server/sim/netdecode.aowl:38 | `gDLock` | LOCK | G | network receive pump (tick thread); gDLanes under gDLock |  |
| server/sim/netdecode.aowl:39 | `gDInit` | LOCK | G | network receive pump (tick thread); gDLanes under gDLock |  |
| server/sim/netdecode.aowl:40 | `gDSink` | LOCK | G | network receive pump (tick thread); gDLanes under gDLock |  |
| server/sim/netencode.aowl:36 | `gPool` | LAZY | V | `netOwner` / `netEncodeEnabled` decide and allocate owners lazily, can run first on a dim thread | call once from prewarmAll |
| server/sim/netencode.aowl:37 | `gDecided` | LAZY | V | `netOwner` / `netEncodeEnabled` decide and allocate owners lazily, can run first on a dim thread | call once from prewarmAll |
| server/sim/netencode.aowl:38 | `gOn` | LAZY | V | `netOwner` / `netEncodeEnabled` decide and allocate owners lazily, can run first on a dim thread | call once from prewarmAll |
| server/sim/netencode.aowl:39 | `gLanes` | LOCK | V | gLanes only under gLanesLock |  |
| server/sim/netencode.aowl:40 | `gLanesLock` | LOCK | V | gLanes only under gLanesLock |  |
| server/sim/netencode.aowl:41 | `gLanesInit` | LOCK | V | gLanes only under gLanesLock |  |
| server/sim/netencode.aowl:42 | `gSink` | UNSAFE | V | `lanePush` (called by `JavaClient.writePacket`, so from player/world code in a dim job) does `drainDone(gPool, netOwner(0), gSink); gSink.setLen(0)` on the shared global (MC_NET_WORKERS=1) | local `var sink` inside lanePush |
| server/sim/netencode.aowl:51 | `gOwners` | LAZY | V | `netOwner` / `netEncodeEnabled` decide and allocate owners lazily, can run first on a dim thread | call once from prewarmAll |
| server/sim/netencode.aowl:52 | `gOwnersPool` | LAZY | V | `netOwner` / `netEncodeEnabled` decide and allocate owners lazily, can run first on a dim thread | call once from prewarmAll |
| server/sim/ownerguard.aowl:17 | `gMode` | LOCK | V | gTickThread atomic; counters/messages under gLock; gMode/lock decided by guardsEnabled on the first thread |  |
| server/sim/ownerguard.aowl:18 | `gTickThread` | LOCK | V | gTickThread atomic; counters/messages under gLock; gMode/lock decided by guardsEnabled on the first thread |  |
| server/sim/ownerguard.aowl:19 | `gLock` | LOCK | V | gTickThread atomic; counters/messages under gLock; gMode/lock decided by guardsEnabled on the first thread |  |
| server/sim/ownerguard.aowl:20 | `gLockReady` | LOCK | V | gTickThread atomic; counters/messages under gLock; gMode/lock decided by guardsEnabled on the first thread |  |
| server/sim/ownerguard.aowl:21 | `gCount` | LOCK | V | gTickThread atomic; counters/messages under gLock; gMode/lock decided by guardsEnabled on the first thread |  |
| server/sim/ownerguard.aowl:22 | `gMessages` | LOCK | V | gTickThread atomic; counters/messages under gLock; gMode/lock decided by guardsEnabled on the first thread |  |
| server/sim/ownerguard.aowl:29 | `gInJob` | TV | V | threadvar |  |
| server/sim/ownerguard.aowl:30 | `gInDim` | TV | V | threadvar |  |
| server/sim/ownerguard.aowl:32 | `gFpOn` | TV | V | threadvar |  |
| server/sim/ownerguard.aowl:33 | `gFpX` | TV | V | threadvar |  |
| server/sim/ownerguard.aowl:34 | `gFpZ` | TV | V | threadvar |  |
| server/sim/ownerguard.aowl:35 | `gFpMargin` | TV | V | threadvar |  |
| server/sim/pktslots.aowl:37 | `gPktDecided` | LOCK | G | network receive pump (tick thread); gTable under gTableLock |  |
| server/sim/pktslots.aowl:38 | `gPktOn` | LOCK | G | network receive pump (tick thread); gTable under gTableLock |  |
| server/sim/pktslots.aowl:39 | `gTable` | LOCK | G | network receive pump (tick thread); gTable under gTableLock |  |
| server/sim/pktslots.aowl:40 | `gTableLock` | LOCK | G | network receive pump (tick thread); gTable under gTableLock |  |
| server/sim/pktslots.aowl:41 | `gTableInit` | LOCK | G | network receive pump (tick thread); gTable under gTableLock |  |
| server/sim/pktslots.aowl:42 | `gPktSink` | LOCK | G | network receive pump (tick thread); gTable under gTableLock |  |
| server/sim/playerlock.aowl:11 | `gPlayerTablesLock` | LOCK | V | the lock itself, initLock at module init |  |
| server/sim/regionphase.aowl:32 | `gDecided` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:33 | `gOn` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:34 | `gPool` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:35 | `gOwner` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:36 | `gRuns` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:37 | `gTasks` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:38 | `gFailed` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/regionphase.aowl:39 | `gMaxShards` | TICK | V | `scanChunksOnPool` returns false inside a job or dim job; the only region body is `scanRolls` (read-only sampling); stats written on the tick thread after the join |  |
| server/sim/savepool.aowl:30 | `gSavePool` | TICK | G | only `compressBatch` (filemanager region save) drains gSaveSink; single concurrent caller assumed. NOT verified that two world threads never save at once (autosave/unload are tick-thread paths); if saves move into dim/region tasks give each caller its own sink |  |
| server/sim/savepool.aowl:31 | `gSaveDecided` | TICK | G | only `compressBatch` (filemanager region save) drains gSaveSink; single concurrent caller assumed. NOT verified that two world threads never save at once (autosave/unload are tick-thread paths); if saves move into dim/region tasks give each caller its own sink |  |
| server/sim/savepool.aowl:32 | `gSaveOn` | TICK | G | only `compressBatch` (filemanager region save) drains gSaveSink; single concurrent caller assumed. NOT verified that two world threads never save at once (autosave/unload are tick-thread paths); if saves move into dim/region tasks give each caller its own sink |  |
| server/sim/savepool.aowl:33 | `gTasks` | LOCK | V | gTasks under gTasksLock |  |
| server/sim/savepool.aowl:34 | `gTasksLock` | LOCK | V | gTasks under gTasksLock |  |
| server/sim/savepool.aowl:35 | `gTasksInit` | LOCK | V | gTasks under gTasksLock |  |
| server/sim/savepool.aowl:36 | `gSaveSink` | TICK | G | only `compressBatch` (filemanager region save) drains gSaveSink; single concurrent caller assumed. NOT verified that two world threads never save at once (autosave/unload are tick-thread paths); if saves move into dim/region tasks give each caller its own sink |  |
| server/sim/savepool.aowl:38 | `gSaveOwner` | TICK | G | only `compressBatch` (filemanager region save) drains gSaveSink; single concurrent caller assumed. NOT verified that two world threads never save at once (autosave/unload are tick-thread paths); if saves move into dim/region tasks give each caller its own sink |  |
| server/ticktimes.aowl:15 | `tickTimesNanos` | TICK | G | server tick bookkeeping |  |
| server/ticktimes.aowl:16 | `aggregatedTickTimesNanos` | TICK | G | server tick bookkeeping |  |
| server/ticktimes.aowl:17 | `tickCount` | TICK | G | server tick bookkeeping |  |
| server/world/bulkedit.aowl:123 | `gBeMemo` | TICK | V | bulk edit callers: fluidhost, erosionwire, firewire, bodymanager (collapse apply), worldedit: all tick thread. gBeMemo is a lazily filled Table, gBulkPhaseNs a `+=` profile array (only with gBulkProfile, never set in tree). FRAGILE: becomes UNSAFE the moment a bulk edit runs inside a dim or region task | prewarm gBeMemo for all block states in prewarmAll (peer file: bulkedit.aowl) |
| server/world/bulkedit.aowl:124 | `gBulkProfile` | TICK | V | bulk edit callers: fluidhost, erosionwire, firewire, bodymanager (collapse apply), worldedit: all tick thread. gBeMemo is a lazily filled Table, gBulkPhaseNs a `+=` profile array (only with gBulkProfile, never set in tree). FRAGILE: becomes UNSAFE the moment a bulk edit runs inside a dim or region task | prewarm gBeMemo for all block states in prewarmAll (peer file: bulkedit.aowl) |
| server/world/bulkedit.aowl:125 | `gBulkPhaseNs` | TICK | V | bulk edit callers: fluidhost, erosionwire, firewire, bodymanager (collapse apply), worldedit: all tick thread. gBeMemo is a lazily filled Table, gBulkPhaseNs a `+=` profile array (only with gBulkProfile, never set in tree). FRAGILE: becomes UNSAFE the moment a bulk edit runs inside a dim or region task | prewarm gBeMemo for all block states in prewarmAll (peer file: bulkedit.aowl) |
| server/world/chunker.aowl:9 | `gLoadEntityChunksHook` | IMM | G | hook procs installed at init |  |
| server/world/chunker.aowl:17 | `gRemoveEntitiesInChunksHook` | IMM | G | hook procs installed at init |  |
| server/world/dragon_fight_world.aowl:36 | `gFights` | TICK | V | written by `installDragonFight` at world creation; read by dim jobs only between phases |  |
| server/world/explosion.aowl:30 | `explosionRandomState` | TV | V | threadvar |  |
| server/world/explosion.aowl:31 | `explosionRandomInit` | TV | V | threadvar |  |
| server/world/levelsync.aowl:19 | `gLoadedGameType` | TICK | V | levelsync runs after the barrier (docs) |  |
| server/world/loot.aowl:51 | `gLootRand` | WORLD | V | only the fallback when LootContextParameters.rng is nil; every caller in tree passes `addr world.lootRand` (lootbridge.aowl:34,60; commandbridge.aowl:498) |  |
| server/world/mapglue.aowl:23 | `gMapManager` | TICK | V | createMap/nextMapId from item use (packet handler, tick thread); `tickMaps(player)` in the player tick reads the table from a dim job and mutates the shared MapData: two players holding the same map in two worlds would race on that MapData (rare, not fixed) | per-map lock or defer map ticks to the join phase |
| server/world/mapglue.aowl:24 | `gNextMapId` | TICK | V | createMap/nextMapId from item use (packet handler, tick thread); `tickMaps(player)` in the player tick reads the table from a dim job and mutates the shared MapData: two players holding the same map in two worlds would race on that MapData (rare, not fixed) | per-map lock or defer map ticks to the join phase |
| server/world/portal/portalmod.aowl:172 | `gPortalManagers` | LOCK | V | gPortalLock taken inside dim jobs (portalmod.aowl:180-204) |  |
| server/world/portal/portalmod.aowl:175 | `gPortalLock` | LOCK | V | gPortalLock taken inside dim jobs (portalmod.aowl:180-204) |  |
| server/world/weather.aowl:24 | `weatherSeedCounter` | TICK | V | only `newWeather` at world creation |  |
| server/world/worldmod.aowl:689 | `gCalculateRespawnHook` | IMM | G | hook procs assigned at init |  |
| server/world/worldmod.aowl:698 | `gPlayerRespawnedHook` | IMM | G | hook procs assigned at init |  |
| server/world/worldmod.aowl:707 | `gPlayerEnteredDimensionHook` | IMM | G | hook procs assigned at init |  |
| server/world/worldmod.aowl:975 | `gNaturalSpawnHook` | IMM | G | hook procs assigned at init |  |
| server/world/worldmod.aowl:981 | `gPlayerEntityTickHook` | IMM | G | hook procs assigned at init |  |
| server/worldedit/wecmd.aowl:61 | `gServer` | TICK | V | wecmd entries asserted tick-thread |  |
| server/worldedit/wecmd.aowl:62 | `gInstalled` | TICK | V | wecmd entries asserted tick-thread |  |
| server/worldedit/wecmd.aowl:63 | `gLastTick` | TICK | V | wecmd entries asserted tick-thread |  |
| server/worldedit/wecmd.aowl:64 | `gPrevEvent` | TICK | V | wecmd entries asserted tick-thread |  |
| server/worldedit/wecmd.aowl:66 | `gPrevInteract` | TICK | V | wecmd entries asserted tick-thread |  |
| server/worldedit/weworld.aowl:74 | `gSessions` | TICK | V | only wecmd handlers (tick thread) |  |
| util/random/random.aowl:24 | `seedUniquifier` | LOCK | V | atomicCompareExchange |  |
| util/text/color.aowl:124 | `colorOverride` | TICK | G | set at startup from config |  |
| util/translation.aowl:30 | `translationsLock` | LOCK | G | translationsLock |  |
| util/translation.aowl:31 | `translationTables` | LOCK | G | translationsLock |  |
| world/chunk_system/generation_executor.aowl:87 | `gExec` | LOCK | G | gGenLock around gTasks/gFreeTasks; gExec created on first schedule (tick thread) |  |
| world/chunk_system/generation_executor.aowl:89 | `gGenLock` | LOCK | G | gGenLock around gTasks/gFreeTasks; gExec created on first schedule (tick thread) |  |
| world/chunk_system/generation_executor.aowl:90 | `gGenLockInit` | LOCK | G | gGenLock around gTasks/gFreeTasks; gExec created on first schedule (tick thread) |  |
| world/chunk_system/generation_executor.aowl:91 | `gTasks` | LOCK | G | gGenLock around gTasks/gFreeTasks; gExec created on first schedule (tick thread) |  |
| world/chunk_system/generation_executor.aowl:92 | `gFreeTasks` | LOCK | G | gGenLock around gTasks/gFreeTasks; gExec created on first schedule (tick thread) |  |
| world/chunk_system/schedule.aowl:92 | `gDepth` | IMM | G | read from env once |  |
| world/chunk_system/schedule.aowl:93 | `gSchedStats` | IMM | G | read from env once |  |
| world/chunk_system/schedule.aowl:94 | `gStPasses` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:95 | `gStWorkPasses` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:96 | `gStSubmitted` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:97 | `gStIo` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:98 | `gStNotReady` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:99 | `gStWaiting` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:100 | `gStStale` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:101 | `gStWorkUs` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:102 | `gStWorkMaxUs` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunk_system/schedule.aowl:103 | `gStLast` | UNSAFE | G | MC_GEN_STATS counters of the schedule pass; the pass runs from `sendChange(chunkLoading)` at the end of `worldmod.tick` (dim job). Non-atomic, benign data loss, only with MC_GEN_STATS=1 (not read in detail) | peer file: atomics or per-schedule counters |
| world/chunkformat.aowl:28 | `unknownPaletteEntries` | UNSAFE | V | `inc` at chunkformat.aowl:72/76/121 from chunk decode, which runs on chunk IO/generation workers; benign (a statistics counter), tests read it | atomic inc (peer file src/world chunk owner) |
| world/generation/carver/carvers.aowl:70 | `replaceableTables` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/decode.aowl:36 | `nullTree` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/decode.aowl:916 | `configuredOverride` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/decode.aowl:917 | `placedOverride` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/decode.aowl:958 | `configuredDefs` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/decode.aowl:959 | `placedDefs` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/feature_order.aowl:138 | `overworldOrder` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/feature_order.aowl:139 | `netherOrder` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/feature_order.aowl:140 | `endOrder` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/placed_features.aowl:22 | `configuredGenerateHook` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/types.aowl:273 | `placedGenerateHook` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/feature/types.aowl:277 | `placedGetHook` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/genlock.aowl:8 | `genLockCell` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/protostructures.aowl:182 | `stepStructures` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/protostructures.aowl:183 | `stepStructuresReady` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/structures/jigsaw.aowl:87 | `poolCache` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/structures/jigsaw_placement.aowl:197 | `structuresJsonRoot` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/structures/jigsaw_placement.aowl:198 | `structuresJsonReady` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/structures/nether_fortress/fortressbase.aowl:44 | `pieceGeneratorHook` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/structures/stronghold/strongholdbase.aowl:43 | `pieceGeneratorHook` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/cache.aowl:20 | `templateIndex` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/cache.aowl:21 | `poolJsonIndex` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/cache.aowl:22 | `processorJsonIndex` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/cache.aowl:23 | `poolElements` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/cache.aowl:24 | `indexed` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/cache.aowl:25 | `globalCacheInstance` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/processor.aowl:61 | `tagSets` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/processor.aowl:62 | `tagSetsReady` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structure/template/processor.aowl:63 | `processorListCache` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structurehooks.aowl:64 | `structureHooks` | LOCK | G | peer-owned generation tables: filled by `prewarmWorldgen` (generation_executor.aowl:208) or guarded by `lockGen` (genlock.aowl; spot-checked: carvers.aowl:75, jigsaw.aowl:242/270, template/cache.aowl, processor.aowl:401); hook procs set once at init. Individual read paths NOT re-verified |  |
| world/generation/structurehooks.aowl:75 | `featureWorldSeed` | TV | V | threadvar, set per chunk in proto_chunk.aowl:399 |  |

### 7.2 Collapsed: lazy block / block-entity / fluid singletons (105, LAZY, G)

Class LAZY for all; evidence and fix as in section 4 item 1. Names:

* `server/block/blocks/amethyst.aowl`: gAmethystBlockAsWallMountedBlock:13
* `server/block/blocks/grindstone.aowl`: gGrindstoneBlockAsWallMountedBlock:13
* `server/block/blocks/plant/bamboo.aowl`: gBambooBlockAsPlantBlockBase:13
* `server/block/blocks/plant/bamboo_sapling.aowl`: gBambooSaplingBlockAsPlantBlockBase:13
* `server/block/blocks/plant/big_dripleaf.aowl`: gBigDripleafBlockAsPlantBlockBase:16
* `server/block/blocks/plant/big_dripleaf_stem.aowl`: gBigDripleafStemBlockAsPlantBlockBase:14
* `server/block/blocks/plant/bush.aowl`: gBushBlockAsPlantBlockBase:13
* `server/block/blocks/plant/cactus_flower.aowl`: gCactusFlowerBlockAsPlantBlockBase:13
* `server/block/blocks/plant/crop/beetroot.aowl`: gBeetrootBlockAsPlantBlockBase:15, gBeetrootBlockAsCropBlockBase:16
* `server/block/blocks/plant/crop/carrot.aowl`: gCarrotBlockAsPlantBlockBase:14, gCarrotBlockAsCropBlockBase:15
* `server/block/blocks/plant/crop/gourds/attached_stem.aowl`: gAttachedStemBlockAsPlantBlockBase:15
* `server/block/blocks/plant/crop/gourds/stem.aowl`: gStemBlockAsPlantBlockBase:16
* `server/block/blocks/plant/crop/nether_wart.aowl`: gNetherWartBlockAsPlantBlockBase:14, gNetherWartBlockAsCropBlockBase:15
* `server/block/blocks/plant/crop/potatoes.aowl`: gPotatoBlockAsPlantBlockBase:14, gPotatoBlockAsCropBlockBase:15
* `server/block/blocks/plant/crop/sweet_berry_bush.aowl`: gSweetBerryBushBlockAsPlantBlockBase:14, gSweetBerryBushBlockAsCropBlockBase:15
* `server/block/blocks/plant/crop/torch_flower.aowl`: gTorchFlowerBlockAsPlantBlockBase:15, gTorchFlowerBlockAsCropBlockBase:16
* `server/block/blocks/plant/crop/wheat.aowl`: gWheatBlockAsPlantBlockBase:14, gWheatBlockAsCropBlockBase:15
* `server/block/blocks/plant/dry_vegetation.aowl`: gDryVegetationBlockAsPlantBlockBase:13
* `server/block/blocks/plant/flower.aowl`: gFlowerBlockAsPlantBlockBase:14
* `server/block/blocks/plant/flowerbed.aowl`: gFlowerbedBlockAsPlantBlockBase:15, gFlowerbedBlockAsSegmented:16
* `server/block/blocks/plant/fungus.aowl`: gFungusBlockAsPlantBlockBase:13
* `server/block/blocks/plant/kelp.aowl`: gKelpBlockAsPlantBlockBase:13
* `server/block/blocks/plant/leaf_litter.aowl`: gLeafLitterBlockAsSegmented:14
* `server/block/blocks/plant/lily_pad.aowl`: gLilyPadBlockAsPlantBlockBase:14
* `server/block/blocks/plant/mushroom_plant.aowl`: gMushroomPlantBlockAsPlantBlockBase:13
* `server/block/blocks/plant/nether_sprouts.aowl`: gNetherSproutsBlockAsPlantBlockBase:13
* `server/block/blocks/plant/roots.aowl`: gRootsBlockAsPlantBlockBase:13
* `server/block/blocks/plant/sapling.aowl`: gSaplingBlockAsPlantBlockBase:14
* `server/block/blocks/plant/sea_pickles.aowl`: gSeaPickleBlockAsPlantBlockBase:14
* `server/block/blocks/plant/seagrass.aowl`: gSeaGrassBlockAsPlantBlockBase:13
* `server/block/blocks/plant/short_plant.aowl`: gShortPlantBlockAsPlantBlockBase:13
* `server/block/blocks/plant/small_dripleaf.aowl`: gSmallDripleafBlockAsPlantBlockBase:13
* `server/block/blocks/plant/spore_blossom.aowl`: gSporeBlossomBlockAsPlantBlockBase:13
* `server/block/blocks/plant/tall_plant.aowl`: gTallPlantBlockAsPlantBlockBase:13
* `server/block/blocks/plant/tall_seagrass.aowl`: gTallSeaGrassBlockAsPlantBlockBase:14
* `server/block/blocks/plant/twisting_vines.aowl`: gTwistingVinesBlockAsPlantBlockBase:13
* `server/block/blocks/plant/weeping_vines.aowl`: gWeepingVinesBlockAsPlantBlockBase:13
* `server/block/blocks/plant/wither_rose.aowl`: gWitherRoseBlockAsPlantBlockBase:14
* `server/block/blocks/redstone/bell.aowl`: gBellBlockAsWallMountedBlock:15
* `server/block/blocks/redstone/buttons.aowl`: gButtonBlockAsWallMountedBlock:15
* `server/block/blocks/redstone/comparator.aowl`: gComparatorBlockAsRedstoneGateBlock:14
* `server/block/blocks/redstone/lever.aowl`: gLeverBlockAsWallMountedBlock:13
* `server/block/blocks/redstone/pressure_plate/plate.aowl`: gPressurePlateBlockAsPressurePlate:14
* `server/block/blocks/redstone/pressure_plate/weighted.aowl`: gWeightedPressurePlateBlockAsPressurePlate:14
* `server/block/blocks/redstone/repeater.aowl`: gRepeaterBlockAsRedstoneGateBlock:14
* `server/block/entities/banner.aowl`: gBannerBlockEntityVt:17
* `server/block/entities/barrel.aowl`: gBarrelBlockEntityVt:20
* `server/block/entities/beacon.aowl`: gBeaconBlockEntityVt:31
* `server/block/entities/bed.aowl`: gBedBlockEntityVt:14
* `server/block/entities/beehive.aowl`: gBeehiveBlockEntityVt:20
* `server/block/entities/bell.aowl`: gBellBlockEntityVt:19
* `server/block/entities/blasting_furnace.aowl`: gBlastingFurnaceBlockEntityVt:19
* `server/block/entities/brewing_stand.aowl`: gBrewingStandBlockEntityVt:35
* `server/block/entities/brushable_block.aowl`: gBrushableBlockBlockEntityVt:18
* `server/block/entities/calibrated_sculk_sensor.aowl`: gCalibratedSculkSensorBlockEntityVt:16
* `server/block/entities/campfire.aowl`: gCampfireBlockEntityVt:18
* `server/block/entities/chest_like_block_entity.aowl`: gChestLikeVt:28
* `server/block/entities/chiseled_bookshelf.aowl`: gChiseledBookshelfBlockEntityVt:22
* `server/block/entities/command_block.aowl`: gCommandBlockEntityVt:24
* `server/block/entities/comparator.aowl`: gComparatorBlockEntityVt:16
* `server/block/entities/conduit.aowl`: gConduitBlockEntityVt:17
* `server/block/entities/copper_golem_statue.aowl`: gCopperGolemStatueBlockEntityVt:15
* `server/block/entities/crafter.aowl`: gCrafterBlockEntityVt:20
* `server/block/entities/creaking_heart.aowl`: gCreakingHeartBlockEntityVt:15
* `server/block/entities/daylight_detector.aowl`: gDaylightDetectorBlockEntityVt:15
* `server/block/entities/decorated_pot.aowl`: gDecoratedPotBlockEntityVt:17
* `server/block/entities/dispenser.aowl`: gDispenserBlockEntityVt:19
* `server/block/entities/dropper.aowl`: gDropperBlockEntityVt:19
* `server/block/entities/enchanting_table.aowl`: gEnchantingTableBlockEntityVt:16
* `server/block/entities/end_gateway.aowl`: gEndGatewayBlockEntityVt:18
* `server/block/entities/end_portal.aowl`: gEndPortalBlockEntityVt:15
* `server/block/entities/ender_chest.aowl`: gEnderChestBlockEntityVt:18
* `server/block/entities/furnace.aowl`: gFurnaceBlockEntityVt:19
* `server/block/entities/hanging_sign.aowl`: gHangingSignBlockEntityVt:20
* `server/block/entities/hopper.aowl`: gHopperBlockEntityVt:23
* `server/block/entities/jigsaw_block.aowl`: gJigsawBlockEntityVt:28, gJigsawGenerateHook:30
* `server/block/entities/jukebox.aowl`: gJukeboxBlockEntityVt:22
* `server/block/entities/lectern.aowl`: gLecternBlockEntityVt:19
* `server/block/entities/mob_spawner.aowl`: gMobSpawnerBlockEntityVt:30
* `server/block/entities/piston.aowl`: gPistonBlockEntityVt:26
* `server/block/entities/potent_sulfur.aowl`: gPotentSulfurBlockEntityVt:15
* `server/block/entities/sculk_catalyst.aowl`: gSculkCatalystBlockEntityVt:16
* `server/block/entities/sculk_sensor.aowl`: gSculkSensorBlockEntityVt:16
* `server/block/entities/sculk_shrieker.aowl`: gSculkShriekerBlockEntityVt:16
* `server/block/entities/shelf.aowl`: gShelfBlockEntityVt:19
* `server/block/entities/shulker_box.aowl`: gShulkerBoxBlockEntityVt:19
* `server/block/entities/sign.aowl`: gSignBlockEntityVt:43
* `server/block/entities/skull.aowl`: gSkullBlockEntityVt:17
* `server/block/entities/smoker.aowl`: gSmokerBlockEntityVt:19
* `server/block/entities/structure_block.aowl`: gStructureBlockBlockEntityVt:33
* `server/block/entities/test_block.aowl`: gTestBlockBlockEntityVt:15
* `server/block/entities/test_instance_block.aowl`: gTestInstanceBlockBlockEntityVt:15
* `server/block/entities/trial_spawner.aowl`: gTrialSpawnerBlockEntityVt:18
* `server/block/entities/vault.aowl`: gVaultBlockEntityVt:17
* `server/block/fluid/lava.aowl`: gFlowingLavaAsFlowingFluid:18
* `server/block/fluid/water.aowl`: gFlowingWaterAsFlowingFluid:15

### 7.3 Collapsed: plugin host, hooks and engine (193)

Class TICK (hook procs installed when the plugin host loads; plugin code runs on the tick thread; a loaded plugin keeps the dim gate shut; plugin job kernels never call plugin code). V for `pluginhooks*` and `enginejobs`, G for the rest.

* `plugin/api/events/player/bedrock_form_response.aowl` (1): gBedrockFormResponseHook:22
* `plugin/api/events/player/custom_click_action.aowl` (1): gCustomClickActionHook:22
* `plugin/api/events/player/egg_throw.aowl` (1): gEggThrowHook:27
* `plugin/api/events/player/fish.aowl` (1): gFishHook:42
* `plugin/datapackcmd.aowl` (3): gServer:19, gDepth:20, gTickBusy:21
* `plugin/engine/aoe.aowl` (18): gLib:46, pInit:47, pShutdown:48, pSetHost:49, pLastError:50, pLoad:51, pUnload:52, pHasEntry:53, pCall:54, pModeOf:55, pModeReason:56, pStdout:57, pStderr:58, pReplace:59, gWorkerMode:62, pClientOpen:63, pClientSelect:64, pClientClose:65
* `plugin/engine/enginehost.aowl` (8): hostTable:28, resultText:29, engineUp:30, gSlots:41, gCallResult:42, gClients:166, gHandles:167, gWorkerError:168
* `plugin/engine/enginejobs.aowl` (5): gJobs:67, gOwners:68, gMeta:69, gReady:70, gNextId:71
* `plugin/engine/engineplugins.aowl` (82): gPlugins:61, gEngineServer:62, gCurPlayer:63, gEvName:64, gEvPlayerName:65, gEvMessage:66, gEvCancelled:67, gEvValue:68, gEvFlag:69, gScope:70, gEvOwner:71, gLive:72, gSubs:73, gSourceText:74, gEvStrs:75, gEvNums:76, gLogLines:87, gLogPending:88, gTasks:612, gNextTask:613, gNowTick:614, gPrevChat:813, gPrevCommand:814, gPrevJoin:815, gPrevLeave:816, gPrevMove:836, gPrevTeleport:837, gPrevToggle:838, gPrevMode:839, gPrevHeld:840, gPrevLogin:841, gPrevInteract:842, gPrevPlace:843, gPrevCommandSrv:879, gPrevBroadcast:880, gPrevTickStart:881, gPrevTickEnd:882, gPrevLoad:883, gPrevPacket:884, gPrevRedstone:885, gPrevSpawn:911, gPrevGrow:912, gPrevChunk:914, gReply:966, gCmdFail:967, gCmdOwners:968, gHostReady:1204, gPrevLevel:1540, gPrevSave:1541, gPrevTime:1542, gPrevProjectile:1555, gPrevItemMove:1565, gPrevJester:1570, gPrevAdvancement:1572, gPrevTarget:1577, gPrevTab:1584, gPrevKick:1590, gPrevPortal:1595, gPrevFurnace:1597, gPrevBlockChange:1607, gPrevPiston:1617, gPrevCombust:1624, gPrevEntityTeleport:1626, gPrevEffect:1637, gPrevHeal:1644, gPrevFood:1645, gPrevStat:1646, gPrevPing:1647, gPrevPreLogin:1648, gPrevDamage:1675, gPrevEntityDeath:1677, gPrevEntitySpawn:1678, gPrevEntityRemove:1679, gPrevExplosion:1680, gPrevWeather:1681, gPrevPlayerEv:1714, gPrevChangeWorld:1715, gPrevFish:1717, gPrevEgg:1718, gPrevClick:1719, gPrevExp:1814, gPrevRespawn:1815
* `plugin/packscmd.aowl` (1): gPackWorld:16
* `plugin/payloads.aowl` (4): gPayloadChannels:7, gModsyncActive:116, gJesterClients:117, gServerCaps:118
* `plugin/pluginhooks.aowl` (24): gPluginChatHook:15, gPluginCommandHook:24, gPluginMoveHook:33, gPluginToggleHook:42, gPluginGameModeHook:51, gPluginItemHeldHook:60, gPluginTeleportHook:69, gPluginChangeWorldHook:78, gPluginJoinHook:87, gPluginLeaveHook:96, gPluginRespawnHook:105, gPluginExpChangeHook:114, gPluginLoginHook:123, gPluginInteractHook:132, gPluginBlockPlaceHook:142, gServerCreateWorldHook:152, gServerUnloadWorldHook:162, gServerSaveAllHook:171, gPluginBedrockSessionHook:219, gPluginBedrockFormHook:228, gPluginBedrockVersionHook:238, gPluginBedrockDataHook:246, gPluginBedrockSendHook:254, gPluginPlayerEventHook:261
* `plugin/pluginhooksblock.aowl` (9): gPluginBlockChangeHook:4, gPluginBlockChangeListened:9, gPluginPortalHook:17, gPluginFurnaceHook:24, gPluginKickHook:31, gPluginTargetHook:38, gPluginAdvancementHook:45, gPluginItemMoveHook:52, gPluginJesterHook:59
* `plugin/pluginhooksevents.aowl` (29): gPluginBlockGrowHook:24, gPluginBlockRedstoneHook:36, gPluginSpawnChangeHook:48, gPluginServerCommandHook:60, gPluginServerBroadcastHook:69, gPluginTickStartHook:78, gPluginTickEndHook:87, gPluginServerLoadHook:96, gPluginPacketReceivedHook:105, gPluginEntityDamageHook:117, gPluginEntityDeathHook:127, gPluginEntitySpawnHook:134, gPluginEntityRemoveHook:141, gPluginExplosionHook:148, gPluginWeatherHook:155, gPluginEntityHealHook:165, gPluginFoodLevelHook:172, gPluginStatHook:179, gPluginServerListPingHook:186, gPluginPreLoginHook:193, gPluginLevelChangeHook:202, gPluginSaveHook:209, gPluginTimeSetHook:215, gPluginEffectHook:224, gPluginCombustHook:233, gPluginEntityTeleportHook:240, gPluginPistonHook:249, gPluginProjectileHitHook:258, gPluginTabCompleteHook:270
* `plugin/pluginmanager.aowl` (6): gRecs:45, gServerOpt:46, gHotReload:47, gHooksInstalled:48, gLastPoll:49, gScriptRuns:251

### 7.4 Collapsed: offline harnesses (25, NA)

* `physics/scenes.aowl` (21): gQuiet:50, gFailures:51, gChecks:52, gGoldMiss:53, gKeys:73, gVals:74, gTols:75, rowKey:78, rowActual:79, rowExpected:80, rowStatus:81, gW:345, gS:346, gNx:347, gNy:348, gNz:349, gAir:800, gLog:801, gBlastIds:867, gBlastNx:868, gBlastNz:869
* `server/entity/mob/testworld.aowl` (1): dropped:17
* `server/sim/poolbench.aowl` (3): gBufs:29, gGrids:30, failures:171
