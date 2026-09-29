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
