# plugin-api → Nimony

Source: `crates/plugin-api` in the upstream repo, ~24k lines of Rust.

## What's actually here

Despite the size, this crate is almost entirely a **WASM-guest SDK**: every
substantive module imports from `crate::wit::<host>::plugin::*`, which is
the `wasmtime::component::bindgen!`-generated binding module (same
generation mechanism `host-bindings` sits on the host side of - see
`src/host_bindings/README.md`). That module isn't hand-written Rust
anywhere in the crate; it's produced at the upstream server's own build time from the
WIT interface files under `plugin-wit/`. There is nothing here to
mechanically translate without first having a Nimony WASM-guest binding
layer, which doesn't exist (see `src/host_bindings/README.md` and
`src/plugin_runtime/README.md` for the three replacement paths already
identified: wasmtime C API FFI, a custom WIT→Nimony generator, or dropping
WASM sandboxing for natively-loaded plugins the way Jester's `aowli`
interpreter already does).

Verified by grepping every top-level and `ext/` source file for `wit::`
imports: only `permissions.rs` and `ext/mod.rs` (a re-export shim) have
none. Everything else - `item.rs`, `block.rs`, `enchantment.rs`, `team.rs`,
`mobs.rs`, `forms.rs`, `display.rs`, `persistent_data.rs`, `logging.rs`,
`ai.rs`, `worldgen.rs`, `commands.rs`, `scheduler.rs`, `datapack.rs`,
`inventory.rs`, `recipe.rs`, `lib.rs`, and all ~230 files under `events/`
(each a ~20-line `FromIntoEvent` wrapper around one `wit::...::EventData`
type) - is WASM-guest binding glue through and through.

`generated/block.rs` (5.2k lines) and `generated/item.rs` (6.7k lines) are
build-time-generated block/item registry data, out of scope for the same
reason `data` is: port the generator once everything upstream of it
is settled, not the generated output by hand.

## Ported

- `permissions.nim` - the plugin sandbox capability-string constants
  (`network.*`, `fs.*`, `sys.*`, `http.outbound`). Pure data, no `wit`
  dependency. `nimony check` clean.
