# src/server/command

Concrete slash-command implementations for the main server crate
(upstream `crates/pumpkin/src/command/commands/*.rs`, ~30.3k lines) -
NOT the same thing as `src/command/` (the tokenizer/tree/dispatcher
library, a port of the separate `crates/pumpkin-command` crate). This
directory uses that library.

## Ported

- **`gamemode.nim`** - `/gamemode <mode>` (self-target form only). Wires
  `src/command/cmdtree.nim`'s node builders + `src/command/gamemodearg.nim`'s
  argument type to `src/server/entity/entity.nim`'s `Player.gamemode`.
  Required one small library change: `CommandSource` (in
  `src/command/cmdsource.nim`) gained a `player*: nil Player` field -
  upstream's `CommandSource.output.as_player()` downcast, needed by any
  command that acts on the issuing player. `gamemodetest.nim` exercises
  it through a real `Tree`/`dispatch` walk (register → parse →
  execute), not just a direct proc call.

  Not ported from `gamemode.rs`: the `<target>` multi-player form (needs
  `EntityArgumentType::Players`, an entity-selector argument type not in
  `src/command/argtype.nim`'s `ArgValue` union yet, plus a player
  registry to resolve selectors against), permission-registry
  registration (needs the unported `pumpkin_util::permission` module),
  and the translated feedback messages (`TextComponent::translate_cross`
  → plain strings, same simplification the rest of this port already
  uses for unported `text`).

## Not started

The other ~30 command files under `upstream-ref/crates/pumpkin/src/command/commands/`,
ranging from trivial (`say.rs`, `stop.rs`, `me.rs` - 40-70 lines each,
good next targets) to substantial (`execute.rs` at 1660 lines - the
`/execute` conditional/redirect command, which needs the
`RedirectModifier`/forking support `cmdtree.nim` explicitly deferred).
Most need a player/world registry (a server-wide list of connected
players, which `src/server/world/worldstub.nim` doesn't model) beyond
what `gamemode.nim` needed.

## Runtime-verification status

Same as everything importing `src/server/entity/entity.nim` (now also
true of `src/command/cmdsource.nim`, transitively, via the new `player`
field): `nimony check` passes clean, but `nimony c -r` hits the
closures-through-vtables crash cataloged as bug #1 in
`NIMONY-COMPILER-BUGS.md` (confirmed again here, same signature:
`lambdalifting.nim(369)`/`eraiser.nim(128)`). `gamemodetest.nim` is
check-verified, not runtime-proven.
