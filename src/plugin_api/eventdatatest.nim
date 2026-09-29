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

echo "all eventdata checks passed"
