# Events

A plugin hears what the server does through events. In aowlmony a handler takes the event as a typed parameter and
`registerEvent(handler)` picks the event from that type; in JavaScript the event type is the first argument of `on(...)`.
Every event has the fields below; a cancellable one has `cancelled` (`e.cancel()` sets it) and the server obeys it after the
handlers ran. Handlers run in the order plugins were loaded; there are no priorities, and one plugin cannot un-cancel another's cancel.

```nim
proc noTnt(e: var BlockPlaceEvent) =
  if e.blockName == "minecraft:tnt": e.cancel()
registerEvent(noTnt)
```

```js
on(BlockPlaceEvent, function (e) { if (e.blockName == "minecraft:tnt") e.cancel(); });
```

## What the server fires (all of these are wired)

| event | Bukkit equivalent | fields (besides `player`) | cancel |
|---|---|---|---|
| `ChatEvent` | AsyncPlayerChatEvent | `message` (writable) | yes |
| `PlayerCommandEvent` | PlayerCommandPreprocessEvent | `command` | yes |
| `JoinEvent`, `LeaveEvent` | PlayerJoinEvent, PlayerQuitEvent | | yes |
| `LoginEvent` | PlayerLoginEvent | `kickMessage` (writable) | yes |
| `MoveEvent` | PlayerMoveEvent | `origin`, `target` | yes |
| `TeleportEvent` | PlayerTeleportEvent | `origin`, `target` | yes |
| `ToggleEvent` | PlayerToggleSneak/Sprint/FlightEvent | `kind`, `on` | yes |
| `GamemodeChangeEvent` | PlayerGameModeChangeEvent | `previous`, `next` | yes |
| `ItemHeldEvent` | PlayerItemHeldEvent | `previousSlot`, `nextSlot` | yes |
| `InteractEvent` | PlayerInteractEvent (block) | `action`, `x`, `y`, `z` | yes |
| `SwingEvent` | PlayerAnimationEvent, left-click PlayerInteractEvent | | yes |
| `InventoryOpenEvent` | InventoryOpenEvent | `window` | yes |
| `PotionEffectEvent` | EntityPotionEffectEvent | `entityId`, `entityType`, `effect`, `duration` (writable), `amplifier` | yes |
| `CombustEvent` | EntityCombustEvent | `entityId`, `entityType`, `ticks` (writable) | yes |
| `EntityTeleportEvent` | EntityTeleportEvent | `entityId`, `entityType`, `origin`, `target` | yes |
| `PistonEvent` | BlockPistonExtendEvent, BlockPistonRetractEvent | `x`, `y`, `z`, `extend`, `moved`, `broken` | yes |
| `ProjectileHitEvent` | ProjectileHitEvent | `entityId`, `entityType`, `ownerId`, `hitEntity`, `targetId`, `x`, `y`, `z` | yes (the projectile flies on) |
| `BlockChangeEvent` | BlockBurn/Fade/Form/Spread/FromTo/Physics/LeavesDecay/Ignite events, and the block changes of players, pistons and explosions | `x`, `y`, `z`, `before`, `after` | yes (the block stays) |
| `PortalEvent` | PlayerPortalEvent, EntityPortalEvent | `entityId`, `entityType`, `x`, `y`, `z`, `target` | yes (stays out of the portal) |
| `FurnaceSmeltEvent` | FurnaceSmeltEvent | `x`, `y`, `z`, `input`, `output` | yes (progress restarts) |
| `KickEvent` | PlayerKickEvent | `reason` (writable) | no (the kick happens) |
| `TabCompleteEvent` | TabCompleteEvent | `buffer`, `suggestions` (add to it) | |
| `TargetEvent` | EntityTargetEvent | `mobId`, `mobType`, `targetId`, `targetType` | yes (the mob picks nobody) |
| `AdvancementEvent` | PlayerAdvancementDoneEvent | `advancement` (the title) | |
| `HopperMoveEvent` | InventoryMoveItemEvent (a hopper pushing into a container) | `x`, `y`, `z`, `item` | yes |
| `SwapHandsEvent` | PlayerSwapHandItemsEvent | | yes |
| `UseItemEvent` | right-click PlayerInteractEvent | | yes |
| `InteractEntityEvent` | PlayerInteractEntityEvent / PlayerInteractAtEntityEvent | `entityId`, `action`, `sneaking`, `known` | yes |
| `BlockPlaceEvent` | BlockPlaceEvent | `blockName`, `against`, `x`, `y`, `z` | yes |
| `BlockBreakEvent` | BlockBreakEvent | `blockName`, `x`, `y`, `z`, `drop` (writable) | yes |
| `DropItemEvent` | PlayerDropItemEvent | `item`, `count` | yes |
| `PickupItemEvent` | PlayerPickupItemEvent | `item`, `count`, `entityId` | yes |
| `ItemConsumeEvent` | PlayerItemConsumeEvent | `item` | yes |
| `BedEnterEvent`, `BedLeaveEvent` | PlayerBedEnterEvent, PlayerBedLeaveEvent | `x`, `y`, `z` | yes |
| `SignChangeEvent` | SignChangeEvent | `x`, `y`, `z`, `lines` | yes |
| `BucketEmptyEvent`, `BucketFillEvent` | PlayerBucketEmptyEvent, PlayerBucketFillEvent | `bucket`, `x`, `y`, `z` | yes |
| `InventoryClickEvent` | InventoryClickEvent | `window`, `clickType`, `slot`, `rawSlot`, `hotbarButton` | yes |
| `InventoryCloseEvent` | InventoryCloseEvent | `window` | |
| `PermissionCheckEvent` | (permission plugins: PermissibleBase) | `node`, `granted` (writable) | |
| `ExpChangeEvent` | PlayerExpChangeEvent | `amount` | |
| `RespawnEvent` | PlayerRespawnEvent | `pos`, `alive` | |
| `DeathEvent` | PlayerDeathEvent | `message` | |
| `FishEvent` | PlayerFishEvent | `state`, `caught`, `exp` | yes |
| `EggThrowEvent` | PlayerEggThrowEvent | `hatching` (writable), `numHatches`, `hatchingType` | yes |
| `ChangeWorldEvent` | PlayerChangedWorldEvent | `pos`, `yaw`, `pitch` | yes |
| `MainHandChangeEvent` | PlayerChangedMainHandEvent | `hand` | |
| `CustomPayloadEvent` | plugin messaging (PlayerRegisterChannelEvent) | `channel`, `length` | yes |
| `CustomClickEvent` | (dialog click) | `id`, `length` | |
| `EntityDamageEvent` | EntityDamageEvent, EntityDamageByEntityEvent | `entityId`, `entityType`, `damageType`, `amount` (writable), `attackerId` | yes |
| `EntityDeathEvent` | EntityDeathEvent | `entityId`, `entityType`, `damageType`, `killerId` | |
| `EntitySpawnEvent` | EntitySpawnEvent, CreatureSpawnEvent, ItemSpawnEvent | `entityId`, `entityType`, `pos` | |
| `EntityRemoveEvent` | EntityRemoveEvent (Paper) | `entityId`, `entityType` | |
| `ExplosionEvent` | ExplosionPrimeEvent, EntityExplodeEvent, BlockExplodeEvent | `pos`, `power` | yes |
| `WeatherChangeEvent` | WeatherChangeEvent, ThunderChangeEvent | `raining`, `thundering` | |
| `BlockGrowEvent` | BlockGrowEvent | `before`, `after`, `x`, `y`, `z` | yes |
| `RedstoneEvent` | BlockRedstoneEvent | `x`, `y`, `z`, `oldCurrent`, `newCurrent` | yes |
| `SpawnChangeEvent` | SpawnChangeEvent | `previous`, `next`, `yaw`, `pitch` | |
| `ChunkSendEvent` | PlayerChunkLoadEvent (Paper) | `x`, `z` | yes |
| `HealEvent` | EntityRegainHealthEvent | `entityId`, `entityType`, `amount` (writable) | yes |
| `FoodLevelChangeEvent` | FoodLevelChangeEvent | `level` (writable), `previous` | yes |
| `StatisticEvent` | PlayerStatisticIncrementEvent; also CraftItemEvent (category 1, crafted, after the player took the result), and the mined (0), used (2), broken (3), picked up (4), dropped (5), killed (6) counts | `category`, `statId`, `amount` | |
| `ServerListPingEvent` | ServerListPingEvent | `address`, `motd` (writable), `online`, `maxPlayers` (writable) | |
| `PreLoginEvent` | AsyncPlayerPreLoginEvent | `name`, `address`, `kickMessage` (writable) | yes (turns the client away) |
| `LevelChangeEvent` | PlayerLevelChangeEvent | `previous`, `level` | |
| `WorldSaveEvent` | WorldSaveEvent | | |
| `TimeSetEvent` | TimeSkipEvent | `previous`, `time` (writable) | yes |
| `ServerCommandEvent` | ServerCommandEvent | `command` | yes |
| `BroadcastEvent` | BroadcastMessageEvent | `message`, `sender` | yes |
| `ServerLoadEvent` | ServerLoadEvent | `reload` | |
| `TickStartEvent`, `TickEndEvent` | ServerTickStartEvent, ServerTickEndEvent (Paper) | `tick` (`durationNs` at the end) | |
| `PacketEvent` | PacketEvent (ProtocolLib) | `packetId`, `length` | yes |
| commands | Command / CommandExecutor | see `command(...)` in `docs/PLUGINS.md` | |
| `onEnable`, `onDisable` | onEnable, onDisable, PluginEnableEvent | | |
| tasks | BukkitScheduler | see `after`, `every` | |

