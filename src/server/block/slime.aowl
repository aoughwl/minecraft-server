## Port of upstream/pumpkin/src/block/blocks/slime.rs.
## Overrides two `BlockBehaviour` methods: `on_landed_upon` (fall damage
## with a 0.0 multiplier - slime blocks negate fall damage entirely) and
## `update_entity_movement_after_fall_on` (bounces the entity instead of
## the default's "just stop vertical movement").

import blockbehaviour
import ../entity/entity

proc newSlimeBehaviour(): BlockBehaviour =
  BlockBehaviour(
    onLandedUponImpl: (proc(entity: EntityBase, fallDistance: float64) {.closure.} =
      let living = getLivingEntity(entity)
      if living != nil:
        handleFallDamage(living, entity, fallDistance, 0.0)),
    updateEntityMovementAfterFallOnImpl: (proc(entity: EntityBase) {.closure.} =
      bounceEntityAfterFall(entity, 1.0)),
  )

proc registerSlime*() =
  registerBlock("minecraft:slime_block", newSlimeBehaviour())
