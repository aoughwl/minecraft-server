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

  PlayerCommandSendEventData* = object
    player*: PlayerUuid
    command*: string
    cancelled*: bool

  PlayerPermissionCheckEventData* = object
    ## No `cancelled` field in the WIT record.
    player*: PlayerUuid
    permission*: string
    permissionResult*: bool

  PlayerRespawnEventData* = object
    ## `previous-world`/`respawned-world: %world` dropped, same reasoning
    ## as EntitySpawn above. No `cancelled` field in the WIT record.
    player*: PlayerUuid
    position*: Vector3[float64]
    yaw*: float32
    pitch*: float32
    alive*: bool

  PlayerItemHeldEventData* = object
    player*: PlayerUuid
    previousSlot*: uint8
    newSlot*: uint8
    cancelled*: bool

  PlayerChangedMainHandEventData* = object
    ## No `cancelled` field in the WIT record. `hand` kept as a plain
    ## string rather than pulling in a Hand enum for one field.
    player*: PlayerUuid
    mainHand*: string

  PlayerFishState* = enum
    pfsFishing
    pfsCaughtFish
    pfsCaughtEntity
    pfsInGround
    pfsFailedAttempt
    pfsReelIn
    pfsBite

  PlayerFishEventData* = object
    ## `caught-uuid: option<uuid>` becomes a (hasX, x) pair. `hand` kept
    ## as a plain string.
    player*: PlayerUuid
    hasCaughtUuid*: bool
    caughtUuid*: string
    caughtType*: string
    hookUuid*: string
    state*: PlayerFishState
    hand*: string
    expToDrop*: int32
    cancelled*: bool

  PlayerEggThrowEventData* = object
    player*: PlayerUuid
    eggUuid*: string
    hatching*: bool
    numHatches*: uint8
    hatchingType*: string
    cancelled*: bool

  InteractAction* = enum
    iaLeftClickBlock
    iaLeftClickAir
    iaRightClickAir
    iaRightClickBlock

  PlayerInteractEventData* = object
    ## `clicked-pos: option<block-pos>` becomes a (hasX, x) pair.
    player*: PlayerUuid
    action*: InteractAction
    hasClickedPos*: bool
    clickedPos*: BlockPos
    blockName*: string
    cancelled*: bool

  PlayerToggleFlightEventData* = object
    player*: PlayerUuid
    isFlying*: bool
    cancelled*: bool

  EntityInteractionAction* = enum
    eiaInteract
    eiaAttack
    eiaInteractAt

  PlayerInteractUnknownEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    action*: EntityInteractionAction
    cancelled*: bool

  PlayerInteractEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    action*: EntityInteractionAction
    sneaking*: bool
    cancelled*: bool

  InventoryClickEventData* = object
    ## `window-type: option<screen>`/`clicked-item`/`cursor:
    ## option<item-stack>` all become (hasX, x) pairs; `click-type` kept
    ## as a plain string rather than pulling in that enum for one field,
    ## and item stacks stay as plain item-name strings, matching this
    ## port's item-field convention elsewhere in this file.
    player*: PlayerUuid
    hasWindowType*: bool
    windowType*: uint32
    clickType*: string
    slot*: int16
    rawSlot*: int16
    hasClickedItem*: bool
    clickedItem*: string
    hasCursor*: bool
    cursor*: string
    hotbarButton*: int32
    cancelled*: bool

  CreatureSpawnEventData* = object
    ## `target-world: %world` dropped, same reasoning as EntitySpawn
    ## above. `player: option<player>` becomes a (hasX, x) pair.
    entityId*: int32
    entityType*: string
    position*: Vector3[float64]
    spawnReason*: string
    hasPlayer*: bool
    player*: PlayerUuid
    cancelled*: bool

  EnderDragonChangePhaseEventData* = object
    entityId*: int32
    currentPhase*: string
    newPhase*: string
    cancelled*: bool

  EntityBreakDoorEventData* = object
    entityId*: int32
    blockPos*: BlockPos
    cancelled*: bool

  EntityChangeBlockEventData* = object
    entityId*: int32
    blockPos*: BlockPos
    newBlock*: string
    cancelled*: bool

  EntityDamageByBlockEventData* = object
    ## `damager-pos: option<block-pos>` becomes a (hasX, x) pair.
    entityId*: int32
    hasDamagerPos*: bool
    damagerPos*: BlockPos
    damage*: float32
    cause*: string
    cancelled*: bool

  EntityDamageByEntityEventData* = object
    entityId*: int32
    damagerId*: int32
    damage*: float32
    cause*: string
    cancelled*: bool

  EntityDropItemEventData* = object
    entityId*: int32
    itemName*: string
    count*: uint8
    cancelled*: bool

  EntityEnterBlockEventData* = object
    entityId*: int32
    blockPos*: BlockPos
    cancelled*: bool

  EntityExhaustionEventData* = object
    entityId*: int32
    exhaustion*: float32
    cancelled*: bool

  EntityInteractEventData* = object
    entityId*: int32
    blockPos*: BlockPos
    cancelled*: bool

  EntityKnockbackEventData* = object
    ## `hit-by-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hasHitById*: bool
    hitById*: int32
    knockback*: Vector3[float64]
    cancelled*: bool

  EntityPlaceEventData* = object
    entityId*: int32
    blockPos*: BlockPos
    blockName*: string
    cancelled*: bool

  EntityPoseChangeEventData* = object
    entityId*: int32
    pose*: string
    cancelled*: bool

  EntityPotionEffectEventData* = object
    entityId*: int32
    effectName*: string
    duration*: int32
    amplifier*: uint8
    cancelled*: bool

  EntitySpellCastEventData* = object
    entityId*: int32
    spell*: string
    cancelled*: bool

  EntityDyeEventData* = object
    ## `player: option<player>` becomes a (hasX, x) pair.
    entityId*: int32
    color*: string
    hasPlayer*: bool
    player*: PlayerUuid
    cancelled*: bool

  EntityEnterLoveModeEventData* = object
    ## `human-entity-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hasHumanEntityId*: bool
    humanEntityId*: int32
    ticksInLove*: int32
    cancelled*: bool

  ExplosionPrimeEventData* = object
    entityId*: int32
    radius*: float32
    fire*: bool
    cancelled*: bool

  FireworkExplodeEventData* = object
    entityId*: int32
    cancelled*: bool

  PiglinBarterEventData* = object
    ## `input-item`/`outcome: list<item-stack>` stay as item-name
    ## strings, matching this port's item-field convention (`outcome`
    ## becomes a single name since a full list of stacks would need a
    ## real ItemStack type not yet threaded through event data).
    entityId*: int32
    inputItem*: string
    cancelled*: bool

  ProjectileHitEventData* = object
    ## `hit-entity-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hitPosition*: Vector3[float64]
    hasHitEntityId*: bool
    hitEntityId*: int32
    cancelled*: bool

  ProjectileLaunchEventData* = object
    ## `shooter-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hasShooterId*: bool
    shooterId*: int32
    cancelled*: bool

  SheepDyeWoolEventData* = object
    ## `player-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    dyeColor*: uint8
    hasPlayerId*: bool
    playerId*: int32
    cancelled*: bool

  SheepRegrowWoolEventData* = object
    entityId*: int32
    cancelled*: bool

  SlimeSplitEventData* = object
    entityId*: int32
    count*: int32
    cancelled*: bool

  StriderTemperatureChangeEventData* = object
    entityId*: int32
    isShivering*: bool
    cancelled*: bool

  BlockBrushEventData* = object
    ## `item: item-stack` becomes an item-name string (this port's
    ## established item-field convention - see PiglinBarter above).
    blockPos*: BlockPos
    player*: PlayerUuid
    item*: string
    cancelled*: bool

  BlockCookEventData* = object
    blockPos*: BlockPos
    source*: string
    resultItem*: string
    cancelled*: bool

  BlockDropItemEventData* = object
    ## `player: option<player>` becomes a (hasX, x) pair.
    blockPos*: BlockPos
    hasPlayer*: bool
    player*: PlayerUuid
    items*: seq[string]
    cancelled*: bool

  BlockExpEventData* = object
    blockPos*: BlockPos
    exp*: int32

  BlockFertilizeEventData* = object
    ## `changed-blocks: list<tuple<block-pos, u16>>` becomes parallel
    ## seqs (position, new state id) rather than a seq of tuples, to
    ## avoid an anonymous tuple type in the public object shape.
    blockPos*: BlockPos
    hasPlayer*: bool
    player*: PlayerUuid
    changedPositions*: seq[BlockPos]
    changedStateIds*: seq[uint16]
    cancelled*: bool

  BlockMultiPlaceEventData* = object
    player*: PlayerUuid
    placedPositions*: seq[BlockPos]
    placedStateIds*: seq[uint16]
    cancelled*: bool

  BlockShearEntityEventData* = object
    blockPos*: BlockPos
    targetEntityId*: int32
    item*: string
    cancelled*: bool

  BlockSpreadEventData* = object
    sourcePos*: BlockPos
    targetPos*: BlockPos
    newStateId*: uint16
    cancelled*: bool

  BrewEventData* = object
    blockPos*: BlockPos
    fuelLevel*: uint8
    cancelled*: bool

  BrewingStandFuelEventData* = object
    blockPos*: BlockPos
    fuelPower*: uint16
    cancelled*: bool

  BrewingStartEventData* = object
    blockPos*: BlockPos
    brewingTime*: int32
    cancelled*: bool

  CampfireStartEventData* = object
    blockPos*: BlockPos
    item*: string
    slot*: uint8
    cookingTime*: int32
    cancelled*: bool

  CauldronLevelChangeEventData* = object
    ## `entity-id: option<s32>` becomes a (hasX, x) pair.
    blockPos*: BlockPos
    oldLevel*: int32
    newLevel*: int32
    reason*: string
    hasEntityId*: bool
    entityId*: int32
    cancelled*: bool

  ChunkPopulateEventData* = object
    chunkX*: int32
    chunkZ*: int32
    cancelled*: bool

  ChunkSendEventData* = object
    chunkX*: int32
    chunkZ*: int32
    cancelled*: bool

  CrafterCraftEventData* = object
    blockPos*: BlockPos
    resultItem*: string
    cancelled*: bool

  CreeperPowerEventData* = object
    ## `lightning-id: option<s32>` becomes a (hasX, x) pair.
    entityId*: int32
    hasLightningId*: bool
    lightningId*: int32
    cause*: string
    cancelled*: bool

  EnchantItemEventData* = object
    ## `%option: s32` (WIT's escaped-keyword field, upstream's enchant-menu
    ## button index) becomes `optionIndex`. `enchantments-to-add:
    ## list<enchantment-value>` becomes parallel seqs (name, level) -
    ## `enchantment-value` isn't ported as its own type yet.
    player*: PlayerUuid
    item*: string
    optionIndex*: int32
    cost*: int32
    enchantmentNames*: seq[string]
    enchantmentLevels*: seq[int32]
    cancelled*: bool

  EntitiesLoadEventData* = object
    chunkX*: int32
    chunkZ*: int32
    entityCount*: uint32
    cancelled*: bool

  EntitiesUnloadEventData* = object
    chunkX*: int32
    chunkZ*: int32
    entityCount*: uint32
    cancelled*: bool

  EntityBlockFormEventData* = object
    entityId*: int32
    blockPos*: BlockPos
    newStateId*: uint16
    cancelled*: bool

  EntityCombustByBlockEventData* = object
    entityId*: int32
    combuster*: BlockPos
    duration*: float32
    cancelled*: bool

  EntityCombustByEntityEventData* = object
    entityId*: int32
    combusterId*: int32
    duration*: float32
    cancelled*: bool

  ExpBottleEventData* = object
    entityId*: int32
    experience*: int32
    location*: BlockPos
    showEffect*: bool
    cancelled*: bool

  FluidLevelChangeEventData* = object
    blockPos*: BlockPos
    newStateId*: uint16
    cancelled*: bool

  FurnaceBurnEventData* = object
    blockPos*: BlockPos
    fuelItem*: string
    burnTime*: uint32
    cancelled*: bool

  FurnaceExtractEventData* = object
    ## No `cancelled` field in the real WIT record - extraction has
    ## already happened by the time this fires.
    player*: PlayerUuid
    blockPos*: BlockPos
    itemId*: string
    itemAmount*: uint32
    expGained*: float32

  FurnaceSmeltEventData* = object
    blockPos*: BlockPos
    sourceItem*: string
    resultItem*: string
    cancelled*: bool

  FurnaceStartSmeltEventData* = object
    blockPos*: BlockPos
    sourceItem*: string
    cookingTime*: uint32
    cancelled*: bool

  HangingPlaceEventData* = object
    ## `player: option<player>` becomes a (hasX, x) pair.
    entityId*: int32
    hasPlayer*: bool
    player*: PlayerUuid
    blockPos*: BlockPos
    blockFace*: string
    cancelled*: bool

  PlayerChangeWorldEventData* = object
    ## `previous-world`/`new-world: %world` dropped, same as elsewhere -
    ## see the file header's `target-world` note.
    player*: PlayerUuid
    position*: Vector3[float64]
    yaw*: float32
    pitch*: float32
    cancelled*: bool

  PlayerCustomPayloadEventData* = object
    player*: PlayerUuid
    channel*: string
    data*: seq[byte]

  PlayerItemConsumeEventData* = object
    player*: PlayerUuid
    itemName*: string
    cancelled*: bool

  PlayerItemDamageEventData* = object
    player*: PlayerUuid
    itemName*: string
    damage*: int32
    cancelled*: bool

  AsyncPlayerChatEventData* = object
    ## `format: text-component` becomes plain `string`, same as elsewhere.
    player*: PlayerUuid
    message*: string
    format*: string
    cancelled*: bool

  AsyncPlayerPreLoginEventData* = object
    playerName*: string
    playerUuid*: string
    ipAddress*: string
    kickMessage*: string
    cancelled*: bool

  PlayerPreLoginEventData* = object
    playerName*: string
    playerUuid*: string
    ipAddress*: string
    kickMessage*: string
    cancelled*: bool

  PlayerAdvancementDoneEventData* = object
    player*: PlayerUuid
    advancementId*: string
    cancelled*: bool

  PlayerAnimationEventData* = object
    player*: PlayerUuid
    animationType*: string
    cancelled*: bool

  PlayerArmorStandManipulateEventData* = object
    player*: PlayerUuid
    armorStandId*: int32
    slot*: uint8
    cancelled*: bool

  PlayerBucketEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    bucketItem*: string
    cancelled*: bool

  PlayerChangedWorldEventData* = object
    ## `from-world`/`to-world: %world` dropped, same as elsewhere.
    player*: PlayerUuid
    cancelled*: bool

  PlayerChannelEventData* = object
    player*: PlayerUuid
    channel*: string
    cancelled*: bool

  PlayerCommandPreprocessEventData* = object
    player*: PlayerUuid
    command*: string
    cancelled*: bool

  PlayerEditBookEventData* = object
    ## `title: option<string>` becomes a (hasX, x) pair.
    player*: PlayerUuid
    slot*: uint32
    pages*: seq[string]
    hasTitle*: bool
    title*: string
    signing*: bool
    cancelled*: bool

  PlayerElytraBoostEventData* = object
    player*: PlayerUuid
    fireworkId*: int32
    cancelled*: bool

  PlayerExpCooldownChangeEventData* = object
    player*: PlayerUuid
    newCooldown*: int32
    cancelled*: bool

  PlayerHarvestBlockEventData* = object
    ## `harvested-items: list<item-stack>` becomes item-name strings, not
    ## real ItemStack values - keeps this file free of the inventory
    ## module dependency the rest of it deliberately avoids.
    player*: PlayerUuid
    blockPos*: BlockPos
    harvestedItems*: seq[string]
    cancelled*: bool

  PlayerHideEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    cancelled*: bool

  PlayerItemBreakEventData* = object
    player*: PlayerUuid
    itemName*: string

  PlayerItemMendEventData* = object
    player*: PlayerUuid
    itemName*: string
    repairAmount*: int32
    expConsumed*: int32
    cancelled*: bool

  PlayerLeashEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    holderId*: int32
    cancelled*: bool

  PlayerLevelChangeEventData* = object
    player*: PlayerUuid
    oldLevel*: int32
    newLevel*: int32

  PlayerLocaleChangeEventData* = object
    player*: PlayerUuid
    newLocale*: string
    cancelled*: bool

  PlayerNameEntityEventData* = object
    ## `name: text-component` becomes plain `string`.
    player*: PlayerUuid
    entityId*: int32
    name*: string
    cancelled*: bool

  PlayerOpenSignEventData* = object
    player*: PlayerUuid
    blockPos*: BlockPos
    isFront*: bool
    cancelled*: bool

  PlayerPortalEventData* = object
    ## `to-pos: option<block-pos>` becomes a (hasX, x) pair.
    player*: PlayerUuid
    fromPos*: BlockPos
    hasToPos*: bool
    toPos*: BlockPos
    cancelled*: bool

  PlayerRiptideEventData* = object
    player*: PlayerUuid
    itemName*: string
    cancelled*: bool

  PlayerShearEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    hand*: uint8
    cancelled*: bool

  PlayerShowEntityEventData* = object
    player*: PlayerUuid
    entityId*: int32
    cancelled*: bool

  PlayerSpawnChangeEventData* = object
    ## `new-spawn: option<block-pos>` becomes a (hasX, x) pair.
    player*: PlayerUuid
    hasNewSpawn*: bool
    newSpawn*: BlockPos
    forced*: bool
    cancelled*: bool

  PlayerStatisticIncrementEventData* = object
    player*: PlayerUuid
    statisticId*: string
    amount*: int32
    cancelled*: bool

  PlayerSwapHandsEventData* = object
    player*: PlayerUuid
    cancelled*: bool

  PlayerTakeLecternBookEventData* = object
    ## `book: item-stack` becomes an item-name string, same reasoning as
    ## PlayerHarvestBlockEventData.
    player*: PlayerUuid
    blockPos*: BlockPos
    book*: string
    cancelled*: bool
