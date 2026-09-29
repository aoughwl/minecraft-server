## Core entity model: `Entity`/`LivingEntity`/`Player` and the `EntityBase`
## dispatch interface that composes them.
## Port of upstream/pumpkin/src/entity/mod.rs (the `Entity` struct and
## `EntityBase` trait) and the `LivingEntity`/`Player` composition shape
## from living.rs/player.rs.
##
## DESIGN DECISION (this is the piece two other module-scale ports -
## src/server/block/ and the rest of src/server/entity/ - were blocked on):
##
## Upstream is NOT a classic inheritance hierarchy. `Entity` is one
## concrete struct holding all the base fields; `LivingEntity` wraps an
## `Entity`; `Player` wraps a `LivingEntity`. What looks like polymorphism
## is `dyn EntityBase`, a trait with ~50 default methods that call back
## into a handful of required methods - chiefly `get_entity()`,
## `get_living_entity() -> Option<&LivingEntity>`,
## `get_player() -> Option<&Player>` - and most default methods just
## delegate to whichever of those returns `Some`. It is composition +
## optional downcasting, not deep inheritance, which is exactly the
## `src/inventory/inventory.nim` manual-vtable shape already established in
## this port: a ref-object "interface" whose fields are `{.closure.}` procs,
## built by a per-concrete-type constructor.
##
## `Entity`/`LivingEntity`/`Player` are plain ref objects composed the same
## way upstream composes them. `EntityBase` is the vtable interface.
## `Entity`, `EntityBase`, `LivingEntity`, and `Player` all live in this one
## file because they're mutually referential (EntityBase's vtable fields
## take/return the concrete types; Player/LivingEntity build an EntityBase
## over themselves) - the same reason `src/nbt/tag.nim` keeps `NbtTag` and
## `NbtCompound` together instead of splitting across files.
##
## NOT decided here, deliberately: upstream's fields are almost entirely
## `Atomic*`/`ArcSwap`/`Mutex<T>` for lock-free cross-thread sharing under
## tokio. Blocker #2 in src/server/README.md (no tick-loop/concurrency
## design yet) is still open, so every field here is a plain mutable field,
## not an atomic - single-threaded-shaped for now. Revisit once a
## concurrency model is chosen; the field *shape* (what data exists, what
## type) should carry over even if the mutation discipline around it changes.

import ../../world/tick   # BlockPos stand-in
import ../../util/vector3
import ../../nbt/tag      # NbtCompound
import ../../generated/entity_pose
import ../../util/gamemode
import ../../inventory/inventory
import ../../inventory/itemstub

