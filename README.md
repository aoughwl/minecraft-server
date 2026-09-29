# minecraft-server

A Nimony port of an upstream open-source, GPLv3-licensed Minecraft server
implementation written in Rust. This project translates its crates to
Nimony, keeping the same module boundaries, so it can eventually serve as
the server counterpart to the Minecraft voxel *client* protocol code
already living in the Jester modpack work (`aoughwl.mcnet` and friends,
under `jester/artifacts/release-src/minecraft/Mods/`). That existing code
is client-only and assumes an external server is authoritative; this repo
is the missing server half.

This is a derivative work under the GPLv3 - see `LICENSE` and `NOTICE.md`
for the full terms and attribution. A local clone of the upstream source
(not vendored into this repo) is kept as a porting reference; see
`NOTICE.md` for where to find it.

## Porting order

Smallest/most self-contained crates first, since later crates depend on them:

1. `nbt` (~3.1k LOC) — NBT tag model, (de)serialization. **In progress.**
   Gzip-compressed NBT (`nbt_compress.rs` → `src/nbt/nbt_compress.nim`) is
   now wired to the `../compress` library and compiles clean, with a
   round-trip test in `src/nbt/gziptest.nim` - but not proven at runtime
   here: `compress` binds `libz.so.1` by that literal Linux name, which
   doesn't resolve on this Windows dev machine, and a deeper ABI mismatch
   surfaced even after working around the name. Expected to work on the
   project's real Linux deployment target; re-verify there.
2. `util` (~15.6k LOC) — **In progress.** Ported so far:
   `math/vertical_surface_type.rs`, `resource_location.rs`, `resource.rs`,
   `identifier.rs`, `difficulty.rs`, `gamemode.rs`, `y_offset.rs`,
   `math/vector2.rs`, `math/vector3.rs` (core - see its doc comment for
   what's skipped), `random/legacy_rand.rs` (the pre-1.13 Java-`Random`-
   compatible LCG), `random/xoroshiro128.rs` (the modern PRNG),
   `random/worldgen_random.rs` (Java `WorldgenRandom` bit-source wrapper
   over Xoroshiro), `noise/mod.rs` (`Gradient` type + gradient table),
   `math/mod.rs`'s `lerp`/`lerp2`/`lerp3`/`smoothstep` (as
   `src/util/mathlerp.nim` - as concrete float32/float64 overloads, not
   Rust's single generic `lerp<T: Float>`: a `[T: SomeFloat]` Nimony
   generic hits a real compiler bug resolving `-` on `T` inside its own
   body, filed as feedback, worked around with duplication), `noise/perlin.rs`'s
   core `PerlinNoise` point-sampling (`src/util/perlin.nim` - `get`/
   `sample_and_lerp` only; `add_to_volume`'s batched fast path,
   `SmearedPerlinNoise`, `NoiseStack`, and `NormalNoise`'s octave-sum/
   normalization machinery are NOT ported yet, see the file's doc comment)
   → `src/util/*.nim`. legacy_rand/xoroshiro128/worldgen_random are all
   verified byte-for-byte against the Rust files' own unit test vectors
   (worldgen_random's specifically check against real vanilla Minecraft
   chunk/decorator seeds and draws) - see `src/util/legacy_randtest.nim`,
   `xoroshiro128test.nim`, `worldgen_randomtest.nim`. `perlin.nim` has NO
   upstream test vectors to check against (perlin.rs has no `#[cfg(test)]`
   block) - `perlintest.nim` checks permutation-table validity, a
   cross-computed HALF_ROUND_OFF bit-pattern constant, and sampling
   determinism/plausible range, but this is NOT yet verified bit-for-bit
   against vanilla world-gen output; treat it as "probably right, not yet
   proven" until real known-answer vectors are found or derived.
   `identifier.rs`'s
   const/compile-time constructors (`from_static`, `parse_static`, ...) and
   all `serde` (de)serialize impls across the crate are intentionally
   skipped for now (see doc comments). ~6k of ~15.6k LOC covered;
   `text/mod.rs` (2.2k), `noise/simplex.rs` + `volume.rs`
   (1k - simplex noise and the DensityVolume batching type), `mod.rs`'s `RandomImpl`/`RandomGenerator`
   trait/enum unification (a real design decision, deferred - each
   generator is a standalone concrete type for now), `gaussian.rs`'s trait
   form (each generator has its own inlined `nextGaussian` instead), and
   the remaining `math/` files (`position.rs`, `bounds.rs`, `block_box.rs`,
   `boundingbox.rs`, `int_provider.rs`, `float_provider.rs`,
   `bit_storage.rs`, `atomic_f32.rs`, `pool.rs`, `euler_angle.rs`,
   `experience.rs`, `mod.rs`) remain.
3. `auth` (~587 LOC) — **Core JWT verification done.** `jwt/mod.rs`'s
   claims model, error kinds, base64 decoding, `build_public_key_from_b64`,
   `decode_header_get_x5u`, the ES384 self-signed verify path
   (`verify_oidc_token_self_signed`), and player-claims extraction
   (including the MD5-based xuid→UUID derivation) are all ported to
   `src/auth/jwt.nim` and wired to a real P-384 ECDSA implementation - a
   new standalone sibling library at `../jwt` (built specifically to
   unblock this; see its own README for what's implemented and how it's
   verified), pulled in via this repo's `nimony.paths`. Proven end-to-end
   against a real ES384 token in `src/auth/jwttest.nim` (`nimony c -r` it
   to check). Still not ported: the Mojang-root-of-trust chain walk (needs
   a security-critical root-key constant sourced properly, not guessed),
   RS256 (needs RSA, not yet in `../jwt`), and the issuer-checked/JWKS-
   fetching OIDC path (needs both RS256 and an HTTP client). `client.rs`
   → `src/auth/client.nim` is now wired to the `requests` library
   (`../requests`, curl-impersonate-based) via `nimony.paths`, but is
   currently **blocked from compiling**: `requests`'s own `profiles.nim`
   hits a Nimony const-eval limitation unrelated to this port (a `seq`
   literal inside a `const array` of objects) - not fixed here since that
   sibling repo wasn't in scope. See doc comments in `src/auth/jwt.nim` /
   `src/auth/client.nim`.
5. `scheduler` (~662 LOC) — **Data model done, driver deferred.**
   `domain.rs`, `error.rs`, and the pure-data parts of `task.rs`/
   `scheduler.rs` (`SchedulerTaskId`, `TaskContext`, `SchedulerConfig`,
   `SchedulerState`, `SchedulerSnapshot`) are ported to `src/scheduler/*.nim`.
   NOT ported: `backend.rs`'s `TaskExecutor` trait, `task.rs`'s
   `TaskFuture`/`TaskWork`/`TaskRequest`/`TaskHandle` (+ its `impl Future`),
   `scheduler.rs`'s `SchedulerService` trait, and all of `global.rs` (326
   LOC, the actual admission/poll driver) — these are `Pin<Box<dyn
   Future>>`/tokio-executor plumbing with no Nimony equivalent (Nimony's
   async is `passive` procs + continuations, not poll-based futures).
   Needs a real design pass once the main server crate (the crate that drives the
   server tick loop) clarifies what should drive scheduler turns. See
   `src/scheduler/lib.nim`'s doc comment.
