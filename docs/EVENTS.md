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
| `StatisticEvent` | PlayerStatisticIncrementEvent | `category`, `statId`, `amount` | |
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

That is 66 event types. Events that fire often (movement, packets, ticks, permission checks, block grow, redstone, chunk send, damage)
cost nothing while no loaded plugin listens to them.

## Bukkit events that do not exist here, and why

Bukkit has well over 200 event classes. An event can only exist when the server has the thing happening and a place that fires it. This
server (a port of Pumpkin) fires the events above; the rest below either need a firing site added in the server or describe a game
system the server does not have.

**Needs a firing site in the server (the system exists):** BlockBurnEvent, BlockCanBuildEvent, BlockFadeEvent, BlockFormEvent,
BlockSpreadEvent, BlockFromToEvent (fluid flow), BlockIgniteEvent, BlockDispenseEvent,
LeavesDecayEvent, BlockPhysicsEvent, EntityTargetEvent, EntityChangeBlockEvent,
EntityShootBowEvent, EntityTameEvent, ProjectileLaunchEvent, ProjectileHitEvent,
PlayerKickEvent, PlayerPortalEvent, PlayerAdvancementDoneEvent,
PlayerShearEntityEvent, PlayerEditBookEvent, PlayerResourcePackStatusEvent,
InventoryDragEvent, InventoryMoveItemEvent, CraftItemEvent,
PrepareItemCraftEvent, FurnaceBurn/Smelt/ExtractEvent, BrewEvent, WorldLoad/Unload/InitEvent, ChunkLoad/UnloadEvent
(upstream declares chunk load and save but never fires them), LightningStrikeEvent, PortalCreateEvent, TabCompleteEvent,
VehicleEnter/Exit/Move/DamageEvent.

**Systems the server does not have:** enchanting table and anvil events, raids, villager trade events, hanging entities,
maps, beacons, loot generation events and similar.

## Adding an event

1. The server code that has the thing happening calls a hook (`src/plugin/pluginhooks.aowl`, `pluginhooksevents.aowl`); an empty
   default means nothing changes for a server without plugins.
2. `src/plugin/engine/engineplugins.aowl` chains onto the hook and offers the event as an entry (`on_...`) with named fields.
3. `plugin_sdk/pluginsdk.aowl` gets the event type, a `registerEvent` overload and a branch in `dispatchEvent`; the JavaScript SDK gets
   the same name.
