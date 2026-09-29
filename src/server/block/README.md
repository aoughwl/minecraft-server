# block/ (upstream `pumpkin/src/block/`)

## What's here

`blockmisc.nim` — `PathComputationType`, the one type in `mod.rs` with zero
dependency on `World`/`Player`/`Entity`/`Server`. That's it so far.

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
  `BlockBehaviour` trait itself to exist as *something* Nimony can express
  (a manual-vtable ref-object interface, per the `src/inventory/inventory.nim`
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
   `src/server/entity/` (`entity.nim`'s `Entity`/`LivingEntity`/`Player`/
   `EntityBase`, a manual vtable matching this file's own suggested
   `src/inventory/inventory.nim` precedent). `World`/`Server` stubs are
   still not done.
2. ~~Decide `BlockBehaviour`'s Nimony shape~~ — **done**, see
   `blockbehaviour.nim`: a manual-vtable `BlockBehaviour` ref object with
   `{.closure.}`-annotated proc fields, `newBlockBehaviour()` for the
   all-trait-defaults case, plus the two free helper fns
   (`stopVerticalMovementAfterFall`/`bounceEntityAfterFall`) upstream's
   `mod.rs` defines alongside the trait. **Scoped down**: upstream's real
   trait has ~30 methods; only the two (`on_landed_upon`/
   `update_entity_movement_after_fall_on`) the two proof-case blocks below
   actually use are ported. Extending the vtable with more methods as more
   blocks land is mechanical from here.
3. ~~A Nimony equivalent for `#[pumpkin_block(name)]`~~ — **done**:
   `registerBlock(name: string, behaviour: BlockBehaviour)` /
   `lookupBlock(name: string): nil BlockBehaviour`, backed by a
   `Table[string, BlockBehaviour]`. Each block file calls `registerBlock`
   itself at load time in place of macro-generated registration.
4. **Both original proof cases ported and passing `nimony check`**:
   `structure_void.nim` (`impl BlockBehaviour for StructureVoidBlock {}`
   → `newBlockBehaviour()`, since an empty impl just inherits every
   default) and `slime.nim` (overrides both vtable methods: 0.0 fall-damage
   multiplier, bounce instead of stop). `blocktest.nim` registers both,
   looks them up by name, and drives real `Entity`/`EntityBase` instances
   through both vtable methods - `nimony check` passes clean.

   **`nimony c -r blocktest.nim` crashes at runtime** -
   `eraiser.nim(128,3) 'fnType.tagEnum == ParamsTagId' [AssertionDefect]`
   plus a related `lambdalifting.nim(369,3) 'env.s != SymId(0)'`. This is
   the **third independent confirmation** of the same closure-through-
   vtable runtime crash already hit in `src/command/`'s dispatcher and
   `src/server/entity/`'s own test - not a logic bug in this file, a
   Nimony compiler issue affecting every manual-vtable interface in this
   port once its closures actually execute. Filed as feedback.

`registry.rs` (the full ~200+-block wiring table) stays out of scope until
that many concrete blocks actually exist - what's here proves the pattern,
not the whole module.

5. **Wired to the real generated block table** (`src/generated/blockdata.nim`,
   1286 blocks from `assets/blocks.json`, once that landed via
   `src/data_codegen/gen_block.nim`). `findRealBlock(name)` resolves a
   `minecraft:`-prefixed registration name against real block data
   (name/translationKey/hardness/blastResistance/mapColor/itemId/
   defaultStateId); `registerBlock` now tracks any registration whose
   name doesn't resolve in `unresolvedBlockRegistrations()` (soft
   diagnostic, not a hard failure - a block file might legitimately
   predate the generated table's snapshot). `realdatawiringtest.nim`
   verifies `findRealBlock` against `slime_block`/`structure_void`'s real
   field values (hand-checked against `blockdata.nim` directly) and
   confirms both proof-case blocks resolve cleanly on registration.
   Same runtime-crash caveat as above applies - `nimony check` clean,
   `nimony c -r` not currently possible for anything importing
   `entity.nim` (this file does, transitively, via `blockbehaviour.nim`).
   The item-table equivalent (`src/inventory/itemstub.nim`'s
   `getMaxStackSize`/`getName`, backed by `src/generated/item.nim`'s
   1658 items) has no such dependency and IS runtime-verified - see
   `src/inventory/itemwiringtest.nim`.

6. **Four more concrete blocks ported**, extending the vtable with a third
   method: `tintedglass.nim` (`impl BlockBehaviour for TintedGlassBlock {}`,
   another empty impl like `structure_void.nim`), `hay.nim` (overrides
   `on_landed_upon` with a 0.2 fall-damage multiplier), `mud.nim`/
   `soulsand.nim` (both override the new `is_pathfindable` method to
   unconditionally return false). `is_pathfindable`'s trait DEFAULT body
   (`defaultIsPathfindable` in `blockbehaviour.nim`) is a simplified
   stand-in for upstream's real one - which branches on
   `state.is_waterlogged()`/`Fluid::from_state_id(...)` for `Water` and
   `state.is_full_cube()` for `Land`/`Air`, none of which exist yet (no
   `BlockState`/`Fluid`/tag registry) - documented in-file; every block
   that needs real pathfinding behavior overrides it directly rather than
   relying on the approximation, same as `mud`/`soul_sand` do here.
   `blocktest.nim` extended to register and exercise all four. Looked at
   `logs.rs`/`glazed_terracotta.rs` as further candidates - both need a
   `BlockStateId`/block-property-permutation system (`on_place` returning
   a computed state id) that doesn't exist yet, genuinely blocked, not
   attempted. Same runtime-crash caveat as above (`nimony check` clean,
   `nimony c -r` not yet possible - anything here imports `entity.nim`).

7. **Two more concrete blocks, one new vtable method.** `honey.nim` (`impl
   BlockBehaviour for HoneyBlock` - overrides all three existing methods:
   0.2 fall-damage multiplier via the already-scoped `handleFallDamage`
   placeholder, `stopVerticalMovementAfterFall`, and `isPathfindable`
   hardcoded false). `fletching_table.nim` needed a genuinely new method -
   `normal_use` - added as `BlockBehaviour.normalUseImpl: proc(): BlockActionResult
   {.closure.}` (scoped to the no-argument case; upstream's real
   `NormalUseArgs<'_>` bundles `&World`/`&Player`/etc. that don't exist
   yet, but `fletching_table.rs`'s override ignores all its args and just
   returns `Pass`, so the no-arg scope covers this real caller exactly).
   `BlockActionResult` itself already existed in `src/server/item/
   itembehaviour.nim` (used by `ItemBehaviour.useOnBlock`) - imported and
   reused rather than redefined. Checked every other file using only
   already-ported methods (`chain.rs`/`end_rod.rs`/`end_portal_frame.rs`)
   and confirmed they all need `on_place`'s state-permutation system too -
   genuinely no more free wins in that category right now.
   `blocktest.nim` extended to register/exercise both. Same
   `nimony check` clean / `nimony c -r` closures-through-vtables-crash
   caveat as every other block file.

8. **`BlockStateId`/property-permutation system built** - the actual
   blocker for `logs.rs`/`chain.rs`/`end_rod.rs`/`end_portal_frame.rs`/
   `glazed_terracotta.rs`. Extended `src/data_codegen/gen_block.nim`'s
   scope: new `gen_blockprops.nim` reads `assets/properties.json` (124
   property definitions, each with a stable `hash_key`) and each block's
   `properties`/`states` fields in `assets/blocks.json`, and computes the
   same mixed-radix per-property multiplier upstream's `block.rs`
   generator does (see `gen_blockprops.nim`'s doc comment for the exact
   algorithm) - real output at `src/generated/blockprops.nim` (1286
   blocks' property lists + multipliers, 124 property defs).
   `src/server/block/blockstateid.nim` builds `resolveStateId(blockName,
   propValues)`/`statePropValues(blockName, stateId)` on top of that -
   given a block + property values, compute the concrete state id, and
   the reverse. Extended `BlockBehaviour`'s vtable with `onPlaceImpl`
   (scoped to the `(direction, waterlogged)` args `chain.rs` needs -
   upstream's real `OnPlaceArgs<'_>` bundles far more, extend as more
   blocks land) and its trait-default body (`args.block.default_state.id`).

   **Proof case**: `chain.nim` (`minecraft:iron_chain`) - a real
   TWO-property block (axis + waterlogged), computing a genuinely
   different state id for each of 6 placement directions × 2 waterlogged
   values. `blockstateidtest.nim` verifies oak_log's single-property case
   (all 3 axis values decode to the exact real state ids 139/140/141,
   default-omitted resolves to the real default 140) AND iron_chain's
   two-property case (bdUp/false → axis=y decodes back correctly,
   bdEast/true → axis=x + waterlogged=true, and the two inputs produce
   different state ids) - actually run via `nimony c -r`. Hits the
   documented closures-through-vtables crash (same signature, confirmed
   again) since it imports `entity.nim` transitively via
   `blockbehaviour.nim` - check-verified, not runtime-proven, same
   caveat as every other file in this directory.

   Not ported (same cut as `gen_block.nim`): the full per-state
   `states[]` array (collision/outline shapes, opacity, luminance) - only
   the id↔property-values mapping. `logs.rs`/`end_rod.rs`/
   `end_portal_frame.rs`/`glazed_terracotta.rs` themselves not yet ported
   as further proof cases (chain.rs alone was the scope of this pass) -
   should now be straightforward given the same pattern.
