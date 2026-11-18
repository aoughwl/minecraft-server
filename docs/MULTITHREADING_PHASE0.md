# Multithreading phase 0: audit results (RNG, prewarm, stop flags)

Companion to docs/MULTITHREADING.md. Read-only audit of the tree at 25265b5. Every item names the smallest change; none is applied yet. Files outside
`src/server/sim/**` are shared or the chunk-system owner's: send the owner a change list before editing (`src/physics/**` is theirs).

## 1. Findings that change the plan

1. **No RNG here is deterministic.** All seeds come from the clock (`getSeed()`, `nowMs()`, `toUnix(getTime())`). `getSeed()` is already thread safe (atomic CAS).
   Only tests pin a sequence (`seedLootRandom`, `seedSpawnRandom`). "Same result at threads = 1" therefore means same algorithm, same seed source, same
   draw order, and test seeding that still works. With several dimensions a per-world stream changes the interleaving versus one shared stream; harmless because the seeds are random.
2. `block_properties` and `recipes` are **not lazy** (filled at module init). Only `/reload` mutating recipes is a hazard (between ticks only).
3. Lazy and unlocked: `registry.cache/loaded`, `tag.decoded`, `block_loot.gCache`, `physics/materials` (per-state `gHave/gMat` fill in `materialOf`, so prewarm must loop every state), `chunk_data.biomeRemaps`.
4. `ITEM_STACK_ID_GEN` (`data/item_stack/mod.aowl:60`) is a plain counter: make it atomic (`atomicFetchAdd`) or per world.

## 2. RNG streams

| RNG | Defined | Uses | Smallest change |
|---|---|---|---|
| `weatherRandomState` | `world/weather.aowl:24` | 4 sites in `tickWeather` | field `rngState` on `Weather` (`serverbase.aowl:62`), set in `newWeather` |
| `explosionRandomState` | `world/explosion.aowl:29` | 1 (`:57`) | `world.explosionRand` field, `randomF32(world)` |
| `gLootRand` | `world/loot.aowl:49` | 5 + 13 callers | `lootRand` on `World`, or a lazily seeded `{.threadvar.}` |
| `gSpawnRand` | `world/natural_spawner.aowl:69` | 7 + about 15 callers | `spawnRand` on `World` (every proc already takes `world`) |
| `gEntityRandomState` | `entity/entitymod.aowl:405` | about 194 external calls | `{.threadvar.}` with lazy init now; later ambient `ptr uint64` set per world tick |
| `gRngState` (block prelude) | `block/blockprelude.aowl:71` | about 38 `rng()` sites | `{.threadvar.}` now; later `rng(world)` |
| `gDurabilityRandom` | `data/item_stack/mod.aowl:61` | 2 | `{.threadvar.}` |
| `gSeedRandom` | `inventory/enchanting_screen_handler.aowl:32` | 1 | leave (tick thread only) |

Order: weather and explosion (exact, no API break), then loot and spawner as `World` fields, then the three threadvars. A threadvar is exactly identical at
threads = 1 and becomes per-thread (so per-dimension in phase 4). `featureWorldSeed` (`world/generation/structurehooks.aowl:75`) is the in-repo precedent for `{.threadvar.}`.

## 3. Prewarm

`src/server/sim/prewarm.aowl` with one `prewarmAll()` called early in `runMain`, **before the first Level or schedule exists** (`sharedExecutor()` starts workers when
the first schedule is built). It forces: `staticRegistries(v)` and `remapBiomeForVersion(0, v)` for every version; `getRegistryKeyTags(v, key)` for every key;
`blockLootTable(i)` for every block; `materialOf(s)` for every state (`physics/materials.prewarmMaterials()`, which `loadMaterialOverrides` and `clearMaterialOverrides` also run themselves after they invalidate the table); `prewarmWorldgen()` (exists). No import cycle: nothing outside
`server/sim` imports `server/sim`. `prewarmMaterials()` now exists in `physics/materials` (done). Also pre-touch the Bedrock crypto's bignum constants if they are lazy (not audited).

## 4. Cross-thread flags

* `stopFlag` (`pumpkinlib.aowl:30`) is written by the console-handler thread and read on the tick thread with plain accesses: use `atomicStore`/`atomicLoad` (pattern in `util/random/random.aowl`).
* `server.stopRequested` is tick-thread only today; make it atomic when commands or RCON leave the tick thread.
* `GenerationExecutor.stopping` is guarded by the lock (fine). `gExec` is written before the workers start (fine). Bedrock crypto job state is ordered by the OS wait (fine).

## 5. Test impact

`loottest` (seeding), `levelsynctest` (`World(... weather: newWeather())` literals need the new field defaulted), `biometest`, `simtest`.
