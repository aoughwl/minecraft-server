## Runtime smoke test for eventdata.nim, run via `nimony c -r`.
## Pure data construction/field access - no vtables/closures involved, so
## this is expected to actually run cleanly (unlike anything importing
## src/server/entity/entity.nim, per that module's README).

import std/syncio
import std/assertions
import eventdata
import ../server/net/netbase
import ../util/vector3
import ../util/gamemode
import ../world/tick

let p1: PlayerUuid = (hi: 1'u64, lo: 2'u64)
let p2: PlayerUuid = (hi: 3'u64, lo: 4'u64)

let joinData = PlayerJoinEventData(
  player: p1,
  joinMessage: "Alice joined the game",
  cancelled: false,
)
assert joinData.player == p1
assert joinData.joinMessage == "Alice joined the game"
assert not joinData.cancelled

let moveData = PlayerMoveEventData(
  player: p1,
  fromPosition: Vector3[float64](x: 0.0, y: 64.0, z: 0.0),
  toPosition: Vector3[float64](x: 1.0, y: 64.0, z: 0.0),
  cancelled: false,
)
assert moveData.toPosition.x == 1.0

let gmData = PlayerGamemodeChangeEventData(
  player: p1,
  previousGamemode: Survival,
  newGamemode: Creative,
  cancelled: false,
)
assert gmData.previousGamemode == Survival
assert gmData.newGamemode == Creative

let chatData = PlayerChatEventData(
  player: p1,
  message: "hello",
  recipients: @[p1, p2],
  signature: @[],
  cancelled: false,
)
assert chatData.recipients.len == 2
assert chatData.signature.len == 0

let placedAt = blockPos(10, 64, -5)
let placeData = BlockPlaceEventData(
  player: p1,
  blockPlaced: "minecraft:stone",
  blockPlacedAgainst: "minecraft:dirt",
  blockPos: placedAt,
  canBuild: true,
  cancelled: false,
)
assert placeData.blockPos.z == -5

let breakData = BlockBreakEventData(
  hasPlayer: true,
  player: p1,
  blockName: "minecraft:oak_log",
  blockPos: blockPos(1, 65, 1),
  exp: 0'u32,
  shouldDrop: true,
  cancelled: false,
)
assert breakData.hasPlayer
assert breakData.blockName == "minecraft:oak_log"

let unattributedBreak = BlockBreakEventData(
  hasPlayer: false,
  player: p1, # ignored when hasPlayer is false, same as an Option's "none"
  blockName: "minecraft:tnt",
  blockPos: blockPos(0, 0, 0),
  exp: 0'u32,
  shouldDrop: false,
  cancelled: false,
)
assert not unattributedBreak.hasPlayer

let damageData = EntityDamageEventData(
  entityId: 42'i32,
  damage: 4.5'f32,
  damageType: "minecraft:generic",
  cancelled: false,
)
assert damageData.entityId == 42'i32
assert damageData.damage == 4.5'f32

let deathData = EntityDeathEventData(
  entityId: 42'i32,
  droppedExp: 5'i32,
)
assert deathData.droppedExp == 5'i32

let playerDeathData = PlayerDeathEventData(
  player: p1,
  deathMessage: "Alice was slain",
  droppedExp: 7'i32,
  keepInventory: false,
  cancelled: false,
)
assert playerDeathData.deathMessage == "Alice was slain"
assert not playerDeathData.keepInventory

let spawnData = EntitySpawnEventData(
  entityId: 100'i32,
  entityType: "minecraft:zombie",
  position: Vector3[float64](x: 5.0, y: 64.0, z: 5.0),
  cancelled: false,
)
assert spawnData.entityType == "minecraft:zombie"

let itemSpawnData = ItemSpawnEventData(
  entityId: 101'i32,
  position: Vector3[float64](x: 5.0, y: 64.0, z: 5.0),
  itemName: "minecraft:diamond",
  cancelled: false,
)
assert itemSpawnData.itemName == "minecraft:diamond"

let itemDespawnData = ItemDespawnEventData(
  entityId: 101'i32,
  cancelled: false,
)
assert itemDespawnData.entityId == 101'i32

let dropData = PlayerDropItemEventData(
  player: p1,
  itemName: "minecraft:apple",
  count: 3'u8,
  cancelled: false,
)
assert dropData.count == 3'u8

let redstoneData = BlockRedstoneEventData(
  stateId: 5'u16,
  blockPos: blockPos(2, 63, 2),
  oldCurrent: 0'i32,
  newCurrent: 15'i32,
  cancelled: false,
)
assert redstoneData.newCurrent == 15'i32

let burnData = BlockBurnEventData(
  ignitingBlock: "minecraft:fire",
  blockName: "minecraft:oak_planks",
  cancelled: false,
)
assert burnData.blockName == "minecraft:oak_planks"

let canBuildData = BlockCanBuildEventData(
  blockToBuild: "minecraft:chest",
  buildable: true,
  player: p1,
  blockName: "minecraft:air",
  cancelled: false,
)
assert canBuildData.buildable

let growData = BlockGrowEventData(
  oldBlock: "minecraft:sapling",
  oldStateId: 3'u16,
  newBlock: "minecraft:oak_log",
  newStateId: 9'u16,
  blockPos: blockPos(0, 64, 0),
  cancelled: false,
)
assert growData.newBlock == "minecraft:oak_log"

