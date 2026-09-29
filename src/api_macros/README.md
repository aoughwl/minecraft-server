# pumpkin-api-macros: not ported, by design

Source: `crates/pumpkin-api-macros/src/lib.rs` (152 lines). This is a Rust
`proc-macro` crate - it runs as compiler codegen during Pumpkin's own build,
not as runtime code, and there is nothing here to compile to Nimony as a
module. Nimony's own metaprogramming ("Macros replaced by compiler plugins
(different API)", `~/nimony/doc/differences.md`) operates on NIF AST through
a separate plugin mechanism, not a drop-in replacement for `syn`/`quote`
token-stream rewriting, and pulling that in now would be solving a problem
no Nimony code in this repo has yet. This doc records what each macro does
so whoever writes the first Nimony plugin-host code (once `pumpkin`'s
plugin system itself is reached) knows what needs replacing and how.

## `#[plugin_method]`

Applied to a fn inside a `#[plugin_impl]` struct. At macro-expansion time it:
1. Rewrites the fn to return `PluginFuture<'_, ReturnType>` and wrap its
   body in `GLOBAL_RUNTIME.block_on(async move { Box::pin(async move { ... }) })`.
2. Does **not** emit anything itself (`TokenStream::new()`) - instead it
   stashes the rewritten fn source as a string in a process-global
   `static PLUGIN_METHODS: Mutex<HashMap<String, String>>`, keyed by fn
   name, for `#[plugin_impl]` to collect later in the same compilation.

That cross-macro-invocation accumulation is the part with no clean Nimony
analogue: it relies on proc-macros in the same crate compile sharing
mutable process state across independent macro-attribute expansions, which
only makes sense in Rust's macro-expansion-as-a-separate-process model.

## `#[plugin_impl]`

Applied to the plugin's main struct. Drains `PLUGIN_METHODS`, re-parses
each stashed fn body, and emits:
- `GLOBAL_RUNTIME`: a lazily-initialized global tokio `Runtime`.
- `METADATA`/`PUMPKIN_API_VERSION`: `#[no_mangle]` statics read by the host
  when it dynamically loads the compiled plugin (`.dll`/`.so`).
- `impl Plugin for Struct { <collected methods> }`.
- `pub fn plugin() -> Box<dyn Plugin>`, the host's dynamic-load entry point.

## `#[with_runtime(global|local)]`

Applied to an `impl` block. Wraps every method body in either
`GLOBAL_RUNTIME.block_on(...)` or a freshly-constructed
`tokio::runtime::Runtime::new().block_on(...)`, so `async` method bodies
can be called from sync context.

## What replaces this in Nimony, once needed

All three macros exist to solve one problem: **let plugin authors write
`async fn`, but expose sync entry points the C-ABI-ish dynamic-load host
can call**, plus emit the fixed `#[no_mangle]` statics every plugin needs.
None of that is proc-macro-specific *in principle* - it's boilerplate that
could equally be:
- A plain Nimony `template`/generic wrapper each plugin author calls
  explicitly (no attribute-macro magic needed) once Nimony's own async
  model (`passive` procs + continuations, not tokio `block_on`) has a
  server-side driver to call into - see the same open question flagged in
  `src/scheduler/lib.nim` for the scheduler's tick-driven futures.
  Nimony has no `block_on`-equivalent because it has no poll-based
  futures to begin with; the honest replacement is "the plugin host calls
  the plugin's `passive` proc directly", not a `block_on` translation.
- A short code-generation script (this repo already has a Nim/Nimony
  toolchain; a `tools/`-style codegen step, not a compiler plugin, is
  proportionate for "stamp out the fixed METADATA/entry-point boilerplate"
  once there's a concrete plugin ABI target crate to generate it for).

Revisit this once `pumpkin`'s plugin-loading side (the actual host, not
this macro crate) is reached and its target shape is known.
