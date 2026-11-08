## Port of upstream/pumpkin/src/block/blocks/honey.rs.

import blockbehaviour
import blockmisc
import ../entity/entity
import ../item/itembehaviour

proc onLandedUpon(entity: EntityBase, fallDistance: float64) =
  let living = getLivingEntity(entity)
  if living != nil:
    handleFallDamage(living, entity, fallDistance, 0.2'f32)

proc updateEntityMovementAfterFallOn(entity: EntityBase) =
  stopVerticalMovementAfterFall(entity)

proc isPathfindable(stateId: uint32, computationType: PathComputationType): bool =
  discard stateId
  discard computationType
  false

proc newHoneyBlock*(): BlockBehaviour =
  BlockBehaviour(
    onLandedUponImpl: (proc(entity: EntityBase, fallDistance: float64) {.closure.} =
      onLandedUpon(entity, fallDistance)),
    updateEntityMovementAfterFallOnImpl: (proc(entity: EntityBase) {.closure.} =
      updateEntityMovementAfterFallOn(entity)),
    isPathfindableImpl: (proc(stateId: uint32, computationType: PathComputationType): bool {.closure.} =
      isPathfindable(stateId, computationType)),
    normalUseImpl: (proc(): BlockActionResult {.closure.} =
      defaultNormalUse()),
  )

proc registerHoney*() =
  registerBlock("minecraft:honey_block", newHoneyBlock())