4a. `api-macros` (~152 LOC) — **Not ported; by design, documented
   instead.** This is a Rust proc-macro crate (`#[plugin_method]`,
   `#[plugin_impl]`, `#[with_runtime]`) that runs as compiler codegen, not
   runtime code, so there is no Nimony module for it to become. Its
   semantics (async-plugin-method wrapping, `#[no_mangle]` plugin-ABI
   statics, tokio `block_on` bridging) are written up in
   `src/api_macros/README.md` for whoever builds the plugin host later -
   the honest Nimony replacement is a plain template/generic wrapper called
   by plugin authors plus a small codegen script, not a compiler plugin,
   once the main server crate's plugin-loading side gives it a concrete target.
4b. `macros` (~1.15k LOC) — **Not ported; documented instead**
   (`src/macros/README.md`). Single-file proc-macro crate, entirely
   compiler codegen: an `Event` derive + `cancellable`/`send_cancellable[_blocking]`
   (event-bus dispatch boilerplate), `packet`/`java_packet`/
   `block[_from_tag]` (registration-constant codegen),
   `PacketWrite`/`PacketRead`/`PacketReadSlice` derives (field-by-field
   protocol serialize/deserialize codegen), and `translate_cross!`/
   `translate_java!` (compile-time translation-key validation). The
   `PacketWrite`/`PacketRead` derive logic is flagged as the reference spec
   for whoever hand-ports individual `src/protocol/` packet types next,
   since Nimony has no derive macros and each packet's serialize/
   deserialize will be hand-written the way `src/nbt/tag.nim`'s is.
4. `config` (~2.2k LOC) — **Mostly done for plain-data configs.**
   Ported: `lighting.rs`, `fun.rs`, `recipe.rs`, `advancement.rs`,
   `player_data.rs`, `pvp.rs`, `logging.rs`, `whitelist.rs`, `chunk.rs`,
   `world.rs`, `server_links.rs`, `telemetry.rs`, `chat.rs`,
   `resource_pack.rs`, and `networking/{lan_broadcast,compression,proxy,
   packet_limiter,query,rcon}.rs` → `src/config/*.nim` (networking ones
   under `src/config/networking/`). All type-check clean. `Uuid` and
   `SocketAddr` are represented by small local stub types (`whitelist.nim`,
   `networking/netaddr.nim`) since neither is ported anywhere yet. Skipped:
   `op.rs`/`networking/auth.rs` (need `util::PermissionLvl`/
   `ProfileAction`, not yet ported), `networking/{java,bedrock}.rs` and
   `networking/mod.rs`'s `NetworkingConfig` aggregate (depend on java/bedrock
   above), `plugins.rs`, and top-level `lib.rs` (458 LOC — the actual
   config-file load/save/merge driver; needs a design pass, not a
   line-by-line port).
