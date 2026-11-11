# item/ (pumpkin/src/item)

- `itembehaviour.aowl`: `mod.rs`, `registry.rs`, plus the `Player` methods items call that `entity/player.aowl` does not have yet: cooldowns, `find_arrow`, `consume_arrow`, `damage_item_in_slot`, `drop_item`, `fishing_bobber`.
- `itemsmod.aowl`: `items/mod.rs`, `default_registry`, and `gItemRegistry`.
- `thrown_items.aowl`: egg, ender pearl, snowball, wind charge, potions, firework rocket, fishing rod, arrow, bow, crossbow, trident.
- `tool_items.aowl`: axe, hoe, shovel, honeycomb, sword, mace, dye, ink sacs, `ignite/*`.
- `placing_items.aowl`: armor stand, boat, minecart, end crystal, ender eye, lead, name tag, spawn egg, map, bundle, bucket.
- `sign_items.aowl`: the `apply_to_sign` methods. Separate, since they name `BlockWorld`.
- `potion.aowl`: `potion.rs`.

`trait ItemBehaviour` is a `ref object` of closures; a concrete item derives from it, so `behaviour of HoneyCombItem` is upstream's `as_any().downcast_ref`.

What lives in `src/server/block` and `src/world/generation` is reached through `gItemHooks` in `itembehaviour.aowl`: fire placement, `EndPortal::get_new_portal`, the stronghold search, spawner block entities, and maps. With no hook filled a flint and steel only lights candles and campfires, an eye of ender finds no stronghold, and a map gets id 0.

`itemstest.aowl` drives every item with a real `Player`.
