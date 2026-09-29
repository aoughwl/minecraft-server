# plugin-runtime

Port status: **mostly documented, not ported.** ~3.3k lines of Rust across
6 files (`lib.rs` 1734, `executor.rs` 1207, `chain.rs` 142, `lifecycle.rs`
89, `policy.rs` 82, `spawn.rs` 29).

This is the wasmtime-hosting side of the upstream server's plugin system - it loads
and drives the WASM plugin components whose ABI `host-bindings`
generates bindings for (see `src/host_bindings/README.md`) and whose
utility layer `plugin-utils` partly covers (see
`src/plugin_utils/`). As predicted before reading the source, essentially
all of it is `wasmtime::component::*` + `tokio` async runtime plumbing:

- **`executor.rs`** (1207 LOC) - a `StoreExecutor` that owns wasmtime
  `Store`s, dispatches guest calls onto them via `wasmtime::component`'s
  `Accessor`/`AccessorTask`/`TypedFunc`, and multiplexes concurrent guest
  calls with `tokio::sync::{Mutex, mpsc, oneshot}` and
  `futures::stream::FuturesUnordered`.
- **`chain.rs`** (142 LOC) - tracks "causal chains" of re-entrant guest
  calls (a guest plugin calling back into the host, which calls another
  guest) via task-local `ReentryContext`/`RootAdmission` state, so
  synchronous re-entry can be told apart from a fresh concurrent call.
- **`policy.rs`** (82 LOC) - `StorePolicy`/`LegacySyncReentry`: an
  admission-control policy over `chain.rs`'s re-entry tracking, entirely
  `async fn`-shaped.
- **`spawn.rs`** (29 LOC) - `RuntimeSpawner`, a trait abstracting "spawn
  this `Pin<Box<dyn Future>>`" so this crate doesn't pick a runtime itself.
- **`lifecycle.rs`** (89 LOC) - the one piece with a genuinely portable
  data core: `DriverState`/`DriverError`. The *state itself* is ported to
  `lifecycle.nim` in this directory. What's NOT ported is the `Lifecycle`
  type (wraps the state in a `tokio::sync::watch` channel for
  publish/subscribe) and `DriverJoin::wait` (an async wait for a terminal
  state) - both are thin, but genuinely tokio-shaped.

None of this can be mechanically translated: Nimony has no WASM
component-model runtime, no `wasmtime` binding, and a structurally
different async model (`passive` procs + continuations, not
poll-based `Future`s/tasks/channels - see `~/nimony/doc/differences.md`).
Every one of `executor.rs`/`chain.rs`/`policy.rs`/`spawn.rs` is built
around exactly the two things Nimony doesn't have here.

## Replacement paths, when this is actually needed

Same three options `src/host_bindings/README.md` already lays out, plus
one runtime-driver-specific note:

1. **wasmtime C API FFI from Nimony** (`{.importc.}` against
   `wasmtime.h`). Gets real WASM sandboxing but means re-deriving
   `executor.rs`'s store-multiplexing and `chain.rs`'s re-entry tracking
   against Nimony's own concurrency primitives (`passive` procs), not a
   1:1 port of the tokio task/channel shapes here.
2. **A custom WIT→Nimony generator** paired with a smaller/embeddable WASM
   engine, if wasmtime's C API proves too heavy to bind cleanly.
3. **Drop the WASM sandbox model entirely** and load plugins natively,
   the way the sibling Jester modpack project already does with its
   `aowli` interpreter (`jester/AGENTS.md`: "Mods are written in
   Nim-family source, compiled to typed intermediate files, and run
   inside `aowli`, an embedded interpreter"). This sidesteps `executor.rs`
   and `chain.rs` almost entirely, since there's no cross-sandbox call
   boundary to multiplex or track re-entry across - native calls are
   already just calls. Worth strong consideration given this project's
   own sibling already solved the equivalent problem this way.

Whichever path is chosen, `lifecycle.nim`'s `DriverState`/`DriverError`
in this directory is reusable as-is - it's just an enum and an error
struct, no wasmtime or tokio dependency baked in.
