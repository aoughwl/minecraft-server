# block/ (upstream `pumpkin/src/block/`)

## What's here

`blockmisc.aowl` — `PathComputationType`, the one type in `mod.rs` with zero
dependency on `World`/`Player`/`Entity`/`Server`. Plus a growing set of
concrete `BlockBehaviour`/direct-proc ports — see the status-update section
below for the current list and how each was unblocked.

## What's NOT here, and why

The upstream module is 275 Rust files, ~47.6k lines:

| Path | Files | What it is |
|---|---|---|
| `mod.rs` | 1 (587 lines) | `BlockBehaviour` trait (dozens of default methods: `normal_use`, `on_entity_collision`, `explode`, `on_synced_block_event`, `get_placement_state`, ...), `BlockMetadata`/`FluidMetadata` traits, a couple of free helper fns |
| `registry.rs` | 1 (1550 lines) | A static registration table: `use`s and instantiates every one of the ~200+ block-behavior structs below into a dispatch map keyed by block id |
| `blocks/` | ~54 top-level + 6 subdirs (`coral/`, `fire/`, `piston/`, `plant/`, `redstone/`, `sculk/`, each with more files) | One `impl BlockBehaviour for XBlock` per block type |
| `entities/` | 54 | Block-entity logic (chests, furnaces, signs, ...) |
| `fluid/` | 6 | Water/lava flow, pathfinding, physics |
| `viewer.rs` | 1 | `ViewerCountTracker`/`ViewerCountListener` traits, `Arc<World>`-bound |

**Tried and confirmed genuinely blocked, not just "looked hard":** picked the
two simplest conceivable candidates to validate the shape before writing
this off -

- `blocks/structure_void.rs` (8 lines) - `impl BlockBehaviour for
  StructureVoidBlock {}`, a completely empty impl. Still needs: the
  `#[pumpkin_block("minecraft:...")]` registration macro (proc-macro,
  documented as unportable in `src/macros/README.md`) and the
  `BlockBehaviour` trait itself to exist as *something* aowlmony can express
  (a manual-vtable ref-object interface, per the `src/inventory/inventory.aowl`
  precedent - but every one of `BlockBehaviour`'s ~20 methods takes an
  `*Args<'_>` struct bundling `&World`/`&Player`/`&dyn EntityBase`/`&Server`
  references, none of which exist here yet even as stub types).
- `blocks/slime.rs` (20 lines) - one real method (`on_landed_upon`), and it
  immediately calls `args.entity.get_living_entity()` - so even the
  "smallest real behavior" needs a working `Entity`/`LivingEntity`
  abstraction, not just a stub struct.

