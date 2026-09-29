# `item/` (upstream/pumpkin/src/item, ~6.9k lines)

## Module map

- `mod.rs` (102 lines) — `ItemMetadata`/`ItemBehaviour` traits. **Ported** → `itembehaviour.nim`.
- `registry.rs` (187 lines) — `ItemRegistry`, `should_try_block_placement`. **Ported** → `itembehaviour.nim`.
- `items/mod.rs` (175 lines) — `default_registry()`, a flat list of `manager.register(SomeItem)`
  calls. No `#[pumpkin_item]` macro here (unlike `block/`'s `#[pumpkin_block]`) — items register
  themselves directly, so there was no "macro → explicit table" step needed. **Not ported**: the
  registry-population function itself, since every concrete item it references is unported (see
  below).
- Also ported since: `ink_sac.rs`'s id set (empty `ItemBehaviour`, same shape as shield/arrow -
  real logic is `apply_to_sign`, an inherent method needing a real `BlockEntity`, not ported) →
  `inksac.nim`; `glowing_ink_sac.rs`, same shape → `glowinginksac.nim`. Both genuinely runtime-run
  (`itemsbatch2test.nim`, `nimony c -r`), no `entity.nim` import needed, same bar as shield/arrow.
- `potion.rs` (209 lines), `items/*.rs` (52 files, ~6.4k lines) — concrete `ItemBehaviour` impls.
  **Mostly not ported.** Ported so far, as free-standing functions rather than through
  `ItemBehaviour` (see below): `dye.rs`'s `can_mine` → `dye.nim`; `swords.rs`'s `can_mine` →
  `swords.nim`; `mace.rs`'s `can_mine` → `mace.nim`; `shield.rs`'s id set (an empty behaviour
  otherwise) → `shield.nim`; `arrow.rs`'s id set (also empty) → `arrow.nim`. `clock.rs` (needs
  `World.playSound`), `egg.rs` (needs `World`/`spawnEntity`) checked and confirmed still blocked.

## What's ported

`itembehaviour.nim`:
- `Hand` (port of `pumpkin_util::Hand`).
- `BlockActionResult` (port of `block::registry::BlockActionResult` — lives here rather than in
  `src/server/block/` because `ItemBehaviour.useOnBlock` returns it and block/'s module isn't
  wired to export it yet; move it there and re-export once that happens, don't define it twice).
- `ItemBehaviour`: manual-vtable ref object (the house pattern for Rust trait objects — see
  `src/inventory/inventory.nim`, `src/server/entity/entity.nim`,
  `src/server/block/blockbehaviour.nim`). Scoped to the methods that only need `Player`, which
  exists (`normalUse`/`normalUseWithRotation`/`normalUseWithHand`/`onStoppedUsing`/`onSpearJab`/
  `onUseTick`/`getUseDuration`/`canMine`). `useOnBlock`/`useOnEntity` are left out — they need
  `Server`/`Block` (unported) and `Arc<dyn EntityBase>` respectively; add them once `Server`
  exists.
- `newDefaultItemBehaviour()`: builds an instance with every field set to upstream's default
  trait-method body, so a concrete item only overrides what it needs.
- `ItemRegistry`: `register`/`getItemBehaviour`/`onUse`/`onStoppedUsing`/`onSpearJab`/`onUseTick`/
  `getUseDuration`/`canMine`. Backed by `seq[(uint16, nil ItemBehaviour)]` with linear lookup
  (matching the small-map convention already used by `src/nbt/tag.nim`'s `NbtCompound`) rather
  than `FxHashMap` — fine at the item-type-count scale this operates at.

`nimony check`-clean. Not run via `nimony c -r`: every concrete item genuinely needs
`Player.inventory` and/or `World` (world/player pickup, sound playback, spawning entities) —
tried `dye.rs` and `egg.rs`, upstream's two smallest-looking candidates, and both need at least
one of those. `Player` (in `src/server/entity/entity.nim`) doesn't have an `inventory` field or a
`world()` accessor yet, and there's no `World` type in this port at all. This is the same wall
`block/`'s leaf cases and `entity/`'s concrete mobs hit — documented instead of forced.

Also known: closures flowing through a manual vtable crash at runtime (`eraiser.nim`/
`ParamsTagId`), confirmed independently 4x elsewhere in this port already (full writeup:
`NIMONY-COMPILER-BUGS.md` #1). `ItemBehaviour`'s dispatch is therefore statically checked only,
not runtime-proven, same caveat as those other modules. `swords.nim`/`mace.nim`/`dye.nim` avoid
importing `itembehaviour.nim` for exactly this reason (a trivial free function stays runtime-
provable as long as it never imports the closure-vtable definitions) but still import
`entity.nim` for `Player`, so they're check-only too. `shield.nim`/`arrow.nim` import neither and
ARE genuinely run (`itemsbatch2test.nim`, `nimony c -r`) - the first item files in this directory
to clear that bar.

## What unblocks the rest

- A `Player.inventory` field/accessor and a minimal `World` type (even a stub with
  `spawnEntity`/`playSound`/`updateBlockEntity` no-ops) would unblock most of the simpler
  concrete items (`egg.rs`, `ender_pearl.rs`, `snowball.rs`, etc. — anything that's "throw a
  projectile and consume the stack").
- `data` (pumpkin-data, 1.5M generated lines, itself only lightly ported via `src/data_codegen/`)
  owns the real `Item`/`ItemStack` types this port currently stubs in
  `src/inventory/itemstub.nim` — several items' logic (`spawn_egg.rs`, `dye.rs`'s color lookup)
  needs real item/registry data beyond id+count.
