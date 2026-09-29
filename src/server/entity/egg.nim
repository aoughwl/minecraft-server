## Port of upstream/pumpkin/src/entity/projectile/egg.rs's construction
## and `EntityBase` composition, following `snowball.nim`'s precedent for
## the simplest tractable slice of a `ThrownItemEntity` user.
##
## Not ported: `on_hit`'s chicken-hatch spawn logic, the
## `PlayerEggThrowEvent` plugin hook, and `init_data_tracker`'s synced
## item-stack rendering - all need `World`/`Server`/the plugin manager,
## none of which exist beyond `worldstub.nim`'s block-state surface.

import entity
import projectile
import ../../nbt/tag
import ../../util/vector3
import ../../inventory/itemstub

const Gravity = 0.03
const EggItemId = 1148'u16 ## src/generated/item.nim's "egg" entry

type
  EggEntity* = ref object
    thrown*: ThrownItemEntity
    itemStack*: ItemStack

proc defaultEggStack(): ItemStack =
  ItemStack(item: Item(id: EggItemId), itemCount: 1)

proc newEggEntity*(e: Entity): EggEntity =
  ## Port of `EggEntity::new` (no owner).
  e.velocity = vec3(0.0, 0.1, 0.0)
  EggEntity(
    thrown: newThrownItemEntityNoOwner(e, Gravity),
    itemStack: defaultEggStack(),
  )

proc newEggEntityShot*(e: Entity, shooter: Entity): EggEntity =
  ## Port of `EggEntity::new_shot` (thrown by `shooter`).
  let thrown = newThrownItemEntity(e, shooter, Gravity)
  e.velocity = vec3(0.0, 0.1, 0.0)
  EggEntity(thrown: thrown, itemStack: defaultEggStack())

proc setItemStack*(egg: EggEntity, stack: ItemStack) =
  ## Port of `EggEntity::set_item_stack`.
  egg.itemStack = stack

proc eggBaseOf*(egg: EggEntity): EntityBase =
  ## Port of `impl EntityBase for EggEntity`.
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = getEntity(egg.thrown)),
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
