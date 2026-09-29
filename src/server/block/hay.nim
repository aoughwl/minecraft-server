## Port of upstream/pumpkin/src/block/blocks/hay.rs.
## Overrides `on_landed_upon` to reduce fall damage to a 0.2 multiplier
## (hay bales cushion falls) instead of the trait default's full 1.0.

import blockbehaviour
import ../entity/entity

proc registerHay*() =
  let b = newBlockBehaviour()
  b.onLandedUponImpl = (proc(entity: EntityBase, fallDistance: float64) {.closure.} =
    let living = getLivingEntity(entity)
    if living != nil:
      handleFallDamage(living, entity, fallDistance, 0.2'f32))
  registerBlock("minecraft:hay_block", b)