That is 75 event types. Events that fire often (movement, packets, ticks, permission checks, block grow, redstone, chunk send, damage)
cost nothing while no loaded plugin listens to them.

## Bukkit events that do not exist here, and why

Bukkit has well over 200 event classes. An event can only exist when the server has the thing happening and a place that fires it. This
server (a port of Pumpkin) fires the events above; the rest below either need a firing site added in the server or describe a game
system the server does not have.

**Needs a firing site in the server (the system exists):** BlockCanBuildEvent, EntityChangeBlockEvent, a hopper pulling items in (only the push is hooked),
BrewEvent and FurnaceBurn/ExtractEvent (the block entities exist; the smelt is covered), PortalCreateEvent, VehicleEnter/Exit/Move/DamageEvent
(boats and minecarts exist).

**Not hookable the way Bukkit has it:** WorldLoad/Unload/InitEvent (the worlds load while the server starts, before any plugin is loaded),
ChunkLoad/UnloadEvent (the chunk system is an asynchronous scheduler with no single place a chunk becomes loaded or unloaded; `ChunkSendEvent`
tells when a player's client gets a chunk), PlayerResourcePackStatusEvent (the answer arrives before the player exists).

**Covered by another event:** InventoryDragEvent (an `InventoryClickEvent` with the quick-craft click type), ProjectileLaunchEvent (the thrown or shot projectile appears as an `EntitySpawnEvent`), CraftItemEvent
(`StatisticEvent`, crafted), the block events of fire, fluids, growth and decay (`BlockChangeEvent`), PlayerPortalEvent and
EntityPortalEvent (`PortalEvent`).

**Systems the server does not have:** dispensers and droppers, bows and crossbows, taming, book editing, shearing (beyond carving a pumpkin, a
`BlockChangeEvent`), lightning (no bolt entity or strikes), enchanting table and anvil events, raids, villager trade events, hanging entities,
maps, beacons, loot generation events and similar.

## Adding an event

1. The server code that has the thing happening calls a hook (`src/plugin/pluginhooks.aowl`, `pluginhooksevents.aowl`); an empty
   default means nothing changes for a server without plugins.
2. `src/plugin/engine/engineplugins.aowl` chains onto the hook and offers the event as an entry (`on_...`) with named fields.
3. `plugin_sdk/pluginsdk.aowl` gets the event type, a `registerEvent` overload and a branch in `dispatchEvent`; the JavaScript SDK gets
   the same name.
