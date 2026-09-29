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

- **`stop.nim`** - `/stop`. The simplest command in the file: no
  arguments, just feedback + a shutdown call. Upstream's `stop_server()`
  (a real process-level shutdown) has no equivalent in this port yet, so
  `CommandSource` gained a `stopProc*: proc() {.closure.}` field (`nil` =
  safe no-op) alongside `sendMessageProc`'s existing shape. `stoptest.nim`
  drives it through a real dispatch walk and confirms `stopProc` fires.

- **`say.nim`** / **`me.nim`** - `/say <message>` and `/me <action>`,
  structurally identical (upstream shares the shape - a single greedy
  string argument broadcast to all players). Neither has a real
  `Server`/player-registry to broadcast through, so `CommandSource`
  gained `displayName*: string` and `broadcastProc*: proc(message,
  senderName: string) {.closure.}` (falls back to echoing to the issuing
  source alone when `nil`). `saymetest.nim` drives both through a real
  dispatch walk and confirms the broadcast callback receives the right
  message/sender.

  Not ported from either: permission-registry registration, and the
  translated `SAY_COMMAND`/`EMOTE_COMMAND` message-type tags (need
  unported `pumpkin_data`/`text` modules) - messages are broadcast as
  plain strings, same simplification `gamemode.nim` already uses.

- **`tps.nim`** - `/tps`. No arguments; reports server tick-rate/MSPT.
  `CommandSource` gained `tpsProc*`/`msptProc*: proc(): float64
  {.closure.}` (both `nil` = report 0.0) since no `Server`/tick-loop type
  exists yet. `NamedColor`-coded feedback (green/yellow/red by tick
  health) is dropped - plain string, same simplification as everywhere
  else. Verified via `tpsreloadreturntest.nim`'s `tpsBlock`.

- **`reload.nim`** - `/reload`. No arguments; announces then reloads
  datapacks. `CommandSource` gained `reloadProc*: proc() {.closure.}`
  (`nil` = safe no-op), matching `stopProc`'s shape exactly. Verified via
  `tpsreloadreturntest.nim`'s `reloadBlock`, confirms `reloadProc` fires.

- **`returncmd.nim`** - `/return <value>`, `/return fail`, `/return run
  ...`. Named `returncmd.nim`, not `return.nim` - `return` is a reserved
  word in Nimony. The `run` branch's redirect-to-root uses
  `cmdtree.nim`'s existing simple-target `setRedirect`, no new tree
  machinery needed (upstream's own `Redirection::Root` is exactly that
  simple case, not a fork). Verified via `tpsreloadreturntest.nim`'s
  `returnValueBlock`/`returnFailBlock` (both dispatch-walked, including
  the integer-argument parse path via `newIntegerArgumentType()`).

  Not ported: permission-registry registration (same simplification as
  every other command file here).

- **`saveoff.nim`** / **`saveon.nim`** - `/save-off` / `/save-on`.
  Upstream iterates `context.server().worlds`, toggling each
  `Level.save_enabled` and reporting whether any world's state actually
  changed (the already-off/already-on error case). No world registry
  exists in this port, so `CommandSource` gained
  `setSaveEnabledProc*: proc(enabled: bool): bool {.closure.}` - `nil`
  falls back to reporting "changed" unconditionally. Verified via
  `saveseedtest.nim`, including the already-off repeat-call case.

- **`seed.nim`** - `/seed`. Reports the world seed. `CommandSource`
  gained `getSeedProc*: proc(): int64 {.closure.}` (`nil` = `0`) since
  no `World`/`Level.seed` field is wired through a command source yet.
  The click-to-copy/hover-tooltip feedback (`ClickEvent`/`HoverEvent`,
  needs the unported `text` module) is dropped for a plain string.
  Verified via `saveseedtest.nim`.