- `eventdata.nim` - a real server-side `EventData` model, now for 170 events
  (~170 of ~273 real `-event-data` WIT records covered; see the file's own
  count against `event.wit` for the exact current tally).
  Latest batch (33 new): `PlayerChangeWorld`/`PlayerCustomPayload`/
  `PlayerItemConsume`/`PlayerItemDamage`/`AsyncPlayerChat`/
  `AsyncPlayerPreLogin`/`PlayerPreLogin`/`PlayerAdvancementDone`/
  `PlayerAnimation`/`PlayerArmorStandManipulate`/`PlayerBucketEntity`/
  `PlayerChangedWorld`/`PlayerChannel`/`PlayerCommandPreprocess`/
  `PlayerEditBook`/`PlayerElytraBoost`/`PlayerExpCooldownChange`/
  `PlayerHarvestBlock`/`PlayerHideEntity`/`PlayerItemBreak`/`PlayerItemMend`/
  `PlayerLeashEntity`/`PlayerLevelChange`/`PlayerLocaleChange`/
  `PlayerNameEntity`/`PlayerOpenSign`/`PlayerPortal`/`PlayerRiptide`/
  `PlayerShearEntity`/`PlayerShowEntity`/`PlayerSpawnChange`/
  `PlayerStatisticIncrement`/`PlayerSwapHands`/`PlayerTakeLecternBook`.
  ~103 records remain (villager/vehicle/raid/dialog/packet/entity-target
  long tail) - same mechanical translation, just more of it.
  Previous batch (29 new): `BlockBrush`/`BlockCook`/`BlockDropItem`/`BlockExp`/
  `BlockFertilize`/`BlockMultiPlace`/`BlockShearEntity`/`BlockSpread`/`Brew`/
  `BrewingStandFuel`/`BrewingStart`/`CampfireStart`/`CauldronLevelChange`/
  `ChunkPopulate`/`ChunkSend`/`CrafterCraft`/`CreeperPower`/`EnchantItem`/
  `EntitiesLoad`/`EntitiesUnload`/`EntityBlockForm`/`EntityCombustByBlock`/
  `EntityCombustByEntity`/`ExpBottle`/`FluidLevelChange`/`FurnaceBurn`/
  `FurnaceExtract`/`FurnaceSmelt`/`FurnaceStartSmelt`/`HangingPlace`.
  ~136 records remain (async player-chat/pre-login/structure variants,
  villager/vehicle/raid/dialog/packet-received/-sent, and most of the
  player-*/inventory-* long tail) - same mechanical translation, just more
  of it; a future pass can keep working straight down the alphabetized
  remaining list.
  Previous batch (26 new): `PlayerCommandSend`/`PlayerPermissionCheck`/
  `PlayerRespawn`/`PlayerItemHeld`/`PlayerChangedMainHand`/`PlayerFish`/
  `PlayerEggThrow`/`PlayerInteract`/`PlayerToggleFlight`/
  `PlayerInteractUnknownEntity`/`PlayerInteractEntity`/`InventoryClick`/
  `CreatureSpawn`/`EnderDragonChangePhase`/`EntityBreakDoor`/
  `EntityChangeBlock`/`EntityDamageByBlock`/`EntityDamageByEntity`/
  `EntityDropItem`/`EntityEnterBlock`/`EntityExhaustion`/`EntityInteract`/
  `EntityKnockback`/`EntityPlace`/`EntityPoseChange`/`EntityPotionEffect`/
  `EntitySpellCast`/`EntityDye`/`EntityEnterLoveMode`/`ExplosionPrime`/
  `FireworkExplode`/`PiglinBarter`/`ProjectileHit`/`ProjectileLaunch`/
  `SheepDyeWool`/`SheepRegrowWool`/`SlimeSplit`/`StriderTemperatureChange`.
  Earlier passes covered `PlayerJoin`/`PlayerLeave`/`PlayerTeleport`/
  `PlayerGamemodeChange`/`PlayerToggleSneak`/`PlayerMove`/`PlayerChat`/
  `BlockPlace`/`BlockBreak`/`EntityDamage`/`EntityDeath`/`PlayerDeath`/
  `EntitySpawn`/`ItemSpawn`/`ItemDespawn`/`PlayerDropItem`/`BlockRedstone`/
  `BlockBurn`/`BlockCanBuild`/`BlockGrow`/`ServerCommand`/`ServerLoad`/
  `SpawnChange`/`ServerTickStart`/`ServerTickEnd`/`ChunkLoad`/`ChunkSave`/
  `PlayerLogin`/`PlayerExpChange`/`PlayerToggleSprint`/`InventoryClose`/
  `EntityDismount`/`EntityPickupItem`/`EntityResurrect`/`EntityTeleport`/
  `EntityToggleSwim`/`FoodLevelChange`/`ItemMerge`/`BlockIgnite`/`BlockForm`/
  `TntPrime`/`NotePlay`/`EntityExplode`/`PlayerBedEnter`/`PlayerBedLeave`/
  `PlayerBucketEmpty`/`PlayerBucketFill`/`PlayerKick`/`BlockPistonExtend`/
  `BlockPistonRetract`/`SignChange`/`BellRing`/`WeatherChange`/
  `ThunderChange`/`InventoryOpen`/`InventoryDrag`/`CraftItem`/
  `EntityCombust`/`EntityRegainHealth`/`EntityAirChange`/`EntityBreed`/
  `EntityMount`/`EntityPortal`/`EntityShootBow`/`EntityTame`/`EntityTarget`/
  `EntityTargetLivingEntity`/`EntityToggleGlide`/`EntityTransform`/
  `EntityRemove`/`BlockDamage`/`BlockFromTo`/`BlockExplode`/`BlockPhysics`/
  `BlockFade`/`SpongeAbsorb`/`HangingBreak`/`HangingBreakByEntity`/
  `WorldLoad`/`WorldUnload`/`ChunkUnload`/`TimeSkip`/`MoistureChange`.
  Also fixed two pre-existing test bugs hit while extending the file:
  `MoistureChangeEventData` has no `cancelled` field in the real WIT record
  (the test wrongly passed one; `nimony check` didn't catch it until the
  file was re-checked after unrelated edits nearby) and a `placeData`
  identifier collision between `BlockPlaceEventData`'s and
  `EntityPlaceEventData`'s test variables (renamed the latter to
  `entityPlaceData`). Built from
  the actual field shapes in
  `upstream-ref/crates/pumpkin-plugin-wit/v0.1/event.wit` (the `.rs`
  wrapper files carry no fields of their own - see the file's doc comment
  for where the real shapes live and the type-substitution choices made:
  a WIT `player` resource becomes `PlayerUuid`, not a live `Entity`/
  `Player` reference, specifically to avoid transitively importing
  `src/server/entity/entity.nim` and inheriting its runtime-unverifiable
  status; `text-component` becomes a plain `string` pending a real
  `TextComponent` port). This does NOT replace the WASM-guest transport
  itself (still undecided, see below) - it's a genuine, transport-
  independent data model server code can build on now. `nimony check`
  clean, and - unlike most of this port's vtable-based code -
  `eventdatatest.nim` actually **runs** clean via `nimony c -r`
  (pure data, no closures/vtables, so it isn't affected by the
  closure-through-vtable runtime crash documented in
  `src/server/entity/README.md`).

The remaining ~112 `events/*.rs` files are mechanical follow-ups once
someone wants them: same WIT-record-to-Nimony-object translation
`eventdata.nim` already demonstrates, just more of them.

## Not ported

Everything else, for the reason above (the WASM-guest binding layer
question - see the replacement paths in `src/host_bindings/`
and `src/plugin_runtime/`). The larger files
(`recipe.rs`, `mobs.rs`, `persistent_data.rs`, `enchantment.rs`, `team.rs`)
are plugin-author-facing builder APIs over those same WIT resource types
and should follow once the resource types themselves have a Nimony shape.
