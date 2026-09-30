## C ABI export of `ServerCore` for an in-process embedding host (Jester's
## `aoughwl.mcserver`, via `dynlib`-loading this module compiled with
## `--app:lib`) to call directly, bypassing minecraft-server's own TCP
## transport (`src/main.nim`) entirely. See `servercore.nim`'s header for
## the transport-split rationale.
##
## `ServerCore` is a Nimony `ref object` (GC'd) and must not cross the C ABI
## boundary raw. Instead, live instances are kept in a process-local table
## here and handed out as opaque integer handles (`cint`); the host passes
## the handle back on every call. Handle 0 is reserved/invalid.

import servercore

var
  cores: seq[ServerCore] = @[]
  ## `cores[handle - 1]` is the ServerCore for `handle`. Never shrinks or
  ## reorders, so handles stay valid for the process lifetime.

proc mcsCreate(motdPtr: cstring): cint {.exportc: "mcs_create", cdecl.} =
  ## Creates a new ServerCore and returns its handle (>= 1), or 0 on failure.
  var motd = "A Nimony Minecraft Server"
  if motdPtr != nil:
    motd = fromCString(motdPtr)
  let core = startEmbeddedServer(motd)
  cores.add(core)
  cint(cores.len)

proc mcsTick(handle: cint): cint {.exportc: "mcs_tick", cdecl.} =
  ## Advances one server tick. Returns 0 on success, -1 for a bad handle.
  let idx = int(handle) - 1
  if idx < 0 or idx >= cores.len:
    return cint(-1)
  tick(cores[idx])
  cint(0)

proc mcsPlayerCount(handle: cint): cint {.exportc: "mcs_player_count", cdecl.} =
  ## Returns the current player count, or -1 for a bad handle.
  let idx = int(handle) - 1
  if idx < 0 or idx >= cores.len:
    return cint(-1)
  cint(playerCount(cores[idx]))

proc mcsTickCount(handle: cint): int64 {.exportc: "mcs_tick_count", cdecl.} =
  ## Returns the total ticks run so far, or -1 for a bad handle.
  let idx = int(handle) - 1
  if idx < 0 or idx >= cores.len:
    return -1'i64
  int64(cores[idx].tickCount)

proc mcsWorldLoaded(handle: cint): cint {.exportc: "mcs_world_loaded", cdecl.} =
  ## Returns 1 if the handle is valid and has a world loaded, 0 otherwise.
  let idx = int(handle) - 1
  if idx < 0 or idx >= cores.len:
    return cint(0)
  cint(1)

## Packet-shaped data injection/retrieval (the eventual replacement for
## socket-based wire packets, per servercore.nim's split) is NOT implemented
## yet - ServerCore itself has no packet-level API to wrap. Follow-up work
## once ServerCore grows real world-tick/command-dispatch/event-bus hooks.
