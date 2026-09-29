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
