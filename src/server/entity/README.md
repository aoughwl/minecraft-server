# entity/ — the `Entity`/`EntityBase` design decision

This is the design decision `src/server/README.md` and `src/server/block/README.md`
both flagged as the real prerequisite for wide-porting `entity/` (83.6k
upstream lines) and `block/` (47.6k lines).

## What upstream actually looks like

Not deep inheritance. `Entity` (`entity/mod.rs`, ~840 fields worth of atomics/
locks) is one concrete struct holding all base per-entity state. `LivingEntity`
(`living.rs`) wraps an `Entity`. `Player` (`player.rs`) wraps a `LivingEntity`.
What looks like polymorphism is `dyn EntityBase` (`entity/mod.rs`'s
`EntityBase` trait, ~50 methods, almost all with default bodies): the trait
requires only a handful of real methods - `get_entity()`,
`get_living_entity() -> Option<&LivingEntity>`,
`get_player() -> Option<&Player>` - and every default method just calls
whichever of those resolves to `Some`. It's composition + optional
downcasting, not a class hierarchy.

## The Nimony shape (`entity.nim`)

Same composition, ported directly:

- `Entity`, `LivingEntity`, `Player` are plain `ref object`s, wrapping each
  other exactly like upstream (`LivingEntity.entity: Entity`,
  `Player.livingEntity: LivingEntity`).
- `EntityBase` is a manual-vtable ref object (the `src/inventory/inventory.nim`
  pattern already established in this port for other Rust trait objects):
  `getEntityImpl`/`getLivingEntityImpl`/`getPlayerImpl`/`tickImpl`/
  `writeCustomNbtImpl`/`readCustomNbtImpl`/`damageImpl`, all `{.closure.}`-
  annotated proc fields.
- `entityBaseOf`/`livingEntityBaseOf`/`playerBaseOf` build one `EntityBase`
  per concrete kind - upstream's per-type `impl EntityBase for X` blocks.
- The trait's default methods (`tick`, `writeNbt`, `readNbt`, `damage`,
  `getScoreboardName`, ...) are free procs taking `EntityBase` and
  delegating through the vtable, exactly mirroring the trait-default bodies
  in `mod.rs`.
- `Entity`/`EntityBase`/`LivingEntity`/`Player` all live in one file because
  they're mutually referential - same reason `src/nbt/tag.nim` keeps
  `NbtTag`/`NbtCompound` together instead of splitting.
- `nil T` field/return types are used throughout for the "or None" slots
  (`getLivingEntityImpl(): nil LivingEntity`, `vehicle: nil EntityBase`, ...)
  - a `(bool, T)` tuple was tried first (the convention used elsewhere in
    this port for optional returns) but Nimony's tuple-literal type
    inference doesn't coerce a non-nilable ref into a nilable-ref tuple
    slot; the nilable-ref-directly approach (nil = None) sidesteps that and
    is arguably closer to Rust's `Option<&T>` anyway.

## What's ported vs. placeholder

Ported for real: the composition/dispatch mechanism itself, base position/
rotation/velocity/pose/bounding-box fields (using `src/util/vector3.nim`,
`src/world/tick.nim`'s `BlockPos` stand-in, `src/generated/entity_pose.nim`),
`RemovalReason`, `BoundingBox`/`EntityDimensions` (straight ports of
`pumpkin-util/src/math/boundingbox.rs`), basic NBT save/load hooks via
`src/nbt/`'s complete reader/writer, and `LivingEntity.health`/damage.

Deliberately NOT ported: upstream's fields are almost entirely
`Atomic*`/`ArcSwap`/`Mutex<T>` for lock-free cross-thread sharing under
tokio - blocker #2 in `src/server/README.md` (no tick-loop/concurrency
design yet) is still open, so every field here is a plain mutable field.
The field *shape* should carry over once a concurrency model is chosen;
the mutation discipline around it will need revisiting.

`DamageType` is a one-field placeholder (`id: string`) standing in for the
generated `data` crate's damage-type registry, following
`src/inventory/itemstub.nim`'s established placeholder pattern.

## Verification status: semantically checked, NOT runtime-proven

`entity.nim` and `entitytest.nim` both pass `nimony check` cleanly - zero
errors or warnings. `entitytest.nim` builds a bare `Entity`, a
`LivingEntity`, and a `Player`, wraps each in its own `EntityBase`, and
checks (via a manual `check`/`fail` helper, see below) that
`getEntity`/`getLivingEntity`/`getPlayer`/`getScoreboardName`/`damage`
resolve correctly at every composition level, plus an NBT write/read round
trip through the `EntityBase` interface into a *different* entity instance.

