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

echo "all eventdata checks passed"
