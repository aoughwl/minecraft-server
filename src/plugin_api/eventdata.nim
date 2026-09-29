## Server-side plugin event data model.
## Port of upstream/plugin-api/src/events/*.rs's `Data` shapes, whose real
## field types are defined not in those .rs wrapper files (each is a
## ~20-line `FromIntoEvent` impl with no fields of its own) but in the WIT
## interface at upstream/pumpkin-plugin-wit/v0.1/event.wit, which the
## upstream build compiles into the `wit::...::EventData` records these
## wrappers convert to/from.
##
## This does NOT replace the WASM-guest plugin transport (still
## undecided - see src/host_bindings/README.md and
## src/plugin_runtime/README.md for the replacement paths). It gives the
## port a genuine, usable server-side event-data model independent of
## that transport: something server code can construct and pass to an
## event bus once one exists, whichever transport eventually delivers it
## to a plugin.
##
## Field-type choices, since WIT's `player`/`text-component` are opaque
## *resource* handles (host-side objects with methods), not plain
## records, so there's no faithful 1:1 struct to copy:
## - `player: player` (a WIT resource) becomes `PlayerUuid` (from
##   src/server/net/netbase.nim) - a plain identifier, not the resource
##   handle or a full `Entity`/`Player` reference. This is deliberate: a
##   real `Player`/`Entity` reference would pull in src/server/entity/
##   transitively, which currently makes ANY importing module
##   unverifiable at runtime (see entity/README.md's finding that mere
##   transitive import of entity.nim triggers the closure-vtable crash,
##   independent of whether vtable code actually runs). Event data is
##   exactly the kind of plain, frequently-constructed value type that
##   shouldn't carry that cost - callers that need the live Player look it
##   up by this id.
## - `text-component`/`*-message: text-component` fields (a builder
##   resource with formatting/hover/click methods, defined across
##   text.wit) become plain `string` (the flat text, no formatting).
##   TODO: replace with a real TextComponent type once upstream's
##   `pumpkin-util::text` module (skipped so far, see util's README) is
##   ported.
## - `position: position` becomes `Vector3[float64]` (src/util/vector3.nim).
## - `game-mode` becomes `GameMode` (src/util/gamemode.nim).
## - `entity-id: s32` becomes `int32` directly (WIT's entities are
##   identified by a plain numeric id, not a resource, so there's no
##   Player-style transitive-import problem to route around here).
## - `option<player>` becomes a `(hasX: bool, x: PlayerUuid)` pair rather
##   than an Option type, matching this port's existing seq/tuple-as-
##   option convention (see `signature` above, or `NbtResult`'s
##   isOk/value pairs in src/nbt/).
## - `damage-type` (a resource from a separate, unread `damage-types.wit`)
##   becomes a plain string (its resource-location name).
## - `target-world: %world` fields are dropped where present (e.g.
##   entity-spawn) - src/server/world/worldstub.nim is a single anonymous
##   stub with no world identity/registry yet, so there's nothing to
##   reference; add a world-id field back once worlds are addressable.

import ../server/net/netbase
import ../util/vector3
import ../util/gamemode
import ../world/tick  # BlockPos stand-in (see its doc comment)

