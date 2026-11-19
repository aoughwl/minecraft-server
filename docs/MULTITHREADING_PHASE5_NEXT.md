# Phase 5: what to move onto region tasks next (design only, nothing built or run)

Read-only study of mt-int at 25ff8f2. No build, no server, no scenario was run; all cost figures come from `docs/bench_server_results.jsonl`
(28 runs of `tools/bench_server.py`, profiler scopes) and from reading the code. Peer-owned and therefore READ-ONLY for this work:
`src/world/chunk_system`, `src/world/generation`, `src/physics` (includes `FluidSim`), `src/server/world/bulkedit.aowl`.

## 0. Bottom line

* **No candidate has a decide pass whose cost is a real fraction of the tick.** The one wired split (random-tick scan) is already the cheap kind
  of work; the next candidates are either cheaper still, or not splittable without changing results, or nondeterministic today.
* The numbers that exist: the whole `block ticks` scope (`worldmod.tickChunks`: draw + scan + scheduled collect + apply + natural spawn hook)
  is 0.02 to 0.14 ms per tick at idle with 289 active chunks (gen phase: 16.6 to 51 ms summed over 279 to 905 ticks, `mspt_mean` 0.12 to 0.25).
  Nothing inside that can repay a pool job.
* During the bench fill phase (`/fill` 32768 blocks, 167 to 238 ticks, mspt_mean about 22 to 29) `block ticks` is about 2.0 to 2.9 s total
  (roughly 9 to 12 ms per tick, about 40 percent of the tick) and `entities` 1.6 to 2.7 s (about 8 to 11 ms per tick). That is by far the biggest
  tick-thread cost in the data, but the profile cannot say WHICH part of the scope it is (scheduled/neighbour-update apply after the fill,
  random-tick apply, the spawn hook, or entity ticks of whatever the fill spawned). Those parts are all apply-side or interleaved with rng and
  hooks, i.e. not decide-pass work. Do not pick a threading target before that is split (section 4, step 0).
* Two real, safe, single-thread wins found on the way (identical results, no threads): section 2c and the entity index in 2e.

## 1. How the existing split works (what a candidate must copy)

`level.drawRandomRolls` (tick thread, the Level's xorshift) -> `regionphase.scanChunksOnPool` (one `RegionTask` per active chunk, home = the
chunk, margin 0, tile 4, 4 colour phases, join) -> concatenate slots in task-id order -> `worldadapter.runTickData` on the tick thread. Gate
`MC_REGION_THREADS=1`; inline fallback when off, in a pool/dim job, or on a failed run. Rule: every random number is drawn on the tick thread in the
old order BEFORE the parallel part; the parallel part only reads and writes its own slot.

## 2. Candidates

### 2a. Crop growth (and the other random-tick bodies) as decide + ordered apply

* Functions: `src/server/block/blocks/plant/crop/cropmod.aowl` `defaultRandomTick_CropBlockBase` and `getAvailableMoisture` (the read part: 3x3
  farmland below + 4 neighbours + 4 diagonals at pos, i.e. blocks within 1 of the position, so chunk margin 1 at borders); apply =
  `callPluginBlockGrowHook` + `world.setBlockState(pos, newState, BfNotifyNeighbors)`; dispatch in `worldadapter.runTickData` (line ~240).
  Other bodies with the same shape: wheat/carrot/potato/beetroot/stem/nether wart/sweet berry/sugar cane/cactus/bamboo/sapling/flower/farmland/
  snow/lava/chests/flower_pots. Note: there is NO grass/mycelium spread and no leaf decay or fire random tick in this port (`grass_block.aowl` only
  has a neighbour-update behaviour; `spreadingsnowy.aowl` is unregistered), so "grass spread" is not a candidate.
* Reads in the decide pass: `world.getBlockAndStateId`/`getBlock` over a 3x3 below + 8 neighbours (block sections of up to 9 chunks) and constant
  tables. Concurrent-read safe only if nothing writes blocks during the phase: true if the phase is a pure join before `runTickData`
  (no setBlockState runs in it). `BlockWorld.getBlock` goes through the world adapter and `loadedChunks` Table lookups: reads only, but verify
  it takes no lazily-initialising path (`world/level` is not peer-owned; `chunk_system` is).
