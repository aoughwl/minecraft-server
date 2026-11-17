# Server mods

A server mod is a plugin (see `docs/PLUGINS.md`) that cooperates with a modded client, here the Jester client, beyond what a vanilla
client understands. This page says what a server mod can do **today**, with examples that run, and what is **planned** and not there yet.
Every section starts with its status.

| Part | Status |
|---|---|
| Custom payload channels (send, receive, declared channels) | **real** |
| Capability handshake (`jester:hello` / `jester:welcome`), per-player capabilities | **real** |
| Tick-phase hooks and scheduled tasks | **real** |
| Reading and writing blocks | **real** (overworld, one block at a time) |
| Live scripting console (`/script`) | **real** (JavaScript) |
| Scenario tests | **real** (`tools/run_scenarios.sh`) |
| Wind field for a mod | **planned** (the service exists in `src/physics`, plugins cannot reach it yet) |
| Body stream (`jester:bodies`), fx (`jester:fx`), modsync | **planned** (specified in `overnight/PROTOCOL.md`, the server side is not written) |
| Custom blocks, items, entities, registries | **planned** |
| Threads and a job system for mods | **planned** |

Where this page and the code disagree, the code is right; `docs/PLUGINS.md` lists the whole plugin API.

## 1. A payload channel (real)

A channel is a `namespace:path` id. The client declares the channels it listens on with `minecraft:register`, and either side then sends
bytes on them. The server tracks what each client declared.

aowlmony (`examples/hello-world/main.aowl` does exactly this):

```nim
import pluginsdk

proc payloadEcho(e: var CustomPayloadEvent) =
  # a client message on "showcase:echo" is answered on "showcase:reply" with the bytes reversed
  if e.channel == "showcase:echo":
    var back: seq[byte] = @[]
    var i = e.data.len - 1
    while i >= 0:
      back.add e.data[i]
      dec i
    discard e.player.sendPayload("showcase:reply", back)

registerEvent(payloadEcho)
```

JavaScript:

```js
on(CustomPayloadEvent, function (e) {
  if (e.channel === "showcase:echo") {
    e.player.sendPayload("showcase:reply", e.data.slice().reverse());   // data is an array of numbers 0..255
  }
});
```

* `p.sendPayload(channel, bytes)` is false when the player is not online. `p.hasChannel(channel)` and `p.channels()` answer from what
  the client declared (a client that never registered has none; the server does not require registration to receive).
* `CustomPayloadEvent` carries `channel`, `length` and the whole `data`. Cancelling it has no effect on the server (nothing else listens).
* Limits: the client sends at most 32 767 bytes of data per packet; the server targets at most 16 000 bytes per frame
  (`overnight/PROTOCOL.md` section 0). The host does not split larger buffers for you.
* Between plugin and host the bytes travel as hex text, so any byte (zero included) is safe. That is a transport detail.

## 2. Capabilities (real)

A client that speaks the Jester protocol sends `minecraft:register` and `jester:hello` while the server configures it, offering the
capabilities it has; the server answers with `jester:welcome` listing what it granted: the intersection of what the client offered and
what server mods **advertise**. Nothing is advertised by default, so a server without a mod grants nothing and the client stays at level 1.

```nim
discard advertiseCapability("wind")      # at the top level of your plugin: the server mod offers wind sync

proc windFor(e: var JoinEvent) =
  if e.player.hasCapability("wind"):
    discard e.player.tell("wind sync is on for your client " & e.player.jesterVersion())

registerEvent(windFor)
```

JavaScript: `server.advertiseCapability("wind")`, `player.hasCapability("wind")`, `player.jesterVersion()`.

Names: `physics2`, `wind`, `bodystream`, `modsync`, `fx`, `materials`, `cui`. `physics2` is dropped unless `bodystream` and `fx` are granted too;
`bodystream` is dropped for a client whose frame limit is under 16 000. `hasCapability` is false for a player who never said hello. A
`jester:hello` sent again in play re-negotiates (the result replaces the earlier one).

Advertising a capability promises the client that the server will behave accordingly. Advertise only what a mod really provides.

## 3. A tick-phase hook (real)

`TickStartEvent` and `TickEndEvent` run around every server tick (`tick`, and for the end event `durationNs`).

```nim
var worst = 0

proc watchTick(e: var TickEndEvent) =
  if e.durationNs > worst:
    worst = e.durationNs
  if e.tick mod 600 == 0:
    log("slowest tick in the last 30 s: " & $(worst div 1000000) & " ms")
    worst = 0

registerEvent(watchTick)
```

For work that is not tied to the tick boundary use `after(ticks, handler)` and `every(ticks, handler)`. These handlers run on the tick
thread, so keep them short. A plugin runs inside the engine, not as a server thread: threads for mods are planned, not available.

