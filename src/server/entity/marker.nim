## Port of upstream/pumpkin/src/entity/marker.rs: `MarkerEntity`, the
## simplest concrete `EntityBase` implementor upstream has - an invisible,
## non-physical entity used to anchor data (structure blocks, some
## datapack machinery). Almost every `EntityBase` override is a plain
## no-op or constant, which makes it the best first proof that
## `entity.nim`'s composition/vtable design supports a real concrete type.

import entity
import ../../nbt/tag

type
  MarkerEntity* = ref object
    entity*: Entity
    data*: NbtCompound

proc newMarkerEntity*(e: Entity): MarkerEntity =
  ## Port of `MarkerEntity::new`. Upstream sets `entity.no_physics = true`;
  ## `Entity` here has no `noPhysics` field yet (not part of the base-field
  ## subset `entity.nim` ported), so that one bit of upstream behavior is a
  ## TODO once that field lands.
  MarkerEntity(entity: e, data: newCompound())

proc markerBaseOf*(m: MarkerEntity): EntityBase =
  ## Port of `impl EntityBase for MarkerEntity`. Every override upstream
  ## gives is a constant/no-op except read/write custom NBT, which is real.
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = m.entity),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = nil),
    getPlayerImpl: (proc(): nil Player {.closure.} = nil),
    tickImpl: (proc(caller: EntityBase) {.closure.} = discard),
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} =
      if m.data.names.len > 0:
        put(nbt, "data", NbtTag(kind: ntkCompound, compoundVal: m.data))),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} =
      let (found, dataTag) = get(nbt, "data")
      if found and dataTag.kind == ntkCompound:
        m.data = dataTag.compoundVal),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} = false),
  )

# Constant overrides upstream gives MarkerEntity (isPushable, canHit, etc.)
# aren't dispatched through EntityBase's vtable in this port yet - that
# needs the wider set of EntityBase methods entity.nim doesn't have (only
# the 7 core ones are ported). Documented here rather than silently
# dropped: isPushable=false, isPushedByFluids=false, canHit=false,
# isImmuneToExplosion=true, initDataTracker=no-op.
