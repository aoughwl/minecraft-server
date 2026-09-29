## Port of upstream/pumpkin/src/entity/projectile/snowball.rs: the
## simplest concrete `ThrownItemEntity` user, picked to prove
## `projectile.nim`'s shared base composes into a real `EntityBase`.
##
## Not ported: `on_hit`'s entity-collision damage (blaze-only splash
## damage) and particle/status broadcast - both need `World`, which
## doesn't exist beyond `worldstub.nim`'s block-state surface.

import entity
import projectile
import ../../nbt/tag
import ../../util/vector3

const Gravity = 0.03

type
  SnowballEntity* = ref object
    thrown*: ThrownItemEntity

proc newSnowballEntity*(e: Entity): SnowballEntity =
  ## Port of `SnowballEntity::new` (no owner).
  e.velocity = vec3(0.0, 0.1, 0.0)
  SnowballEntity(thrown: newThrownItemEntityNoOwner(e, Gravity))

proc newSnowballEntityShot*(e: Entity, shooter: Entity): SnowballEntity =
  ## Port of `SnowballEntity::new_shot` (thrown by `shooter`).
  let thrown = newThrownItemEntity(e, shooter, Gravity)
  e.velocity = vec3(0.0, 0.1, 0.0)
  SnowballEntity(thrown: thrown)

proc snowballBaseOf*(s: SnowballEntity): EntityBase =
  ## Port of `impl EntityBase for SnowballEntity`.
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = getEntity(s.thrown)),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = nil),
    getPlayerImpl: (proc(): nil Player {.closure.} = nil),
    tickImpl: (proc(caller: EntityBase) {.closure.} =
      # TODO: process_tick's gravity/inertia/block-collision sweep needs
      # World, which doesn't exist yet.
      discard),
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} = discard),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} = discard),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} = false),
  )