type
  RemovalReason* = enum
    rrKilled
    rrDiscarded
    rrUnloadedToChunk
    rrUnloadedWithPlayer
    rrChangedDimension

  BoundingBox* = object
    ## Port of pumpkin-util's math/boundingbox.rs `BoundingBox`.
    min*, max*: Vector3[float64]

  EntityDimensions* = object
    ## Port of math/boundingbox.rs `EntityDimensions`.
    width*, height*, eyeHeight*: float32

  DamageType* = object
    ## Placeholder for the generated `data` crate's damage-type registry
    ## (unported - see src/inventory/itemstub.nim for the established
    ## placeholder-type pattern this follows). Real upstream `DamageType`
    ## carries a translation key, exhaustion, message-id family, and
    ## scaling behavior; this just carries enough to identify one.
    id*: string

  EntityKind* = enum
    ## Stands in for upstream's `&'static EntityType` (a generated registry
    ## entry). Just enough to distinguish "this ref is conceptually a
    ## LivingEntity/Player" without needing the full entity-type table.
    ekEntity
    ekLiving
    ekPlayer

  EntityBase* = ref object
    ## Manual-vtable interface standing in for `dyn EntityBase`. Built by
    ## `entityBaseOf`/`livingEntityBaseOf`/`playerBaseOf` below, one per
    ## concrete kind, the way `src/inventory/inventory.nim` builds an
    ## `Inventory` interface per concrete inventory type.
    ##
    ## KNOWN NIMONY COMPILER BUG: assigning a closure (not a bare lambda)
    ## to a ref-object proc-typed field crashes the compiler unless the
    ## field's proc type carries `{.closure.}` - every field below has it
    ## proactively for that reason.
    kind*: EntityKind
    getEntityImpl*: proc(): Entity {.closure.}
    getLivingEntityImpl*: proc(): nil LivingEntity {.closure.}
    getPlayerImpl*: proc(): nil Player {.closure.}
    tickImpl*: proc(caller: EntityBase) {.closure.}
    writeCustomNbtImpl*: proc(nbt: var NbtCompound) {.closure.}
    readCustomNbtImpl*: proc(nbt: NbtCompound) {.closure.}
    damageImpl*: proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.}

  Entity* = ref object
    ## Port of `mod.rs`'s `Entity` struct - base per-entity data every
    ## kind carries. Subset of upstream's fields: the ones with no
    ## dependency on `World`/`Server`/the plugin/networking layers, which
    ## don't exist yet. Extend as those land.
    entityId*: int32
    entityUuid*: string        ## upstream `uuid::Uuid`; no uuid module ported yet
    kind*: EntityKind
    pos*: Vector3[float64]
    lastPos*: Vector3[float64]
    movement*: Vector3[float64]
    blockPos*: BlockPos
    velocity*: Vector3[float64]
    onGround*: bool
    sneaking*, sprinting*, swimming*, invisible*, glowing*: bool
    yaw*, headYaw*, bodyYaw*, pitch*: float32
    pose*: EntityPose
    boundingBox*: BoundingBox
    dimensions*: EntityDimensions
    invulnerable*: bool
    fireTicks*: int32
    age*: int32                ## negative = baby
    removalReason*: (bool, RemovalReason)
    passengers*: seq[EntityBase]
    vehicle*: nil EntityBase
    customData*: NbtCompound

  LivingEntity* = ref object
    ## Port of `living.rs`'s `LivingEntity` - wraps a base `Entity`.
    entity*: Entity
    health*: float32
    maxHealth*: float32
    lastDamageTaken*: float32

  Player* = ref object
    ## Port of `player.rs`'s `Player` (heavily trimmed - the real one is
    ## thousands of lines of inventory/permission/network state, none of
    ## which is ported yet beyond what's here). Wraps a `LivingEntity`.
    livingEntity*: LivingEntity
    gameProfileName*: string   ## stands in for `gameprofile.name`
    gamemode*: GameMode
    inventory*: nil Inventory  ## upstream `player.inventory` (real player
      ## inventory type still unported - see src/inventory/README.md; this
      ## is typed as the base `Inventory` interface so callers that only
      ## need generic inventory ops can use it once a concrete player
      ## inventory exists, same as any other `Inventory` implementor)
    mainHandItem*: ItemStack  ## upstream `PlayerInventory.held_item()`/
      ## `set_held_item()` - a real player inventory has a hotbar with a
      ## selected-slot index, not just one bare main-hand slot; this is a
      ## minimal stand-in (same "held item slot concept" gap the
      ## egg/ender_pearl/snowball items were blocked on) rather than that
      ## full layout, following this port's placeholder-type house style.
    offHandItem*: ItemStack  ## upstream `PlayerInventory.off_hand_item()`

# --- Entity's own behaviour (the `impl Entity` blocks, not the trait) ------

proc newEntity*(entityId: int32, entityUuid: string, dims: EntityDimensions): Entity =
  Entity(
    entityId: entityId,
    entityUuid: entityUuid,
    kind: ekEntity,
    pose: epStanding,
    dimensions: dims,
    removalReason: (false, rrKilled),
    passengers: @[],
    vehicle: nil,
    customData: newCompound(),
  )

proc writeNbt*(e: Entity, nbt: var NbtCompound) =
  ## Port of `Entity::write_nbt`'s base-field subset.
  put(nbt, "OnGround", NbtTag(kind: ntkByte, byteVal: (if e.onGround: 1'i8 else: 0'i8)))
  put(nbt, "Pos", NbtTag(kind: ntkList, listVal: @[
    NbtTag(kind: ntkDouble, doubleVal: e.pos.x),
    NbtTag(kind: ntkDouble, doubleVal: e.pos.y),
    NbtTag(kind: ntkDouble, doubleVal: e.pos.z),
  ]))

proc readNbt*(e: Entity, nbt: NbtCompound) =
  let (foundGround, groundTag) = get(nbt, "OnGround")
  if foundGround and groundTag.kind == ntkByte:
    e.onGround = groundTag.byteVal != 0

proc remove*(e: Entity, reason = rrDiscarded) =
  e.removalReason = (true, reason)

# --- EntityBase construction: one per concrete kind, matching upstream's --
# --- per-type `impl EntityBase for X` blocks -------------------------------

proc entityBaseOf*(e: Entity): EntityBase =
  ## Port of the bottom of upstream's `impl EntityBase for Entity`
  ## (used directly by non-living entities: items, projectiles, markers).
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = e),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = nil),
    getPlayerImpl: (proc(): nil Player {.closure.} = nil),
    tickImpl: (proc(caller: EntityBase) {.closure.} = discard),  ## upstream default is a no-op physics/age tick
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} = discard),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} = discard),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} = false),
  )

