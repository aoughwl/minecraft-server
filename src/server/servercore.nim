## The transport-independent server core: world + player registry + basic
## server identity, with no dependency on sockets or the wire protocol.
##
## Split rationale (per the port's standing architecture question: "when
## Jester is itself the host/singleplayer, direct in-process calls should
## be faster than looping packets through TCP loopback"):
##
## - `ServerCore` (this module) is the actual server state and logic:
##   world, players, config. It knows nothing about how a caller reaches
##   it - no socket, no packet framing, no `NetReader`/`NetWriter`.
## - `src/main.nim`'s network-listener code path is ONE transport in front
##   of a `ServerCore`: it decodes wire packets (`src/protocol`) and calls
##   straight into this module's procs.
## - A future embedding host (Jester's `aoughwl.mcserver`/`mcnet`, when it
##   is itself the singleplayer host) is a SECOND transport in front of
##   the same `ServerCore`: instead of encoding/decoding packets over a
##   loopback socket, it calls `newServerCore()`/`.tick()`/etc. directly
##   as plain Nimony procs from the same process. See `startEmbeddedServer`
##   below - it's deliberately just a thin constructor, because "embedded
##   mode" IS the core with no transport wrapped around it, not a
##   different code path that needs to stay in sync with the networked one.
##
## Anything added to the server's actual behavior (world ticking, command
## dispatch, event bus) belongs in `ServerCore` or something it owns, NOT
## in `main.nim` or a future `hostmode.nim` - those may only decode/encode
## and forward.

import world/worldstub
import playerregistry
import ../config/world as worldcfg

type
  ServerCore* = ref object
    world*: World
    players*: PlayerRegistry
    levelConfig*: LevelConfig
    motd*: string
    tickCount*: uint64

proc newServerCore*(motd: string = "A Nimony Minecraft Server"): ServerCore =
  ## The one constructor both transports (networked `main.nim` and a
  ## future embedded host) call. Nothing here differs between the two -
  ## that's the point of the split.
  ServerCore(
    world: newWorld(),
    players: newPlayerRegistry(),
    levelConfig: defaultLevelConfig(),
    motd: motd,
    tickCount: 0'u64,
  )

proc tick*(core: ServerCore) =
  ## One server tick. Currently just advances the counter - real
  ## world/entity/scheduler ticking (src/world/tick.nim,
  ## src/scheduler) hooks in here as it's wired up. Both transports
  ## should drive ticks by calling this, not by reimplementing a loop.
  core.tickCount += 1'u64

proc playerCount*(core: ServerCore): int {.inline.} =
  core.players.players.len

proc startEmbeddedServer*(motd: string = "A Nimony Minecraft Server"): ServerCore =
  ## Entry point for an in-process embedding host (e.g. Jester's
  ## `aoughwl.mcserver` calling directly into this library instead of
  ## going through `aoughwl.mcnet`'s socket-based wire protocol). Returns
  ## a live `ServerCore` the host drives by calling `tick()` and the
  ## world/player-registry procs directly - no packet encode/decode, no
  ## socket, no loopback round-trip.
  ##
  ## The Nimony<->host C-ABI export shape (proc names, calling convention,
  ## how Jester's build links against this) is intentionally NOT decided
  ## here yet - this proc is the seam a future pass wraps in `{.exportc.}`/
  ## a thin C header once that FFI design happens. What matters now is
  ## that the seam exists and nothing upstream of it needs to change.
  newServerCore(motd)
