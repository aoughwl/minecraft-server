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

## 7. Populated-tick profile and entity index design (measured 2026-11-19, `C:/m/int_c2.exe`, branch mt-prof from mt-int e8117d6)

### 7.1 Method

`tools/bench_populated.py` (new, standalone, no build): fresh world seed 123456789, view 6 / simulation 4, `pregen 8c` (289 chunks), then 3 idle
`mcbot.py` bots at spawn, then steps of `/summon` (alternating zombie, cow, skeleton, chicken, random x,z within 40 blocks of spawn, y 100) to a
total of 0, 100, 300, 600 summoned; each step 5 s settle then `/profile start` for 25 s (about 400 to 507 ticks) then `/profile export`. One server at
a time, ports 26800.., machine not otherwise idle (other agents' jobs run on it; absolute ms carry noise of a few percent, see the 0-step rows).
Sub-scopes `blockticks:rolls/scan/apply/spawner` exist in this build; entity sub-scopes do not. The server console had no working way to count
entities (`execute if entity` answered "Unknown command"), so the natural mob count at step 0 is NOT known; only the summoned count is.

### 7.2 Results (ms per tick, scope self time; all three bots stayed online)

Default settings (all gates off):

| summoned | mspt mean | p95 | entities | blockticks:spawner | players | apply | rolls | world maint | block entities |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 21.1 | 32.7 | 9.21 | 10.08 | 0.64 | 0.33 | 0.31 | 0.30 | 0.20 |
| 100 | 28.2 | 45.3 | 15.52 | 10.73 | 0.65 | 0.35 | 0.32 | 0.31 | 0.21 |
| 300 | 42.9 | 67.9 | 30.18 | 10.78 | 0.64 | 0.35 | 0.32 | 0.31 | 0.21 |
| 600 | 61.1 | 92.6 | 48.83 | 10.47 | 0.62 | 0.29 | 0.28 | 0.29 | 0.20 |

`MC_REGION_THREADS=1 MC_THREADS=4`:

| summoned | mspt mean | p95 | entities | blockticks:spawner | players | scan | rolls | apply |
|---|---|---|---|---|---|---|---|---|
| 0 | 19.4 | 28.0 | 7.14 | 10.10 | 0.63 | 0.51 | 0.32 | 0.09 |
| 100 | 24.5 | 40.8 | 12.73 | 9.75 | 0.61 | 0.51 | 0.30 | 0.08 |
| 300 | 38.7 | 62.2 | 26.65 | 10.03 | 0.62 | 0.49 | 0.30 | 0.08 |
| 600 | 63.3 | 95.5 | 50.75 | 10.45 | 0.63 | 0.50 | 0.29 | 0.08 |

The tick budget is 50 ms: both configurations are over it at 600 summoned (mean 61 to 63). Network and chunk IO outside the tick are under 0.4 ms
per tick. Pre-`activeChunkSet` build (`int_all.exe`, no sub-scopes, `block ticks` includes the spawner): 0 summoned mspt 19.4, entities 7.38, block
ticks 10.95; 600 summoned mspt 59.0, entities 46.96, block ticks 10.98.

### 7.3 What the data says

1. **Entity ticking dominates and grows linearly**: marginal cost about 0.063 to 0.070 ms per summoned mob per tick at every step (100: +6.3,
   300: +21.0, 600: +39.6 ms over step 0). No superlinear term is visible up to 600 summons, so there is no O(E^2) scan in the loop at this size.
   At 600 it is 80 percent of the tick.
2. **The spawner is a constant 10 ms per tick (about half the tick at idle) independent of mob count** (10.1 / 10.7 / 10.8 / 10.5). It does not
   move when 600 hostile mobs (far above the monster cap) exist, so it is not the entity scan in `newSpawnState`. By code reading it is the
   per-active-chunk pass (`readChunkSync`, shuffle, `getRandomPosWithin` with a clock-seeded rng per call, `spawnCategoryForPosition`) for categories
   that are never capped (ambient, water, axolotls), run every tick over 289 chunks: about 35 microseconds per chunk. The attribution is an
   inference (no sub-scope inside `naturalSpawnTick`); the constancy is measured. This is a much bigger target than anything in sections 2a to 2d.
3. **Block ticks (rolls + scan + apply) total 0.7 to 0.95 ms per tick**, under 2 percent of the tick. Consistent with 2a/2b: nothing to win there.
   The gate-on scan (0.51) is not cheaper than the inline path (gate off: rolls 0.31 + apply 0.33; scan is not separately reported when off).
4. **Gate on vs off**: the differences (mspt 19.4 vs 21.1, 24.5 vs 28.2, 38.7 vs 42.9, 63.3 vs 61.1) are within this machine's run-to-run noise (the
   old-build 0-step row alone differs by 1.7 ms from the new one with no relevant code change). There is no demonstrable effect of
   `MC_REGION_THREADS=1` on a populated tick, as predicted: the region workload is under 1 ms of a 20 to 60 ms tick.
