# minecraft-server

A Nimony port of [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin), a
from-scratch Minecraft server written in Rust. This project translates
Pumpkin's crates to Nimony, keeping the same module boundaries, so it can
eventually serve as the server counterpart to the Minecraft voxel *client*
protocol code already living in the Jester modpack work
(`aoughwl.mcnet` and friends, under `jester/artifacts/release-src/minecraft/Mods/`).
That existing code is client-only and assumes an external server is
authoritative; this repo is the missing server half.

Upstream source lives at `../pumpkingmc` (cloned separately, not vendored
here) and is the reference for every port.

## Porting order

Smallest/most self-contained crates first, since later crates depend on them:

1. `pumpkin-nbt` (~3.1k LOC) — NBT tag model, (de)serialization. **In progress.**
2. `pumpkin-util` (~15.6k LOC) — **In progress.** Ported so far:
   `math/vertical_surface_type.rs`, `resource_location.rs`, `resource.rs`,
   `identifier.rs`, `difficulty.rs`, `gamemode.rs`, `y_offset.rs` →
   `src/util/*.nim`. `identifier.rs`'s const/compile-time constructors
   (`from_static`, `parse_static`, ...) and all `serde` (de)serialize impls
   across the crate are intentionally skipped for now (see doc comments).
   ~2.5k of ~15.6k LOC covered; `text/mod.rs` (2.2k), `noise/*` (1.7k),
   `random/*` (1.5k), and the `math/` vector/position/provider files remain.
3. `pumpkin-config` (~2.2k LOC)
4. `pumpkin-codecs` / `pumpkin-protocol` (~40k LOC combined)
5. `pumpkin-world`, `pumpkin-inventory`, `pumpkin-command`
6. `pumpkin` (main server crate, ~269k LOC)
7. `pumpkin-data` (~1.5M LOC — almost entirely generated block/item/registry
   tables; port the generator, not the generated output, once the shape of
   everything above is settled)

## Layout

```
src/
  nbt/
    tag.nim        -- NbtTag variant type + core ops (port of tag.rs)
    compound.nim    -- NbtCompound (TODO)
    serializer.nim  -- writer (TODO)
    deserializer.nim -- reader (TODO)
```

Each `.nim` file's doc comment names the upstream `.rs` file it ports from.
