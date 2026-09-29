## Per-chunk ring-buffer tick scheduler: `MaxTickDelay` delay buckets, plus
## a queued-set to reject duplicate (position, value) tick requests.
## Port of upstream/world/src/tick/scheduler.rs
##
## Upstream wraps everything in `Mutex<Option<Box<...>>>` + `AtomicUsize`
## because `ChunkTickScheduler` is shared across Tokio tasks. This port has
## no concurrency model decided yet for the server tick loop (see the
## deferred-async notes in src/scheduler/lib.nim), so this is a plain
## single-threaded version - add synchronization at the call site once
## that design exists, rather than guessing at a Nimony threading pattern
## here. `queuedTicks` is a linear-scan seq rather than a hash set (same
## simplification already used for NbtCompound in src/nbt/tag.nim).
## Also specialized to `value: string` rather than upstream's generic `T:
## Hash + Eq` - matches tick.nim's own id-string simplification (no block/
## fluid registry type exists yet to be generic over); genericize once one
## does.

import tick

type
  QueuedKey = object
    position: BlockPos
    value: string

  ChunkTickScheduler* = object
    tickQueue: array[MaxTickDelay, seq[OrderedTick[string]]]
    queuedTicks: seq[QueuedKey]
    offset: int
    hasInner: bool ## Mirrors upstream's `Option<Box<Inner>>`: false means
                    ## "never allocated / gone empty and dropped".

proc newChunkTickScheduler*(): ChunkTickScheduler =
  result = ChunkTickScheduler(offset: 0, hasInner: false)
  for i in 0 ..< MaxTickDelay:
    result.tickQueue[i] = @[]
  result.queuedTicks = @[]

proc findQueued(s: ChunkTickScheduler, position: BlockPos, value: string): int =
  for i, k in s.queuedTicks:
    if k.position.x == position.x and k.position.y == position.y and
       k.position.z == position.z and k.value == value:
      return i
  -1

proc stepTick*(s: var ChunkTickScheduler): seq[OrderedTick[string]] =
  let currentOffset = s.offset mod MaxTickDelay
  s.offset = (currentOffset + 1) mod MaxTickDelay
  if not s.hasInner:
    return @[]

  result = s.tickQueue[currentOffset]
  s.tickQueue[currentOffset] = @[]

  if result.len > 0:
    for nextTick in result:
      let idx = findQueued(s, nextTick.position, nextTick.value)
      if idx >= 0:
        s.queuedTicks.delete(idx)
    if s.queuedTicks.len == 0:
      s.hasInner = false

proc scheduleTick*(s: var ChunkTickScheduler, tick: ScheduledTick[string], subTickOrder: uint64) =
  if not s.hasInner:
    s.hasInner = true
  if findQueued(s, tick.position, tick.value) < 0:
    s.queuedTicks.add(QueuedKey(position: tick.position, value: tick.value))
    let index = (s.offset + int(tick.delay)) mod MaxTickDelay
    s.tickQueue[index].add(OrderedTick[string](
      priority: tick.priority, subTickOrder: subTickOrder,
      position: tick.position, value: tick.value))

proc isScheduled*(s: ChunkTickScheduler, pos: BlockPos, value: string): bool =
  s.hasInner and findQueued(s, pos, value) >= 0

proc clearArea*(s: var ChunkTickScheduler, minPos, maxPos: BlockPos) =
  if not s.hasInner:
    return

  proc contains(position: BlockPos): bool {.closure.} =
    position.x >= minPos.x and position.x < maxPos.x and
    position.y >= minPos.y and position.y < maxPos.y and
    position.z >= minPos.z and position.z < maxPos.z

  for i in 0 ..< MaxTickDelay:
    var kept: seq[OrderedTick[string]] = @[]
    for t in s.tickQueue[i]:
      if not contains(t.position):
        kept.add(t)
    s.tickQueue[i] = kept

  var keptQueued: seq[QueuedKey] = @[]
  for k in s.queuedTicks:
    if not contains(k.position):
      keptQueued.add(k)
  s.queuedTicks = keptQueued

  if s.queuedTicks.len == 0:
    s.hasInner = false

proc hasTicks*(s: ChunkTickScheduler): bool =
  s.hasInner and s.queuedTicks.len > 0

proc toSeq*(s: ChunkTickScheduler): seq[ScheduledTick[string]] =
  result = @[]
  if not s.hasInner:
    return
  for i in 0 ..< MaxTickDelay:
    let index = (s.offset + i) mod MaxTickDelay
    for x in s.tickQueue[index]:
      result.add(ScheduledTick[string](delay: uint8(i), priority: x.priority,
        position: x.position, value: x.value))
