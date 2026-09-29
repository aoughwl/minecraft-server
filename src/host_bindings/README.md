# pumpkin-host-bindings — not ported (nothing to port)

Upstream: `crates/pumpkin-host-bindings/src/lib.rs`, 70 lines.

## What the crate actually is

The entire file is one `wasmtime::component::bindgen! { ... }` macro
invocation. It takes no hand-written logic at all - it points wasmtime's
code generator at the WIT (WebAssembly Interface Types) world defined in
`../pumpkin-plugin-wit/v0.1/` (60+ `.wit` files, ~14.2k lines total,
covering advancement/attributes/biomes/block-entity/command/datapack/
entity/event/player/server/world/... interfaces) and, at Rust compile
time, generates:

- Rust struct/trait bindings for every exported/imported WIT interface
  method (the big `imports: { ... }` map pins ~50 of those methods to
  `async | store | trappable` wasmtime call semantics).
- The host-side glue that lets the main `pumpkin` server crate call into
  a loaded WASM plugin component, and vice versa, across the component
  model ABI boundary.

There is no Rust logic here to translate line-by-line - it's 100% codegen
input, the actual "source" is the WIT files, and the actual "output" is
wasmtime-specific Rust bound to wasmtime's `wasmtime::component` runtime
types.

## Why this isn't portable yet, and what would replace it

Nimony has no WASM component-model runtime and no WIT-bindgen equivalent
(checked `~/nimony/doc/differences.md`, `language.md`; nothing in
`~/nimony/lib/std/` touches WASM or component-model ABI). Three real paths
once the plugin system is actually needed:

1. **Bind to wasmtime's C API from Nimony.** wasmtime ships a stable C API
   (`wasmtime.h`); Nimony can FFI against arbitrary C via `{.importc,
   header.}`, so a hand-written (or generated) Nimony wrapper over
   `wasmtime-c-api` could reproduce this, driven off the same `.wit`
   files with a small custom generator instead of `bindgen!`.
2. **Write a WIT-to-Nimony generator** that parses the `.wit` files
   directly (they're a fairly simple IDL) and emits the Nimony proc
   signatures + marshalling code by hand, sidestepping wasmtime's Rust
   macro entirely. More work, but no C FFI layer to maintain.
3. **Drop the WASM sandboxing model** for this port and let plugins be
   native Nimony/Nim modules loaded some other way (dynlib, or in-process
   like `aowli` does for the Jester modpack work this project sits
   alongside) - a bigger design decision, not this crate's call to make
   alone.

None of these is a 70-line job, and guessing wrong here would mean
redoing the entire plugin ABI layer later. Deferred until the plugin
system is actually being built and one of the above is chosen deliberately.

## What IS portable right now

The WIT files themselves (`../pumpkin-plugin-wit/v0.1/*.wit`, referenced
by upstream's `Cargo.toml`/`bindgen!` path but not vendored into this
port) are plain data/interface definitions, not Rust - they're the
actual source of truth for the plugin ABI and would be the starting point
for whichever option above gets picked. `pumpkin-plugin-api`,
`pumpkin-plugin-runtime`, and `pumpkin-plugin-utils`'s WASM-guest `init`
path (see `src/plugin_utils/lib.nim`'s skipped section) all sit on the
same unresolved dependency.