Running the compiled binary (`nimony c -r`) crashes inside Nimony's own
runtime panic machinery: `eraiser.nim(128,3) 'fnType.tagEnum ==
ParamsTagId' [AssertionDefect]`, triggered even with `std/assertions`'
`assert` removed entirely from this file (replaced with a hand-written
`check`/`fail` pair that doesn't go through `std/assertions`' raise path).
This is a **second, independent confirmation** of the same closure/vtable
runtime crash a concurrent fork found porting `src/command/`'s dispatcher
(`cmddispatchtest.nim`'s header documents the same symptom): `nimony
check` passes clean on code that builds and calls through closure-typed
vtable fields, but the compiled binary crashes once those closures actually
execute at runtime - not confined to one file's code, confirmed here on an
entirely separate vtable construction. Filed as feedback; not something
this repo can fix.

**Net effect**: treat `entity.nim`'s design and structure as solid and its
logic as semantically verified by the compiler, but not yet proven correct
by execution. Once the underlying compiler issue is fixed, `entitytest.nim`
should just start passing with no changes needed - it was written to prove
real behavior, not just compile.

## Concrete entities ported on top of this design

Two concrete `EntityBase` implementors, picked as the simplest upstream
has (chosen specifically to prove the design supports real subtypes, not
just the base composition itself):

- `marker.nim` (`MarkerEntity`, port of `marker.rs`) - an invisible,
  non-physical anchor entity. Almost every override upstream gives it is a
  constant/no-op; `writeCustomNbt`/`readCustomNbt` are real (own opaque
  NBT payload storage). Missing: upstream's `no_physics` flag needs an
  `Entity` field this port hasn't added yet.
- `experienceorb.nim` (`ExperienceOrbEntity`, port of `experience_orb.rs`)
  - has one genuinely portable pure function, `roundToOrbSize` (the
  greedy XP-to-orb-size split table), ported and value-verified, plus
  real per-instance state (`amount`, `orbAge`) and a real despawn-at-age
  check in `tick`. Upstream's actual physics/pickup/XP-application logic
  all needs `World`/`Player.experiencePickUpDelay`/`applyMendingFromXp`,
  none of which exist yet - left as documented TODOs, not faked.

A third: `projectile.nim` (`ThrownItemEntity`, port of
`projectile/mod.rs`'s shared base every thrown projectile builds on) plus
`snowball.nim` (`SnowballEntity`, the simplest concrete user of it, port of
`projectile/snowball.rs`). `ThrownItemEntity`'s construction
(spawn-at-owner's-eye-height) and velocity math (`set_velocity`/
`set_velocity_from` - normalize, jitter, scale by power, derive yaw/pitch
from the resulting vector) are ported for real and hand-verified in
`projectiletest.nim` (zero-uncertainty cases reduce to exact closed-form
answers, checked by direct assertion). Upstream draws its jitter from
`rand::random::<f64>()` (Rust's unseeded system RNG, not the
world-seeded generator), so this isn't a determinism-sensitive path the
way `legacy_rand.nim`'s other callers are - `setVelocity`/`setVelocityFrom`
take an explicit `var LegacyRand` parameter instead of a hidden global,
since no ambient RNG instance exists anywhere in this port yet and any
uniform source is faithful to upstream's own non-determinism. Not
ported: `process_tick`'s gravity/inertia/block-collision sweep and
`on_hit`'s entity-collision damage/particle broadcast, both need `World`
beyond what `worldstub.nim` provides.

## Verification: a REFINED finding on the closure/vtable crash

`orbsizetest.nim` runs clean end to end (`nimony c -r`) - it imports
`roundToOrbSize` in isolation with zero import of `entity.nim`, proving
the pure logic is correct.

`concretetest.nim` (which imports `entity.nim`/`marker.nim`/
`experienceorb.nim` and constructs `Entity`/`MarkerEntity`/
`ExperienceOrbEntity` instances, but never calls `markerBaseOf`/
`experienceOrbBaseOf` - the only procs that construct `EntityBase`'s
`{.closure.}` fields) still crashes at `nimony c -r`, before printing
anything. This refines the bug already filed as feedback: the crash is
**not** gated on a closure vtable field actually being called - it's
triggered by *reachable* code that *constructs* one, even if that
construction never executes. That's consistent with the crash living in
closure-lifting/lowering at whole-binary init or link time rather than at
a call site. Worth knowing for whoever eventually debugs
`eraiser.nim`/`ParamsTagId`.

## What this unblocks

`src/server/block/README.md`'s stated blocker #1 (stub `World`/`Player`/
`Entity` types, decide `Entity`'s shape) is now half-done: `Entity`/
`LivingEntity`/`Player`/`EntityBase` exist. Still needed before `block/`'s
simplest cases (`structure_void.rs`, `slime.rs`) become portable:

1. `World`/`Server` stub types (even minimal/empty ones) - not attempted
   here, out of this pass's scope.
2. `BlockBehaviour`'s Nimony shape - same manual-vtable pattern as
   `EntityBase`, bundling whatever of `World`/`Player`/`EntityBase`/`Server`
   each method needs.
3. A `registerBlock(name, behaviour)`-style plain call replacing the
   `#[pumpkin_block(name)]` macro's registration codegen.

(Items 2-3 have since landed - see `src/server/block/blockbehaviour.nim`.
Item 1 landed as `src/server/world/worldstub.nim` - see its own doc comment
for scope. `Player` was also extended with `gamemode: GameMode` and
`inventory: nil Inventory` fields to unblock the item leaf cases
`src/server/item/README.md` found blocked.)

## A THIRD independent confirmation, with a further refinement

`src/server/world/worldstubtest.nim` (imports only `worldstub.nim`, which
does NOT import `entity.nim`) runs clean end-to-end via `nimony c -r` - real
proof the World stub's block-state math is correct, including the
negative-coordinate floor-division case.

`src/server/item/dyetest.nim`, by contrast - which imports `dye.nim`, which
imports `entity.nim` for the `Player` type, but constructs no `EntityBase`
and calls no closure at all - still crashes at `nimony c -r` with the same
`eraiser.nim`/`ParamsTagId` assertion. This sharpens the "reachable, not
executed" finding above even further: the crash isn't gated on *this file*
containing closure-vtable-constructing code being reachable - it's
sufficient for *any transitively imported module* (here, `entity.nim`,
several imports away) to define such code, even when the importing file
itself never touches it. Practically: **nothing that imports `entity.nim`
can currently be runtime-verified via `nimony c -r`, full stop** - not just
code that builds or calls an `EntityBase`. `dyeCanMine` itself is `nimony
check`-clean and correct by inspection (one enum comparison), but is not,
and currently cannot be, runtime-proven.

`projectiletest.nim` (above) hits the identical `eraiser.nim`/`ParamsTagId`
crash at `nimony c -r` - a further confirmation, not a new bug, consistent
with "anything importing entity.nim can't run yet."

## Two more concrete entities, plus real-dimension retrofitting

`egg.nim` (`EggEntity`, port of `projectile/egg.rs`) and `enderpearl.nim`
(`EnderPearlEntity`, port of `projectile/ender_pearl.rs`) - both simple
`ThrownItemEntity` users, same shape as `snowball.nim`. Ported: both
constructors (`new`/`new_shot`) and `EntityBase` composition. `EggEntity`
additionally carries a real `ItemStack` (`src/inventory/itemstub.nim`,
backed by `src/generated/item.nim`'s real 1658-item table) and
`set_item_stack`. Not ported (need `World`/`Server`/the plugin manager,
none of which exist beyond `worldstub.nim`): egg's chicken-hatch spawn
logic and `PlayerEggThrowEvent` plugin hook; ender pearl's portal-particle
spawn, owner teleport/damage, and endermite-spawn-on-hit chance.
`eggpearltest.nim` verifies construction/velocity/item-stack fields the
same way `concretetest.nim`/`projectiletest.nim` do - `nimony check`-clean,
not runtime-proven (same closures-through-vtables blocker).

Also retrofitted `concretetest.nim` (marker/experience-orb) and
`projectiletest.nim` (snowball) to build their test entities' dimensions
from `src/generated/entity_type.nim`'s real per-type table via a small
`realDims(name)` helper, instead of the ad-hoc guesses used before that
table existed (it didn't exist when those tests were first written).
Confirmed marker's real dimensions are exactly 0x0 (the invisible-anchor
shape upstream gives it) - a concrete check now catches that.

## TNTEntity: NBT round-trip real, physics/explosion tick deferred

`tnt.nim` (`TNTEntity`, port of `tnt.rs`, primed TNT) - the NBT
save/load (`write_custom_nbt`/`read_custom_nbt`: `fuse`/
`explosion_power`, with the default-power epsilon check and the 0..128
clamp on load) and `random_short_fuse`'s pure math are ported for real.
Not ported: `primed()`'s constructor (needs `World` beyond
`worldstub.nim`'s surface, plus an ambient RNG - same "no hidden global
RNG" stance `projectile.nim` already takes, so `randomShortFuse` takes
an explicit `var LegacyRand` parameter instead) and `tick()`'s
gravity/collision/synced-data-tracker/`World.explode` logic (needs the
entity-physics/collision system this port hasn't reached yet).

`randomshortfusetest.nim` isolates `randomShortFuse` with NO import of
`entity.nim`/`tnt.nim` (a standalone copy of the one function, matching
`orbsizetest.nim`'s precedent for isolating pure logic from its
`EntityBase`-touching neighbors) - **genuinely runtime-proven** via
`nimony c -r`: 100 draws checked against the expected `[10, 29]` range
for `fuse=80`, plus the `fuse=0` degenerate case. `tnttest.nim`'s NBT
round-trip (constructs a real `TNTEntity`) hits the same documented
closures-through-vtables crash as everything else touching
`entity.nim` - check-verified only.