type
  PlayerJoinEventData* = object
    player*: PlayerUuid
    joinMessage*: string
    cancelled*: bool

  PlayerLeaveEventData* = object
    player*: PlayerUuid
    leaveMessage*: string
    cancelled*: bool

  PlayerTeleportEventData* = object
    player*: PlayerUuid
    fromPosition*: Vector3[float64]
    toPosition*: Vector3[float64]
    cancelled*: bool

  PlayerGamemodeChangeEventData* = object
    player*: PlayerUuid
    previousGamemode*: GameMode
    newGamemode*: GameMode
    cancelled*: bool

  PlayerToggleSneakEventData* = object
    player*: PlayerUuid
    isSneaking*: bool
    cancelled*: bool

  PlayerMoveEventData* = object
    player*: PlayerUuid
    fromPosition*: Vector3[float64]
    toPosition*: Vector3[float64]
    cancelled*: bool

  PlayerChatEventData* = object
    ## `signature: option<list<u8>>` becomes an empty seq for "none",
    ## matching the seq-as-option convention already used elsewhere in
    ## this port (e.g. src/nbt/ has no separate Option type either).
    player*: PlayerUuid
    message*: string
    recipients*: seq[PlayerUuid]
    signature*: seq[byte]
    cancelled*: bool

  BlockPlaceEventData* = object
    ## `block-placed`/`block-placed-against` are `string` in the WIT
    ## record (presumably a resource-location-formatted block id) rather
    ## than a resolved block-state reference, so this stays a plain
    ## string here too rather than reaching for the still-mostly-unported
    ## block registry.
    player*: PlayerUuid
    blockPlaced*: string
    blockPlacedAgainst*: string
    blockPos*: BlockPos
    canBuild*: bool
    cancelled*: bool

  BlockBreakEventData* = object
    ## `player: option<player>` (breaking can be unattributed, e.g. an
    ## explosion) becomes a `(bool, PlayerUuid)` pair rather than pulling
    ## in an Option type - same seq/tuple-as-option convention used
    ## elsewhere in this port (`signature` above; `NbtResult` isOk/value
    ## pairs in src/nbt/).
    hasPlayer*: bool
    player*: PlayerUuid
    blockName*: string
    blockPos*: BlockPos
    exp*: uint32
    shouldDrop*: bool
    cancelled*: bool

  EntityDamageEventData* = object
    ## `damage-type` is a resource type from a separate `damage-types.wit`
    ## interface this port hasn't read/ported; kept as a plain string
    ## (its resource-location name) rather than blocking on that.
    entityId*: int32
    damage*: float32
    damageType*: string
    cancelled*: bool

  EntityDeathEventData* = object
    ## No `cancelled` field in the WIT record - death, once decided, isn't
    ## cancellable via this event.
    entityId*: int32
    droppedExp*: int32

  PlayerDeathEventData* = object
    player*: PlayerUuid
    deathMessage*: string
    droppedExp*: int32
    keepInventory*: bool
    cancelled*: bool

  EntitySpawnEventData* = object
    ## `target-world: %world` (a WIT resource) has no Nimony World
    ## identity to map onto yet (src/server/world/worldstub.nim is a
    ## single anonymous stub, not a named/registered world) - dropped
    ## rather than faked; a real id can be added once worlds are
    ## addressable.
    entityId*: int32
    entityType*: string
    position*: Vector3[float64]
    cancelled*: bool

  ItemSpawnEventData* = object
    entityId*: int32
    position*: Vector3[float64]
    itemName*: string
    cancelled*: bool

  ItemDespawnEventData* = object
    entityId*: int32
    cancelled*: bool

  PlayerDropItemEventData* = object
    player*: PlayerUuid
    itemName*: string
    count*: uint8
    cancelled*: bool

  BlockRedstoneEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    stateId*: uint16
    blockPos*: BlockPos
    oldCurrent*: int32
    newCurrent*: int32
    cancelled*: bool

  BlockBurnEventData* = object
    ignitingBlock*: string
    blockName*: string
    cancelled*: bool

  BlockCanBuildEventData* = object
    blockToBuild*: string
    buildable*: bool
    player*: PlayerUuid
    blockName*: string
    cancelled*: bool

  BlockGrowEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    oldBlock*: string
    oldStateId*: uint16
    newBlock*: string
    newStateId*: uint16
    blockPos*: BlockPos
    cancelled*: bool

  ServerCommandEventData* = object
    command*: string
    cancelled*: bool

  ServerLoadType* = enum
    sltStartup
    sltReload

  ServerLoadEventData* = object
    loadType*: ServerLoadType

  SpawnChangeEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    ## No `cancelled` field in the WIT record.
    previousPosition*: BlockPos
    previousYaw*: float32
    previousPitch*: float32
    newPosition*: BlockPos
    newYaw*: float32
    newPitch*: float32

  ServerTickStartEventData* = object
    tick*: int32

  ServerTickEndEventData* = object
    tick*: int32
    durationNanos*: int64

  ChunkLoadEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    chunkX*: int32
    chunkZ*: int32
    cancelled*: bool

  ChunkSaveEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    chunkX*: int32
    chunkZ*: int32
    cancelled*: bool

  PlayerLoginEventData* = object
    player*: PlayerUuid
    kickMessage*: string
    cancelled*: bool

  PlayerExpChangeEventData* = object
    player*: PlayerUuid
    amount*: int32

  PlayerToggleSprintEventData* = object
    player*: PlayerUuid
    isSprinting*: bool
    cancelled*: bool

  InventoryCloseEventData* = object
    ## `window-type: option<screen>` becomes a `(hasX, x)` pair, same
    ## seq/tuple-as-option convention used throughout this file.
    player*: PlayerUuid
    hasWindowType*: bool
    windowType*: uint32

  EntityDismountEventData* = object
    entityId*: int32
    dismountedId*: int32
    cancelled*: bool

  EntityPickupItemEventData* = object
    entityId*: int32
    itemName*: string
    count*: uint8
    cancelled*: bool

  EntityResurrectEventData* = object
    entityId*: int32
    cancelled*: bool

  EntityTeleportEventData* = object
    entityId*: int32
    fromPosition*: Vector3[float64]
    toPosition*: Vector3[float64]
    cancelled*: bool

  EntityToggleSwimEventData* = object
    entityId*: int32
    isSwimming*: bool
    cancelled*: bool

  FoodLevelChangeEventData* = object
    entityId*: int32
    foodLevel*: uint8
    cancelled*: bool

  ItemMergeEventData* = object
    entityId*: int32
    targetId*: int32
    cancelled*: bool

  BlockIgniteEventData* = object
    blockPos*: BlockPos
    cancelled*: bool

  BlockFormEventData* = object
    blockPos*: BlockPos
    cancelled*: bool

  TntPrimeEventData* = object
    blockPos*: BlockPos
    primeReason*: string
    cancelled*: bool

  NotePlayEventData* = object
    blockPos*: BlockPos
    instrument*: string
    note*: uint8
    cancelled*: bool

  EntityExplodeEventData* = object
    entityId*: int32
    position*: Vector3[float64]
    yieldRate*: float32
    cancelled*: bool

  PlayerBedEnterEventData* = object
    player*: PlayerUuid
    bedPos*: BlockPos
    cancelled*: bool

  PlayerBedLeaveEventData* = object
    ## No `cancelled` field in the WIT record.
    player*: PlayerUuid
    bedPos*: BlockPos

  PlayerBucketEmptyEventData* = object
    player*: PlayerUuid
    blockPos*: BlockPos
    bucket*: string
    cancelled*: bool

  PlayerBucketFillEventData* = object
    player*: PlayerUuid
    blockPos*: BlockPos
    bucket*: string
    cancelled*: bool

  PlayerKickEventData* = object
    player*: PlayerUuid
    reason*: string
    cancelled*: bool

  BlockPistonExtendEventData* = object
    ## `direction` is a plain string in the WIT record (not a resolved
    ## enum), kept as-is.
    blockPos*: BlockPos
    direction*: string
    cancelled*: bool

  BlockPistonRetractEventData* = object
    blockPos*: BlockPos
    direction*: string
    cancelled*: bool

  SignChangeEventData* = object
    player*: PlayerUuid
    blockPos*: BlockPos
    lines*: seq[string]
    cancelled*: bool

  BellRingEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    ## `entity-id`/`direction` are both `option<T>`, becoming (hasX, x)
    ## pairs per this file's established convention.
    blockPos*: BlockPos
    hasEntityId*: bool
    entityId*: int32
    hasDirection*: bool
    direction*: string
    cancelled*: bool

  WeatherChangeEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    toWeatherState*: bool
    cancelled*: bool

  ThunderChangeEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    toThunderState*: bool
    cancelled*: bool

  InventoryOpenEventData* = object
    player*: PlayerUuid
    cancelled*: bool

  InventoryDragEventData* = object
    player*: PlayerUuid
    cancelled*: bool

  CraftItemEventData* = object
    player*: PlayerUuid
    recipeId*: string
    cancelled*: bool

  EntityCombustEventData* = object
    entityId*: int32
    durationSecs*: float32
    cancelled*: bool

  EntityRegainHealthEventData* = object
    entityId*: int32
    amount*: float32
    cancelled*: bool

  EntityAirChangeEventData* = object
    entityId*: int32
    amount*: int32
    cancelled*: bool

  EntityBreedEventData* = object
    fatherId*: int32
    motherId*: int32
    childId*: int32
    cancelled*: bool

  EntityMountEventData* = object
    entityId*: int32
    mountedId*: int32
    cancelled*: bool

  EntityPortalEventData* = object
    entityId*: int32
    portalPos*: BlockPos
    cancelled*: bool

  EntityShootBowEventData* = object
    entityId*: int32
    weaponName*: string
    force*: float32
    cancelled*: bool

  EntityTameEventData* = object
    ## `owner: player` becomes `PlayerUuid`, same reasoning as `player`
    ## fields throughout this file.
    entityId*: int32
    owner*: PlayerUuid
    cancelled*: bool

  EntityTargetEventData* = object
    ## `target-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hasTargetId*: bool
    targetId*: int32
    cancelled*: bool

  EntityTargetLivingEntityEventData* = object
    entityId*: int32
    hasTargetId*: bool
    targetId*: int32
    reason*: string
    cancelled*: bool

  EntityToggleGlideEventData* = object
    entityId*: int32
    isGliding*: bool
    cancelled*: bool

  EntityTransformEventData* = object
    entityId*: int32
    newEntityId*: int32
    transformReason*: string
    cancelled*: bool

  EntityRemoveEventData* = object
    entityId*: int32
    cause*: string
    cancelled*: bool

  BlockDamageEventData* = object
    player*: PlayerUuid
    blockPos*: BlockPos
    instaBreak*: bool
    cancelled*: bool

  BlockFromToEventData* = object
    fromPos*: BlockPos
    toPos*: BlockPos
    cancelled*: bool

  BlockExplodeEventData* = object
    blockPos*: BlockPos
    yieldRate*: float32
    cancelled*: bool

  BlockPhysicsEventData* = object
    blockPos*: BlockPos
    changedPos*: BlockPos
    cancelled*: bool

  BlockFadeEventData* = object
    blockPos*: BlockPos
    cancelled*: bool

  SpongeAbsorbEventData* = object
    blockPos*: BlockPos
    cancelled*: bool

  HangingBreakEventData* = object
    ## `remover-entity-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hasRemoverEntityId*: bool
    removerEntityId*: int32
    cancelled*: bool

  HangingBreakByEntityEventData* = object
    entityId*: int32
    removerEntityId*: int32
    cancelled*: bool

  WorldLoadEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    ## The WIT record has no other fields; kept as a marker type so the
    ## event still exists in this model even though it's presently empty.
    dummy*: bool

  WorldUnloadEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    cancelled*: bool

  ChunkUnloadEventData* = object
    chunkX*: int32
    chunkZ*: int32
    cancelled*: bool

  TimeSkipEventData* = object
    skipAmount*: int64
    cancelled*: bool

  MoistureChangeEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn above.
    blockPos*: BlockPos
    newMoisture*: int32
    cancelled*: bool