* RNG hazard (blocking, found in code): the crop body draws from `blockprelude.rng()` which is a THREADVAR xorshift64* seeded from
  `getSeed()` (wall clock). So growth is nondeterministic run to run even at threads=1 today, and a decide pass on a worker would use that
  worker's own stream. "Identical world hash at 1/2/4" is impossible until the draw is made reproducible. Fix inside the existing pattern:
  `drawRandomRolls` draws a second u32 per roll (a "behaviour roll", level stream, tick thread); the body takes it instead of `rng()`. That
  changes the gate-off stream layout too (do it unconditionally), and bodies that still call `rng()` stay clock-seeded (every other random-tick
  body, plus anything a plugin hook does).
* Apply must do, per sample in order: re-validate, then consume the roll, run the plugin `BlockGrowEvent` hook (cancellable, plugin code:
  must stay on the tick thread), `setBlockState` (BlockChangeEvent hook, block log, neighbour updates, light, scheduled ticks that may land in other
  chunks). Because an earlier sample's `setBlockState` can change a later sample's inputs (farmland dries, neighbouring crop), the decided
  result is only valid if no block in the sample's 3x3-chunk neighbourhood changed since the decide pass: keep a per-world "chunks written this
  apply" set (filled from `block/worldadapter.setBlockState`, not from `chunk_system`, which is peer-owned) and recompute inline when it is hit.
* Expected gain: about zero. A tick hits `3 x ticking sections x active chunks` cells (about 7 k at 289 chunks), only the fraction that are crops
  does the 20-read moisture scan (microseconds each). Even a 10 000-crop farm gives tens of crop ticks per tick, well under 0.1 ms. The cost
  that exists is in the apply (`setBlockState` + hooks) which cannot move.
* Verdict: pattern-compatible, correct to build, **not worth building** on this data. Only the make-the-RNG-reproducible part has independent value.

### 2b. Scheduled-tick collection

* Functions: `src/world/level.aowl` `collectScheduledTicks` (mutates `chunk.blockTicks/fluidTicks` via `stepTick`, edits
  `chunksWithScheduledTicks`, then two sorts); apply = `runTickData` first two loops (`onScheduledTick`, fluid `onScheduledTickImpl`).
* The collect is a loop over chunks that have schedules; per-chunk `stepTick` mutates its own scheduler (footprint = home chunk, margin 0), the
  set edit and the final sorts are global. It could be made a decide (pop into per-chunk slots, apply the set edits and the global sort on the tick
  thread; the order is fixed by the existing `tickLess` sort so any chunk order gives the same list). The reads are not read-only (it pops) but
  the writes are home-chunk-only.
* Gain: none. It is O(chunks with schedules) pointer work, a fraction of the 0.1 ms idle scope. The expensive part is the apply of the
  collected ticks (behaviour bodies: neighbour updates, fluids, redstone), which writes blocks across borders and fires hooks: not splittable.
  The previous audit row stands.
* Verdict: no worthwhile gain.

### 2c. Mob spawn candidate scan (`src/server/world/natural_spawner.aowl`, `naturalSpawnTick`, called from `tickChunks` via `gNaturalSpawnHook`)

* Real structure: `newSpawnState` (counts mobs: for EVERY entity does a linear `for c in world.activeChunks` search: O(E x A), A = 289 at one
  player) runs on every tick, then `getFilteredSpawningCategories`; if any category is allowed: `readChunkSync` for every active chunk, a
  Fisher-Yates shuffle with `world.spawnRand`, then per chunk `spawnForChunk` -> `getRandomPosWithin` -> `spawnCategoryForPosition`
  (group spawn with about 10 draws, `isValidSpawnPositionForType`, `spawnEntity`).
* Determinism: `getRandomPosWithin` seeds `fromSeed(getSeed())` per call (`util/random.getSeed` = clock xor atomic counter), so the candidate
  position is nondeterministic by design; the rest uses `World.spawnRand`, advanced by every earlier chunk's group attempts and by the mutable
  `SpawnState` (mob caps, `afterSpawn` charges) that each spawn changes. The pass is a sequential dependency chain; "decide per chunk" cannot be
  precomputed without changing the sequences (as the previous audit said), and there is no reproducible baseline to compare hashes against.
  Reading the heightmap for the candidate (`getHeightmap`, chunk-local, margin 0) is the only pure part and it is a few reads.
