# `item/` (upstream/pumpkin/src/item, ~6.9k lines)

## Module map

- `mod.rs` (102 lines) — `ItemMetadata`/`ItemBehaviour` traits. **Ported** → `itembehaviour.aowl`.
- `registry.rs` (187 lines) — `ItemRegistry`, `should_try_block_placement`. **Ported** → `itembehaviour.aowl`.
- `items/mod.rs` (175 lines) — `default_registry()`, a flat list of `manager.register(SomeItem)`
  calls. No `#[pumpkin_item]` macro here (unlike `block/`'s `#[pumpkin_block]`) — items register
  themselves directly, so there was no "macro → explicit table" step needed. **Not ported**: the
  registry-population function itself, since every concrete item it references is unported (see
  below).
- Also ported since: `ink_sac.rs`'s id set (empty `ItemBehaviour`, same shape as shield/arrow -
  real logic is `apply_to_sign`, an inherent method needing a real `BlockEntity`, not ported) →
  `inksac.aowl`; `glowing_ink_sac.rs`, same shape → `glowinginksac.aowl`. Both genuinely runtime-run
  (`itemsbatch2test.aowl`, `aowlmony c -r`), no `entity.aowl` import needed, same bar as shield/arrow.
  `knowledge_book.rs`'s second, unrelated struct `DiscFragmentItem` (empty `ItemBehaviour`, same
  shape) → `discfragment.aowl`, same runtime-run bar. A systematic scan (every `impl ItemBehaviour
  for X` block reduced to just its method-name list) found exactly these 5 as-any-only impls in
  the whole `items/` directory - `KnowledgeBookItem` itself (the other struct sharing that file)
  needs `player.inventory()`, so it's not in this category.
- `potion.rs` (209 lines), `items/*.rs` (52 files, ~6.4k lines) — concrete `ItemBehaviour` impls.
  **Mostly not ported.** Ported so far, as free-standing functions rather than through
  `ItemBehaviour` (see below): `dye.rs`'s `can_mine` → `dye.aowl`; `swords.rs`'s `can_mine` →
  `swords.aowl`; `mace.rs`'s `can_mine` → `mace.aowl`; `shield.rs`'s id set (an empty behaviour
  otherwise) → `shield.aowl`; `arrow.rs`'s id set (also empty) → `arrow.aowl`. `clock.rs` (needs
  `World.playSound`) still checked and confirmed blocked (needs a real clock-animation
  time-of-day/lodestone-compass query, not just `playSound`). `snowball.rs`'s full `normal_use`
  → `snowball.aowl`; `egg.rs`'s full `normal_use` (including `EggEntity.set_item_stack`
  propagation) → `egg.aowl` — both unblocked now that `worldstub.aowl` has `spawnEntity`/
  `playSound` and `entity.aowl`'s `Player` has `position()`/`rotation()`/`heldItem()`/
  `setHeldItem()`/`offHandItem()`/`setStackInHand()`/`decrementUnlessCreative()` (all new this
  pass, following upstream's `PlayerInventory`/`ItemStack` call shape but backed by the minimal
  `mainHandItem`/`offHandItem` fields this port has instead of a full hotbar). `ender_pearl.rs`
  is the same shape again (teleport-on-hit aside, which needs `World.teleport`) - not done this
  pass, a natural next proof case.
  Real `Player.world()` doesn't exist (no per-player world reference yet) - both new procs take
  `world: World` as an explicit parameter instead.
  Verified via `eggsnowballtest.aowl`: real `Player`/`World` state, spot-checked recorded
  sound/spawn events and stack decrement/creative-mode/main-hand-then-off-hand-fallback logic
  against upstream's exact semantics. `aowlmony check` clean; `aowlmony c -r` confirmed (not
  assumed) to hit the closures-through-vtables crash via `entity.aowl` - check-verified, not
  runtime-proven, same as every other file here that touches `Player`.

## What's ported