5. **Does the active-chunk set reduce work?** Not measurably: with 600 summoned, entities 46.96 (old linear search) vs 48.83 (set); block ticks 10.98
   vs spawner 10.47 + 0.9: equal within noise. The arithmetic predicted it (289 compares per entity is about 0.05 to 0.1 ms per 1000 entities). It is
   correct and free but not where the time is. Its other saving, skipping the AI cost of entities in inactive chunks, is NOT exercised here (every
   summon is inside the 9x9 simulation area) and was not measured.
6. **Not seen**: crop farms, redstone, fluids, item entities, many real players (3 idle bots only), network cost. The entity scope has no sub-split
   (AI, movement/collision, packet sends), so the 0.065 ms per mob is the whole entity tick.

### 7.4 Design: chunk-bucketed entity index (design only, nothing built)

Goal: spatial queries touch only nearby entities. Honest expected gain from the profile: the entity loop is linear and spends its time inside
`entity.tick` per mob, which an index does not remove. The index removes (a) the O(E) scans mobs issue per query during their tick
(`getNearbyEntities`, `getClosestEntity`) and (b) O(E) scans in `newSpawnState`, item merging and `sendEntitiesTo`. The profile cannot say how much
of the 0.065 ms per mob is (a); because the slope is linear and not quadratic, (a) is small at 600 mobs, so expect a payoff at 2000+ mobs or many
item entities, not at 600. Do the spawner work (7.5) first: that 10 ms is certain.

Data structure, all in `src/server/entity/entitymod.aowl`:

* `WorldEntities` (type, line 299): keep `entities: seq[EntityBase]` as the authoritative ordered list (external code reads and assigns it:
  `src/server/block/worldhooks.aowl` lines 825 to 845, `src/server/entity/itementity.aowl` line 70, `saveAllEntities`, `sendEntitiesTo`). Add
  `byChunk: Table[int64, seq[EntityBase]]` (key `chunkKey(cx, cz)`, the helper `activeChunkSet` uses) and per-entity `indexKey: int64` and
  `spawnSeq: int64` (monotonic, assigned at add, never changed by moves).
* Maintain in: `addEntitySilent` (line 4108), `spawnEntityNonSave` (~4125), `removeEntity` (~4130; it currently rebuilds the whole list, make it
  one pass and drop from the bucket), and the chunk move in the position update (~line 1104, where `self.chunkPos` changes): move between buckets
  when `getSectionCord(floorX/Z)` changes. Entities that write `pos` directly (the comment in `tickEntities` says fast movers do) must be reconciled:
  route through one `moveEntityIndexed(world, entity)` helper or recompute the key at the end of each entity's tick in `tickEntities` (one floor and
  a compare). Teleports, dimension changes and NBT loading go through the same add/remove.
* External writers of `store.entities` (`worldhooks.aowl` ~845, tests) bypass the index. Preferred: rename the field so the compiler finds every
  user and give them proc access; fallback: `rebuildIndex(store)` after those assignments.

Queries to switch:

* `getNearbyEntities` (4024) and `getClosestEntity` (4042): compute the chunk range of `pos +- radius`, gather buckets, filter by squared distance as
  now, then sort candidates by `spawnSeq`. Insertion order equals today's list order (`removeEntity` filters and keeps order), so results and the
  `d < best` first-wins tie rule are identical.
* `tickEntities` (4150): keeps iterating the ordered list (tick order must not change); its `isActiveChunk` test is already O(1). Optional second
  step: iterate only active-chunk buckets in `spawnSeq` order (pays only when many mobs are far from players; measure first).
* `natural_spawner.newSpawnState` (line 209): iterate active-chunk buckets in `spawnSeq` order (counts are order independent but `addCharge` float
  sums are not, so keep the order to stay bit-identical).
* `itementity.aowl` line 70 (item merge scan), `broadcastEntitySpawn`, `sendEntitiesTo` (view-distance filter): later consumers.

Risks: (1) stale buckets from direct `pos` writes make entities silently miss queries; guard with a debug check in `tickEntities` under an env flag
comparing `indexKey` with the live floor. (2) Result-order changes if candidates are not sorted by `spawnSeq` (changes ties and float sums).
(3) Thread safety: the index inherits the per-world owner thread; decide passes must only read it. (4) Memory: one Table entry per occupied chunk,
negligible. (5) `loadWorld`'s pre-created `entitiesBox` (`newWorldEntities`, line 598) must build the index, and tests that construct
`WorldEntities(entities: @[])` literals need a nil Table treated as empty. (6) The 6 external callers of the two query procs must not change; only
the bodies. Tests: `entitymodtest`; a new randomized test (add/move/remove 2000 entities, compare every query to the linear scan including order);
`natural_spawnertest` unchanged.

