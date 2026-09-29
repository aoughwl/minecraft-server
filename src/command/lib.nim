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
## NOT started, and why: everything above `StringReader` is built on a
## generic `ArgumentType<S>` trait (argument_types/argument_type.rs, 174
## lines) parameterized over a `CommandSource` trait (source.rs, 189
## lines) representing whoever ran the command (player/console/command
## block). Individual argument types (BoolArgumentType, IntegerArgumentType,
## the ~25 files under argument_types/), the brigadier-style command tree
## (node/*, 1.5k+ lines including the 1277-line dispatcher), and the SNBT
## parser (snbt/*, ~2k lines) all sit on top of that trait pair. Porting
## them piecemeal without first deciding Nimony's replacement for
## `dyn ArgumentType<S>` (concrete enum dispatch vs. constrained generics
## vs. proc-pointer tables) would mean redoing them. That's the right next
## slice, but it's a design decision, not a mechanical translation -
## deferred to whoever picks this crate back up.