* Gain by threads: none. **Gain by algorithm: real and free.** Replace the linear `activeChunks` search in `newSpawnState` (line ~217) and in
  `entitymod.tickEntities` (line ~4158, the same loop per entity per tick) with one `activeChunkSet` (HashSet of `chunkKey`) built once in
  `worldmod.updateActiveChunks`. Results identical (same membership test). With E entities this removes E x 289 comparisons twice per tick
  (about 0.3 ms per 1000 entities each, and it scales with view distance squared). Testable by `natural_spawnertest` and `entitymodtest` unchanged.
  This is outside "region tasks" but is the only change here with a measurable payoff that is also provably result-identical.
* Verdict: no region split worth doing; do the set lookup.

### 2d. Fluid and redstone scans

* Vanilla fluids/redstone are scheduled-tick apply (2b): not splittable. Finite fluids (`src/server/fluids/fluidhost.aowl`, OFF by default via
  `/fluids on`): `scanPlayers` (version check of up to 175 sections per player every 10 ticks) and `runScans`/`rescanSection` (4096-cell loop
  per section, `MaxScansPerTick` = 12) are read-mostly: footprint home chunk + 1 for `exposed` (6 neighbour reads), write only `d.sim` tracked
  cells. A decide could return "fluid cells to adopt / tracked cells to forget" per section; apply (`adoptCell`, `forgetCell`, `wakeSection`)
  must run in order because `wakeSection` changes `isPending`, which later sections' forget test reads (so the decide must NOT evaluate
  `isPending`/`isTracked`; apply re-checks them). The sim itself (`FluidSim.step`, `src/physics`, peer-owned, READ-ONLY here) is the real cost
  and stays serial; `writeBack` goes through `bulkedit.writeCells` (peer-owned).
* Gain: scans are a transient (first look at 175 sections is about 15 ticks of 12 x 4096 cells = 49 k cell visits per tick, then only changed
  sections). The feature is opt-in and its scenario (`fluids_finite`) currently fails with and without gates. No evidence of a cost.
* Verdict: no worthwhile gain now. `fluidhost.gDims`/`gTick` are module-level (phase 2 item 3 not done), a further blocker.

### 2e. Entity AI target selection

* Functions: `src/server/entity/ai/goal/track_target.aowl` `findClosestTarget` (via `canStart`: `reciprocalChance` roll, then
  `world.getClosestPlayer` / `getClosestEntity`, `targetPredicate.test`, `callPluginTargetHook`), `entitymod.getNearbyEntities`/`getClosestEntity`
  (full O(E) scan of `entitiesOf(world).entities` that also allocates a seq, per query), `look_at_entity`, `escape_danger`, `mobaware.findShelter`
  (block reads).
* Cost shape: with E mobs, every active-target goal with a non-player target type is O(E) per search, so O(E x searches). This is the one place
  with a plausible superlinear read-only cost, and `entities` is the second-largest scope in the bench (8 to 11 ms per tick in the fill phase).
  But the bench has one idle bot and the composition of that cost (is it AI at all?) is unknown.
* Splitting hazard (blocking): the query reads entity positions that EARLIER entities of the same `tickEntities` loop already moved this tick,
  so a decide pass either changes semantics (start-of-tick snapshot: legal for the threads=1 vs N identity if both modes use it, but a behaviour
  change against today, one tick of target latency) or is not a decide pass. The goal selector interleaves `rng` draws (global threadvar), a
  cancellable plugin hook and navigation writes in one callback; `entitiesOf` falls back to module-level `gWorlds` (phase 2 item 2 partly done:
  `entitiesBox`), `gCollisionProviders` is a global mutable. Footprint = follow range (16 to 40 blocks = 1 to 3 chunks margin; mobs cross tile
  borders), so it needs a border phase.
* Cheaper first: a chunk-bucketed entity index (key -> list, kept by the existing entity chunk-move code) makes `getNearbyEntities` O(local).
  Candidate order must equal the entity list order (insertion-ordered buckets, or sort candidates by list index) so ties in `getClosestEntity` break
  identically. A single-thread change in `entitymod.aowl` (not a peer dir).
* Verdict: potentially the largest eventual gain; not a first region task. Do the profile split and the index before any threading.