### 7.5 Recommended order from this data

1. Spawner pass (10 ms constant, `natural_spawner.naturalSpawnTick`): add a sub-scope split first (one build): `newSpawnState`, chunk gather and
   shuffle, `spawnForChunk` per category. Then fixes that keep the rng stream: avoid `readChunkSync` and the shuffle for categories that cannot
   spawn, avoid the per-call `fromSeed(getSeed())`. Needs a build; not done here.
2. Entity sub-scopes (AI goals, movement/pathing, packets) to learn the real shape of the 0.065 ms per mob. Without that the index is a guess.
3. Entity index (7.4) only if step 2 shows query time is a large share.
4. No more region-task workloads: block ticks are under 1 ms per tick even populated.

Raw outputs (outside the repo): `C:/m3/prof_def.json`, `prof_rt.json`, `prof_old.json`. Not verified: the natural entity count, anything with real
players or non-idle bots, an A/B on spawner caps, the gate at more than 4 threads.

## 8. Spawner pass measured (mt-int 87b40e3, clean build)

Idle populated bench (3 bots, 0 summoned, 25 s profile): mean tick 21.1 ms before, 17.4 ms after the biome-table / no-list-copy / hoisted-player-positions change (spawner total 10.1 ms -> about 8.6 ms per tick, `spawner:category`; `randpos` 0.13, `state` 0.23, `gather` 0.05, `shuffle` ~0.001 ms per tick). With 300 mobs: mean tick 36.9 ms, `entities` about 25 ms per tick. The remaining `spawner:category` cost is the draw-heavy group loop itself (3 groups x up to 4 draws plus adjustSpawnPosition / isValidSpawnPositionForType per candidate), which cannot be skipped without changing the RNG stream. A 40-sample main-thread stack probe (gdb) of an idle 150 s run caught the main thread sleeping in 26 of 40 samples; the 14 busy samples were spread over pathfinding (computePathWith, getNode, getPathTypeFromState), noise biome lookup, randRange, portal tick and the scheduler, with no single dominant frame, so no further cheap target was found. Entity ticking, not the spawner, is what grows with load.

## 9. Entity tick breakdown (mt-int f6c5eb3, clean build, bench_populated, 30 s profile, 3 bots)

ms per tick, scope self time:

| scope | 0 mobs | 300 mobs |
|---|---|---|
| mspt mean | 20.4 | 39.3 |
| mob:navigator (pathfinding) | 3.25 | 13.18 |
| spawner:category | 9.08 | 8.47 |
| living:entitytick | 1.84 | 6.17 |
| ent:tick (dispatch) | 0.24 | 2.44 |
| living:travel | 1.42 | 2.23 |
| living:blockcoll | 0.48 | 1.23 |
| living:sendchanges | 0.29 | 0.89 |
| mob:goalsel | 0.35 | 0.53 |

Pathfinding is half of the entity cost and the part that grows. `ent:nearby` (the O(E) scan an entity index would remove) does not appear among the top scopes, so **an entity index is not justified**; do not build it. The offload target is the navigator.

With `MC_THREADS=4 MC_PATH_WORKERS=1` at 300 mobs the tick is **621 ms mean** (p95 675), `mob:navigator` 594 ms per tick: the existing path-worker gate is far worse than inline pathfinding here. It stays default off and must not be enabled; cause not yet found (suspects: the tick thread joins each path job in the same tick, per-path snapshot capture cost, or workers starved).

### 9.1 Path-worker gate after the snapshot fix (mt-int aadc3b6, clean build)

Cause of the 621 ms tick: `Navigator.tick` captured a 67 x 102 x 67 = 457,878-cell BlockSnapshot per path request with one world lookup per cell (23.4 ms each, about 20 requests per tick at 300 mobs); `drainDone` also allocated per call and the pool's owner table grew by one entry per navigator ever created. Fixes: section-wise snapshot copy (23.4 ms -> about 1.6 ms), allocation-free drainDone with owner slots dropped at zero.

Measured again, `MC_THREADS=4 MC_PATH_WORKERS=1`, 300 mobs: mean tick **37.96 ms** (p95 47.95), `mob:navigator` 11.53 ms per tick, against 39.3 ms and 13.18 ms inline. So the gate is no longer harmful but is also only about 1.7 ms per tick (within noise) faster: the capture cost on the tick thread cancels most of the search cost moved off it. It stays default off. Further gain needs the capture itself to leave the tick thread (shared per-area capture or read-only section handles from the chunk system) and is not planned.