- **`difficulty.nim`** - `/difficulty` (query) and `/difficulty
  <peaceful|easy|normal|hard>` (set). `CommandSource` gained
  `difficultyProc*`/`setDifficultyProc*` (`nil` falls back to `Normal`
  / a no-op) since no `Server`/`Level` type exists yet, matching
  `tpsProc`'s shape. Builds on `src/util/difficulty.nim` (already
  ported). Verified via `difficultytest.nim`'s three blocks (query,
  set, already-set failure) through real Tree/dispatch walks; hit and
  worked around a new Nimony diagnostic bug along the way (two
  closures in one object-constructor call sharing a captured local
  broke "prove initialized" for later uses of it - see
  `NIMONY-COMPILER-BUGS.md` #13). Same `nimony c -r` caveat as every
  other file here (bug #1, confirmed again with the same
  `lambdalifting.nim(369)`/`eraiser.nim(128)` signature).

- **`defaultgamemode.nim`** - `/defaultgamemode <mode>`. First command in
  this directory to need an actual player registry rather than a
  single-field `CommandSource` stand-in: `context.server().get_all_players()`
  is now backed by `src/server/playerregistry.nim`, a minimal in-memory
  `seq[Player]` registry (lookup-by-uuid/lookup-by-name/broadcast - NOT
  the full async multi-client server, that's still correctly deferred
  pending a concurrency-model decision, same as everywhere else in this
  port). `CommandSource` gained `playerRegistry*: nil PlayerRegistry`
  and `forceGamemode*: bool` (standing in for
  `server.basic_config.force_gamemode` - no `BasicConfiguration` type
  exists yet). `defaultgamemodetest.nim` drives 4 real dispatch-walk
  cases: force-on changes every non-matching player and reports the
  right count, force-off changes nothing, a nil registry is safe
  (0 changes, not a crash), and invalid-mode parsing still fails
  correctly. Not ported: permission registration, the translated
  feedback message, and persisting the new default onto a `Server`
  type (none exists to persist it on).

- **`saveall.nim`** - `/save-all` and `/save-all flush` (upstream registers
  the same executor under both literals - kept as two real tree nodes,
  not collapsed). `CommandSource` gained `saveAllProc*: proc() {.closure.}`
  (`nil` = safe no-op), matching `stopProc`'s shape. Async task-spawn
  dropped (called synchronously, assumed to succeed - no concurrency
  model exists in this port yet). Verified via `savelistkilltest.nim`'s
  `saveAllBlock`.

- **`list.nim`** - `/list` and `/list uuids`. First file to actually READ
  `src/server/playerregistry.nim`'s registry (`defaultgamemode.nim` only
  wrote through it). `CommandSource` gained `maxPlayersProc*: proc(): int32
  {.closure.}` (`nil` falls back to the connected-player count itself,
  i.e. "full") since no per-client-platform `AdvancedConfiguration` type
  exists. A `nil` registry reports zero players rather than crashing,
  matching `defaultgamemode.nim`'s nil-is-safe precedent. Verified via
  `savelistkilltest.nim`'s `listEmptyBlock`/`listWithPlayersBlock`.

- **`kill.nim`** - `/kill`, self-target form only. The `<targets>`
  multi-entity form needs `EntityArgumentType::Entities`, an
  entity-selector argument type not in `src/command/argtype.nim`'s
  `ArgValue` union yet (same blocker `gamemode.nim`'s `<target>` form
  cites). `target.kill()` becomes a direct `health = 0` +
  `removalReason = (true, rrKilled)` write - no real death
  event/drops/XP behaviour exists yet. Verified via
  `savelistkilltest.nim`'s `killNoPlayerBlock`/`killSelfBlock`.

Not ported from any of the three: permission-registry registration and
translated feedback text, same simplifications every other file here
already uses.

## Not started

The other ~15 command files under `upstream-ref/crates/pumpkin/src/command/commands/`,
ranging from small (`tellraw.rs` ~42 lines - needs `EntityArgumentType::Players`,
an entity-selector argument type not in `src/command/argtype.nim`'s
`ArgValue` union yet, plus `ComponentArgumentType` for the unported
`text` module) to substantial (`execute.rs` at 1660 lines - the
`/execute` conditional/redirect command, which needs the
`RedirectModifier`/forking support `cmdtree.nim` explicitly deferred).
`src/server/playerregistry.nim`'s minimal player registry (see
`defaultgamemode.nim`/`list.nim`/`kill.nim` above) now covers the "needs
a list of connected players" blocker several of these previously cited -
worth re-checking each file's real dependencies before assuming it's
still blocked the same way, the same lesson `defaultgamemode.rs` itself
already taught.

- **`setidletimeout.nim`** - `/setidletimeout <minutes>`. Single
  non-negative-integer argument, gated at the parser via
  `newIntegerArgumentType(min = 0)`. `CommandSource` gained an
  `idleTimeoutProc*: proc(minutes: int32) {.closure.}` field standing in
  for `context.server().player_idle_timeout.store(...)` (no `Server`
  type in this port yet). `setidletimeouttest.nim` drives it through a
  real Tree/dispatch walk.

  **Important finding from this file**: it imports neither `entity.nim`
  nor `cmdsource.nim`'s `player` field's type, yet `nimony c -r` still
  hits the exact same closures-through-vtables crash. That proves the
  crash isn't specific to `Entity`/`Player` at all - `src/command/
  cmdtree.nim`/`cmddispatch.nim`'s own `Command`/`Requirement`
  closure-typed fields are sufficient on their own. See
  `NIMONY-COMPILER-BUGS.md` #1's "Further refinement" note.

## Runtime-verification status

Same as everything importing `src/server/entity/entity.nim` (now also
true of `src/command/cmdsource.nim`, transitively, via the `player`
field - and by extension every file in this directory, since they all
import `cmdsource.nim`, even `stop.nim` which has no direct `Player`
need of its own): `nimony check` passes clean, but `nimony c -r` hits
the closures-through-vtables crash cataloged as bug #1 in
`NIMONY-COMPILER-BUGS.md` (confirmed again here for `stoptest.nim`,
same exact signature: `lambdalifting.nim(369)`/`eraiser.nim(128)`).
`gamemodetest.nim`/`saymetest.nim`/`stoptest.nim`/`setidletimeouttest.nim`/
`savelistkilltest.nim` are all check-verified, not runtime-proven - and
`setidletimeouttest.nim` specifically shows the crash's real trigger is
`src/command/`'s own closure-vtable types (`cmdtree.nim`/`cmddispatch.nim`),
not `entity.nim` as earlier files' doc comments implied.
`savelistkilltest.nim` confirms the identical signature again
(`lambdalifting.nim(369,3)`/`eraiser.nim(128,3)`), run directly via
PowerShell to double-check it's not a regression.