## 3. Recommendation

1. **Do not start another region-task workload yet.** The honest conclusion of the data is that world-tick time at one player is tick-thread
   apply work plus entity ticking; the decide-able parts are microseconds.
2. **Best next candidate as a region task: 2a (crop growth decide)** if one must be chosen: the only one whose reads are provably
   concurrent-safe, whose footprint is simple (margin 1), and whose determinism fix (level-drawn behaviour rolls) is needed anyway. Expect no
   speedup; it is a correctness-first step, not a performance step.
3. **Best next change by value**: 2c's `activeChunkSet` (and the same fix in `tickEntities`), then 2e's entity chunk index, both guarded by a
   profile that proves where the fill-phase 10 ms per tick goes.

## 4. Step plan

0. Measure (needs a quiet machine and a build; not done here): add sub-scopes inside `ScBlockTicks` (draw, scan, collect, apply scheduled block,
   apply scheduled fluid, apply random, spawn hook) and inside `ScEntities` (entity count by type, AI goal tick, `getNearbyEntities` calls and
   time); run `tools/bench_server.py` base and a populated scenario (e.g. 200 mobs, a crop farm of 5 000 crops, one water pour). Choose targets from
   that. Profiler files are `src/server/profiler`: append scope names only.
1. `activeChunkSet`: build in `updateActiveChunks` (one `HashSet[int64]` of `chunkKey`), use it in `natural_spawner.newSpawnState` and
   `entitymod.tickEntities`. Check: `natural_spawnertest`, `entitymodtest`, `worldtest` unchanged; add a test that both give the same active set
   as the old linear search for random positions.
2. If 2a is still wanted: (a) add the behaviour roll to `ChunkRolls` (second u32 per draw) and make `CropBlockBase.randomTick` take it (default
   body keeps `rng()` for callers without a roll); (b) split the body into `decideGrow(world, pos, roll) -> GrowDecision` (pure: new state plus
   the chunks read) and `applyGrow` (hook + setBlockState); (c) one region task per active chunk with a crop sample, margin 1, tile size >= 3,
   decisions stored in the `ChunkRolls` slot; (d) apply loop in `runTickData` in sample order with the written-chunks check and inline recompute;
   (e) gate with the existing `MC_REGION_THREADS=1`, default off, inline fallback unchanged.
3. Add `assertInFootprint` calls in the decide reads (margin 1) so `MC_THREAD_ASSERT=1` catches a read outside the 3x3.

## 5. Test design (identical world hash at threads 1, 2, 4)

Extend `src/server/sim/regionphasetest.aowl` (already a scripted 10x10-chunk world, 30 ticks, gate off / 0 / 1 / 4 workers, 3 reps):

* World: farmland plus crops at seeded positions straddling chunk borders (including rows exactly on x or z = 15/0), age 0 to 6, some
  water-adjacent farmland, wheat/carrot/potato/beetroot, a few growth positions cancelled through a test hook.
* Run 200 ticks with `randomTickSpeed` 3 and 40 (the latter makes growth and the written-chunk recompute path frequent). Seed `Level.randState`
  and the behaviour-roll stream identically per run.
* Per tick record a digest of (sample positions, decided new states, whether the recompute path ran); at the end the world hash (all block
  sections, block log length, scheduled tick queues) and the recompute count.
* Assert equal digests and world hash for: gate off (inline decide), enabled with 0, 1, 2 and 4 workers, 5 reps each; assert at least one
  recompute happened at speed 40 (otherwise the test proves nothing) and that growth happened (hash differs from the initial world).
* Also: a run with the footprint guard on and a deliberate out-of-margin read that must be flagged; and the existing `leveltest`,
  `ownerguardtest`, `regionschedtest`, `jobpooltest`.
* Server-level confirmation (later, on a free machine): one scenario with a crop farm, `MC_REGION_THREADS=1` with `MC_THREADS=1/2/4`, `/save-all`,
  compare region file hashes with a fixed seed. Not meaningful today because other random-tick bodies and mob spawning draw clock-seeded rng.

## 6. Not verified

Everything above is from reading code and the existing bench file; no build, no run, no sub-scope profile. The statement that the fill-phase cost
is apply-side is an inference from code structure, not a measurement.
