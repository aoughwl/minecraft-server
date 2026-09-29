## Port of upstream/pumpkin/src/entity/projectile/ender_pearl.rs's
## construction and `EntityBase` composition, following `snowball.nim`'s
## precedent for the simplest tractable slice of a `ThrownItemEntity`
## user.
##
## Not ported: `on_hit`'s portal-particle spawn, owner teleport/damage,
## endermite spawn-on-hit chance, and the entity-collision damage path -
## all need `World`/`Server`, real particle/sound registries, and a
## teleport implementation, none of which exist beyond `worldstub.nim`'s
## block-state surface.

import entity
import projectile
import ../../nbt/tag
import ../../util/vector3

const Gravity = 0.03

type
  EnderPearlEntity* = ref object
    thrown*: ThrownItemEntity

proc newEnderPearlEntity*(e: Entity): EnderPearlEntity =
  ## Port of `EnderPearlEntity::new` (no owner).
  e.velocity = vec3(0.0, 0.1, 0.0)
  EnderPearlEntity(thrown: newThrownItemEntityNoOwner(e, Gravity))

proc newEnderPearlEntityShot*(e: Entity, shooter: Entity): EnderPearlEntity =
  ## Port of `EnderPearlEntity::new_shot` (thrown by `shooter`).
  let thrown = newThrownItemEntity(e, shooter, Gravity)
  e.velocity = vec3(0.0, 0.1, 0.0)
  EnderPearlEntity(thrown: thrown)

proc enderPearlBaseOf*(pearl: EnderPearlEntity): EntityBase =
  ## Port of `impl EntityBase for EnderPearlEntity`.
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = getEntity(pearl.thrown)),
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
