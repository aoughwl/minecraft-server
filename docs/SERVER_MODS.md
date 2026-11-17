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
| `jester:wind` sender (INIT, UPDATE, TIME_SYNC) | **real** (`src/server/net/jester/windsync.aowl`) |
| Wind, materials and the structural solver for a mod | **real** (`windAt`, `materialByName`, `materialAt`, `massOf`, `solveRegion`) |
| Mod sync (`jester-mods.json`, MANIFEST/STATUS, hold the join) | **real** |
| Body stream and fx: the message encoders and decoders | **real** (`src/server/net/jester/{bodymsg,fxmsg}.aowl`); nothing sends them yet |
| Bodies as entities, fx sending | **planned** |
| Distant-terrain summaries (`jester:lod`, capability `lod`) | **real** (`src/server/net/jester/lodsync.aowl`, section 11) |
| Custom blocks, items, entities, registries | **planned**, design in `docs/REGISTRIES.md` |
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

Names: `physics2`, `wind`, `bodystream`, `modsync`, `fx`, `materials`, `cui`, `lod`. `physics2` is dropped unless `bodystream` and `fx` are granted too;
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

## 5. A wind-reactive block (real, polling)

The server's wind field, the material table and the structural solver are callable from a plugin:

```nim
proc gust(e: var TickEndEvent) =
  if e.tick mod 20 == 0:
    let w = windAt(10.0, 70.0, 10.0)                  # blocks per second at the overworld's current game time
    if w.speed > 12.0 and blockAt(10, 64, 10) == "minecraft:torch":
      discard setBlock(10, 64, 10, "minecraft:air")   # the storm blows the torch out
registerEvent(gust)
```

| Call (aowlmony / JavaScript `server.`) | Answers |
|---|---|
| `windAt(x, y, z)` | `Wind`: `x, y, z, speed` in blocks/second |
| `materialByName("stone")`, `materialAt(x, y, z)` | `MaterialInfo`: `known`, `matClass`, `density`, `fill`, `stiffness`, `damping`, `tensile`, `compressive` (MPa), `dragArea`, `breakThreshold`, `flammability`, `ignitability`, `liquid`, `indestructible` |
| `massOf("stone", volume)` | kilograms of `volume` cubic metres (a full block is 1) |
| `solveRegion(x, y, z, nx, ny, nz, floorAnchored = true, wind = false)` | `SolveResult`: `ok`, `error`, `maxRatio`, `converged`, `rounds`, `granular`, `caveIns`, `components` and `broken`: a list of `{x, y, z, ratio, kind}` |

`solveRegion` reads the overworld box from its minimum corner (at most 32 768 blocks; unloaded chunks count as air), runs the solver of `src/physics/solver.aowl`
through its adapter, and reports which blocks would fail and how (`bending`, `shear`, `crush`, `tension`, `hang`, `unsupported`). With `floorAnchored` the bottom
layer holds the structure up; otherwise only indestructible blocks do. With `wind` the wind field's drag at the cells is added as load. It reports; it does not break
blocks. The numbers come from the table in `src/physics/materials.aowl`, calibrated in `src/physics/solveradapter.aowl` (its header lists the calibration honestly).
The call runs on the tick thread: keep regions small or call it rarely.

JavaScript:

```js
on(TickEndEvent, function (e) {
  if (e.tick % 100 !== 0) return;
  var r = server.solveRegion(100, 64, 100, 8, 8, 8, { wind: true });
  if (r.ok && r.broken.length) server.broadcast(r.broken.length + " blocks would fail, worst ratio " + r.maxRatio.toFixed(2));
});
```

## 6. A custom block (planned)

Registering a new block (state ids, a model for the client, behaviour) needs the registries work: blocks, states, items, entity types, a stable
per-world id map and synchronisation in the configuration phase. None of that exists, so a plugin can only reuse vanilla blocks. When it
exists, a custom block will be declared in the plugin and synced to a client that granted `modsync`.

## 6b. Mod sync (real)

A `jester-mods.json` in the server folder lists the client mods the server cares about:

```json
{ "policy": "advisory",
  "kick_message": "Install the mods listed on our website.",
  "mods": [
    { "id": "aoughwl:wind", "version": "0.9.0", "role": "required", "sha256": "<64 hex digits>", "size": 48213, "url": "" },
    { "id": "aoughwl:kinetic", "version": "0.3.0", "role": "optional", "sha256": "", "size": 0, "url": "https://example.org/kinetic" } ] }
```

`policy` is `advisory` (list only) or `enforce` (turn a client away whose `required` mod is missing or does not match). `role` is `required`, `optional` or `server-only`.
When the file exists and lists mods the server advertises `modsync`. A client that granted it gets the `jester:modsync` MANIFEST in the configuration phase and the join
waits (up to 15 s) for its STATUS: under `enforce` a missing or mismatched required mod, or no answer in time, ends in a disconnect with `kick_message`; under `advisory`
the join proceeds. A plugin reads what a client reported with `p.modState(modId)`: 0 ok, 1 missing, 2 hash mismatch, 3 version mismatch, 4 disabled by the player,
-1 nothing reported. A malformed file is logged and ignored. The file is read at server start. Behaviour depends on the ids you list (data), never on names in code.

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

## 10. Finite fluids (real, optional, off by default)

`src/physics/fluids.aowl` (pure conserved-volume model) + `src/server/fluids/` (host, `/fluids on|off|status`, op level 3): water and lava as a volume per
cell, pressure-style flow, a per-tick cell budget, every change written through `bulkedit.writeCells`. Off = vanilla, untouched. See docs/FLUIDS.md
(also the level 1, client-only visual version).

## 11. Distant-terrain summaries: `jester:lod` (real, built in)

A client that offers the `lod` capability (bit 7) gets, for every chunk column past its view distance out to a radius, a summary: per
4 x 4 cell the top block's y and state, the water depth over the floor and the floor block, and the biome (wire format: overnight/PROTOCOL.md
section 10, `src/server/net/jester/lodmsg.aowl`). Nearest ring first, packed under the client's `max_frame`. A vanilla client never sees it.

Sources, cheapest data first: the shared cache; a chunk the level holds (exact, `summarizeChunk`); otherwise the noise stage only
(`src/world/generation/lodsummary.aowl` `summarizeNoise`: corner densities, aquifer and cell caches walked top down to the first block, no
surface rules, carvers or features; the dry-land top is guessed from the biome). Noise summaries run on the chunk worker pool's low-priority
lane (`generation_executor.submitLod`: a worker takes one only when no generation job waits), or inline within `MC_LOD_INLINE_MS` a tick
when there are no workers.

The client's FLOW word (voxel's load gate: hold while the near terrain loads, go once it is drawn) pauses that client's summaries and is
the pre-generator's go/hold word too, so `/pregen` is throttled by a remote client without the signal file.

| Variable | Default | Meaning |
|---|---|---|
| `MC_LOD_RADIUS` | 64 | chunks covered (at most 128; 0 turns the channel off and stops advertising `lod`) |
| `MC_LOD_COLUMNS_PER_TICK` | 64 | columns sent to one player per tick |
| `MC_LOD_INFLIGHT` | 2 per worker, at least 4 | noise jobs on the pool at once |
| `MC_LOD_INLINE_MS` | 3 | tick-thread allowance for noise summaries when the pool has no workers |

Test: `sh tools/run_scenarios.sh <exe> lod_summaries` (`LOD_TEST_RADIUS`, default 24).