proc livingEntityBaseOf*(le: LivingEntity): EntityBase =
  ## Port of `impl EntityBase for LivingEntity`: `get_living_entity`
  ## resolves to `Some(self)`, `tick` dispatches to living-specific tick
  ## (health regen etc. - not yet ported, so a no-op placeholder) instead
  ## of the base `Entity` tick, matching upstream's override shape.
  EntityBase(
    kind: ekLiving,
    getEntityImpl: (proc(): Entity {.closure.} = le.entity),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = le),
    getPlayerImpl: (proc(): nil Player {.closure.} = nil),
    tickImpl: (proc(caller: EntityBase) {.closure.} = discard),  ## TODO: health regen, status effects
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} = discard),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} = discard),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} =
      le.health = max(0.0'f32, le.health - amount)
      le.lastDamageTaken = amount
      true),
  )

proc playerBaseOf*(p: Player): EntityBase =
  ## Port of `impl EntityBase for Player`: `get_player` resolves to
  ## `Some(self)`, so default methods like `get_scoreboard_name` that
  ## check `get_player()` first take the player-name branch instead of
  ## the entity-uuid fallback.
  EntityBase(
    kind: ekPlayer,
    getEntityImpl: (proc(): Entity {.closure.} = p.livingEntity.entity),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = p.livingEntity),
    getPlayerImpl: (proc(): nil Player {.closure.} = p),
    tickImpl: (proc(caller: EntityBase) {.closure.} = discard),  ## TODO: input/network tick
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} = discard),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} = discard),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} =
      p.livingEntity.health = max(0.0'f32, p.livingEntity.health - amount)
      true),
  )

# --- EntityBase's default methods: free procs delegating through the ------
# --- vtable, mirroring the trait's default-method bodies in mod.rs --------

proc getEntity*(eb: EntityBase): Entity {.inline.} =
  eb.getEntityImpl()

proc getLivingEntity*(eb: EntityBase): nil LivingEntity {.inline.} =
  eb.getLivingEntityImpl()

proc getPlayer*(eb: EntityBase): nil Player {.inline.} =
  eb.getPlayerImpl()

proc tick*(eb: EntityBase, caller: EntityBase) =
  ## Port of the trait default: living entities get the living-specific
  ## tick, everything else falls through to the base entity tick. Both
  ## branches currently call the same `tickImpl` - `getLivingEntity`'s
  ## result decides *which* vtable would be consulted once living-vs-base
  ## tick bodies actually diverge (see the TODOs in `livingEntityBaseOf`).
  let living = getLivingEntity(eb)
  if living != nil:
    eb.tickImpl(caller)
  else:
    eb.tickImpl(caller)

proc writeNbt*(eb: EntityBase, nbt: var NbtCompound) =
  writeNbt(getEntity(eb), nbt)
  eb.writeCustomNbtImpl(nbt)

proc readNbt*(eb: EntityBase, nbt: NbtCompound) =
  readNbt(getEntity(eb), nbt)
  eb.readCustomNbtImpl(nbt)

proc damage*(eb: EntityBase, caller: EntityBase, amount: float32, dtype: DamageType): bool =
  eb.damageImpl(caller, amount, dtype)

proc getScoreboardName*(eb: EntityBase): string =
  ## Port of the trait default: players are tracked by profile name,
  ## everything else by UUID.
  let player = getPlayer(eb)
  if player != nil:
    player.gameProfileName
  else:
    getEntity(eb).entityUuid

# --- Player convenience accessors (upstream `player.rs`'s call shape) ------

proc position*(p: Player): Vector3[float64] {.inline.} =
  ## Port of `Player::position()`.
  p.livingEntity.entity.pos

proc rotation*(p: Player): (float32, float32) {.inline.} =
  ## Port of `Player::rotation()`, returning `(yaw, pitch)`.
  (p.livingEntity.entity.yaw, p.livingEntity.entity.pitch)

proc getEntity*(p: Player): Entity {.inline.} =
  p.livingEntity.entity

proc heldItem*(p: Player): ItemStack {.inline.} =
  ## Port of `PlayerInventory::held_item()`.
  p.mainHandItem

proc setHeldItem*(p: Player, stack: ItemStack) {.inline.} =
  ## Port of `PlayerInventory::set_held_item()`.
  p.mainHandItem = stack

proc offHandItem*(p: Player): ItemStack {.inline.} =
  ## Port of `PlayerInventory::off_hand_item()`.
  p.offHandItem

proc setStackInHand*(p: Player, offHand: bool, stack: ItemStack) =
  ## Port of `PlayerInventory::set_stack_in_hand()`. Takes a plain
  ## `offHand: bool` rather upstream's `pumpkin_util::Hand` - `itembehaviour.nim`
  ## defines its own `Hand` enum but imports this module, so importing it
  ## back here to match upstream's parameter type would be circular.
  if offHand: p.offHandItem = stack
  else: p.mainHandItem = stack

proc decrementUnlessCreative*(s: var ItemStack, mode: GameMode, amount: uint8) =
  ## Port of `ItemStack::decrement_unless_creative` - creative mode is
  ## infinite-supply, so a creative player's stack is never actually spent.
  if mode != Creative:
    decrement(s, amount)
