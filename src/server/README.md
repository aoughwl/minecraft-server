# Main server crate — assessment

Port target for the upstream repo's main server crate (~269k lines, the
largest crate in the workspace: the actual server — entities, players,
world driving, networking, commands, blocks, items, plugins, the tick
loop). This is a map for whoever continues this crate, not a claim that
it's ported.

## What's here so far

- `errorclass.nim` — port of `error.rs`'s `a shared error` trait, as plain
  overloaded procs (`isKick`/`severity`/`clientKickReason`) over
  `InventoryError` and `ReadingError` (both exist in this port already).
  `PlayerDataError`'s two variants aren't added yet since
  `world`'s `data/player_data.rs` isn't ported - add overloads for
  it here once it exists, don't split into a new file.

Everything else in `crash.rs`, `lib.rs`, `main.rs`, `logging.rs`,
`telemetry.rs` is process bootstrap (CLI arg parsing, panic hooks,
tracing-subscriber setup, an actual `main()`) - not meaningfully portable
until there's a real Nimony server binary to bootstrap; revisit last.

## Module sizes (Rust LOC), smallest to largest

| Module | LOC | Notes |
|---|---|---|
| `server/` | 3.4k | Server-wide state: tick-rate manager, scheduler, connection cache, key store (encryption), recipe/seasonal-event registries. `mod.rs` (1.3k) is the actual `Server` struct - the central "everything lives on this" type. High-value, but needs `World`/`Player`/plugin types from elsewhere in this same crate first. |
| `enchantment/` | 1.9k | Enchantment *effects* (30+ small effect types: `add_value`, `explode`, `apply_mob_effect`, ...) plus `helper.rs` (332 LOC). Most individual effect files are tiny (18-110 LOC) and reasonably self-contained aside from needing item/entity/world types. Good next target - lots of small, independent wins. |
| `data/` | 6.2k | Server-side data stores (likely playerdata, structure data, etc. - not inspected file-by-file yet). |
| `item/` | 6.9k | Item behavior (use/interact logic per item kind) - depends on the unported `data` item registry for anything beyond the shape. |
| `world/` | 18.7k | The *runtime* World (distinct from `world`'s storage layer, already partly ported to `src/world/`) - chunk loading orchestration, world ticking, weather, etc. |
| `net/` | 19.5k | Connection handling built on `protocol` (partly ported to `src/protocol/`) - packet dispatch per client state (login/config/play), player connection lifecycle. |
| `command/` | 30.3k | The actual `/gamemode`, `/give`, etc. command implementations, built on `command`'s dispatcher (partly ported to `src/command/` - tokenizer only, dispatcher itself deferred there). |
| `plugin/` | 47.4k | The plugin-host side (event bus, hooks) - overlaps heavily with the WASM-component-model plugin system already found to be out of scope for Nimony right now (`host-bindings`, `plugin-runtime`, `plugin-utils`'s WASM path - see their READMEs). |
| `block/` | 47.6k | Block behavior (per-block-type interaction/physics logic) - same registry dependency as `item/`, at larger scale. |
| `entity/` | 83.6k | The single largest module: `Player`, mobs, entity AI, physics, damage, effects. This is the crate's structural core - almost everything else (`net/`, `command/`, `enchantment/`, `item/`, `block/`) ultimately operates on `Entity`/`Player`. |

## Why this crate wasn't ported wholesale

Three real blockers, not just scale:

1. **`data` (1.5M generated lines) is unported.** Block states,
   item registries, entity type tables, sound/particle IDs - nearly every
   module here reads from it. Until it (or at least its *shape* - a
   registry-lookup interface, even backed by empty/stub tables) exists,
   ports here can only produce data models with placeholder registry
   lookups, the way `src/gametest/model.nim` and `src/inventory/itemstub.nim`
   already do.
2. **No tick-loop/concurrency design decided yet.** Rust's `Server`/`World`/
   `Player` types are `Arc<RwLock<..>>`-shared across tokio tasks; Nimony's
   async model (`passive` procs + continuations, no poll-based Futures) is
   structurally different enough that translating this needs an actual
   design pass, not a mechanical per-file port. `src/scheduler/` and
   `src/plugin_runtime/` both hit this and deferred it explicitly - `server/`
   and `entity/` are where that design actually has to get made, since
   they're the modules that would drive it.
3. **`entity/`'s scale means an ad-hoc partial port would fragment badly.**
   With 83.6k lines built around one central `Entity`/`Player` type
   hierarchy, porting isolated pieces (as this session did successfully for
   smaller, more decomposable crates like `config` or
   `inventory`) risks producing inconsistent partial models that
   all need reconciling later. This module specifically deserves a
   dedicated design pass (what does an `Entity` look like without Rust's
   trait-object component pattern? enum-dispatch? a manual vtable per
   entity kind, as `src/inventory/inventory.nim` did for `Inventory`?)
   before wide porting starts, not file-by-file opportunism.

## Suggested next steps, in order

1. `enchantment/`'s effect files - small, mostly independent, good
   incremental wins once item/entity stand-in types exist (follow
   `src/inventory/itemstub.nim`'s placeholder pattern).
2. Decide `Entity`'s Nimony shape (single design decision, unblocks the
   most LOC).
3. `data`'s *shape* (not its full generated content) - a registry
   interface with a few real entries, so downstream modules stop needing
   placeholder types.
4. `net/` packet dispatch, once `src/protocol/`'s packet layer is further
   along.
