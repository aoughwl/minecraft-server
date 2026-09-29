## command port status (module index / scope notes).
## Upstream: upstream/command (~14.1k lines).
##
## Ported (tokenizer layer - foundational, self-contained, no unported
## dependencies):
## - cmderrors.nim    <- errors/command_syntax_error.rs (simplified: plain
##                        `kind` enum + string message instead of the
##                        trait-object AnyCommandErrorType registry, which
##                        needs errors/error_types.rs (413 lines) and
##                        util::text::TextComponent, itself not yet
##                        ported)
## - string_range.nim <- context/string_range.rs
## - string_reader.nim <- string_reader.rs (Cow<str> collapsed to owned
##                        string; char-level UTF-8 stepping simplified to
##                        byte-level - see file doc comment)
## - cmdnumbers.nim   <- the numeric read_int/read_long/read_float/
##                        read_double methods of string_reader.rs, split
##                        out since they need std/parseutils
##
## Ported (the design pass, tree/dispatcher layer):
## - cmdsource.nim    <- source.rs's `CommandSource` trait + `DummySource`,
##                        `ReturnValue`/`ResultValueTaker`. Collapsed the
##                        `CommandSource: S`-generic-everywhere shape into
##                        one concrete manual-vtable ref object (same
##                        pattern as Inventory/Slot) since no real
##                        Player/console type exists in this port yet to
##                        make genericity pay for itself. TextComponent ->
##                        plain string (matches cmderrors.nim).
## - argtype.nim      <- argument_types/argument_type.rs's `ArgumentType`/
##                        `AnyArgumentType` trait pair + the core/*.rs leaf
##                        types (bool, integer, long, float, double,
##                        string). `Item`/`Any`-erasure became a closed
##                        `ArgValue` variant (the types the tokenizer
##                        already supports) plus a manual-vtable
##                        `ArgumentType`. Suggestions/examples/
##                        client_side_parser dropped (client-facing, not
##                        needed for parse/dispatch correctness).
## - cmdtree.nim      <- node/{mod,tree}.rs (~1.5k lines). `Tree` stays an
##                        arena (`seq[CommandNode]` + index-based
##                        children), matching upstream's own slab shape and
##                        incidentally avoiding the self-recursive-ref-in-
##                        case-object Nimony bug. `Command<S>`/
##                        `Requirement<S>` become `{.closure.}` proc
##                        fields/seqs. `RedirectModifier::Custom`
##                        (multi-source forking, e.g. `/execute as @a run
##                        ...`) and ambiguity detection are NOT ported -
##                        real forking needs a multi-CommandSource
##                        execution model this port doesn't have yet;
##                        ambiguity detection is a registration-time
##                        diagnostic, not required for dispatch.
## - cmddispatch.nim  <- node/dispatcher.rs (~1277 lines). `parseNode`
##                        reproduces upstream's real backtracking (try
##                        every child, reset the reader and move on if one
##                        fails) rather than a naive first-match walk.
##                        Split into its own file from cmdtree.nim mostly
##                        for size (see its own doc comment - NOT required
##                        to work around the compiler crash below, that
##                        one's fixed at the source).
## - cmddispatchtest.nim - proves the tree/dispatcher parses and runs a
##                        sample "gamemode <int>"/"spawn" command tree.
##                        `nimony check` passes; `nimony c -r` currently
##                        crashes the compiler at the lambda-lifting stage
##                        once real closures flow through the vtables at
##                        runtime - see that file's STATUS header. Treat
##                        this whole slice as semantically-checked, not
##                        runtime-verified, until that's resolved.
##
## Nimony compiler bug found and FIXED here (filed as feedback): iterating
## a `seq[proc(...) {.closure.}]` field with `for x in someSeq: x(...)`
## crashes the compiler (`derefs.nim` `checkForDangerousLocations`,
## `fnType.isParamsTag` AssertionDefect) at `nimony check` time already -
## cmdtree.nim's `meetsRequirements` hit this and was rewritten as an
## indexed `while` loop, which works.
##
## NOT started: individual richer argument types (`block.rs`, `item.rs`,
## `nbt.rs`, `range.rs`, the `coordinates/` family, `resource*.rs`,
## `particle.rs`, `structure.rs`, etc. - all need real world/registry
## types this port doesn't have), `errors/error_types.rs` (the static
## error-constant registry cmderrors.nim simplified away), the SNBT parser
## (`snbt/*`, ~2k lines), suggestions (`suggestion/*`), `argument_builder.rs`
## (a fluent tree-construction DSL - `cmdtree.nim`'s `addLiteral`/
## `addArgument`/`setCommand` procs cover the same ground more plainly),
## and command *execution* for any real vanilla command (every /gamemode,
## /give etc. handler needs Player/World/Server types from the still-
## mostly-unported main server crate).
