## `BlockBehaviour`: the per-block-type dispatch interface, plus the
## registration table that stands in for the `#[pumpkin_block(name)]`
## proc-macro (documented unportable in src/macros/README.md - Nimony has
## no derive/attribute macros, so registration becomes an explicit call
## instead of macro-generated wiring).
## Port of upstream/pumpkin/src/block/mod.rs's `BlockBehaviour` trait
## (default-method bodies + the two free helper fns `stop_vertical_
## movement_after_fall`/`bounce_entity_after_fall`) and the two blocks
## under blocks/ that use it: structure_void.rs, slime.rs.
##
## SCOPE: upstream's `BlockBehaviour` has ~30 methods; porting all of them
## needs `World`/`Server`/`Block`/`BlockState`/redstone types that don't
## exist yet. This ports only the two methods the two proof-case blocks
## actually override (`on_landed_upon`, `update_entity_movement_after_
## fall_on`) plus their trait-default bodies, to validate the vtable +
## registration shape end to end. Extending the vtable with more methods
## as more blocks get ported is mechanical from here - the pattern's fixed.

import ../entity/entity
import std/tables

type
  BlockBehaviour* = ref object
    ## Manual-vtable interface, the same pattern as `src/inventory/
    ## inventory.nim`'s `Inventory` and `src/server/entity/entity.nim`'s
    ## `EntityBase`. KNOWN NIMONY COMPILER BUG: a closure (not a bare
    ## lambda) assigned to a ref-object proc-typed field crashes the
    ## compiler unless the field's proc type carries `{.closure.}` -
    ## every field below has it proactively.
    onLandedUponImpl*: proc(entity: EntityBase, fallDistance: float64) {.closure.}
    updateEntityMovementAfterFallOnImpl*: proc(entity: EntityBase) {.closure.}

# --- upstream's two free helper fns (mod.rs) --------------------------------

proc stopVerticalMovementAfterFall*(entity: EntityBase) =
  let e = getEntity(entity)
  e.velocity.y = 0.0

proc bounceEntityAfterFall*(entity: EntityBase, bounceMultiplier: float64) =
  let e = getEntity(entity)
  if e.sneaking:
    e.velocity.y = 0.0
  elif e.velocity.y < 0.0:
    let entityFactor = (if getLivingEntity(entity) != nil: 1.0 else: 0.8)
    e.velocity.y = -e.velocity.y * bounceMultiplier * entityFactor

proc handleFallDamage*(living: LivingEntity, caller: EntityBase, fallDistance: float64, damageMultiplier: float32) =
  ## Placeholder for `LivingEntity::handle_fall_damage` - upstream computes
  ## real fall-damage amounts from distance/armor/effects; this just
  ## proves the call shape (real damage math needs the unported
  ## damage-type/effect registries).
  discard living
  discard caller
  discard fallDistance
  discard damageMultiplier

# --- trait-default bodies (mod.rs's `fn on_landed_upon`/`fn update_entity_ --
# --- movement_after_fall_on` default impls) ---------------------------------

proc defaultOnLandedUpon*(entity: EntityBase, fallDistance: float64) =
  let living = getLivingEntity(entity)
  if living != nil:
    handleFallDamage(living, entity, fallDistance, 1.0)

proc defaultUpdateEntityMovementAfterFallOn*(entity: EntityBase) =
  stopVerticalMovementAfterFall(entity)

proc newBlockBehaviour*(): BlockBehaviour =
  ## A `BlockBehaviour` with every method at its trait-default body -
  ## matches upstream's `impl BlockBehaviour for X {}` (an empty impl
  ## block, which just inherits every default).
  BlockBehaviour(
    onLandedUponImpl: (proc(entity: EntityBase, fallDistance: float64) {.closure.} =
      defaultOnLandedUpon(entity, fallDistance)),
    updateEntityMovementAfterFallOnImpl: (proc(entity: EntityBase) {.closure.} =
      defaultUpdateEntityMovementAfterFallOn(entity)),
  )

proc onLandedUpon*(b: BlockBehaviour, entity: EntityBase, fallDistance: float64) {.inline.} =
  b.onLandedUponImpl(entity, fallDistance)

proc updateEntityMovementAfterFallOn*(b: BlockBehaviour, entity: EntityBase) {.inline.} =
  b.updateEntityMovementAfterFallOnImpl(entity)

# --- registration: replaces `#[pumpkin_block(name)]` ------------------------

var blockRegistry: Table[string, BlockBehaviour] = initTable[string, BlockBehaviour]()

proc registerBlock*(name: string, behaviour: BlockBehaviour) =
  ## Each block file calls this at load time in place of the macro's
  ## registration codegen (upstream's `registry.rs` builds the equivalent
  ## table at compile-derived startup by instantiating every `impl
  ## BlockBehaviour` block - here it's an explicit call per block).
  blockRegistry[name] = behaviour

proc lookupBlock*(name: string): nil BlockBehaviour =
  ## `nil` = not registered, matching `entity.nim`'s established
  ## nilable-ref-for-optional convention (a `(bool, T)` tuple doesn't
  ## coerce a non-nilable ref into a nilable slot cleanly, per that
  ## file's own note).
  if blockRegistry.hasKey(name):
    try:
      let found: BlockBehaviour = blockRegistry[name]
      result = found
    except ErrorCode:
      result = nil
  else:
    result = nil
