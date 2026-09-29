## Scheduled block/fluid tick entries: priority, ordering, and NBT
## (de)serialization for a chunk's pending-tick lists.
## Port of upstream/world/src/tick/mod.rs

import ../nbt/tag

type
  BlockPos* = object
    ## Local stand-in for `util::math::position::BlockPos`, which
    ## isn't ported yet (src/util/ has no position.nim). Plain x/y/z i32s -
    ## replace with the real type once it exists; the field names/shape
    ## are chosen to match what that port will need.
    x*, y*, z*: int32

proc blockPos*(x, y, z: int32): BlockPos {.inline.} =
  BlockPos(x: x, y: y, z: z)

const MaxTickDelay* = 1 shl 8

type
  TickPriority* = enum
    tpExtremelyHigh = -3
    tpVeryHigh = -2
    tpHigh = -1
    tpNormal = 0
    tpLow = 1
    tpVeryLow = 2
    tpExtremelyLow = 3

proc tickPriorityValues*(): array[7, TickPriority] {.inline.} =
  [tpExtremelyHigh, tpVeryHigh, tpHigh, tpNormal, tpLow, tpVeryLow, tpExtremelyLow]

proc tickPriorityFromInt*(value: int32): (bool, TickPriority) =
  case value
  of -3: (true, tpExtremelyHigh)
  of -2: (true, tpVeryHigh)
  of -1: (true, tpHigh)
  of 0: (true, tpNormal)
  of 1: (true, tpLow)
  of 2: (true, tpVeryLow)
  of 3: (true, tpExtremelyLow)
  else: (false, tpNormal)

type
  ScheduledTick*[T] = object
    delay*: uint8
    priority*: TickPriority
    position*: BlockPos
    value*: T

  OrderedTick*[T] = object
    priority*: TickPriority
    subTickOrder*: uint64
    position*: BlockPos
    value*: T

proc newOrderedTick*[T](position: BlockPos, value: sink T): OrderedTick[T] {.inline.} =
  OrderedTick[T](priority: tpNormal, subTickOrder: 0, position: position, value: value)

proc `==`*[T](a, b: OrderedTick[T]): bool {.inline.} =
  a.priority == b.priority and a.subTickOrder == b.subTickOrder

proc cmp*[T](a, b: OrderedTick[T]): int =
  ## Total order: priority first (enum ordinal order, matching upstream's
  ## derived `Ord` on the `#[repr(i32)]` enum), then insertion-order
  ## tiebreak via `subTickOrder`.
  if ord(a.priority) != ord(b.priority):
    return ord(a.priority) - ord(b.priority)
  if a.subTickOrder < b.subTickOrder: -1
  elif a.subTickOrder > b.subTickOrder: 1
  else: 0

proc `<`*[T](a, b: OrderedTick[T]): bool {.inline.} =
  cmp(a, b) < 0

# --- NBT (de)serialization --------------------------------------------------
#
# Upstream is generic over `T: ToResourceLocation`/`T: FromResourceLocation`
# (a block/fluid registry entry that knows its own id string). Neither trait
# nor a registry type exists in this port yet (they'd live in the unported
# data), so these take/produce the id string directly rather than a
# generic `T` - callers can wrap once a registry type exists.

proc toNbtCompound*(tick: ScheduledTick[string]): NbtCompound =
  result = newCompound()
  put(result, "x", NbtTag(kind: ntkInt, intVal: tick.position.x))
  put(result, "y", NbtTag(kind: ntkInt, intVal: tick.position.y))
  put(result, "z", NbtTag(kind: ntkInt, intVal: tick.position.z))
  put(result, "t", NbtTag(kind: ntkInt, intVal: int32(tick.delay)))
  put(result, "p", NbtTag(kind: ntkInt, intVal: int32(ord(tick.priority))))
  put(result, "i", NbtTag(kind: ntkString, stringVal: tick.value))

proc fromNbtCompound*(nbt: NbtCompound): (bool, ScheduledTick[string]) =
  let empty = ScheduledTick[string](delay: 0, priority: tpNormal,
    position: blockPos(0, 0, 0), value: "")
  let (hasX, xTag) = get(nbt, "x")
  let (hasY, yTag) = get(nbt, "y")
  let (hasZ, zTag) = get(nbt, "z")
  let (hasT, tTag) = get(nbt, "t")
  let (hasP, pTag) = get(nbt, "p")
  let (hasI, iTag) = get(nbt, "i")
  if not (hasX and hasY and hasZ and hasT and hasP and hasI):
    return (false, empty)
  if xTag.kind != ntkInt or yTag.kind != ntkInt or zTag.kind != ntkInt or
     tTag.kind != ntkInt or pTag.kind != ntkInt or iTag.kind != ntkString:
    return (false, empty)
  let (okPrio, priority) = tickPriorityFromInt(pTag.intVal)
  if not okPrio:
    return (false, empty)
  (true, ScheduledTick[string](
    delay: uint8(tTag.intVal),
    priority: priority,
    position: blockPos(xTag.intVal, yTag.intVal, zTag.intVal),
    value: iTag.stringVal,
  ))