So there is no version of "port a few simple blocks first" that's honest
right now: block 0 already needs the same `Entity`-shape decision flagged
by the main-crate scoping pass (`src/server/README.md`) as the real
prerequisite. `registry.rs` additionally needs ~all 200+ block structs to
exist before it means anything (it's pure wiring, no logic of its own).

## What would unblock this — status update

1. ~~Stub `World`/`Player`/`Server` ref-object types... and decide
   `Entity`'s shape~~ — **`Entity`'s shape is decided**, see
   `src/server/entity/` (`entity.aowl`'s `Entity`/`LivingEntity`/`Player`/
   `EntityBase`, a manual vtable matching this file's own suggested
   `src/inventory/inventory.aowl` precedent). `World`/`Server` stubs are
   still not done.
2. ~~Decide `BlockBehaviour`'s aowlmony shape~~ — **done**, see
   `blockbehaviour.aowl`: a manual-vtable `BlockBehaviour` ref object with
   `{.closure.}`-annotated proc fields, `newBlockBehaviour()` for the
   all-trait-defaults case, plus the two free helper fns
   (`stopVerticalMovementAfterFall`/`bounceEntityAfterFall`) upstream's
   `mod.rs` defines alongside the trait. **Scoped down**: upstream's real
   trait has ~30 methods; only the two (`on_landed_upon`/
   `update_entity_movement_after_fall_on`) the two proof-case blocks below
   actually use are ported. Extending the vtable with more methods as more
   blocks land is mechanical from here.
3. ~~A aowlmony equivalent for `#[pumpkin_block(name)]`~~ — **done**:
   `registerBlock(name: string, behaviour: BlockBehaviour)` /
   `lookupBlock(name: string): nil BlockBehaviour`, backed by a
   `Table[string, BlockBehaviour]`. Each block file calls `registerBlock`
   itself at load time in place of macro-generated registration.
4. **Both original proof cases ported and passing `aowlmony check`**:
   `structure_void.aowl` (`impl BlockBehaviour for StructureVoidBlock {}`
   → `newBlockBehaviour()`, since an empty impl just inherits every
   default) and `slime.aowl` (overrides both vtable methods: 0.0 fall-damage
   multiplier, bounce instead of stop). `blocktest.aowl` registers both,
   looks them up by name, and drives real `Entity`/`EntityBase` instances
   through both vtable methods - `aowlmony check` passes clean.

   **`aowlmony c -r blocktest.aowl` crashes at runtime** -
   `eraiser.aowl(128,3) 'fnType.tagEnum == ParamsTagId' [AssertionDefect]`
   plus a related `lambdalifting.aowl(369,3) 'env.s != SymId(0)'`. This is
   the **third independent confirmation** of the same closure-through-
   vtable runtime crash already hit in `src/command/`'s dispatcher and
   `src/server/entity/`'s own test - not a logic bug in this file, a
   aowlmony compiler issue affecting every manual-vtable interface in this
   port once its closures actually execute. Filed as feedback.

`registry.rs` (the full ~200+-block wiring table) stays out of scope until
that many concrete blocks actually exist - what's here proves the pattern,
not the whole module.

5. **Wired to the real generated block table** (`src/generated/blockdata.aowl`,
   1286 blocks from `assets/blocks.json`, once that landed via
   `src/data_codegen/gen_block.aowl`). `findRealBlock(name)` resolves a
   `minecraft:`-prefixed registration name against real block data
   (name/translationKey/hardness/blastResistance/mapColor/itemId/
   defaultStateId); `registerBlock` now tracks any registration whose
   name doesn't resolve in `unresolvedBlockRegistrations()` (soft
   diagnostic, not a hard failure - a block file might legitimately
   predate the generated table's snapshot). `realdatawiringtest.aowl`
   verifies `findRealBlock` against `slime_block`/`structure_void`'s real
   field values (hand-checked against `blockdata.aowl` directly) and
   confirms both proof-case blocks resolve cleanly on registration.
   Same runtime-crash caveat as above applies - `aowlmony check` clean,
   `aowlmony c -r` not currently possible for anything importing
   `entity.aowl` (this file does, transitively, via `blockbehaviour.aowl`).
   The item-table equivalent (`src/inventory/itemstub.aowl`'s
   `getMaxStackSize`/`getName`, backed by `src/generated/item.aowl`'s
   1658 items) has no such dependency and IS runtime-verified - see
   `src/inventory/itemwiringtest.aowl`.

6. **Four more concrete blocks ported**, extending the vtable with a third
   method: `tintedglass.aowl` (`impl BlockBehaviour for TintedGlassBlock {}`,
   another empty impl like `structure_void.aowl`), `hay.aowl` (overrides
   `on_landed_upon` with a 0.2 fall-damage multiplier), `mud.aowl`/
   `soulsand.aowl` (both override the new `is_pathfindable` method to
   unconditionally return false). `is_pathfindable`'s trait DEFAULT body
   (`defaultIsPathfindable` in `blockbehaviour.aowl`) is a simplified
   stand-in for upstream's real one - which branches on
   `state.is_waterlogged()`/`Fluid::from_state_id(...)` for `Water` and
   `state.is_full_cube()` for `Land`/`Air`, none of which exist yet (no
   `BlockState`/`Fluid`/tag registry) - documented in-file; every block
   that needs real pathfinding behavior overrides it directly rather than
   relying on the approximation, same as `mud`/`soul_sand` do here.
   `blocktest.aowl` extended to register and exercise all four. Looked at
   `logs.rs`/`glazed_terracotta.rs` as further candidates - both need a
   `BlockStateId`/block-property-permutation system (`on_place` returning
   a computed state id) that doesn't exist yet, genuinely blocked, not
   attempted. Same runtime-crash caveat as above (`aowlmony check` clean,
   `aowlmony c -r` not yet possible - anything here imports `entity.aowl`).

7. **Two more concrete blocks, one new vtable method.** `honey.aowl` (`impl
   BlockBehaviour for HoneyBlock` - overrides all three existing methods:
   0.2 fall-damage multiplier via the already-scoped `handleFallDamage`
   placeholder, `stopVerticalMovementAfterFall`, and `isPathfindable`
   hardcoded false). `fletching_table.aowl` needed a genuinely new method -
   `normal_use` - added as `BlockBehaviour.normalUseImpl: proc(): BlockActionResult
   {.closure.}` (scoped to the no-argument case; upstream's real
   `NormalUseArgs<'_>` bundles `&World`/`&Player`/etc. that don't exist
   yet, but `fletching_table.rs`'s override ignores all its args and just
   returns `Pass`, so the no-arg scope covers this real caller exactly).
   `BlockActionResult` itself already existed in `src/server/item/
   itembehaviour.aowl` (used by `ItemBehaviour.useOnBlock`) - imported and
   reused rather than redefined. Checked every other file using only
   already-ported methods (`chain.rs`/`end_rod.rs`/`end_portal_frame.rs`)
   and confirmed they all need `on_place`'s state-permutation system too -
   genuinely no more free wins in that category right now.
   `blocktest.aowl` extended to register/exercise both. Same
   `aowlmony check` clean / `aowlmony c -r` closures-through-vtables-crash
   caveat as every other block file.

8. **`BlockStateId`/property-permutation system built** - the actual
   blocker for `logs.rs`/`chain.rs`/`end_rod.rs`/`end_portal_frame.rs`/
   `glazed_terracotta.rs`. Extended `src/data_codegen/gen_block.aowl`'s
   scope: new `gen_blockprops.aowl` reads `assets/properties.json` (124
   property definitions, each with a stable `hash_key`) and each block's
   `properties`/`states` fields in `assets/blocks.json`, and computes the
   same mixed-radix per-property multiplier upstream's `block.rs`
   generator does (see `gen_blockprops.aowl`'s doc comment for the exact
   algorithm) - real output at `src/generated/blockprops.aowl` (1286
   blocks' property lists + multipliers, 124 property defs).
   `src/server/block/blockstateid.aowl` builds `resolveStateId(blockName,
   propValues)`/`statePropValues(blockName, stateId)` on top of that -
   given a block + property values, compute the concrete state id, and
   the reverse. Extended `BlockBehaviour`'s vtable with `onPlaceImpl`
   (scoped to the `(direction, waterlogged)` args `chain.rs` needs -
   upstream's real `OnPlaceArgs<'_>` bundles far more, extend as more
   blocks land) and its trait-default body (`args.block.default_state.id`).

   **Proof case**: `chain.aowl` (`minecraft:iron_chain`) - a real
   TWO-property block (axis + waterlogged), computing a genuinely
   different state id for each of 6 placement directions × 2 waterlogged
   values. `blockstateidtest.aowl` verifies oak_log's single-property case
   (all 3 axis values decode to the exact real state ids 139/140/141,
   default-omitted resolves to the real default 140) AND iron_chain's
   two-property case (bdUp/false → axis=y decodes back correctly,
   bdEast/true → axis=x + waterlogged=true, and the two inputs produce
   different state ids) - actually run via `aowlmony c -r`. Hits the
   documented closures-through-vtables crash (same signature, confirmed
   again) since it imports `entity.aowl` transitively via
   `blockbehaviour.aowl` - check-verified, not runtime-proven, same
   caveat as every other file in this directory.

   Not ported (same cut as `gen_block.aowl`): the full per-state
   `states[]` array (collision/outline shapes, opacity, luminance) - only
   the id↔property-values mapping.

9. **Two more proof cases using `BlockStateId`**: `logs.aowl` (`logs.rs`,
   ported against `oak_log` as a representative member of the
   `minecraft:logs` tag - no tag-membership data exists yet, so this
   registers one member rather than the whole tag; single "axis"
   property, direction→axis mapping) and `glazed_terracotta.aowl`
   (`glazed_terracotta.rs`, ported against `white_glazed_terracotta` as a
   representative of that tag; single "facing" property). The latter
   needed upstream's `get_horizontal_facing()`, which isn't a method on
   this port's `Entity` (only raw `yaw`/`pitch` fields exist) - the
   standard Minecraft yaw-quantization formula is reproduced locally in
   `glazed_terracotta.aowl` rather than added to `entity.aowl` (out of
   scope for a block-only pass). Real logic lives in
   `onPlaceGlazedTerracotta(player)`, callable directly with a player
   reference; the fixed `(direction, waterlogged)` `onPlaceImpl` vtable
   signature has no player slot (scoped to what `chain.rs` needed), so
   its vtable entry falls back to `defaultOnPlace`.

   `logsglazedtest.aowl` verifies both blocks' state-id math for real:
   `oak_log`'s three axis directions decode back to distinct real state
   ids, `white_glazed_terracotta`'s vtable path and a direct nil-player
   call both correctly fall back to the real default state.
   `aowlmony check` passes clean on all four files; `aowlmony c -r` hits the
   same documented closures-through-vtables crash as every other file
   here (confirmed again, exact same signature -
   `eraiser.aowl(128,3)`/`lambdalifting.aowl(369,3)`) - check-verified, not
   runtime-proven.

   `end_rod.rs`/`end_portal_frame.rs` remain unattempted: `end_rod.rs`
   needs `args.world.get_block_state_id` (a real neighbor-block query
   `worldstub.aowl` doesn't expose yet), a step beyond what `chain.rs`/
   `logs.rs`/`glazed_terracotta.rs` needed.

10. **Two more single-property proof cases**: `barrier.aowl` and
    `mangroveroots.aowl` (`barrier.rs`/`mangrove_roots.rs`). Both blocks'
    `on_place` only needs a `waterlogged` bool (`args.replacing.water_source()`,
    no World query), so both fit `onPlaceImpl`'s existing `(direction,
    waterlogged)` signature with `direction` simply ignored - the simplest
    possible case on top of `blockstateid.aowl`, one property instead of
    chain's/logs'/glazed_terracotta's two-or-one-with-direction-mapping.
    `get_state_for_neighbor_update`'s `schedule_fluid_tick` call needs a
    real World and isn't ported. `waterloggedtest.aowl` verifies both
    blocks' dry/wet state ids differ and decode back correctly via
    `statePropValues`, actually run via `aowlmony c -r` for the check pass
    (same closures-through-vtables `aowlmony c -r` runtime caveat as every
    other file here).

    Systematic scan for more of this shape: every `impl BlockBehaviour for
    X` block in `blocks/` reduced to just its method-name list. The only
    other `on_place`-only files are `glazed_terracotta.rs`/`logs.rs`
    (already ported). `spreading_snowy_block.rs`'s `PodzolBlock`/
    `MyceliumBlock` looked promising (`on_place` +
    `get_state_for_neighbor_update` only) but their shared `SnowyBlock`
    helper calls `world.get_block(&position.up())` - a real neighbor-block
    query `worldstub.aowl` doesn't expose, same wall `end_rod.rs` already
    hit. No further free wins in this category right now.

11. **`end_rod.rs`**: the neighbor-block-query wall above is now
    resolved. `worldstub.aowl` gained `getBlockStateAt`/
    `getNeighborBlockState` (bare-coordinate, direction-agnostic
    deliberately - see that file's doc comment for why it doesn't import
    `blockbehaviour.aowl`'s `BlockDirection` directly, to avoid pulling
    `entity.aowl` into every `worldstub` consumer including the currently
    genuinely-runtime-proven `worldstubtest.aowl`). `blockbehaviour.aowl`
    gained `directionOffset(BlockDirection): (dx, dy, dz)` to bridge the
    two. `blockstateid.aowl` gained `isStateOfBlock(blockName, stateId)`
    (is a state id within a block's own contiguous range - upstream's
    `Block::from_state_id(id).eq(args.block)` check).

    `end_rod.aowl` ports the real logic: read the neighbor block in the
    placement direction, and if it's also an end rod facing back at this
    one, align with it; otherwise face opposite the placement direction.
    Not wired through `BlockBehaviour.onPlaceImpl` - that closure's fixed
    `(direction, waterlogged): int` signature has no room for a
    `World`/position and no real block-placement call site exists yet to
    supply one meaningfully. `onPlaceEndRod(world, pos, direction)` is
    exposed directly instead, matching the upstream logic 1:1.

    `endrodtest.aowl` proves both branches for real: no matching neighbor
    → facing = opposite of placement; a real end-rod-facing-back neighbor
    written into `worldstub` → facing = placement direction itself. Also
    proves `getNeighborBlockState`/`getBlockStateAt` directly. `aowlmony
    check` passes clean on all four changed/new files
    (`worldstub.aowl`/`blockbehaviour.aowl`/`blockstateid.aowl`/
    `end_rod.aowl`/`endrodtest.aowl`); `aowlmony c -r` hits the same
    documented closures-through-vtables crash as every other file here
    (`eraiser.aowl(128,3)`/`lambdalifting.aowl(369,3)`, via
    `end_rod.aowl`'s import of `blockbehaviour.aowl` → `entity.aowl`) -
    check-verified, not runtime-proven. `worldstub.aowl`'s own two new
    procs, tested in isolation, stay in the genuinely-runtime-proven
    category (see `worldstubtest.aowl`).

    `spreading_snowy_block.rs` is now also unblocked in principle (same
    neighbor-query need) but wasn't attempted in this pass - a
    reasonable next proof case.

12. **`spreading_snowy_block.rs`**: ported `SnowyBlock`'s `on_place`/
    `get_state_for_neighbor_update` (podzol/mycelium's `snowy` state
    property, resolved from whether the block above is snow) to
    `spreadingsnowy.aowl`, exposed the same way `end_rod.aowl` is - direct
    `snowyOnPlace`/`snowyGetStateForNeighborUpdate` procs taking `World`/
    `BlockPos`, not forced through `onPlaceImpl`'s fixed signature.

    **Not ported**: `SpreadingSnowyBlock`'s `random_tick`/`can_propagate`/
    `can_stay_alive` (needs a real block-tag system, `LightEngine`'s
    light-dampening math, `World.is_loaded`/`get_max_local_raw_brightness`,
    and a random-tick scheduler - none of which exist). The "is this block
    tagged as snow" check upstream does via `tag::Block::MINECRAFT_SNOW` is
    approximated here by exact-name match against `minecraft:snow`/
    `minecraft:snow_block` - documented in-file as a real gap pending a
    tag system, not a faked equivalence.

    `snowytest.aowl` proves the real state-id math for both directions (no
    snow above → `snowy: false`; snow written into `worldstub` above the
    placement position → `snowy: true`; neighbor-update ignores non-`Up`
    directions; neighbor-update flips an existing state to snowy). `aowlmony
    check` passes clean on `spreadingsnowy.aowl`/`snowytest.aowl`; `aowlmony
    c -r` hits the same documented `eraiser.aowl(128,3)` crash as every
    other file here - check-verified, not runtime-proven.
