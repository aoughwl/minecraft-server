# Fabric gaps in the aowlmony server

Goal (overnight Phase 3 #4): the aowlmony Pumpkin-port server does everything the Java/Fabric server did for our worlds, so the
Java/Fabric path can go. Status per gap, what proves it, and the exact blocker for what is not finished. Where this page and the
code disagree, the code is right. Numbers are from the runs listed in `dev/overnight/PROGRESS.md`.

| Gap | Status |
|---|---|
| Java save import without Java | **works** (tested on a copy of `Survival_World-978c829b`, read-only source) |
| Flat world type | **works** (level.dat honoured since the port; creation option added) |
| Amplified world type | **works** (new: the vanilla amplified noise router and settings) |
| Large-biomes world type | **works** (new: the vanilla large-biomes noise router and settings) |
| Data packs | **partial**: functions, block/item/function tags, shaped/shapeless/cooking recipes; list below |
| Player-data round trip | **works** (inventory, ender chest, position, game mode, health, food, xp; offline and online UUIDs) |
| Join guard | **works** (held while loading, refused while stopping, version mismatch clear at the handshake) |

## 1. World types

`pumpkin.toml` (top-level, only written when not the default):

```toml
world_type = "flat"          # default | flat | amplified | large_biomes
```

* Read only when the save has no `level.dat` yet. It writes the generator into `level.dat` exactly as vanilla does
  (`dimensions.minecraft:overworld.generator`): flat is `type: minecraft:flat` with `settings: {biome, layers}` (bedrock, 2 dirt,
  grass block, plains); amplified and large biomes are `type: minecraft:noise` with `settings: "minecraft:amplified"` /
  `"minecraft:large_biomes"`.
* An existing world keeps whatever its `level.dat` says (a Java world made as amplified loads as amplified). `Level` reads the
  settings reference (`noiseVariant`) and flat layers (`isFlat`, `flatLayers`, `flatBiome`) in `src/world/level.aowl`.
* Amplified and large biomes use the density-function sets `amplified` and `large_biomes` that were already in the pinned
  `assets/density_function.json` but never generated: `src/data_codegen/gen_noise_router.aowl` now also emits
  `AMPLIFIED_BASE_NOISE_ROUTER` and `LARGE_BIOMES_BASE_NOISE_ROUTER` (the three existing routers come out byte for byte as before:
  the diff of `src/generated/noise_router.aowl` is only additions). `src/world/generation/generator/generator.aowl` picks the
  router and the generation settings from the variant.
* **A new world used to get seed 0 whatever `seed` said** (`defaultLevelData(seed)` ignores its argument). `loadServer` now stores
  the configured seed in the new level.dat.
* Proof: `src/world/worldtypestest.aowl` (level.dat written and read back for every type; then the same seed, the same six chunks
  generated four times). Flat columns are exactly bedrock, dirt, dirt, grass_block, air, with one surface height; amplified
  differs from default in 1328 of 13824 sampled cells and its height range grows from 62..130 to 62..184; large biomes differs in
  1113 cells and its range is 62..84.
* **Flat worlds never finished a chunk before this change** (found by the live run, then reproduced by `flatpumptest.aowl`): for a flat
  generator the `StructureStart` and `StructureReferences` stages did nothing and left the proto chunk's stage at `Biomes`; the
  scheduler reads that stage to see a step done, so it re-ran `StructureStart` for ever (server at 100% CPU, region files
  written, no chunk ever published to a player). `generation_cache.aowl` now advances the stage for the non-noise generator.
  Before: 20000 scheduler passes and 0 chunks loaded; after: 38 passes, chunk (0,0) loaded.
* Live (whole-server exe, bot on a scratch server, `tools/run_fabric_live.py worldtype <type>`): flat: the column under the player is
  exactly 4 solid cells y -64..-61; amplified: 21 chunk columns, 115 solid cells in the spawn column; large_biomes: 21 columns, 150
  cells; `data/minecraft/world_gen_settings.dat` holds the matching generator (1.21.9+ keeps it there, not in level.dat).
* Not verified: block-for-block equality with a vanilla amplified or large-biomes world of the same seed (no vanilla output to
  compare with here). The data is vanilla's; the surface rules, structures and carvers are the default overworld's.
* Not done: custom flat presets by option (edit the `layers` in `level.dat` instead), the `single_biome` and `checkerboard`
  biome sources, `world_type` for an existing save.

## 2. Data packs

`<world>/datapacks/<folder>/` with `pack.mcmeta` and `data/<namespace>/...`, loaded at start and by `/datapack reload`
(`src/server/datapack/datapack.aowl`, glue `src/plugin/datapackcmd.aowl`). Packs load in folder-name order; a later pack wins a
function or recipe id and a `replace` tag. `level.dat` `DataPacks.Disabled` (`file/<folder>`) is honoured.

| Part | Supported |
|---|---|
| functions | `function/` or `functions/` `*.mcfunction`: comments, blank lines, leading `/`, `\` continuation. `/function ns:path` runs every line through the command dispatcher as the sender. `#minecraft:load` runs once at start and after `/datapack reload`; `#minecraft:tick` every server tick (as the console). Call depth capped at 16. |
| tags | `block`, `item` (ids resolved, `#` references expanded, `replace`), and `function`. A data pack tag is also written into the tag packet the client receives at join (every version's map), so the client sees it after rejoining. |
| recipes | `crafting_shaped`, `crafting_shapeless`, `smelting`, `blasting`, `smoking`, `campfire_cooking`; both the 1.21 (`"id"`, string ingredients) and older (`"item"`, `{"item"}`/`{"tag"}`) spellings. A vanilla id is replaced. They are added to the lists the crafting screen matches against. |
| commands | `/function`, `/datapack list`, `/datapack reload` (op level 2). |

Proof: `src/server/datapack/datapacktest.aowl` writes a pack to disk and checks every row above, including that a second load does
not stack and that `resetDatapacks()` restores the built-in tags and recipes exactly (a tag that gained dirt loses it again).

Blockers and gaps (exact):

* **zip packs**: reported, not read. The only zip reader in the tree is private to `src/physics/packs.aowl`; move it into a shared
  module and `loadDatapacks` can open zips.
* **tag registries other than block, item, function** (entity type, fluid, game event, damage type, ...): parsed and reported as
  unsupported. Block and item were done because their registry ids resolve through `Block.fromRegistryKey` /
  `Item.fromRegistryKey`; the others need the same lookup for their id space.
* **recipe types** `stonecutting`, `smithing_*`, `crafting_transmute`, `crafting_special_*`: reported as unsupported. The
  generated structs exist (`StonecutterRecipe`, `TransmuteRecipe`); the loader does not read them yet.
* **other data**: loot tables, predicates, advancements, damage types, dimension and worldgen JSON in a pack are not read.
* **macros** (`$` lines, `/function ns:x {args}`), `/schedule`, `execute run function`: not supported (the dispatcher has no
  function-aware `execute`).
* **live clients**: a reload re-reads the server's tables immediately; clients already online keep their tag and recipe state
  until they rejoin (no `update_tags` / recipe-book resend on reload).
* **live** (`tools/run_fabric_live.py <exe> datapack`, whole-server exe): `/datapack list` shows the pack with its counts, `/function
  live:hello` runs its two lines through the dispatcher and the answers reach the sender, an unknown id is refused, `/datapack reload`
  reports, and `#minecraft:load` ran once at start. **Not run live**: the `#minecraft:tick` hook (covered only by the unit test of the
  tag expansion and by reading), crafting with a pack recipe in a real client, a client re-joining to receive the tag packet.

## 3. Player-data round trip

Already in the port (`Player.writeNbt` / `readNbt`, `PlayerDataStorage`, saved on leave, by the periodic save and by `/save-all`).
What was missing was proof, and a check that the file is keyed the way a vanilla save is.

* `src/server/data/playerroundtriptest.aowl`: a Player with items in the hotbar and the main inventory, an ender-chest stack, a
  position and rotation, creative mode, 14 health, 9 food and 4 xp levels is saved by `extractDataAndSavePlayer`, a new Player is
  built as a rejoin builds one, `loadData` + `readNbt`, and every field is compared. Run for an offline UUID and a made-up online
  UUID; also asserts `offlineUuid("Notch")` is vanilla's `b50ad385-829d-3141-a216-7e7d7539ba7f`, so a vanilla/Fabric save's
  `playerdata/<uuid>.dat` is the file this server asks for.
* `tools/run_fabric_live.py <exe> playerdata` (whole-server exe, bot): `/gamemode creative`, 7 diamonds, an obsidian stack in ender
  chest slot 3, `/tp 12 90 -34`, `/stop` (server exit code 0), restart, rejoin: position 12.50 90.00 -33.50, `Inventory` holds the 7
  diamonds, `playerGameType` is 1, `EnderItems` holds the obsidian. The file is `playerdata/cd5edcc0-2bd9-328c-9850-91ee24abb170.dat`
  (the vanilla offline UUID of the bot name).

## 4. Join guard

`Server.joinHold` (non-empty = no joins), set by `loadServer` until `main` has the worlds loaded, plus `stopRequested`. `login.aowl`
`joinRefusal(server)` is checked first in `handleLoginStart` and kicks with the reason ("The server is still loading the world.
Please try again in a moment." / "The server is shutting down. Please reconnect in a minute."). A client whose protocol is older
or newer than the server's is refused at the handshake with vanilla's translated outdated-client / outdated-server text naming the
server version (this already existed). A `level.dat` of a newer data version than the server supports stops the server at start
with `wieUnsupportedDataVersion` and the version number instead of loading a world it could damage.

* Proof: `src/server/net/java/joinguardtest.aowl` (held, stopping and released logins; an old and a new protocol at the handshake).
  The listener is bound after `loadServer` returns, so in practice a client cannot reach the guard during the world load; the
  guard is for anything that holds joins later (a mod, a long pregeneration, the stop sequence).
* Pre-existing, not mine: `joinflowtest.aowl` fails an assertion on `origin/main` (checked on a clean worktree of 01d2826), so the
  guard test is its own file.

## 5. Java save import without Java

`src/world/javaimporttest.aowl <world folder> [region] [max chunks]` reads a vanilla/Fabric world folder (read-only) and checks:
`level.dat` read, written, read again (every key of `Data` survives, only `LastPlayed`/`Version` may differ); every
`playerdata/*.dat` through `PlayerDataStorage` (compound equal); a region's chunks parsed, re-serialised, re-parsed and written to a
new `.mca` (every block of every section equal, block entities and heightmaps equal, every root key this port does not model kept
verbatim, the new `.mca` read back chunk for chunk).

Live: `tools/run_fabric_live.py <exe> javaworld <folder>` copies `level.dat`, `playerdata` and the four regions around the origin of the
Java world into a scratch server and joins: 21 chunk columns of the real terrain, 126 solid cells in the spawn column. The saved
player of that world could not be joined by the test bot (its parser does not read item components); his saved inventory and
position are covered by the unit test above (player data identical after a save), not by a live rejoin.

Not covered: entities/poi regions, the nether and end folders (same code path), `.mca` files with external `.mcc` chunks (not
present in the test world), linear/other region formats, advancements and stats (copied by file, not parsed).