6. `gametest` (~1.9k LOC) — **Small ported slice, rest blocked.**
   `error.rs` → `src/gametest/error.nim` (full port) and `model.rs` →
   `src/gametest/model.nim` (full port, `serde`/`serde_json` skipped;
   `environment: Value` becomes a raw JSON-text `string` placeholder).
   `model.nim` needed `Rotation` from data's `block_rotation.rs`;
   rather than block on all of data, `src/gametest/rotation_stub.nim`
   hand-copies just the 4-way enum + its `then` combinator (see its header
   for the TODO to de-duplicate once data is ported for real).
   NOT ported: `world.rs` (an `#[async_trait]` interface over
   `util::math::position::BlockPos`/`world::world::
   BlockFlags`/`data::BlockStateId`, none of which exist in this
   port yet), and `helper.rs`, `manager.rs` (391 LOC), `runner/*` (459 LOC),
   `structure/placement.rs` (389 LOC), `structure/template.rs` (223 LOC),
   `block_based/test.rs` — all either depend on the above or are
   async-trait/state-machine driven or the tick loop shape mentioned under
   `scheduler` above. See `src/gametest/lib.nim`'s doc comment.
7. `codecs` / `protocol` (~40k LOC combined) — **In
   progress.** `lifecycle.rs`, `number.rs` (JSON interop skipped), and the
   core `DataResult<R>` type from `data_result.rs` (its macro-generated
   `apply2..applyN` applicative family skipped, no Nimony equivalent) →
   `src/codecs/*.nim`. NOT ported: `map_like.rs`, `dynamic_ops.rs`,
   `json_ops.rs`, `codec/*`, `struct_builder.rs`, `list_builder.rs` — a
   generic Codec/DynamicOps framework built on Rust trait objects and GATs
   with no direct Nimony equivalent; deferred until a concrete consumer
   forces the design (e.g. `nbt`'s `nbt_ops.rs`, itself stubbed
   pending this).
   `protocol`: `codec/var_int.rs` + `codec/var_uint.rs` +
   `codec/var_long.rs`/`var_ulong.rs` → `src/protocol/varint.nim` (`VarInt`,
   `VarUInt`, `VarLong`, `VarULong`), plus `src/protocol/protobase.nim`
   (`ReadingError`/`WritingError`/result types, port of the non-serde-trait
   parts of `ser/mod.rs`). Same Java-plain-LEB128-vs-Bedrock-ZigZag split as
   `src/nbt/serializer.nim`/`deserializer.nim`, verified byte-for-byte
   against `var_int.rs`'s own `#[cfg(test)]` vectors in
   `src/protocol/varinttest.nim` (round-trip across `i32::MIN/-2/-1/0/1/2/
   i32::MAX` for both shapes, boundary values, and both overflow-rejection
   tests). Async `decode_async`/`encode_async` variants (tokio-specific)
   are not ported.
   Follow-up pass added the shared codec/framing layer: `ser/mod.rs`'s
   `NetworkReadExt`/`NetworkWriteExt` traits → `src/protocol/netcodec.nim`
   (`NetReader`/`NetWriter`, one concrete pair over an owned `seq[byte]`
   instead of Rust's generic-over-`Read`/`Write` trait, matching
   `src/nbt/`'s reader/writer shape) — numeric BE reads/writes, bool,
   var_int/uint/long via `varint.nim`, bounded strings (with a from-scratch
   UTF-16-length bound check decoding UTF-8 by hand, including surrogate
   pairs), `getOption`/`getList` generics, UUID as a raw (hi, lo) `u64`
   pair (no `Uuid` type ported anywhere yet). `codec/bit_set.rs` →
   `src/protocol/bitset.nim`, verified byte-for-byte against its own
   `#[cfg(test)]` vectors in `src/protocol/bitsettest.nim` (all 4 tests,
   including the exact encoded-byte assertion and the negative-length
   rejection). `codec/uuid.rs` → `src/protocol/uuid.nim` (thin re-export,
   see above). `lib.rs`'s `ConnectionState`, `IdOr<T>`, `RawPacket` →
   `src/protocol/proto.nim`. Skipped: `StreamDecryptor`/`StreamEncryptor`
   (AES-128-CFB8 login encryption over async I/O - tokio-specific, no
   Nimony equivalent yet) and the `ClientPacket`/`ServerPacket` traits
   (Nimony has no traits; concrete packet types will expose their own
   read/write procs directly). `netcodectest.nim` round-trips every numeric
   type, bools, a var_int, and a UTF-8 string with multi-byte/surrogate-pair
   characters through the new writer/reader - passing.
   First concrete packet types: 8 Java login/config-state packets (both
   directions where upstream has both) → `src/protocol/loginpackets.nim` -
   `CSetCompression`, `CLoginDisconnect`, `SKeepAlive` (config-state),
   `SConfigPong`, `CFinishConfig`/`SAcknowledgeFinishConfig` (empty-body),
   `CLoginCookieRequest`, `SLoginCookieResponse`, `SLoginPluginResponse`.
   Picked for being small and NOT multi-version-branching (upstream's
   `JavaMinecraftVersion`-gated field differences aren't reproduced yet -
   these are ported against the current/latest wire shape only; a real
   multi-version story needs `pumpkin_util::version` ported first). Each
   exposes its own `writePacketData`/`readPacketData` procs directly
   instead of upstream's `ClientPacket`/`ServerPacket` traits, the same
   shape `src/nbt/tag.nim`'s serialize/deserialize use. All 8 verified
   with real round-trip encode→decode→compare tests in
   `src/protocol/loginpacketstest.nim` (run via `nimony c -r`, not just
   checked) - passing. NOT started: `data_component.rs` (2.9k),
   `item_stack_seralizer.rs`, and the much larger remaining packet surface
   (most play-state packets, `java/client/config/registry_data.rs` and
   other NBT/registry-heavy ones, all of `bedrock/`).
   Follow-up pass added a `writeList`/`writeListRes` generic to
   `netcodec.nim` (the write-side counterpart to the existing `getList`)
   and 4 more config-state packet types: `registry_data.rs` →
   `src/protocol/configpackets.nim` (`CRegistryData` - `RegistryEntryData`
   modeled as `{entryId, hasData, data: seq[byte]}`, the raw NBT blob
   written/read verbatim as upstream does; the reader's "has data" branch
   reads to end-of-frame since there's no length prefix on the blob
   itself, matching upstream's real one-entry-per-packet usage - documented
   in-file as not safe for a hypothetical multi-entry-with-data packet),
   and `reset_chat.rs`/`feature_flags.rs`/`ping.rs` →
   `src/protocol/configpackets2.nim` (`CConfigResetChat`, `CFeatureFlags`,
   `CConfigPing`). All with real round-trip tests
   (`configpackets{,2}test.nim`, `nimony c -r` passing).
   Explicitly assessed and deferred: `codec/item_stack_seralizer.rs` (856
   lines) - genuinely blocked, not just unstarted: it's built directly on
   `codec/data_component.rs`'s full ~2887-line `DataComponent`
   registry/codec (itself needs `pumpkin-data`'s generated component
   tables), `JavaMinecraftVersion` multi-version branching (not ported),
   and a real `ItemStack.patch: Map<DataComponent, Option<Data>>` model -
   `src/inventory/itemstub.nim`'s placeholder `ItemStack` (id+count only)
   isn't shaped for it. Revisit once `data_component.rs` has its own
   design pass.
   Still not started (~34k LOC): `codec/data_component.rs` (2.9k),
   `codec/item_stack_seralizer.rs`, `serial/*`, `query.rs`, `rcon.rs`, most
   of the `java/`'s and all of `bedrock/`'s several hundred individual
   packet types, `packet_encoder.rs`/`packet_decoder.rs`. Did not end up
   drawing on Jester's client-side `aoughwl.mcnet/netwire.nim` etc. beyond
   confirming the same varint shape is the right one to match; worth a
   closer look by whoever ports `packet_encoder.rs`/`packet_decoder.rs`
   next, since that's where Jester's client-side framing code is the more
   directly relevant reference.
8. `plugin-utils` (~710 LOC) — **Done except HTTP.** `models.rs`,
   `updater.rs`, `license.rs` (lease read/write via `std/json`, grace-period
   evaluation), and `lib.rs`'s global-state glue → `src/plugin_utils/*.nim`.
   `init(context)`'s WASM-guest path is skipped (needs unported
   `plugin-api`). `http.rs` is a call-shape stub only: Nimony's
   stdlib has no HTTP client or TLS at all, so `check_license_online`/
   `check_for_updates` compile and return a clear "not implemented" error
   rather than a fake success - needs libcurl/WinHTTP FFI eventually.
