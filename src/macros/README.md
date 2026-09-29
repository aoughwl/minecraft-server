# pumpkin-macros (not ported — documented)

Source: `pumpkingmc/crates/pumpkin-macros/src/lib.rs`, 1,151 lines, a single
file. Entirely Rust proc-macro codegen (`proc_macro`/`syn`/`quote`) — no
plain runtime logic anywhere in the crate, so unlike the initial assumption
there is nothing here to port line-by-line. Same situation as
`pumpkin-api-macros` (see `../api_macros/README.md`) and
`pumpkin-host-bindings` (`../host_bindings/README.md`): Nimony's macro
replacement is a structurally different, NIF-AST-based compiler-plugin
mechanism, not a token-stream rewriter, so there is no mechanical
translation. This file records what each macro actually does semantically,
for whoever designs the Nimony equivalent once a concrete caller needs it.

## `#[derive(Event)]` (line 16)

Generates a `static` unique-per-type ID and implements a marker `Event`
trait returning it, by hashing the type's own name at macro-expansion time
(`static_hash_str`-derived constant). Nimony equivalent: a plain
`distinct int` id assigned via an enum or a compile-time `const` table,
since Nimony has no proc-macro-time hashing of type names — this would need
to become an explicit registry (e.g. `type EventId = enum ...`) rather than
an auto-derived one.

## `#[cancellable]` (line 50)

Attribute macro applied to an event `struct`: injects a `cancelled: bool`
field and a `CancellableEvent` impl (`cancelled()`/`set_cancelled()`).
Nimony equivalent: just declare the field by hand on every cancellable
event struct, or use a common `EventBase` object that cancellable events
embed - either is a one-line manual change per struct, not worth automating
until the event system itself is designed.

## `send_cancellable!` / `send_cancellable_blocking!` (lines 104, 186)

Function-like macros that expand to "construct event, fire it through the
plugin/event bus, check `cancelled()`, run the `after` block only if not
cancelled" boilerplate, in async and blocking flavors. This is the most
Rust-idiom-specific piece: it's built on the crate's async event-dispatch
API (tokio), which doesn't exist yet in this port (see
`src/scheduler/lib.nim`'s note on Nimony's `passive`-proc/continuation
async model being fundamentally different from poll-based futures).
Nimony equivalent: once an event bus and the scheduler's driver are
designed, this becomes a plain template (`template sendCancellable(event,
body): untyped = ...`) — straightforward once the pieces it wraps exist,
premature now.

## `#[packet]` / `#[java_packet]` (lines 273, 295)

Attribute macros on a packet struct: register its packet ID (a literal or,
for `java_packet`, a `Block::ID` expression) as an associated constant.
Nimony equivalent: a plain `const PacketId = ...` in each packet type, or
a table `{TypeName: id}` built by hand — no macro needed, this is just
struct-literal boilerplate Rust chose to auto-generate.

## `#[pumpkin_block]` / `#[pumpkin_block_from_tag]` (lines 351, 385)

Similar registration macros for block-behavior structs, resolving a block
name/tag string to a `Block`/`BlockState` ID `const`. Blocked on
`pumpkin-data`'s (1.5M LOC, mostly generated) block registry existing in
Nimony first — no point designing the replacement before that data exists.

## `#[derive(PacketWrite)]` / `#[derive(PacketRead)]` / `#[derive(PacketReadSlice)]` (lines 566, 640, 706)

The largest and most reusable piece: field-by-field derives that emit a
packet's `serialize`/`deserialize` body by walking its struct fields (with
a `#[serial(...)]` attribute controlling per-field encoding — varint vs.
fixed-width, `Vec<T>` length-prefixing, etc.). This is exactly the
boilerplate `src/protocol/`'s hand-written packet types will need for
every packet once that crate's individual packet structs get ported.
Nimony has no derive-macro equivalent, so each packet's
`serializeData`/`deserializeData` will need to be **hand-written**,
following the same pattern already established in `src/nbt/tag.nim`
(explicit field-by-field read/write procs) rather than generated. Whoever
ports individual `src/protocol/` packet types next should treat this
file's `read_expr`/`write_expr`/`check_serial_attributes` logic (lines
760-954) as the *reference spec* for what each packet's hand-written
procs need to reproduce (varint-vs-fixed selection, `Vec` framing, etc.),
not as something to port.

## `translate_cross!` / `translate_java!` (lines 1042, 1122)

Compile-time-only macros that validate a translation-key string literal
against Pumpkin's own translation resource files, erroring at Pumpkin's
build time if the key doesn't exist. Purely a build-time lint with no
runtime behavior — the Nimony equivalent (if ever wanted) would be a
small standalone script run in CI/`tools/`, not a macro, since Nimony
has no proc-macro-time file I/O against sibling resource files either.

## Summary

Nothing in this crate is portable as-is; nothing here was faked or
stubbed. The one piece worth prioritizing later is the `PacketWrite`/
`PacketRead`/`PacketReadSlice` derive logic's *semantics* (not its Rust
implementation) as a checklist for hand-porting `src/protocol/`'s
individual packets.