let serverCommandData = ServerCommandEventData(
  command: "gamemode creative Alice",
  cancelled: false,
)
assert serverCommandData.command.len > 0

let loadData = ServerLoadEventData(loadType: sltStartup)
assert loadData.loadType == sltStartup

let spawnChangeData = SpawnChangeEventData(
  previousPosition: blockPos(0, 64, 0),
  previousYaw: 0.0'f32,
  previousPitch: 0.0'f32,
  newPosition: blockPos(100, 70, 100),
  newYaw: 90.0'f32,
  newPitch: 0.0'f32,
)
assert spawnChangeData.newPosition.x == 100

let tickStartData = ServerTickStartEventData(tick: 12345'i32)
assert tickStartData.tick == 12345'i32

let tickEndData = ServerTickEndEventData(tick: 12345'i32, durationNanos: 2_000_000'i64)
assert tickEndData.durationNanos == 2_000_000'i64

let chunkLoadData = ChunkLoadEventData(chunkX: 3'i32, chunkZ: -4'i32, cancelled: false)
assert chunkLoadData.chunkZ == -4'i32

let chunkSaveData = ChunkSaveEventData(chunkX: 3'i32, chunkZ: -4'i32, cancelled: false)
assert chunkSaveData.chunkX == 3'i32

let loginData = PlayerLoginEventData(player: p1, kickMessage: "", cancelled: false)
assert not loginData.cancelled

let expData = PlayerExpChangeEventData(player: p1, amount: 5'i32)
assert expData.amount == 5'i32

let sprintData = PlayerToggleSprintEventData(player: p1, isSprinting: true, cancelled: false)
assert sprintData.isSprinting

let invCloseData = InventoryCloseEventData(player: p1, hasWindowType: true, windowType: 2'u32)
assert invCloseData.hasWindowType

let dismountData = EntityDismountEventData(entityId: 10'i32, dismountedId: 20'i32, cancelled: false)
assert dismountData.dismountedId == 20'i32

let pickupData = EntityPickupItemEventData(entityId: 10'i32, itemName: "minecraft:stone", count: 3'u8, cancelled: false)
assert pickupData.count == 3'u8

let resurrectData = EntityResurrectEventData(entityId: 10'i32, cancelled: false)
assert resurrectData.entityId == 10'i32

let entityTeleportData = EntityTeleportEventData(
  entityId: 10'i32,
  fromPosition: Vector3[float64](x: 0.0, y: 64.0, z: 0.0),
  toPosition: Vector3[float64](x: 5.0, y: 64.0, z: 5.0),
  cancelled: false,
)
assert entityTeleportData.toPosition.x == 5.0

let swimData = EntityToggleSwimEventData(entityId: 10'i32, isSwimming: true, cancelled: false)
assert swimData.isSwimming

let foodData = FoodLevelChangeEventData(entityId: 10'i32, foodLevel: 18'u8, cancelled: false)
assert foodData.foodLevel == 18'u8

let mergeData = ItemMergeEventData(entityId: 10'i32, targetId: 11'i32, cancelled: false)
assert mergeData.targetId == 11'i32

let igniteData = BlockIgniteEventData(blockPos: blockPos(1, 64, 1), cancelled: false)
assert igniteData.blockPos.x == 1

let formData = BlockFormEventData(blockPos: blockPos(1, 64, 1), cancelled: false)
assert formData.blockPos.y == 64

let tntData = TntPrimeEventData(blockPos: blockPos(1, 64, 1), primeReason: "fire", cancelled: false)
assert tntData.primeReason == "fire"

let notePlayData = NotePlayEventData(blockPos: blockPos(1, 64, 1), instrument: "harp", note: 12'u8, cancelled: false)
assert notePlayData.note == 12'u8

let explodeData = EntityExplodeEventData(
  entityId: 10'i32,
  position: Vector3[float64](x: 0.0, y: 64.0, z: 0.0),
  yieldRate: 0.5'f32,
  cancelled: false,
)
assert explodeData.yieldRate == 0.5'f32

let bedEnterData = PlayerBedEnterEventData(player: p1, bedPos: blockPos(1, 64, 1), cancelled: false)
assert bedEnterData.bedPos.x == 1

let bedLeaveData = PlayerBedLeaveEventData(player: p1, bedPos: blockPos(1, 64, 1))
assert bedLeaveData.bedPos.y == 64

let bucketEmptyData = PlayerBucketEmptyEventData(player: p1, blockPos: blockPos(1, 64, 1), bucket: "water_bucket", cancelled: false)
assert bucketEmptyData.bucket == "water_bucket"

let bucketFillData = PlayerBucketFillEventData(player: p1, blockPos: blockPos(1, 64, 1), bucket: "empty_bucket", cancelled: false)
assert bucketFillData.bucket == "empty_bucket"

let kickData = PlayerKickEventData(player: p1, reason: "AFK", cancelled: false)
assert kickData.reason == "AFK"

let pistonExtendData = BlockPistonExtendEventData(blockPos: blockPos(1, 64, 1), direction: "up", cancelled: false)
assert pistonExtendData.direction == "up"

let pistonRetractData = BlockPistonRetractEventData(blockPos: blockPos(1, 64, 1), direction: "down", cancelled: false)
assert pistonRetractData.direction == "down"

let signData = SignChangeEventData(player: p1, blockPos: blockPos(1, 64, 1), lines: @["hello", "world", "", ""], cancelled: false)
assert signData.lines.len == 4
assert signData.lines[0] == "hello"

let bellData = BellRingEventData(
  blockPos: blockPos(1, 64, 1),
  hasEntityId: true,
  entityId: 10'i32,
  hasDirection: false,
  direction: "",
  cancelled: false,
)
assert bellData.hasEntityId
assert not bellData.hasDirection

let weatherData = WeatherChangeEventData(toWeatherState: true, cancelled: false)
assert weatherData.toWeatherState

let thunderData = ThunderChangeEventData(toThunderState: false, cancelled: false)
assert not thunderData.toThunderState

let invOpenData = InventoryOpenEventData(player: p1, cancelled: false)
assert invOpenData.player == p1

let invDragData = InventoryDragEventData(player: p1, cancelled: false)
assert invDragData.player == p1

let craftData = CraftItemEventData(player: p1, recipeId: "minecraft:stick", cancelled: false)
assert craftData.recipeId == "minecraft:stick"

let combustData = EntityCombustEventData(entityId: 5'i32, durationSecs: 3.0'f32, cancelled: false)
assert combustData.durationSecs == 3.0'f32

let regainData = EntityRegainHealthEventData(entityId: 5'i32, amount: 2.0'f32, cancelled: false)
assert regainData.amount == 2.0'f32

let airData = EntityAirChangeEventData(entityId: 5'i32, amount: 300'i32, cancelled: false)
assert airData.amount == 300'i32

let breedData = EntityBreedEventData(fatherId: 1'i32, motherId: 2'i32, childId: 3'i32, cancelled: false)
assert breedData.childId == 3'i32

let mountData = EntityMountEventData(entityId: 5'i32, mountedId: 6'i32, cancelled: false)
assert mountData.mountedId == 6'i32

let portalData = EntityPortalEventData(entityId: 5'i32, portalPos: blockPos(1, 64, 1), cancelled: false)
assert portalData.portalPos.y == 64

let shootData = EntityShootBowEventData(entityId: 5'i32, weaponName: "bow", force: 1.0'f32, cancelled: false)
assert shootData.weaponName == "bow"

let tameData = EntityTameEventData(entityId: 5'i32, owner: p1, cancelled: false)
assert tameData.owner == p1

let targetData = EntityTargetEventData(entityId: 5'i32, hasTargetId: true, targetId: 9'i32, cancelled: false)
assert targetData.hasTargetId
assert targetData.targetId == 9'i32

let targetLivingData = EntityTargetLivingEntityEventData(entityId: 5'i32, hasTargetId: false, targetId: 0'i32, reason: "closest", cancelled: false)
assert not targetLivingData.hasTargetId
assert targetLivingData.reason == "closest"

let glideData = EntityToggleGlideEventData(entityId: 5'i32, isGliding: true, cancelled: false)
assert glideData.isGliding

let transformData = EntityTransformEventData(entityId: 5'i32, newEntityId: 7'i32, transformReason: "curing", cancelled: false)
assert transformData.newEntityId == 7'i32

let removeData = EntityRemoveEventData(entityId: 5'i32, cause: "death", cancelled: false)
assert removeData.cause == "death"

let blockDamageData = BlockDamageEventData(player: p1, blockPos: blockPos(1, 64, 1), instaBreak: true, cancelled: false)
assert blockDamageData.instaBreak

let fromToData = BlockFromToEventData(fromPos: blockPos(1, 64, 1), toPos: blockPos(2, 64, 1), cancelled: false)
assert fromToData.toPos.x == 2

let blockExplodeData = BlockExplodeEventData(blockPos: blockPos(1, 64, 1), yieldRate: 0.5'f32, cancelled: false)
assert blockExplodeData.yieldRate == 0.5'f32

let physicsData = BlockPhysicsEventData(blockPos: blockPos(1, 64, 1), changedPos: blockPos(1, 65, 1), cancelled: false)
assert physicsData.changedPos.y == 65

let fadeData = BlockFadeEventData(blockPos: blockPos(1, 64, 1), cancelled: false)
assert not fadeData.cancelled

let spongeData = SpongeAbsorbEventData(blockPos: blockPos(1, 64, 1), cancelled: false)
assert not spongeData.cancelled

let hangBreakData = HangingBreakEventData(entityId: 5'i32, hasRemoverEntityId: false, removerEntityId: 0'i32, cancelled: false)
assert not hangBreakData.hasRemoverEntityId

let hangBreakByData = HangingBreakByEntityEventData(entityId: 5'i32, removerEntityId: 6'i32, cancelled: false)
assert hangBreakByData.removerEntityId == 6'i32

let worldLoadData = WorldLoadEventData(dummy: true)
assert worldLoadData.dummy

let worldUnloadData = WorldUnloadEventData(cancelled: false)
assert not worldUnloadData.cancelled

let chunkUnloadData = ChunkUnloadEventData(chunkX: 3'i32, chunkZ: -2'i32, cancelled: false)
assert chunkUnloadData.chunkZ == -2'i32

let timeSkipData = TimeSkipEventData(skipAmount: 24000'i64, cancelled: false)
assert timeSkipData.skipAmount == 24000'i64

let moistureData = MoistureChangeEventData(blockPos: blockPos(1, 64, 1), newMoisture: 4'i32)
assert moistureData.newMoisture == 4'i32

let cmdSendData = PlayerCommandSendEventData(player: p1, command: "/help", cancelled: false)
assert cmdSendData.command == "/help"

let permCheckData = PlayerPermissionCheckEventData(player: p1, permission: "server.stop", permissionResult: false)
assert not permCheckData.permissionResult

let respawnData = PlayerRespawnEventData(player: p1, position: Vector3[float64](x: 0.0, y: 64.0, z: 0.0), yaw: 0.0'f32, pitch: 0.0'f32, alive: true)
assert respawnData.alive

let itemHeldData = PlayerItemHeldEventData(player: p1, previousSlot: 0'u8, newSlot: 3'u8, cancelled: false)
assert itemHeldData.newSlot == 3'u8

let mainHandData = PlayerChangedMainHandEventData(player: p1, mainHand: "left")
assert mainHandData.mainHand == "left"

let fishData = PlayerFishEventData(player: p1, hasCaughtUuid: false, caughtUuid: "", caughtType: "", hookUuid: "abc", state: pfsBite, hand: "main_hand", expToDrop: 1'i32, cancelled: false)
assert fishData.state == pfsBite

let eggThrowData = PlayerEggThrowEventData(player: p1, eggUuid: "abc", hatching: true, numHatches: 1'u8, hatchingType: "minecraft:chicken", cancelled: false)
assert eggThrowData.hatching

let interactData = PlayerInteractEventData(player: p1, action: iaRightClickBlock, hasClickedPos: true, clickedPos: blockPos(1, 64, 1), blockName: "minecraft:chest", cancelled: false)
assert interactData.action == iaRightClickBlock

let toggleFlightData = PlayerToggleFlightEventData(player: p1, isFlying: true, cancelled: false)
assert toggleFlightData.isFlying

let interactUnknownData = PlayerInteractUnknownEntityEventData(player: p1, entityId: 7'i32, action: eiaAttack, cancelled: false)
assert interactUnknownData.action == eiaAttack

let interactEntityData = PlayerInteractEntityEventData(player: p1, entityId: 7'i32, action: eiaInteract, sneaking: true, cancelled: false)
assert interactEntityData.sneaking

let invClickData = InventoryClickEventData(player: p1, hasWindowType: false, windowType: 0'u32, clickType: "pickup", slot: 5'i16, rawSlot: 5'i16, hasClickedItem: true, clickedItem: "minecraft:stone", hasCursor: false, cursor: "", hotbarButton: -1'i32, cancelled: false)
assert invClickData.clickedItem == "minecraft:stone"

let creatureSpawnData = CreatureSpawnEventData(entityId: 8'i32, entityType: "minecraft:zombie", position: Vector3[float64](x: 0.0, y: 64.0, z: 0.0), spawnReason: "natural", hasPlayer: false, player: p1, cancelled: false)
assert creatureSpawnData.entityType == "minecraft:zombie"

let dragonPhaseData = EnderDragonChangePhaseEventData(entityId: 9'i32, currentPhase: "circling", newPhase: "charging_player", cancelled: false)
assert dragonPhaseData.newPhase == "charging_player"

let breakDoorData = EntityBreakDoorEventData(entityId: 10'i32, blockPos: blockPos(2, 64, 2), cancelled: false)
assert breakDoorData.entityId == 10'i32

let changeBlockData = EntityChangeBlockEventData(entityId: 10'i32, blockPos: blockPos(2, 64, 2), newBlock: "minecraft:dirt_path", cancelled: false)
assert changeBlockData.newBlock == "minecraft:dirt_path"

let dmgByBlockData = EntityDamageByBlockEventData(entityId: 10'i32, hasDamagerPos: true, damagerPos: blockPos(2, 64, 2), damage: 4.0'f32, cause: "cactus", cancelled: false)
assert dmgByBlockData.damage == 4.0'f32

let dmgByEntityData = EntityDamageByEntityEventData(entityId: 10'i32, damagerId: 11'i32, damage: 6.0'f32, cause: "attack", cancelled: false)
assert dmgByEntityData.damagerId == 11'i32

let dropItemData = EntityDropItemEventData(entityId: 10'i32, itemName: "minecraft:bone", count: 2'u8, cancelled: false)
assert dropItemData.count == 2'u8

let enterBlockData = EntityEnterBlockEventData(entityId: 10'i32, blockPos: blockPos(2, 64, 2), cancelled: false)
assert enterBlockData.blockPos == blockPos(2, 64, 2)

let exhaustionData = EntityExhaustionEventData(entityId: 10'i32, exhaustion: 0.1'f32, cancelled: false)
assert exhaustionData.exhaustion == 0.1'f32

let entityInteractData = EntityInteractEventData(entityId: 10'i32, blockPos: blockPos(2, 64, 2), cancelled: false)
assert entityInteractData.cancelled == false

let knockbackData = EntityKnockbackEventData(entityId: 10'i32, hasHitById: true, hitById: 11'i32, knockback: Vector3[float64](x: 1.0, y: 0.0, z: 0.0), cancelled: false)
assert knockbackData.hasHitById

let entityPlaceData = EntityPlaceEventData(entityId: 10'i32, blockPos: blockPos(2, 64, 2), blockName: "minecraft:armor_stand", cancelled: false)
assert entityPlaceData.blockName == "minecraft:armor_stand"

let poseData = EntityPoseChangeEventData(entityId: 10'i32, pose: "sleeping", cancelled: false)
assert poseData.pose == "sleeping"

let potionData = EntityPotionEffectEventData(entityId: 10'i32, effectName: "minecraft:speed", duration: 200'i32, amplifier: 1'u8, cancelled: false)
assert potionData.duration == 200'i32

let spellData = EntitySpellCastEventData(entityId: 10'i32, spell: "summon_vex", cancelled: false)
assert spellData.spell == "summon_vex"

let dyeData = EntityDyeEventData(entityId: 10'i32, color: "red", hasPlayer: true, player: p1, cancelled: false)
assert dyeData.color == "red"

let loveModeData = EntityEnterLoveModeEventData(entityId: 10'i32, hasHumanEntityId: true, humanEntityId: 7'i32, ticksInLove: 600'i32, cancelled: false)
assert loveModeData.ticksInLove == 600'i32

let explosionPrimeData = ExplosionPrimeEventData(entityId: 12'i32, radius: 3.0'f32, fire: false, cancelled: false)
assert explosionPrimeData.radius == 3.0'f32

let fireworkData = FireworkExplodeEventData(entityId: 12'i32, cancelled: false)
assert fireworkData.entityId == 12'i32

let piglinBarterData = PiglinBarterEventData(entityId: 13'i32, inputItem: "minecraft:gold_ingot", cancelled: false)
assert piglinBarterData.inputItem == "minecraft:gold_ingot"

let projHitData = ProjectileHitEventData(entityId: 14'i32, hitPosition: Vector3[float64](x: 0.0, y: 64.0, z: 0.0), hasHitEntityId: true, hitEntityId: 15'i32, cancelled: false)
assert projHitData.hitEntityId == 15'i32

let projLaunchData = ProjectileLaunchEventData(entityId: 14'i32, hasShooterId: true, shooterId: 1'i32, cancelled: false)
assert projLaunchData.shooterId == 1'i32

let sheepDyeData = SheepDyeWoolEventData(entityId: 16'i32, dyeColor: 3'u8, hasPlayerId: false, playerId: 0'i32, cancelled: false)
assert sheepDyeData.dyeColor == 3'u8

let sheepRegrowData = SheepRegrowWoolEventData(entityId: 16'i32, cancelled: false)
assert sheepRegrowData.entityId == 16'i32

let slimeSplitData = SlimeSplitEventData(entityId: 17'i32, count: 4'i32, cancelled: false)
assert slimeSplitData.count == 4'i32

let striderTempData = StriderTemperatureChangeEventData(entityId: 18'i32, isShivering: true, cancelled: false)
assert striderTempData.isShivering

let bp1 = BlockPos(x: 1, y: 2, z: 3)
let bp2 = BlockPos(x: 4, y: 5, z: 6)

let brushData = BlockBrushEventData(blockPos: bp1, player: p1, item: "minecraft:brush", cancelled: false)
assert brushData.item == "minecraft:brush"

let cookData = BlockCookEventData(blockPos: bp1, source: "minecraft:cobblestone", resultItem: "minecraft:stone", cancelled: false)
assert cookData.resultItem == "minecraft:stone"

let blockDropItemData = BlockDropItemEventData(blockPos: bp1, hasPlayer: true, player: p1, items: @["minecraft:wheat"], cancelled: false)
assert blockDropItemData.items.len == 1

let blockExpData = BlockExpEventData(blockPos: bp1, exp: 3'i32)
assert blockExpData.exp == 3'i32

let fertilizeData = BlockFertilizeEventData(blockPos: bp1, hasPlayer: false, player: p1, changedPositions: @[bp1, bp2], changedStateIds: @[10'u16, 11'u16], cancelled: false)
assert fertilizeData.changedPositions.len == 2 and fertilizeData.changedStateIds.len == 2

let multiPlaceData = BlockMultiPlaceEventData(player: p1, placedPositions: @[bp1, bp2], placedStateIds: @[1'u16, 2'u16], cancelled: false)
assert multiPlaceData.placedPositions.len == 2

let shearEntityData = BlockShearEntityEventData(blockPos: bp1, targetEntityId: 20'i32, item: "minecraft:shears", cancelled: false)
assert shearEntityData.targetEntityId == 20'i32

let blockSpreadData = BlockSpreadEventData(sourcePos: bp1, targetPos: bp2, newStateId: 5'u16, cancelled: false)
assert blockSpreadData.newStateId == 5'u16

let brewData = BrewEventData(blockPos: bp1, fuelLevel: 20'u8, cancelled: false)
assert brewData.fuelLevel == 20'u8

let brewFuelData = BrewingStandFuelEventData(blockPos: bp1, fuelPower: 40'u16, cancelled: false)
assert brewFuelData.fuelPower == 40'u16

let brewStartData = BrewingStartEventData(blockPos: bp1, brewingTime: 400'i32, cancelled: false)
assert brewStartData.brewingTime == 400'i32

let campfireData = CampfireStartEventData(blockPos: bp1, item: "minecraft:beef", slot: 0'u8, cookingTime: 600'i32, cancelled: false)
assert campfireData.cookingTime == 600'i32

let cauldronData = CauldronLevelChangeEventData(blockPos: bp1, oldLevel: 1'i32, newLevel: 2'i32, reason: "fill", hasEntityId: true, entityId: 5'i32, cancelled: false)
assert cauldronData.newLevel == 2'i32

let chunkPopData = ChunkPopulateEventData(chunkX: 0'i32, chunkZ: 0'i32, cancelled: false)
assert chunkPopData.chunkX == 0'i32

let chunkSendData = ChunkSendEventData(chunkX: 1'i32, chunkZ: 1'i32, cancelled: false)
assert chunkSendData.chunkZ == 1'i32

let crafterData = CrafterCraftEventData(blockPos: bp1, resultItem: "minecraft:stick", cancelled: false)
assert crafterData.resultItem == "minecraft:stick"

let creeperPowerData = CreeperPowerEventData(entityId: 21'i32, hasLightningId: true, lightningId: 22'i32, cause: "lightning", cancelled: false)
assert creeperPowerData.cause == "lightning"

let enchantData = EnchantItemEventData(player: p1, item: "minecraft:diamond_sword", optionIndex: 0'i32, cost: 5'i32, enchantmentNames: @["minecraft:sharpness"], enchantmentLevels: @[3'i32], cancelled: false)
assert enchantData.enchantmentNames.len == 1

let entitiesLoadData = EntitiesLoadEventData(chunkX: 0'i32, chunkZ: 0'i32, entityCount: 4'u32, cancelled: false)
assert entitiesLoadData.entityCount == 4'u32

let entitiesUnloadData = EntitiesUnloadEventData(chunkX: 0'i32, chunkZ: 0'i32, entityCount: 4'u32, cancelled: false)
assert entitiesUnloadData.entityCount == 4'u32

let blockFormData = EntityBlockFormEventData(entityId: 23'i32, blockPos: bp1, newStateId: 6'u16, cancelled: false)
assert blockFormData.newStateId == 6'u16

let combustByBlockData = EntityCombustByBlockEventData(entityId: 24'i32, combuster: bp1, duration: 5.0'f32, cancelled: false)
assert combustByBlockData.duration == 5.0'f32

let combustByEntityData = EntityCombustByEntityEventData(entityId: 24'i32, combusterId: 25'i32, duration: 5.0'f32, cancelled: false)
assert combustByEntityData.combusterId == 25'i32

let expBottleData = ExpBottleEventData(entityId: 26'i32, experience: 7'i32, location: bp1, showEffect: true, cancelled: false)
assert expBottleData.experience == 7'i32

let fluidLevelData = FluidLevelChangeEventData(blockPos: bp1, newStateId: 8'u16, cancelled: false)
assert fluidLevelData.newStateId == 8'u16

let furnaceBurnData = FurnaceBurnEventData(blockPos: bp1, fuelItem: "minecraft:coal", burnTime: 1600'u32, cancelled: false)
assert furnaceBurnData.burnTime == 1600'u32

let furnaceExtractData = FurnaceExtractEventData(player: p1, blockPos: bp1, itemId: "minecraft:iron_ingot", itemAmount: 3'u32, expGained: 1.5'f32)
assert furnaceExtractData.itemAmount == 3'u32

let furnaceSmeltData = FurnaceSmeltEventData(blockPos: bp1, sourceItem: "minecraft:raw_iron", resultItem: "minecraft:iron_ingot", cancelled: false)
assert furnaceSmeltData.resultItem == "minecraft:iron_ingot"

let furnaceStartSmeltData = FurnaceStartSmeltEventData(blockPos: bp1, sourceItem: "minecraft:raw_iron", cookingTime: 200'u32, cancelled: false)
assert furnaceStartSmeltData.cookingTime == 200'u32

let hangingPlaceData = HangingPlaceEventData(entityId: 27'i32, hasPlayer: true, player: p1, blockPos: bp1, blockFace: "north", cancelled: false)
assert hangingPlaceData.blockFace == "north"

let changeWorldData = PlayerChangeWorldEventData(player: p1, position: Vector3[float64](x: 1.0, y: 2.0, z: 3.0), yaw: 0.0'f32, pitch: 0.0'f32, cancelled: false)
assert changeWorldData.position.x == 1.0

let customPayloadData = PlayerCustomPayloadEventData(player: p1, channel: "minecraft:brand", data: @[1'u8, 2'u8])
assert customPayloadData.data.len == 2

let itemConsumeData = PlayerItemConsumeEventData(player: p1, itemName: "minecraft:apple", cancelled: false)
assert itemConsumeData.itemName == "minecraft:apple"

let itemDamageData = PlayerItemDamageEventData(player: p1, itemName: "minecraft:diamond_pickaxe", damage: 2'i32, cancelled: false)
assert itemDamageData.damage == 2'i32

let asyncChatData = AsyncPlayerChatEventData(player: p1, message: "hi", format: "<player> hi", cancelled: false)
assert asyncChatData.message == "hi"

let asyncPreLoginData = AsyncPlayerPreLoginEventData(playerName: "steve", playerUuid: "uuid", ipAddress: "127.0.0.1", kickMessage: "", cancelled: false)
assert asyncPreLoginData.playerName == "steve"

let preLoginData = PlayerPreLoginEventData(playerName: "steve", playerUuid: "uuid", ipAddress: "127.0.0.1", kickMessage: "", cancelled: false)
assert preLoginData.ipAddress == "127.0.0.1"

let advancementDoneData = PlayerAdvancementDoneEventData(player: p1, advancementId: "minecraft:story/mine_stone", cancelled: false)
assert advancementDoneData.advancementId == "minecraft:story/mine_stone"

let animationData = PlayerAnimationEventData(player: p1, animationType: "swing_main_arm", cancelled: false)
assert animationData.animationType == "swing_main_arm"

let armorStandData = PlayerArmorStandManipulateEventData(player: p1, armorStandId: 30'i32, slot: 5'u8, cancelled: false)
assert armorStandData.slot == 5'u8

let bucketEntityData = PlayerBucketEntityEventData(player: p1, entityId: 31'i32, bucketItem: "minecraft:water_bucket", cancelled: false)
assert bucketEntityData.entityId == 31'i32

let changedWorldData = PlayerChangedWorldEventData(player: p1, cancelled: false)
assert changedWorldData.cancelled == false

let channelData = PlayerChannelEventData(player: p1, channel: "minecraft:brand", cancelled: false)
assert channelData.channel == "minecraft:brand"

let cmdPreprocessData = PlayerCommandPreprocessEventData(player: p1, command: "/gamemode creative", cancelled: false)
assert cmdPreprocessData.command == "/gamemode creative"

let editBookData = PlayerEditBookEventData(player: p1, slot: 0'u32, pages: @["page 1"], hasTitle: true, title: "My Book", signing: false, cancelled: false)
assert editBookData.pages.len == 1

let elytraBoostData = PlayerElytraBoostEventData(player: p1, fireworkId: 32'i32, cancelled: false)
assert elytraBoostData.fireworkId == 32'i32

let expCooldownData = PlayerExpCooldownChangeEventData(player: p1, newCooldown: 40'i32, cancelled: false)
assert expCooldownData.newCooldown == 40'i32

let harvestBlockData = PlayerHarvestBlockEventData(player: p1, blockPos: bp1, harvestedItems: @["minecraft:wheat"], cancelled: false)
assert harvestBlockData.harvestedItems.len == 1

let hideEntityData = PlayerHideEntityEventData(player: p1, entityId: 33'i32, cancelled: false)
assert hideEntityData.entityId == 33'i32

let itemBreakData = PlayerItemBreakEventData(player: p1, itemName: "minecraft:wooden_pickaxe")
assert itemBreakData.itemName == "minecraft:wooden_pickaxe"

let itemMendData = PlayerItemMendEventData(player: p1, itemName: "minecraft:bow", repairAmount: 5'i32, expConsumed: 2'i32, cancelled: false)
assert itemMendData.repairAmount == 5'i32

let leashEntityData = PlayerLeashEntityEventData(player: p1, entityId: 34'i32, holderId: 1'i32, cancelled: false)
assert leashEntityData.entityId == 34'i32

let levelChangeData = PlayerLevelChangeEventData(player: p1, oldLevel: 4'i32, newLevel: 5'i32)
assert levelChangeData.newLevel == 5'i32

let localeChangeData = PlayerLocaleChangeEventData(player: p1, newLocale: "en_us", cancelled: false)
assert localeChangeData.newLocale == "en_us"

let nameEntityData = PlayerNameEntityEventData(player: p1, entityId: 35'i32, name: "Rex", cancelled: false)
assert nameEntityData.name == "Rex"

let openSignData = PlayerOpenSignEventData(player: p1, blockPos: bp1, isFront: true, cancelled: false)
assert openSignData.isFront == true

let playerPortalData = PlayerPortalEventData(player: p1, fromPos: bp1, hasToPos: false, toPos: bp1, cancelled: false)
assert playerPortalData.hasToPos == false

let riptideData = PlayerRiptideEventData(player: p1, itemName: "minecraft:trident", cancelled: false)
assert riptideData.itemName == "minecraft:trident"

let playerShearEntityData = PlayerShearEntityEventData(player: p1, entityId: 36'i32, hand: 0'u8, cancelled: false)
assert playerShearEntityData.entityId == 36'i32

let showEntityData = PlayerShowEntityEventData(player: p1, entityId: 37'i32, cancelled: false)
assert showEntityData.entityId == 37'i32

let playerSpawnChangeData = PlayerSpawnChangeEventData(player: p1, hasNewSpawn: true, newSpawn: bp1, forced: true, cancelled: false)
assert playerSpawnChangeData.forced == true

let statIncrementData = PlayerStatisticIncrementEventData(player: p1, statisticId: "minecraft:custom:minecraft:jump", amount: 1'i32, cancelled: false)
assert statIncrementData.amount == 1'i32

let swapHandsData = PlayerSwapHandsEventData(player: p1, cancelled: false)
assert swapHandsData.cancelled == false

let takeLecternBookData = PlayerTakeLecternBookEventData(player: p1, blockPos: bp1, book: "minecraft:written_book", cancelled: false)
assert takeLecternBookData.book == "minecraft:written_book"

let areaEffectData = AreaEffectCloudApplyEventData(entityId: 40'i32, affectedEntities: @[41'i32, 42'i32], cancelled: false)
assert areaEffectData.affectedEntities.len == 2

let arrowBodyData = ArrowBodyCountChangeEventData(entityId: 43'i32, oldAmount: 1'u32, newAmount: 2'u32, cancelled: false)
assert arrowBodyData.newAmount == 2'u32

let structGenData = AsyncStructureGenerateEventData(worldName: "overworld", structureName: "village", pos: bp1, cancelled: false)
assert structGenData.structureName == "village"

let structSpawnData = AsyncStructureSpawnEventData(worldName: "overworld", structureName: "village", pos: bp1, cancelled: false)
assert structSpawnData.structureName == "village"

let batSleepData = BatToggleSleepEventData(entityId: 44'i32, isAwake: true, cancelled: false)
assert batSleepData.isAwake == true

let bedrockFormData = BedrockFormResponseEventData(player: p1, formId: 1'u32, hasResponseData: true, responseData: "yes")
assert bedrockFormData.responseData == "yes"

let bellResonateData = BellResonateEventData(blockPos: bp1, cancelled: false)
assert bellResonateData.blockPos == bp1

let blockDamageAbortData = BlockDamageAbortEventData(player: p1, blockPos: bp1, itemInHand: "minecraft:diamond_pickaxe")
assert blockDamageAbortData.itemInHand == "minecraft:diamond_pickaxe"

let dispenseArmorData = BlockDispenseArmorEventData(blockPos: bp1, targetEntityId: 45'i32, item: "minecraft:iron_helmet", cancelled: false)
assert dispenseArmorData.item == "minecraft:iron_helmet"

let dispenseData = BlockDispenseEventData(blockPos: bp1, itemName: "minecraft:arrow", cancelled: false)
assert dispenseData.itemName == "minecraft:arrow"

let dispenseLootData = BlockDispenseLootEventData(blockPos: bp1, items: @["minecraft:bone", "minecraft:string"], cancelled: false)
assert dispenseLootData.items.len == 2

let receiveGameData = BlockReceiveGameEventData(blockPos: bp1, gameEvent: "minecraft:block_change", hasSourceEntity: true, sourceEntityId: 46'i32, cancelled: false)
assert receiveGameData.hasSourceEntity == true

let dialogClearData = DialogClearEventData(player: p1, cancelled: false)
assert dialogClearData.cancelled == false

let dialogClickData = DialogClickActionEventData(player: p1, id: "confirm", hasPayload: false, payload: @[], cancelled: false)
assert dialogClickData.id == "confirm"

let dialogShowData = DialogShowEventData(player: p1, dialogId: "server_links", cancelled: false)
assert dialogShowData.dialogId == "server_links"

let entityKnockbackData = EntityKnockbackByEntityEventData(entityId: 47'i32, hitById: 48'i32, force: 1.5, x: 0.1, z: 0.2, cancelled: false)
assert entityKnockbackData.hitById == 48'i32

let portalEnterData = EntityPortalEnterEventData(entityId: 49'i32, location: bp1, cancelled: false)
assert portalEnterData.entityId == 49'i32

let portalExitData = EntityPortalExitEventData(entityId: 49'i32, fromPos: bp1, hasToPos: true, toPos: bp1, cancelled: false)
assert portalExitData.hasToPos == true

let targetBlockData = EntityTargetBlockEventData(entityId: 50'i32, blockPos: bp1, cancelled: false)
assert targetBlockData.entityId == 50'i32

let unleashData = EntityUnleashEventData(entityId: 51'i32, reason: "player_unleash", cancelled: false)
assert unleashData.reason == "player_unleash"

let genericGameData = GenericGameEventData(eventId: "minecraft:custom", pos: Vector3[float64](x: 0.0, y: 64.0, z: 0.0), cancelled: false)
assert genericGameData.eventId == "minecraft:custom"

let hopperSearchData = HopperInventorySearchEventData(blockPos: bp1, searchPos: bp1, cancelled: false)
assert hopperSearchData.cancelled == false

let horseJumpData = HorseJumpEventData(entityId: 52'i32, power: 0.8'f32, cancelled: false)
assert horseJumpData.power == 0.8'f32

let invBlockStartData = InventoryBlockStartEventData(blockPos: bp1)
assert invBlockStartData.blockPos == bp1

let invCreativeData = InventoryCreativeEventData(player: p1, slot: 5'i16, itemId: "minecraft:diamond", itemCount: 64'u8, cancelled: false)
assert invCreativeData.itemCount == 64'u8

let invInteractData = InventoryInteractEventData(player: p1, cancelled: false)
assert invInteractData.cancelled == false

let invMoveItemData = InventoryMoveItemEventData(sourcePos: bp1, targetPos: bp1, itemId: "minecraft:coal", itemAmount: 3'u32, cancelled: false)
assert invMoveItemData.itemAmount == 3'u32

let invPickupData = InventoryPickupItemEventData(blockPos: bp1, itemEntityId: 53'i32, itemId: "minecraft:coal", cancelled: false)
assert invPickupData.itemEntityId == 53'i32

let leavesDecayData = LeavesDecayEventData(blockPos: bp1, cancelled: false)
assert leavesDecayData.cancelled == false

let lightningData = LightningStrikeEventData(position: Vector3[float64](x: 0.0, y: 64.0, z: 0.0), isEffect: false, cancelled: false)
assert lightningData.isEffect == false

let lingeringData = LingeringPotionSplashEventData(entityId: 54'i32, location: bp1, potionItem: "minecraft:lingering_potion", cancelled: false)
assert lingeringData.potionItem == "minecraft:lingering_potion"

let lootGenData = LootGenerateEventData(lootTable: "minecraft:chests/village/village_weaponsmith", cancelled: false)
assert lootGenData.lootTable.len > 0

let mapInitData = MapInitializeEventData(mapId: 1'i32)
assert mapInitData.mapId == 1'i32

echo "all eventdata checks passed"
