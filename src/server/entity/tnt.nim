## Port of upstream/pumpkin/src/entity/tnt.rs: `TNTEntity`, primed TNT.
##
## Ported for real: the NBT save/load (`fuse`/`explosion_power`, with
## the default-power epsilon check and the 0..128 clamp on load) and
## `random_short_fuse`'s pure math. NOT ported: `primed()`'s constructor
## (needs a `World` reference beyond `worldstub.nim`'s current surface,
## plus an ambient RNG - same "no hidden global RNG" stance
## `projectile.nim` already takes), and `tick()` (needs `move_entity`/
## `tick_block_collisions`/synced-data-tracker/`World.explode`, none of
## which exist yet - the entity-physics/collision system this port
## hasn't reached). Documented as TODOs, not faked.

import entity
import ../../nbt/tag
import ../../nbt/nbtbase
import ../../util/legacy_rand

const
  TntDefaultFuse* = 80'u32
  TntDefaultPower* = 4.0'f32

type
  TNTEntity* = ref object
    entity*: Entity
    power*: float32
    fuse*: uint32

proc newTNTEntity*(e: Entity, power: float32, fuse: uint32): TNTEntity =
  TNTEntity(entity: e, power: power, fuse: fuse)

proc randomShortFuse*(fuse: uint32, rng: var LegacyRand): uint32 =
  ## Port of `PrimedTnt.getRandomShortFuse` /
  ## `TNTEntity::random_short_fuse`: `rand::random_range(0..(fuse/4).max(1))
  ## + fuse/8`. Takes an explicit RNG rather than upstream's ambient
  ## `rand::random_range` - same "no hidden global RNG instance exists in
  ## this port yet" stance `projectile.nim`'s `setVelocity` already takes.
  let bound = max(fuse div 4, 1'u32)
  uint32(nextBoundedI32(rng, int32(bound))) + fuse div 8

proc writeCustomNbt(t: TNTEntity, nbt: var NbtCompound) =
  ## Port of `write_custom_nbt`.
  put(nbt, "fuse", NbtTag(kind: ntkShort, shortVal: int16(t.fuse)))
  if abs(t.power - TntDefaultPower) > 1e-6'f32:
    put(nbt, "explosion_power", NbtTag(kind: ntkFloat, floatVal: t.power))

proc readCustomNbt(t: TNTEntity, nbt: NbtCompound) =
  ## Port of `read_custom_nbt`. `get_numeric_short`/`get_numeric_float`
  ## (nbt_ops.nim's ergonomic accessors) aren't ported yet, so this reads
  ## the raw tag directly and applies the same fallback/clamp upstream does.
  let (foundFuse, fuseTag) = get(nbt, "fuse")
  t.fuse = if foundFuse and fuseTag.kind == ntkShort:
    uint32(max(fuseTag.shortVal, 0'i16))
  else:
    TntDefaultFuse
  let (foundPower, powerTag) = get(nbt, "explosion_power")
  let rawPower = if foundPower and powerTag.kind == ntkFloat: powerTag.floatVal else: TntDefaultPower
  t.power = clamp(rawPower, 0.0'f32, 128.0'f32)

proc tntBaseOf*(t: TNTEntity): EntityBase =
  ## Port of `impl EntityBase for TNTEntity`. `tick`/`initDataTracker` are
  ## no-ops here (see file doc comment); the rest is real.
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = t.entity),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = nil),
    getPlayerImpl: (proc(): nil Player {.closure.} = nil),
    tickImpl: (proc(caller: EntityBase) {.closure.} = discard), ## TODO: see file doc comment
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} = writeCustomNbt(t, nbt)),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} = readCustomNbt(t, nbt)),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} = false),
  )

# Constant overrides upstream gives TNTEntity (get_gravity=0.04,
# bedrock_y_offset=0.49) aren't dispatched through EntityBase's vtable in
# this port yet - only the 7 core methods are, same gap noted in
# marker.nim.
