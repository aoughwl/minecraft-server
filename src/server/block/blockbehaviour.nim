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
import ../item/itembehaviour
import ../../generated/blockdata as realblock
import blockmisc
import blockstateid
import std/tables
import std/strutils

type
  BlockDirection* = enum
    ## Port of `pumpkin_data::BlockDirection` (the 6-way face enum used by
    ## `on_place`'s placement direction). Only the variant NAMES are
    ## needed here - the real type carries id/opposite/axis helpers this
    ## port doesn't need yet.
    bdNorth
    bdSouth
    bdEast
    bdWest
    bdUp
    bdDown

  BlockBehaviour* = ref object
    ## Manual-vtable interface, the same pattern as `src/inventory/
    ## inventory.nim`'s `Inventory` and `src/server/entity/entity.nim`'s
    ## `EntityBase`. KNOWN NIMONY COMPILER BUG: a closure (not a bare
    ## lambda) assigned to a ref-object proc-typed field crashes the
    ## compiler unless the field's proc type carries `{.closure.}` -
    ## every field below has it proactively.
    onLandedUponImpl*: proc(entity: EntityBase, fallDistance: float64) {.closure.}
    updateEntityMovementAfterFallOnImpl*: proc(entity: EntityBase) {.closure.}
    isPathfindableImpl*: proc(stateId: uint32, computationType: PathComputationType): bool {.closure.}
    normalUseImpl*: proc(): BlockActionResult {.closure.}
      ## Port of `mod.rs`'s `normal_use` - upstream's real signature takes a
      ## `NormalUseArgs<'_>` bundling `&World`/`&Player`/`&BlockState`/etc.;
      ## none of those exist as real types here yet, so this is scoped to
      ## the no-argument case every current caller (fletching_table.rs)
      ## actually needs. Extend the signature once a block needs the args.
    onPlaceImpl*: proc(direction: BlockDirection, waterlogged: bool): int {.closure.}
      ## Port of `mod.rs`'s `on_place`. Upstream's real `OnPlaceArgs<'_>`
      ## bundles `&World`/`&Player`/`replacing: &BlockState`/etc.; scoped
      ## here to the two inputs `chain.rs` (the first real state-permuting
      ## caller) actually reads: the placement direction and whether the
      ## replaced block was a water source. Extend once a block needs
      ## more of the real args.

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

proc defaultNormalUse*(): BlockActionResult =
  ## `mod.rs`'s `normal_use` trait default: `BlockActionResult::Pass`.
  barPass

proc defaultOnPlace*(blockName: string): int =
  ## `mod.rs`'s `on_place` trait default: `args.block.default_state.id`.
  let (found, id) = blockstateid.defaultStateId(blockName)
  if found: id else: 0

proc defaultIsPathfindable*(stateId: uint32, computationType: PathComputationType): bool =
  ## Simplified stand-in for mod.rs's real default, which branches on
  ## `state.is_waterlogged()`/`Fluid::from_state_id(...).has_tag(...)` for
  ## `Water` and `state.is_full_cube()` for `Land`/`Air` - none of which
  ## exist yet (no `BlockState`/`Fluid`/tag registry in this port). This
  ## approximates "solid full blocks aren't pathfindable, nothing is a
  ## fluid" until those land; every concrete block below that needs real
  ## pathfinding behavior overrides this directly rather than relying on
  ## the approximation.
  discard stateId
  case computationType
  of pctWater: false
  of pctLand, pctAir: true

proc newBlockBehaviour*(blockName: string = ""): BlockBehaviour =
  ## A `BlockBehaviour` with every method at its trait-default body -
  ## matches upstream's `impl BlockBehaviour for X {}` (an empty impl
  ## block, which just inherits every default). `blockName` is only
  ## needed for `defaultOnPlace`'s real-default-state lookup; blocks that
  ## don't need it (nothing calls `onPlace`) can omit it.
  BlockBehaviour(
    onLandedUponImpl: (proc(entity: EntityBase, fallDistance: float64) {.closure.} =
      defaultOnLandedUpon(entity, fallDistance)),
    updateEntityMovementAfterFallOnImpl: (proc(entity: EntityBase) {.closure.} =
      defaultUpdateEntityMovementAfterFallOn(entity)),
    isPathfindableImpl: (proc(stateId: uint32, computationType: PathComputationType): bool {.closure.} =
      defaultIsPathfindable(stateId, computationType)),
    normalUseImpl: (proc(): BlockActionResult {.closure.} =
      defaultNormalUse()),
    onPlaceImpl: (proc(direction: BlockDirection, waterlogged: bool): int {.closure.} =
      discard direction
      discard waterlogged
      defaultOnPlace(blockName)),
  )

proc onLandedUpon*(b: BlockBehaviour, entity: EntityBase, fallDistance: float64) {.inline.} =
  b.onLandedUponImpl(entity, fallDistance)

proc updateEntityMovementAfterFallOn*(b: BlockBehaviour, entity: EntityBase) {.inline.} =
  b.updateEntityMovementAfterFallOnImpl(entity)

proc isPathfindable*(b: BlockBehaviour, stateId: uint32, computationType: PathComputationType): bool {.inline.} =
  b.isPathfindableImpl(stateId, computationType)

proc normalUse*(b: BlockBehaviour): BlockActionResult {.inline.} =
  b.normalUseImpl()

proc onPlace*(b: BlockBehaviour, direction: BlockDirection, waterlogged: bool): int {.inline.} =
  b.onPlaceImpl(direction, waterlogged)

# --- registration: replaces `#[pumpkin_block(name)]` ------------------------

var blockRegistry: Table[string, BlockBehaviour] = initTable[string, BlockBehaviour]()
var unknownRegistrations: seq[string] = @[]
  ## Block names registered that don't resolve against the real block
  ## table (src/generated/blockdata.nim). Kept as a plain diagnostic list
  ## rather than a hard failure, since a block file's own name might
  ## legitimately predate the generated table's snapshot of blocks.json
  ## (a modded/future block, or a test fixture) - `registerBlock` still
  ## registers it, `unresolvedBlockRegistrations()` exposes the list for
  ## whoever wants to assert on it (e.g. a startup-sanity test).

proc stripMcPrefix(name: string): string {.inline.} =
  ## Block files register with the wire-format "minecraft:" namespace
  ## prefix (matching upstream's registration strings); the generated
  ## table's `name` field is unprefixed.
  if name.startsWith("minecraft:"): name[10 .. ^1] else: name

proc findRealBlock*(name: string): (bool, realblock.Block) =
  let bare = stripMcPrefix(name)
  for b in realblock.AllBlocks:
    if b.name == bare:
      return (true, b)
  (false, realblock.Block())

proc registerBlock*(name: string, behaviour: BlockBehaviour) =
  ## Each block file calls this at load time in place of the macro's
  ## registration codegen (upstream's `registry.rs` builds the equivalent
  ## table at compile-derived startup by instantiating every `impl
  ## BlockBehaviour` block - here it's an explicit call per block).
  let (found, _) = findRealBlock(name)
  if not found:
    unknownRegistrations.add(name)
  blockRegistry[name] = behaviour

proc unresolvedBlockRegistrations*(): seq[string] {.inline.} =
  unknownRegistrations

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