`itembehaviour.aowl`:
- `Hand` (port of `pumpkin_util::Hand`).
- `BlockActionResult` (port of `block::registry::BlockActionResult` — lives here rather than in
  `src/server/block/` because `ItemBehaviour.useOnBlock` returns it and block/'s module isn't
  wired to export it yet; move it there and re-export once that happens, don't define it twice).
- `ItemBehaviour`: manual-vtable ref object (the house pattern for Rust trait objects — see
  `src/inventory/inventory.aowl`, `src/server/entity/entity.aowl`,
  `src/server/block/blockbehaviour.aowl`). Scoped to the methods that only need `Player`, which
  exists (`normalUse`/`normalUseWithRotation`/`normalUseWithHand`/`onStoppedUsing`/`onSpearJab`/
  `onUseTick`/`getUseDuration`/`canMine`). `useOnBlock`/`useOnEntity` are left out — they need
  `Server`/`Block` (unported) and `Arc<dyn EntityBase>` respectively; add them once `Server`
  exists.
- `newDefaultItemBehaviour()`: builds an instance with every field set to upstream's default
  trait-method body, so a concrete item only overrides what it needs.
- `ItemRegistry`: `register`/`getItemBehaviour`/`onUse`/`onStoppedUsing`/`onSpearJab`/`onUseTick`/
  `getUseDuration`/`canMine`. Backed by `seq[(uint16, nil ItemBehaviour)]` with linear lookup
  (matching the small-map convention already used by `src/nbt/tag.aowl`'s `NbtCompound`) rather
  than `FxHashMap` — fine at the item-type-count scale this operates at.

`aowlmony check`-clean. Not run via `aowlmony c -r`: every concrete item genuinely needs
`Player.inventory` and/or `World` (world/player pickup, sound playback, spawning entities) —
tried `dye.rs` and `egg.rs`, upstream's two smallest-looking candidates, and both need at least
one of those. `Player` (in `src/server/entity/entity.aowl`) doesn't have an `inventory` field or a
`world()` accessor yet, and there's no `World` type in this port at all. This is the same wall
`block/`'s leaf cases and `entity/`'s concrete mobs hit — documented instead of forced.

Also known: closures flowing through a manual vtable crash at runtime (`eraiser.aowl`/
`ParamsTagId`), confirmed independently 4x elsewhere in this port already (full writeup:
`COMPILER-BUGS.md` #1). `ItemBehaviour`'s dispatch is therefore statically checked only,
not runtime-proven, same caveat as those other modules. `swords.aowl`/`mace.aowl`/`dye.aowl` avoid
importing `itembehaviour.aowl` for exactly this reason (a trivial free function stays runtime-
provable as long as it never imports the closure-vtable definitions) but still import
`entity.aowl` for `Player`, so they're check-only too. `shield.aowl`/`arrow.aowl` import neither and
ARE genuinely run (`itemsbatch2test.aowl`, `aowlmony c -r`) - the first item files in this directory
to clear that bar.

## What unblocks the rest

- ~~A `Player.inventory` field/accessor~~ — done (`entity.aowl`'s `Player.inventory: nil
  Inventory`). ~~A minimal `World` type (even a stub with `spawnEntity`/`playSound`/
  `updateBlockEntity` no-ops)~~ — `spawnEntity`/`playSound` now exist on
  `src/server/world/worldstub.aowl`'s `World` as recording stubs (not silent no-ops - see that
  file's doc comments), genuinely runtime-verified via `worldstubtest.aowl`.
- Still missing for `egg.rs`/`ender_pearl.rs`/`snowball.rs`-shaped items ("throw a projectile
  and consume the stack"): a concrete *player* inventory type with a "held item" slot concept
  (`src/inventory/itemstub.aowl`'s `Inventory` interface is generic slot storage, not a player's
  specific main-hand/off-hand/hotbar layout) and `Player.position()`/`Player.rotation()`
  accessors (`Entity` has raw position/rotation fields per `entity.aowl`, but no convenience
  accessor matching upstream's call shape yet). `updateBlockEntity` still not added — no
  concrete caller needs it yet, kept unbuilt per this repo's "don't build ahead of a real
  caller" house style.
- `data` (pumpkin-data, 1.5M generated lines, itself only lightly ported via `src/data_codegen/`)
  owns the real `Item`/`ItemStack` types this port currently stubs in
  `src/inventory/itemstub.aowl` — several items' logic (`spawn_egg.rs`, `dye.rs`'s color lookup)
  needs real item/registry data beyond id+count.
