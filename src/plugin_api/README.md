# pumpkin-plugin-api → Nimony

Source: `crates/pumpkin-plugin-api` in the Pumpkin repo, ~24k lines of Rust.

## What's actually here

Despite the size, this crate is almost entirely a **WASM-guest SDK**: every
substantive module imports from `crate::wit::pumpkin::plugin::*`, which is
the `wasmtime::component::bindgen!`-generated binding module (same
generation mechanism `pumpkin-host-bindings` sits on the host side of - see
`src/host_bindings/README.md`). That module isn't hand-written Rust
anywhere in the crate; it's produced at Pumpkin's own build time from the
WIT interface files under `pumpkin-plugin-wit/`. There is nothing here to
mechanically translate without first having a Nimony WASM-guest binding
layer, which doesn't exist (see `src/host_bindings/README.md` and
`src/plugin_runtime/README.md` for the three replacement paths already
identified: wasmtime C API FFI, a custom WIT→Nimony generator, or dropping
WASM sandboxing for natively-loaded plugins the way Jester's `aowli`
interpreter already does).

Verified by grepping every top-level and `ext/` source file for `wit::`
imports: only `permissions.rs` and `ext/mod.rs` (a re-export shim) have
none. Everything else - `item.rs`, `block.rs`, `enchantment.rs`, `team.rs`,
`mobs.rs`, `forms.rs`, `display.rs`, `persistent_data.rs`, `logging.rs`,
`ai.rs`, `worldgen.rs`, `commands.rs`, `scheduler.rs`, `datapack.rs`,
`inventory.rs`, `recipe.rs`, `lib.rs`, and all ~230 files under `events/`
(each a ~20-line `FromIntoEvent` wrapper around one `wit::...::EventData`
type) - is WASM-guest binding glue through and through.

`generated/block.rs` (5.2k lines) and `generated/item.rs` (6.7k lines) are
build-time-generated block/item registry data, out of scope for the same
reason `pumpkin-data` is: port the generator once everything upstream of it
is settled, not the generated output by hand.

## Ported

- `permissions.nim` - the plugin sandbox capability-string constants
  (`network.*`, `fs.*`, `sys.*`, `http.outbound`). Pure data, no `wit`
  dependency. `nimony check` clean.

## Not ported

Everything else, for the reason above. When the WASM-guest binding layer
question gets resolved (see the replacement paths in `src/host_bindings/`
and `src/plugin_runtime/`), the ~230 `events/*.rs` files are mechanical
once a `wit`-equivalent `Event`/`EventType` enum exists - each one is just
`{event name} -> {matching EventData variant}`. The larger files
(`recipe.rs`, `mobs.rs`, `persistent_data.rs`, `enchantment.rs`, `team.rs`)
are plugin-author-facing builder APIs over those same WIT resource types
and should follow once the resource types themselves have a Nimony shape.
