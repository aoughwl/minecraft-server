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
4a. `pumpkin-api-macros` (~152 LOC) — **Not ported; by design, documented
   instead.** This is a Rust proc-macro crate (`#[plugin_method]`,
   `#[plugin_impl]`, `#[with_runtime]`) that runs as compiler codegen, not
   runtime code, so there is no Nimony module for it to become. Its
   semantics (async-plugin-method wrapping, `#[no_mangle]` plugin-ABI
   statics, tokio `block_on` bridging) are written up in
   `src/api_macros/README.md` for whoever builds the plugin host later -
   the honest Nimony replacement is a plain template/generic wrapper called
   by plugin authors plus a small codegen script, not a compiler plugin,
   once `pumpkin`'s plugin-loading side gives it a concrete target.
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
   `pumpkin-protocol`: `codec/var_int.rs` + `codec/var_uint.rs` +
   `codec/var_long.rs`/`var_ulong.rs` → `src/protocol/varint.nim` (`VarInt`,
   `VarUInt`, `VarLong`, `VarULong`), plus `src/protocol/protobase.nim`
   (`ReadingError`/`WritingError`/result types, port of the non-serde-trait
   parts of `ser/mod.rs`). Same Java-plain-LEB128-vs-Bedrock-ZigZag split as
   `src/nbt/serializer.nim`/`deserializer.nim`, verified byte-for-byte
   against `var_int.rs`'s own `#[cfg(test)]` vectors in
   `src/protocol/varinttest.nim` (round-trip across `i32::MIN/-2/-1/0/1/2/
   i32::MAX` for both shapes, boundary values, and both overflow-rejection
   tests). Async `decode_async`/`encode_async` variants (tokio-specific)
   are not ported. Everything else in the crate (~37k LOC: `codec/
   bit_set.rs`/`bitset.rs`/`data_component.rs`/`item_stack_seralizer.rs`/
   `uuid.rs`/etc., `ser/mod.rs`'s serializer/deserializer, `java/`'s and
   `bedrock/`'s several hundred individual packet types, `packet_encoder.rs`/
   `packet_decoder.rs`, `query.rs`) is not yet started - this pass
   prioritized the varint/varlong wire primitives (used by every packet's
   framing) over any specific packet. Did not end up drawing on Jester's
   client-side `aoughwl.mcnet/netwire.nim` etc. beyond confirming the same
   varint shape is the right one to match; worth a closer look by whoever
   ports `packet_encoder.rs`/`packet_decoder.rs` next, since that's where
   Jester's client-side framing code is the more directly relevant
   reference.
8. `pumpkin-plugin-utils` (~710 LOC) — **Done except HTTP.** `models.rs`,
   `updater.rs`, `license.rs` (lease read/write via `std/json`, grace-period
   evaluation), and `lib.rs`'s global-state glue → `src/plugin_utils/*.nim`.
   `init(context)`'s WASM-guest path is skipped (needs unported
   `pumpkin-plugin-api`). `http.rs` is a call-shape stub only: Nimony's
   stdlib has no HTTP client or TLS at all, so `check_license_online`/
   `check_for_updates` compile and return a clear "not implemented" error
   rather than a fake success - needs libcurl/WinHTTP FFI eventually.
9. `pumpkin-host-bindings` (~70 LOC) — **Not portable yet; documented
   instead.** The entire file is one `wasmtime::component::bindgen!`
   macro call over `../pumpkin-plugin-wit/v0.1/*.wit` (~14.2k lines of
   WIT across 60+ files) - there is no hand-written Rust logic to
   translate, and Nimony has no WASM component-model runtime or
   WIT-bindgen equivalent. See `src/host_bindings/README.md` for the full
   explanation and the three real options once the plugin ABI is actually
   being built (wasmtime C API FFI, a custom WIT→Nimony generator, or
   dropping the WASM sandbox model for native-loaded plugins).
10. `pumpkin-world`, `pumpkin-inventory`, `pumpkin-command` (~14.1k LOC) —
    **command: tokenizer layer done.** `errors/command_syntax_error.rs`
    (simplified), `context/string_range.rs`, `string_reader.rs`, and its
    numeric parsing all ported to `src/command/*.nim`, type-checked clean.
    NOT started: the `ArgumentType<S>`/`CommandSource` trait pair
    everything else in the crate is built on (individual argument types,
    the brigadier-style command tree/dispatcher, SNBT parsing) — see
    `src/command/lib.nim`'s doc comment for why that's a design decision
    to make once, not a mechanical per-file port.
11. `pumpkin` (main server crate, ~269k LOC)
12. `pumpkin-data` (~1.5M LOC — almost entirely generated block/item/registry
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