9. `host-bindings` (~70 LOC) — **Not portable yet; documented
   instead.** The entire file is one `wasmtime::component::bindgen!`
   macro call over `../plugin-wit/v0.1/*.wit` (~14.2k lines of
   WIT across 60+ files) - there is no hand-written Rust logic to
   translate, and Nimony has no WASM component-model runtime or
   WIT-bindgen equivalent. See `src/host_bindings/README.md` for the full
   explanation and the three real options once the plugin ABI is actually
   being built (wasmtime C API FFI, a custom WIT→Nimony generator, or
   dropping the WASM sandbox model for native-loaded plugins).
9b. `plugin-runtime` (~3.3k LOC) — **Not portable yet; documented
    instead, except one small data type.** wasmtime `Store`
    multiplexing/execution (`executor.rs`), cross-plugin re-entry tracking
    (`chain.rs`), an async admission policy over that (`policy.rs`), and a
    runtime-agnostic spawn trait (`spawn.rs`) are all tokio+wasmtime
    plumbing with no Nimony equivalent (no WASM runtime, and Nimony's
    async is `passive` procs + continuations, not poll-based futures).
    `lifecycle.rs`'s `DriverState`/`DriverError` — the one piece that's
    plain data — is ported to `src/plugin_runtime/lifecycle.nim`; the
    `Lifecycle`/`DriverJoin` types wrapping it in a tokio `watch` channel
    are not. See `src/plugin_runtime/README.md` for the three replacement
    paths, including the option (worth real consideration) of skipping
    WASM sandboxing entirely and loading plugins natively the way the
    sibling Jester project's `aowli` interpreter already does.
