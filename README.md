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
   `identifier.rs`, `difficulty.rs`, `gamemode.rs`, `y_offset.rs`,
   `math/vector2.rs`, `math/vector3.rs` (core - see its doc comment for
   what's skipped), `random/legacy_rand.rs` (the pre-1.13 Java-`Random`-
   compatible LCG; verified byte-for-byte against the Rust file's own unit
   test vectors, including gaussian/triangular/split derivation - see
   `src/util/legacy_randtest.nim`) → `src/util/*.nim`. `identifier.rs`'s
   const/compile-time constructors (`from_static`, `parse_static`, ...) and
   all `serde` (de)serialize impls across the crate are intentionally
   skipped for now (see doc comments). ~4.5k of ~15.6k LOC covered;
   `text/mod.rs` (2.2k), `noise/*` (1.7k, depends on `random/`), the rest of
   `random/*` (`mod.rs`'s `RandomImpl`/`RandomGenerator` trait/enum
   unification, `xoroshiro128.rs`, `worldgen_random.rs`, `gaussian.rs`'s
   trait form), and the remaining `math/` files (`position.rs`,
   `bounds.rs`, `block_box.rs`, `boundingbox.rs`, `int_provider.rs`,
   `float_provider.rs`, `bit_storage.rs`, `atomic_f32.rs`, `pool.rs`,
   `euler_angle.rs`, `experience.rs`, `mod.rs`) remain.
3. `pumpkin-auth` (~587 LOC) — **Mostly blocked.** `jwt/mod.rs`'s claims
   model, error kinds, and base64 decoding are ported to `src/auth/jwt.nim`.
   Its actual JWT signature verification needs NIST P-384 ECDSA, which
   Nimony's stdlib (checked `~/nimony/lib/std/`) does not provide at all —
   no elliptic-curve primitives beyond nothing. `client.rs` (reqwest/rustls
   HTTP client glue) is skipped outright: no Nimony HTTP+TLS client to
   build on. See doc comments in `src/auth/jwt.nim` / `src/auth/client.nim`.
5. `pumpkin-scheduler` (~662 LOC) — **Data model done, driver deferred.**
   `domain.rs`, `error.rs`, and the pure-data parts of `task.rs`/
   `scheduler.rs` (`SchedulerTaskId`, `TaskContext`, `SchedulerConfig`,
   `SchedulerState`, `SchedulerSnapshot`) are ported to `src/scheduler/*.nim`.
   NOT ported: `backend.rs`'s `TaskExecutor` trait, `task.rs`'s
   `TaskFuture`/`TaskWork`/`TaskRequest`/`TaskHandle` (+ its `impl Future`),
   `scheduler.rs`'s `SchedulerService` trait, and all of `global.rs` (326
   LOC, the actual admission/poll driver) — these are `Pin<Box<dyn
   Future>>`/tokio-executor plumbing with no Nimony equivalent (Nimony's
   async is `passive` procs + continuations, not poll-based futures).
   Needs a real design pass once `pumpkin` (the crate that drives the
   server tick loop) clarifies what should drive scheduler turns. See
   `src/scheduler/lib.nim`'s doc comment.
4. `pumpkin-config` (~2.2k LOC) — **Mostly done for plain-data configs.**
   Ported: `lighting.rs`, `fun.rs`, `recipe.rs`, `advancement.rs`,
   `player_data.rs`, `pvp.rs`, `logging.rs`, `whitelist.rs`, `chunk.rs`,
   `world.rs`, `server_links.rs`, `telemetry.rs`, `chat.rs`,
   `resource_pack.rs`, and `networking/{lan_broadcast,compression,proxy,
   packet_limiter,query,rcon}.rs` → `src/config/*.nim` (networking ones
   under `src/config/networking/`). All type-check clean. `Uuid` and
   `SocketAddr` are represented by small local stub types (`whitelist.nim`,
   `networking/netaddr.nim`) since neither is ported anywhere yet. Skipped:
   `op.rs`/`networking/auth.rs` (need `pumpkin_util::PermissionLvl`/
   `ProfileAction`, not yet ported), `networking/{java,bedrock}.rs` and
   `networking/mod.rs`'s `NetworkingConfig` aggregate (depend on java/bedrock
   above), `plugins.rs`, and top-level `lib.rs` (458 LOC — the actual
   config-file load/save/merge driver; needs a design pass, not a
   line-by-line port).
6. `pumpkin-gametest` (~1.9k LOC) — **Small ported slice, rest blocked.**
   `error.rs` → `src/gametest/error.nim` (full port) and `model.rs` →
   `src/gametest/model.nim` (full port, `serde`/`serde_json` skipped;
   `environment: Value` becomes a raw JSON-text `string` placeholder).
   `model.nim` needed `Rotation` from pumpkin-data's `block_rotation.rs`;
   rather than block on all of pumpkin-data, `src/gametest/rotation_stub.nim`
   hand-copies just the 4-way enum + its `then` combinator (see its header
   for the TODO to de-duplicate once pumpkin-data is ported for real).
   NOT ported: `world.rs` (an `#[async_trait]` interface over
   `pumpkin_util::math::position::BlockPos`/`pumpkin_world::world::
   BlockFlags`/`pumpkin_data::BlockStateId`, none of which exist in this
   port yet), and `helper.rs`, `manager.rs` (391 LOC), `runner/*` (459 LOC),
   `structure/placement.rs` (389 LOC), `structure/template.rs` (223 LOC),
   `block_based/test.rs` — all either depend on the above or are
   async-trait/state-machine driven or the tick loop shape mentioned under
   `pumpkin-scheduler` above. See `src/gametest/lib.nim`'s doc comment.
7. `pumpkin-codecs` / `pumpkin-protocol` (~40k LOC combined) — **In
   progress.** `lifecycle.rs`, `number.rs` (JSON interop skipped), and the
   core `DataResult<R>` type from `data_result.rs` (its macro-generated
   `apply2..applyN` applicative family skipped, no Nimony equivalent) →
   `src/codecs/*.nim`. NOT ported: `map_like.rs`, `dynamic_ops.rs`,
   `json_ops.rs`, `codec/*`, `struct_builder.rs`, `list_builder.rs` — a
   generic Codec/DynamicOps framework built on Rust trait objects and GATs
   with no direct Nimony equivalent; deferred until a concrete consumer
   forces the design (e.g. `pumpkin-nbt`'s `nbt_ops.rs`, itself stubbed
   pending this).
8. `pumpkin-plugin-utils` (~710 LOC) — **Done except HTTP.** `models.rs`,
   `updater.rs`, `license.rs` (lease read/write via `std/json`, grace-period
   evaluation), and `lib.rs`'s global-state glue → `src/plugin_utils/*.nim`.
   `init(context)`'s WASM-guest path is skipped (needs unported
   `pumpkin-plugin-api`). `http.rs` is a call-shape stub only: Nimony's
   stdlib has no HTTP client or TLS at all, so `check_license_online`/
   `check_for_updates` compile and return a clear "not implemented" error
   rather than a fake success - needs libcurl/WinHTTP FFI eventually.
9. `pumpkin-world`, `pumpkin-inventory`, `pumpkin-command`
10. `pumpkin` (main server crate, ~269k LOC)
11. `pumpkin-data` (~1.5M LOC — almost entirely generated block/item/registry
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