## 4. Reading and writing blocks (real)

`blockAt(x, y, z)` gives the block's name, `setBlock(x, y, z, name)` places one (overworld only). This is enough for a block that reacts
to something by polling:

```nim
proc dryOut(e: var TickEndEvent) =
  if e.tick mod 20 == 0 and blockAt(10, 64, 10) == "minecraft:water":
    discard setBlock(10, 64, 10, "minecraft:air")

registerEvent(dryOut)
```

Per-block events exist as well (`BlockChangeEvent`, `PistonEvent`, `FurnaceSmeltEvent`, ...; see `docs/EVENTS.md`). The block change event is
busy: the server only offers it while some plugin subscribes.

## 5. A wind-reactive block (planned)

The wind field service and the material table are written (`src/physics/`), but no plugin call reads them yet. What a mod will do once it
does is query the wind at a position and react:

```nim
# PLANNED, does not run: there is no windAt in the SDK yet
proc gust(e: var TickEndEvent) =
  if e.tick mod 20 == 0:
    let w = windAt(10.0, 70.0, 10.0)       # a vector, blocks per second
    if w.speed > 12.0 and blockAt(10, 64, 10) == "minecraft:torch":
      discard setBlock(10, 64, 10, "minecraft:air")
registerEvent(gust)
```

Today a plugin can approximate that with its own state and the tick hook; it cannot see the field the physics uses.

## 6. A custom block (planned)

Registering a new block (state ids, a model for the client, behaviour) needs the registries work: blocks, states, items, entity types, a stable
per-world id map and synchronisation in the configuration phase. None of that exists, so a plugin can only reuse vanilla blocks. When it
exists, a custom block will be declared in the plugin and synced to a client that granted `modsync`.

## 7. The scripting console (real, JavaScript)

An operator (or the console) can run a snippet on the engine without writing a plugin:

```
/script print("online: " + server.onlineCount())
/script @snippet.js                         a file, read again on every run
```

The snippet runs as a plugin of its own that is unloaded again afterwards; `print` (the same as `server.log`) sends output back to whoever ran the
command, and a thrown error comes back as `error: ...`. Without `AOE_PLUGIN_WORKERS=1` all JavaScript plugins share one program, so each run
restarts them (twice); with worker mode only the snippet's process is started. aowlmony snippets are not supported (they need a compile).

## 8. Testing a mod (real)

`tools/run_scenarios.sh <server exe> [scenario,...|all]` starts a scratch server on a spare port (`PORT`, default 25590), installs the
showcase plugin, plays a bot through scenarios and prints one line each:

```
SCENARIO payload_roundtrip      PASS           0.2s
SCENARIO capability_handshake   INCONCLUSIVE   0.0s the showcase plugins are not loaded ...
```

`PASS` means every check held, `FAIL` that one did not (the run exits non-zero), `INCONCLUSIVE` that the scenario could not test what it is about
(a precondition is missing); it never counts as a pass or a failure. Write a scenario in `tools/mcbot_scenarios.py` with the `@scenario`
decorator; the helper `s` (see the header of that file) can run commands, read chat, blocks and chunks as a client knows them, send
payloads and wait for the server's. The bot does not track entities yet. `WORLD=<folder>` starts from an existing world instead of a fresh one.

## 9. WorldEdit (real, built into the server)

`src/server/worldedit/` is a WorldEdit-style editor, op level 2. Commands are registered as `/set`, `/pos1`, ... so a client types `//set stone`;
`/we <name> <args>` reaches the same code. Selection: `//pos1 [x,y,z]`, `//pos2`, `//sel`, `//size`, and `//wand` (wooden axe: left click
a block for pos1, right click for pos2). Edits: `//set`, `//replace <mask> <pattern>`, `//walls`, `//hollow`, `//sphere [-h]`, `//cyl [-h]`,
`//copy`, `//cut`, `//paste [-a] [-s]`, `//rotate`, `//flip`, `//stack`, `//move [-s]`, `//count`, `//distribution [-d]`, `//undo [n]`, `//redo [n]`.
Patterns are `stone`, `50%stone,50%dirt`, `oak_stairs[facing=east]`; masks `stone,dirt`, `!air`, `*`.

Every edit goes through `bulkedit` (one light pass, one client update per section, block entities kept, block log entries with the command
cause). Undo keeps the pre-edit section snapshot, so it restores block states and block entities exactly. Limits: 4 000 000 cells per edit,
64 undo entries and 24 M cells of history per player. Not done: `//rotate` about x or z, region shapes other than cuboid, schematics, biomes.

`worldedit:cui`: a client that registered the channel, sent `v|<n>` on it, or holds the Jester `cui` capability receives `s|cuboid` and
`p|<0|1>|x|y|z|volume` (UTF-8 text, one per packet) whenever its selection changes.
