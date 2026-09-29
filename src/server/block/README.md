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

## What would unblock this

In order:
1. ~~Stub `World`/`Player`/`Server` ref-object types... and decide
   `Entity`'s shape~~ — **`Entity`'s shape is decided**, see
   `src/server/entity/` (`entity.nim`'s `Entity`/`LivingEntity`/`Player`/
   `EntityBase`, a manual vtable matching this file's own suggested
   `src/inventory/inventory.nim` precedent). `World`/`Server` stubs are
   still not done - smaller remaining ask.
2. Decide `BlockBehaviour`'s Nimony shape: a manual vtable of `{.closure.}`
   proc fields (watch the known `{.closure.}`-omission compiler crash), each
   taking a plain object arg bundling whatever of the above it needs.
3. A Nimony equivalent for `#[pumpkin_block(name)]` - at minimum, a plain
   `registerBlock(name: string, behaviour: BlockBehaviour)` call each block
   file makes at load time in place of the macro's registration codegen.
4. Then `blocks/structure_void.rs`-style empty impls become genuinely
   five-minute ports, and `registry.rs` becomes a plain lookup table once
   enough blocks exist to populate it.
