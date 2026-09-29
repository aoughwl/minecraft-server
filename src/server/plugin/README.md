# `src/server/plugin/` — main crate `plugin/` module

Upstream's `crates/pumpkin/src/plugin/` (~38.9k lines across the files
directly in `plugin/`, not counting `plugin/api/events/*`'s ~230 tiny
per-event files which are counted separately below) is the native-server
side of the plugin system. Its sibling crates (`pumpkin-plugin-api`,
`pumpkin-plugin-runtime`, `pumpkin-plugin-utils`, `pumpkin-host-bindings`)
were already found to be almost entirely WASM-component-model-specific —
see `src/plugin_runtime/README.md`, `src/plugin_api/README.md`,
`src/host_bindings/README.md`. `plugin/` follows the same shape, at a
larger scale: it's where the server *hosts* that WASM bridge.

## Module map (LOC via `wc -l`)

| Path | LOC | Status |
|---|---|---|
| `plugin/loader/wasm/wasm_host/wit/v0_1/**` | ~35k+ | **Not portable.** `wasmtime::component::bindgen!`-generated WIT host bindings — the same category already documented unportable in `src/host_bindings/README.md`. This is the overwhelming majority of the module's size. |
| `plugin/mod.rs` | 1336 | **Not ported this pass.** The actual plugin manager: registration, `DynEventHandler` dispatch, `PLUGIN_API_VERSION`/`PLUGIN_DIR` (both ported below), loader orchestration. Needs a real design pass (event-dispatch data model is now tractable given `src/plugin_api/eventdata.nim`'s real `EventData` types, but the manager itself is `Arc`/async-heavy — same concurrency-model gap as `src/scheduler/`). |
| `plugin/permissions.rs` | 110 | **Ported.** `permissions.nim` — plain string constants + `getPermissionDescription`. |
| `plugin/loader/native.rs` | 95 | **Partially ported.** `native.nim` — `LoaderError`/`LoaderResult[T]`, `PLUGIN_API_VERSION`, `canLoad`/`canUnload`'s platform-extension logic (parameterized on OS rather than `cfg!`). NOT ported: the actual dynamic-library load + `PUMPKIN_API_VERSION`/`METADATA`/`plugin` symbol lookups — needs Nimony's dynlib FFI (not yet investigated for this port) and a chosen async signature. |
| `plugin/loader/mod.rs` | (small) | `LoaderError` enum ported into `native.nim` (it's the loader-level error, used by all loader backends, not native-specific — kept in `native.nim` since that's the only loader ported so far). |
| `plugin/loader/wasm/mod.rs`, `state.rs`, `signature.rs`, `logging.rs`, `args.rs` | ~1.1k | **Not portable** — WASM-loader-specific glue (wasmtime `Store`/`Linker` setup), same gap as `pumpkin-plugin-runtime`. |
| `plugin/api/context.rs`, `gui.rs`, `title.rs` | ~680 | **Not assessed this pass.** Plugin-facing builder APIs; likely a mix of portable data shapes and WASM-guest-call glue, worth a dedicated look. |
| `plugin/api/events/**` (~230 files) | not counted above | **Partially covered.** These are the native-side counterpart to the already-ported `src/plugin_api/eventdata.nim` (8 event types with real `EventData` payloads, verified runtime-clean). The remaining ~220 event types follow the same mechanical pattern — good parallelizable follow-up work, same as the original `pumpkin-data` codegen submodule sweep. |

## What's genuinely done here

`permissions.nim` and `native.nim`'s logic (not its dylib-loading stub) are
both real, and `plugintest.nim` **actually runs** (`nimony c -r`) and
passes — no `entity.nim` import, so unaffected by the closures-through-
vtables crash cataloged in `NIMONY-COMPILER-BUGS.md`. This is a small but
solid, genuinely-proven slice of a 38.9k-line module dominated by
WASM-bridge code this port has consistently and correctly declined to fake.

## Next steps, roughly by value

1. Port more `plugin/api/events/*` types into `src/plugin_api/eventdata.nim`
   (mechanical, parallelizable, no blockers).
2. Design `plugin/mod.rs`'s event-dispatch core as plain data + concrete
   dispatch (not `DynEventHandler` trait objects) — the `EventData` variant
   type this would dispatch already exists.
3. Investigate Nimony's dynlib FFI (`{.dynlib.}`/`loadLib`/`symAddr`) to
   unblock `native.nim`'s actual plugin loading — this is the one piece of
   the whole plugin system that doesn't need a WASM runtime or an async
   model decided first, just C-backend dynamic-library FFI.