9c. `plugin-api` (~24k LOC) — **Not portable yet; documented
    instead, except one small data file.** Grepped every top-level and
    `ext/` source file for `wit::` imports: only `permissions.rs` has none.
    Everything else - `item.rs`, `block.rs`, `enchantment.rs`, `team.rs`,
    `mobs.rs`, `forms.rs`, `display.rs`, `persistent_data.rs`, `logging.rs`,
    `ai.rs`, `worldgen.rs`, `commands.rs`, `scheduler.rs`, `datapack.rs`,
    `inventory.rs`, `recipe.rs`, `lib.rs`, and all ~230 files under
    `events/*` (each a ~20-line wrapper around one generated `wit`
    `EventData` type) - is WASM-guest SDK code built directly on the same
    `wasmtime::component::bindgen!`-generated `wit` module that blocks
    `host-bindings`/`plugin-runtime`. `generated/block.rs`
    (5.2k LOC) and `generated/item.rs` (6.7k LOC) are build-time-generated
    registry data, out of scope like `data`. Ported:
    `permissions.nim` (plugin sandbox capability-string constants, pure
    data). See `src/plugin_api/README.md`.
10. `world`, `inventory`, `command` (~14.1k LOC) —
    **command: tokenizer layer AND the tree/dispatcher design pass done.**
    `errors/command_syntax_error.rs` (simplified), `context/string_range.rs`,
    `string_reader.rs`, and its numeric parsing → `src/command/*.nim`.
    The `ArgumentType<S>`/`CommandSource` trait pair the rest of the crate
    builds on got its design decision: `cmdsource.nim` collapses
    `CommandSource`'s generic-everywhere shape into one concrete
    manual-vtable ref object (no real Player/console type exists yet to
    make genericity pay for itself); `argtype.nim` ports the
    `ArgumentType`/`AnyArgumentType` pair plus the `core/*.rs` leaf types
    (bool/integer/long/float/double/string) via a closed `ArgValue`
    variant standing in for `Box<dyn Any>`; `cmdtree.nim` ports
    `node/{mod,tree}.rs` (arena-of-nodes, `Command`/`Requirement` as
    closures, redirect-by-index for the simple case, no multi-source
    forking or ambiguity detection); `cmddispatch.nim` ports
    `node/dispatcher.rs`'s real backtracking parse algorithm. All five
    files `nimony check` clean, including `cmddispatchtest.nim` which
    builds a sample "gamemode <int>"/"spawn" tree - but that test only
    passes `nimony check`, not `nimony c -r`: full codegen currently
    crashes the compiler once real closures flow through the vtables at
    runtime (a lambda-lifting-stage internal AssertionDefect, distinct
    from - and not yet reduced/filed like - the `for..in`-over-closure-seq
    bug that WAS found, minimally reproduced, fixed here, and filed as
    feedback: `meetsRequirements` originally crashed `nimony check` itself
    this way). Treat the tree/dispatcher as semantically-checked, not
    proven at runtime, until that codegen crash is resolved. See
    `src/command/lib.nim`'s doc comment for the full breakdown.
    NOT started: individual richer argument types (block/item/nbt/range/
    coordinates/particle/structure/... - all need real world/registry
    types), `errors/error_types.rs`, the SNBT parser, suggestions,
    `argument_builder.rs` (a fluent DSL `cmdtree.nim`'s plain builder procs
    cover already), and real command execution (needs Player/World/Server
    from the still-mostly-unported main server crate).
    **inventory: core interface + a couple of leaves ported** to
    `src/inventory/*.nim` (6 files, all `nimony check` clean):
    `error.rs`→`invbase.nim`, `window_property.rs`→`window_property.nim`,
    `viewer.rs`→`viewer.nim`, `inventory/inventory.rs`→`inventory.nim`
    (the core `Inventory`/`Clearable` trait plus the NBT slot-array sync
    helpers), `double.rs`→`double.nim`. `itemstub.nim` is a placeholder
    `Item`/`ItemStack` (id + count only) standing in for
    `data::item`/`item_stack`, which don't exist yet — every
    proc taking/returning `ItemStack` here will need revisiting once
    `data`'s real item model lands. Nimony has no trait objects
    (single dispatch, no `dyn Trait`), so `Inventory` is a ref object
    holding a manual vtable of proc fields (each field/closure needs
    `{.closure.}` - a Nimony compiler-internal AssertionDefect surfaced
    when a vtable-field call wasn't marked, so every closure assigned to
    an `Inventory` field is now explicit about it) rather than a trait;
    concrete inventories (simple/player/double) fill in the vtable.
    **Since then, also ported** (re-checked each file's real deps rather
    than trusting the blanket note below): `slot.rs`→`slot.nim` (the
    `Slot` trait, same manual-vtable pattern as `Inventory`, plus
    `NormalSlot`/`ArmorSlot`; armor-type restriction (`can_insert`) is
    left accepting anything - needs `data`'s `Item`/`EquipmentSlot`
    tables), `crafting/crafting_inventory.rs`→`crafting.nim` (fully
    self-contained, ported clean), `entity_equipment.rs`→
    `entity_equipment.nim` (keyed by a placeholder `EquipmentKind` enum
    instead of the real `EquipmentSlot`). `itemstub.nim` grew
    `split`/`decrement`/`increment`/`getMaxStackSize`/
    `areItemsAndComponentsEqual` to support these. `crafting/recipes.rs`'s
    `RecipeInputInventory` trait-extension became a plain
    `CraftingInventory{inv, width, height}` wrapper rather than a trait
    hierarchy (Nimony's vtable-`Inventory` has no room to extend); its
    `recipe_provider.rs` sibling stays unported (needs
    `pumpkin_protocol::codec::recipe`/`data::recipes`).
    **`screen_handler.rs`'s design decision made** (1.3k lines, ~30-method
    trait): same scoped-down manual-vtable approach as
    `src/server/block/blockbehaviour.nim`'s - `ScreenHandler` is a
    ref-object vtable covering `quickMove`/`onClosed` (what a proof-case
    concrete handler needs), not the full click-routing surface
    (`internal_on_slot_click` alone is 434 lines needing `Player`/`World`).
    Ported to `src/inventory/screenhandler.nim`: `ScreenProperty` (full,
    self-contained, using the existing `PropertyDelegate` vtable),
    `ScreenHandlerBehaviour` (plain struct: slots/syncId/windowType),
    `addSlot`/`addPlayer{Hotbar,Inventory}Slots`, and `insertItem` - a
    full, faithful port of the 86-line slot-merge algorithm, since it's
    pure slot-index/count arithmetic with no Player/World dependency at
    all. Concrete proof case: `beacon_screen_handler.rs` →
    `src/inventory/beaconhandler.nim` (`newBeaconScreenHandler`, full
    quick-move logic). `itemstub.nim` grew `setCount`/`isStackable` to
    support `insertItem`. `screenhandlertest.nim` exercises `insertItem`
    directly (closure-free, pure algorithm - passes) and builds a beacon
    handler shape-check; building/using the handler itself hits the same
    closures-through-vtables runtime crash documented elsewhere in this
    port (4th independent confirmation, after `src/command/`,
    `src/server/entity/`, `src/server/block/) - `nimony check` clean,
    `nimony c -r` crashes at `eraiser.nim`'s `ParamsTagId` assertion.
    Documented, not hidden.
    Still ~8.5k of ~11k LOC remain: all the per-container
    `*_screen_handler.rs` files beyond beacon, `player/`, `brewing/`,
    `furnace_like/`, `enchanting/`, `anvil/`, `merchant/`,
    `container_click.rs`, `drag_handler.rs`, `sync_handler.rs`,
    `gui_builder.rs`, and `internal_on_slot_click`'s full click-routing
    logic — all need either the real item/registry types, `Player`/`World`
    types from the main server crate, or both. Extending
    `ScreenHandler`'s vtable as more handlers land is mechanical from
    here, per `blockbehaviour.nim`'s precedent.
11. `world` (~78.6k LOC) — **Just started.** The crate is
    dominated by world generation (noise/structure/feature placement under
    `generation/`, ~65k of the 78.6k LOC) which needs util's
    still-incomplete noise/random port and is out of scope for now.
    Ported instead, from the smaller top-level/tick/chunk-loading surface:
    `cylindrical_chunk_iterator.rs` → `src/world/cylindrical.nim` (view-distance
    cylinder membership + load/unload diffing; the LUT-based
    `all_chunks_within` fast path was replaced with a direct bounding-loop
    recompute, since its LUT lives in unported data - same
    semantics, no precomputed table), `tick/mod.rs` → `src/world/tick.nim`
    (`TickPriority`, `ScheduledTick`/`OrderedTick`, NBT (de)serialization -
    specialized to a `value: string` id rather than upstream's generic
    `T: ToResourceLocation`, since no block/fluid registry type exists yet;
    a local `BlockPos` stand-in covers for `util::math::position`,
    also not ported yet), and `tick/scheduler.rs` →
    `src/world/tickscheduler.nim` (the ring-buffer `ChunkTickScheduler` -
    de-async'd to a plain single-threaded version, no concurrency model
    exists yet for the tick loop; same string-specialization as tick.nim).
    `dimension.rs` is a two-line stub documenting why it's blocked
    (`Level`/`data::dimension::Dimension` both unported).
    `chunk/palette.rs`'s `PalettedContainer<V, const DIM: usize>` got its
    design pass: ported to `src/world/palette.nim` as `PalettedContainer`
    with `dim` as a runtime `int` field (Nimony has no const-generic array
    types, and only two concrete shapes - 16 for blocks, 4 for biomes -
    are ever used, so forcing generality bought nothing) and the stored
    value type fixed to a concrete `uint32` (generic `V` hit real Nimony
    friction; both real uses - block-state id, biome id - are plain
    integers anyway). Dense/Indexed storage, palette dedup, and the
    swap-remove-on-zero-count shrink path are all ported; `nimony c -r`
    tested via `palettetest.nim` (fill 4096 cells with 300 distinct
    values to force an Indexed→Dense upgrade, verify every cell, then
    refill to one value and verify the palette shrinks back to 1). That
    test caught a real bug: a first pass wrongly special-cased Dense
    storage to skip palette/counts bookkeeping, which silently broke the
    palette-shrink path once upgraded - fixed once the test failed to
    just report "compiles". Left out: the Bedrock-specific
    `bedrock_palette_bits`/`bedrock_water_state`/
    `has_random_ticking_fluid` helpers (need `BlockState`/`Fluid`, not
    ported) and the on-disk bit-packed (de)serialization
    (`ChunkSectionBlockStates`/`ChunkSectionBiomes`, `format/anvil.rs`/
    `format/linear.rs`, ~3.5k lines) - a separate, more mechanical
    follow-up now that the in-memory shape is settled.
    `biome/`'s climate-parameter math is now ported: `data`'s (generated)
    `quantize_coord`/`unquantize_coord`/`Parameter`/`TargetPoint`/
    `ParameterPoint` plus `biome/multi_noise.rs`'s `to_long` and
    `biome/mod.rs`'s `hash_seed`, all combined into `src/world/biomeparam.nim`
    since none of the individual pieces are meaningful alone and all are
    pure, registry-free math. `hash_seed` uses the `sha256` already
    available via the `jwt` sibling repo's cross-repo import. Verified with
    `biomeparamtest.nim` (`nimony c -r`) against upstream's own
    `hash_seed_test` vectors (`hash_seed(0) == 8794265229978523055`,
    `hash_seed(-777i64 as u64) == -1087248400229165450`) plus
    Parameter-distance/ParameterPoint-fitness sanity checks — both pass.
    The rest of `biome/` (`BiomeSupplier`/`MultiNoiseBiomeSupplier`/
    `ActiveBiomeSupplier` in `mod.rs`, all of `position_finder.rs`,
    `end.rs`) needs the unported generated `BiomeTree`/biome registry and
    `MultiNoiseSampler` (noise sampling - `perlin.rs`/`simplex.rs` are
    unverified even where present), so left for later.
    `lighting/` hits the same dead end `block/` already documented in
    `src/server/block/README.md`: `lighting/storage.rs` (the smallest
    file, 184 lines) already needs `chunk_system::{Chunk, Cache}`, which
    doesn't exist yet even as a stub — `engine.rs`/`runtime.rs` (892/637
    lines) are built on the same foundation, so not attempted.
    `format/anvil.rs`'s on-disk region-file (.mca) layout is now ported at
    the format-math level: `src/world/anvilformat.nim` covers the 8 KiB
    location/timestamp header (parse/build, with the `sectorOffset < 2`
    reserved-sector guard), region/chunk-index math (verified against the
    floor-division trap negative chunk coordinates hit - `>>` on a signed
    int is arithmetic/floor-rounding in both Rust and Nimony, so this had
    to be checked explicitly, not just trusted), per-chunk sector-count
    accounting, and the length-prefixed/compression-tagged payload framing.
    Deliberately NOT ported: the actual gzip/zlib/LZ4 (de)compression
    bodies (same gap as `nbt_compress.nim` - no zlib/gzip module in
    Nimony's stdlib) and the async file I/O / mutex-guarded in-place
    sector allocator (`AnvilChunkFile::write`/`write_indices` - no
    concurrency model chosen yet, same gap flagged for the scheduler).
    `anvilformattest.nim` round-trips real data through every piece
    (`nimony c -r`, all pass) using uncompressed payloads to exercise real
    framing without the missing compression bodies; `format/linear.rs`
    (the alternate Linear region format, ~778 lines) not attempted.
    Not started: `block/`, the rest of `biome/` (registry-dependent parts),
    the rest of `chunk/` (`mod.rs`, `io/`),
    `level.rs`, `world.rs`, the rest of `lighting/`, `poi/`, `world_info/`,
    `chunk_system/`, all of `generation/`.
12. the main server crate (~269k LOC) — **Assessed; tiny slice
    ported, full map written.** Ported `error.rs`'s a shared error trait as
    overloaded procs → `src/server/errorclass.nim` (over `InventoryError`/
    `ReadingError`; `PlayerDataError` pending that type's port). Everything
    else is mapped in `src/server/README.md` by module (`entity/` 83.6k,
    `block/` 47.6k, `plugin/` 47.4k, `command/` 30.3k, `net/` 19.5k,
    `world/` 18.7k, `item/` 6.9k, `data/` 6.2k, `server/` 3.4k,
    `enchantment/` 1.9k) with three concrete blockers identified (unported
    `data` registries, no tick-loop/concurrency design yet, and
    `entity/`'s scale needing a real `Entity`-shape design pass before wide
    porting). Since then: `enchantment/` - 5 files ported to
    `src/server/enchantment/` (the `LevelBasedValue` formula type + 4 pure
    value-transform effects; ~15 remaining effect files need `World`/
    `Player`/`Entity` stand-ins, not yet stubbed). `block/` - assessed in
    detail, confirmed genuinely blocked even at its simplest: tried the two
    smallest conceivable block impls (an 8-line empty one, a 20-line
    one-method one) and both need the `#[pumpkin_block]` registration macro
    (unportable, see `src/macros/README.md`) and a working `Entity`
    abstraction before *any* block can port, not just complex ones. One
    free-standing type (`PathComputationType`) ported to
    `src/server/block/blockmisc.nim`; full writeup with the concrete
    unblock order in `src/server/block/README.md`. See both READMEs before
    starting more work here.
12b. `item/` (~6.9k LOC, part of the upstream main server crate) —
    **Core interface/registry ported; concrete items blocked.**
    `ItemBehaviour`/`ItemMetadata`/`ItemRegistry`/`BlockActionResult`/`Hand`
    ported to `src/server/item/itembehaviour.nim` (manual-vtable pattern,
    same as `block/`/`entity/`). No `#[pumpkin_item]` macro exists here -
    items self-register via plain `manager.register(...)` calls, unlike
    `block/`. All ~53 concrete item files need `Player.inventory` and/or a
    `World` type (pickup, sound, entity spawning), neither of which exist
    yet - tried the two smallest-looking candidates (`dye.rs`, `egg.rs`)
    and both hit this wall. See `src/server/item/README.md` for the exact
    unblock path.
13. `data` (~1.5M LOC — almost entirely generated block/item/registry
   tables) — **Generator path confirmed viable; proof-of-concept done.**
   The generator (the upstream data-codegen tool, ~36.8k lines across ~90 small
   per-domain submodules driven by one `main.rs`) reads JSON already
   checked into the upstream repo's `assets/` (92MB, confirmed present -
   not a blocker). Rust builds each submodule's output as a
   `proc_macro2::TokenStream` via `quote!`; Nimony has no equivalent (and
   doesn't need one) since a generator can just build its output as a
   plain string and `writeFile` it directly - simpler than the Rust
   approach, not a gap. `std/json` is present in Nimony's stdlib (unlike
   gzip/crypto/HTTP, confirmed missing elsewhere in this port) and
   sufficient. `src/data_codegen/gen_sound_category.nim` is a complete,
   run-and-verified port of the smallest submodule (JSON in -> generated,
   type-checked `src/generated/sound_category.nim` out, values verified
   correct) establishing the pattern. The other ~89 submodules
   (`scoreboard_slot.rs` trivial, up through `block.rs`/`item.rs`/
   `biome.rs`/`recipes.rs`/`noise_router.rs` which encode real structural
   complexity) each need the same file-by-file treatment - see
   `src/data_codegen/README.md` for the full breakdown, two open design
   questions (output layout, whether `main.rs`'s WIT-generation side
   duties are in scope), and a note that these submodules are independent
   of each other and would parallelize well across multiple forks.

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
