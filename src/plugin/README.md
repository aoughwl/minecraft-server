# plugin (port of pumpkin/src/plugin, pumpkin-plugin-api, pumpkin-macros, pumpkin-api-macros)

## Runtime survey (phase 1, 2026-11-11)

Upstream hosts plugins as WebAssembly components on wasmtime. aowlmony has no wasmtime, so the first question
was which engine to use. What exists on this machine, searched under `dev/`, `Desktop/` and `C:\msys64`:

| candidate | where | verdict |
|---|---|---|
| wasmtime, wasm3, WAMR, wabt, wasm-tools, cargo, rustc | nowhere (no binary, no source, no static lib; `libwamreg.a` in msys is the Windows registry shim, not WAMR; msys only has `wasm-ld` and `liblldWasm.a`, a linker) | unusable |
| aowlwasm (`dev/aowlwasm`, `dev/aoe-web-*`) | a WASM and JS *generator* (aowlmony IR to .wasm), not an executor | wrong direction; useful only for producing test modules |
| node (`C:\Program Files\nodejs`) | has WebAssembly, but is a separate process, no component model | not embeddable, rejected |
| **titicaca's `webwasm.aowl` + `webwasmrt.aowl`** (`Desktop/jester_data/apps/titicaca/basemods/aoughwl.web.dom`, also `dev/titicaca/src`) | a pure, stdlib-only WebAssembly decoder, validator (full spec: GC, SIMD, exceptions, tail calls, multi-memory, bulk memory) and interpreter with host functions, written in aowlmony | **chosen for core modules** |
| titicaca's `jsdomwasm.aowl` | the JS API binding over those two files; shows how to bind host functions and instantiate | read as the usage reference |

Decision: reuse `webwasm` + `webwasmrt` (copied unchanged but for a header, so the wasm runtime stays in step with
titicaca; copy lives in `src/plugin/wasm/`), wrapped by `wasmvm.aowl` (one store per plugin, host closures,
linear-memory helpers). It runs real Rust-compiled core modules (those only use core wasm 1.0/2.0 plus the
features rustc enables). It does not know the component model, so the component binary format, the canonical ABI
(lift/lower of strings, lists, records, variants, options, results, resources) and a linker that wires a component's
imports to host interfaces are written here (`component*.aowl`). Binding a C runtime was not an option (none exists);
writing a fresh interpreter would only duplicate webwasmrt.

Costs to know: the interpreter keeps memory as one `int` per byte on the bank and is a plain bytecode loop, so it is
far slower than wasmtime's compiled code. Plugins are event handlers, so that is acceptable; a hot-path plugin would
notice.

## Missing inputs

- `ref/pumpkin-1.21.11/pumpkin-plugin-wit/` is an empty git submodule directory in the pinned checkout: the WIT files
  are not there. The newer tree `ref/pumpkin/crates/pumpkin-plugin-wit/{v0.1,v0.2}` has them (93 files, 33k lines), and
  the pinned loader is `wasm_host/wit/v0_1`, so v0.1 from the newer tree is the interface source.
- No rustc or cargo here, so no real Rust-built plugin component is available as a fixture. Components used in tests
  are assembled by hand.

## Layout and status

    src/plugin/wasm/webwasm.aowl      decoder + validator (copied from titicaca)
    src/plugin/wasm/webwasmrt.aowl    store + interpreter (copied from titicaca)
    src/plugin/wasm/wasmvm.aowl       host layer over the two: WasmVm, host functions, memory access
    src/plugin/wasm/canonabi.aowl     component model values (CmType/CVal) and the canonical ABI: flatten, align/size,
                                      lift/lower of scalars, strings (utf8, utf16), lists, records, tuples, variants,
                                      options, results, enums, flags, own/borrow handles, spilling past 16 flat params
    src/plugin/wasm/component.aowl    component binary decoder and linker (core modules, core instances, aliases, canon
                                      lift/lower/resource.drop, instance imports, exports) and callExport
    src/plugin/pluginhost.aowl        host side: PluginHost, host interfaces (logging, context, command), loadPlugin,
                                      fireEvent
    src/plugin/pluginmgr.aowl         the server's plugin manager: scans plugins/*.wasm, registers plugin commands in the
                                      fallback dispatcher, fires player join/leave

    src/plugin/wit/                   host interfaces, one file each, registered by witall.aowl (installWitInterfaces):
                                      wittext (text-component), witscheduler, witbossbar, witworld (world resource),
                                      witsrv (server resource), wituuid, witi18n; witstate.aowl holds their shared
                                      state (text arena, boss bars, the `WitHooks` closures into the server)
    src/plugin/pluginwire.aowl        fills `WitHooks` from the real Server (worlds, players, blocks, boss bar packets)
    src/plugin/signature.aowl         pumpkin.metadata / wasm_signature sections and the verification flow (no Ed25519 yet)

Tests (each is a `*test.aowl`, run with `python tools/run_tests.py plugin`):

    wasmvmtest        hand-assembled core module: host import called from wasm, wasm export called from host, memory both ways, a trap
    canonabitest      layout and flat/memory known answers, variant joining, strings, lists, handles, >16 param spill
    componenttest     hand-built component in wit-component's shape (shim + fixup modules, canon lower/lift): host to guest and guest to host calls with strings
    wit/witifacetest  every interface above called through the registry with lifted CVal arguments, against fakes
    wit/witcomptest   a hand-built component importing scheduler, world, text, boss-bar and server: on-load schedules
                      a task, handle-task sets a block and shows a boss bar (`--write FILE X Y Z STATE NAME DELAY`
                      writes it for the over-the-wire run with `mcbot.py --plugin`)
    signaturetest     custom-section scanning, strip, metadata/envelope parsing, verifier payload, error branches
    pluginhosttest    a hand-built plugin against v0.1-shaped interfaces: logs on load, registers command `hello` and a join
                      handler; the test runs the command through the dispatcher and fires a join event

Player interfaces (wit/witplayer, witentity, witeventsplayer, with witserver for the rep lookups): the `player`,
`java-player` (kick only), `entity` and `living-entity` resources are backed by the real server (`Player`,
`EntityBase`, `CommandPlayer`); the player events join, leave, chat, command-send, move, respawn and death are fired
from the server (chat, command and move through the closures of pluginhooks.aowl that play.aowl calls; respawn and
death by chaining `gPlayerRespawnedHook` and `gPlayerHooks.handleKilled`). `pluginhostplayertest` runs a hand-built
plugin that sends a text component to a joining player and cancels chat; `python tools/mcbot.py --wasm-plugin` does the same
over the wire (tools/mcbot_plugin.py). What each file leaves out is its PARTIAL line.

Second batch (witplayer2, witentity2, and more in witworld and witsrv): about 90 more `player` methods (tab list, cameras,
sounds, particles, block change, knockback, links, ban, stats, cooldowns, abilities, ip, skin, ...), the entity box/
passenger/nearby methods, the world's spawn location, game rules, sound, particle, entities and explosions (through the
new `WitHooks.createExplosion`), and `server` command execution, tab-list header/footer and links. `witplayer2test` runs
them through the registry against a real `Server` and `Player` and reads the packets back. State the server has no field
for (permission overrides, movement lock, freeze ticks, hidden players, per-player time/weather) is kept in witplayer2
and only the plugin sees it.

Events fired from the server, beyond the first batch: login (servermod `addPlayer`, a cancel kicks the client), teleport
(`requestTeleport`), change-world (`teleportWorld`), gamemode-change (`setGamemode`), exp-change (chained on
`gPlayerHooks.addExperiencePoints`), item-held, toggle-sneak/sprint/flight and interact (right-click-block), through the new
closures of pluginhooks.aowl. Dispatch is upstream's (`PluginManager::fire`): blocking handlers first in registration
order, each seeing the previous one's edits and able to cancel; non-blocking handlers then run on the result and their
reply is dropped; the WIT `priority` is stored and orders nothing, and a cancelled event still reaches every handler.
`pluginhostplayertest` checks this (`--write FILE login` writes the plugin so that it cancels logins).

Server hooks (small, in other agents' files): `src/server/servermod.aowl` imports `../plugin/pluginmgr`, calls
`startPlugins(server)` after `installCommands`, `firePlayerJoin(player)` after `worldmod.addPlayer` in `addPlayer`, and
`firePlayerLeave(player)` after `handlePlayerLeave` in `removePlayer`.

Not done (also PARTIAL lines in the sources): the other host interfaces (player and entity are the other half's; item-stack,
block-entity, scoreboard, gui, forms, recipe, the managers behind `server`, the chunk and world-border resources, ...) trap with "unimplemented host function"; WASI p2, which
a Rust std plugin imports, is not provided; nested components and guest-defined resources; v0.2 host; signature and
permission enforcement; pumpkin-plugin-api (the guest SDK), pumpkin-macros, pumpkin-api-macros and the wit generators in
pumpkin-codegen are untouched (they need rustc and the WIT-to-aowlmony generator described in src/plugin_api/README.md).

## Manager, WASI and the later interfaces (phase 3)

    src/plugin/wit/witwasi.aowl        WASI preview 2: wasi:cli (environment, exit, stdin, stdout, stderr, terminal-*), wasi:io
                                       (error, poll, streams), wasi:clocks (monotonic, wall), wasi:random (random, insecure,
                                       insecure-seed), the empty wasi:filesystem/preopens. stdout and stderr are line buffered
                                       into the server log as `[plugin] stdout: ...`; the environment only through the
                                       `sys.env` / `sys.env.<KEY>` permissions; `pollable.block` moves a clock skew, it never
                                       sleeps the tick thread
    src/plugin/wit/witstack.aowl       item-stack over the real `ItemStack` (enchantments, custom name, custom data as an
                                       `nbt-tree` flat table with upstream's bounds and cycle errors)
    src/plugin/wit/witblockentity.aowl block-entity and the command-block, sign, jukebox, chest and mob-spawner views, through
                                       `BlockEntityHooks` (pluginwire2.aowl runs them against the worlds' real block entities)
    src/plugin/wit/witscoreboard.aowl  scoreboard (objectives, scores, teams, display slots) through `ScoreboardHooks`
    src/plugin/wit/witgui.aowl         gui, backed by api/gui.aowl (`PluginGui`, `PluginInventory`, `PluginScreenHandler`)
    src/plugin/wit/witrecipe.aowl      recipe-manager: shaped, shapeless and cooking recipes into `server.recipeManager`
    src/plugin/wit/witforms.aowl       the JSON of a Bedrock form from the `form` variant (`serializeForm`; the interface itself
                                       has no host function)
    src/plugin/wit/witall.aowl         `installWitInterfaces` returns the `WitExt` that owns the state and hooks of the above
    src/plugin/api/apimod.aowl         PluginMetadata, PluginState        (plugin/api/mod.rs)
    src/plugin/api/eventsmod.aowl      EventPriority, Cancellable, HandlerMap: `fire`'s blocking-then-non-blocking order
    src/plugin/api/context.aowl        Context: data folder, register / unregister command (namespaced permission, plugin as
                                       the tree's source, commands packet again), register_permission, services, `Plugin`
    src/plugin/api/gui.aowl            PluginGui, PluginInventory, PluginScreenHandler            (plugin/api/gui.rs)
    src/plugin/loader/loadermod.aowl   PluginLoader (load, can_load, unload, can_unload) and LoaderError   (loader/mod.rs)
    src/plugin/cache.aowl              the permission cache file and the SHA-256 of a plugin file     (plugin/cache.rs)
    src/plugin/managercore.aowl        PluginManager without the server: load_plugins, dependency order, permission cache,
                                       try_load_plugin, unload_plugin, states                          (plugin/mod.rs)
    src/plugin/pluginserver.aowl       the manager over the wasm loader and the real Server; `/plugin`; the hot reload poll
    src/plugin/pluginwire2.aowl        fills the hooks of block entities, scoreboard and recipes from the Server
    src/server/command/plugin.aowl     `/plugin list|load|unload|reload|hotreload`                (commands/plugin.rs)

Tests: `managercoretest` (topological_sort's upstream test, SHA-256 known answers, cache round trip, the manager over a fake
loader in a scratch folder, handler order, the context), `wit/witasm` (hand assembler of component test fixtures),
`wit/witwasitest` (a hand-built wasip2-shaped component run through the linker, then every WASI function through the
registry), `wit/witexttest` (item-stack, gui, recipe, scoreboard, block-entity and forms through the registry),
`src/server/command/plugintest` (`/plugin`). Over the wire: `python tools/mcbot.py --plugmgr --op` (tools/mcbot_plugmgr.py)
loads, unloads and reloads plugins on a running server.

## Signatures and the filesystem (phase 4)

    src/plugin/ed25519.aowl            Ed25519 (RFC 8032) over the jwt package's BigInt and SHA-512: public key, sign, verify
    src/plugin/ed25519test.aowl        SHA-512 known answers and RFC 8032 section 7.1 tests 1 and 2 (public key, signature, verify,
                                       tampered message / signature / key rejected); about one second per scalar multiplication
    src/plugin/signature.aowl          now verifies for real; `KeyManager`, `injectPumpkinSections` (serde field order) sign
    src/plugin/wit/witfs.aowl          wasi:filesystem: the `data` preopen (`fs.read.data` / `fs.write.data`), descriptors, open-at,
                                       read / write / append streams, stat, directories, mkdir, rmdir, unlink, rename (files)

`pluginhost.preparePlugin` calls `verifyWasmPlugin` as `WasmPluginLoader::load` does: an unsigned plugin or a failed signature
logs a warning, loading goes on. `witwasitest` runs the filesystem through the registry against a scratch folder.

## Player and entity host interfaces, part A (phase 5)

    src/plugin/wit/witplayer3.aowl       player: set-display-name (plugin-side), delete-message-by-id / -by-signature (CDeleteChat), open-book
                                         (COpenBook), teleport-world, open-gui (PluginScreenHandler through openHandledScreenDirect), item in hand,
                                         inventory / ender chest slots through item-stack handles, the `inventory` and `player-inventory`
                                         resources, open-ender-chest, status effects (add, remove, clear, has, get, list), advancements (award,
                                         revoke, progress, completed, selected tab), ray-trace-block / -entity, get-target-*, launch-projectile
                                         (snowball, egg, ender pearl, fireball, small fireball, wind charge), bedrock-player open-form (witforms JSON, `sendBedrockForm`; the answer arrives as
                                         bedrock-form-response-event), java-player get-version / brand /
                                         server-address / settings, send-custom-payload, send-game-event, send-entity-status, resource packs, clear-dialog
    src/plugin/wit/witentity3.aowl       entity: air, set-vehicle, custom data (plugin-side), raycast and ray traces; living-entity: max health,
                                         attributes, equipment; the `mob` resource (target, AI switch, navigation, look-at, freeze ticks)
    src/plugin/wit/witray.aowl           the ray tracing both use (World::raycast for blocks, bounding boxes for entities)
    src/plugin/wit/witeventsplayer2.aowl the events of `PlayerEvKind` (pluginhooks.aowl) converted to the WIT event variant and fired
    src/protocol/java/client/play/{open_book,delete_chat,resource_pack}.aowl   the packets those need

`silent` and `has-gravity` are real fields of the server's `Entity` (`silent`, `noGravity`): `Entity.playSound` stays quiet, `getGravity` answers 0, a thrown
projectile skips its gravity, and the Silent / NoGravity metadata is sent. `item-stack` handles that come out of an inventory own a copy.
The server calls one hook for the new events, `gPluginPlayerEventHook(player, PlayerEv)`: swing arm and use item (the raycast for the
interact action is the host's), interact entity, custom payload (dispatch.aowl), client information (main hand), inventory click (play.aowl) and
close (player.aowl), block break (worldmod.breakBlock, with the should-drop flag read back), drop (player.aowl), pickup (itementity.aowl), sign update,
bed enter and leave (block/worldhooks.aowl), item consume (entitymod.aowl) and permission check (the `hasPermission` of each CommandPlayer is wrapped by pluginmgr.aowl). The existing
`gPluginBlockPlaceHook` is filled now.

Tests: `wit/witplayer3test` (every function above through the registry against a real Server and Player, packets read back),
`wit/witeventsplayer2test` (a hand-assembled plugin cancels a one-item drop and answers permission checks). Over the wire:
`python tools/mcbot.py --wasm-plugin2 --op` with the plugin written by `witeventsplayer2test --write`.

## Block, world and server events

    src/plugin/api/events/{block,world,server}/*.aowl   the event types (`BlockBreakEvent` .. `ServerTickEndEvent`), `mod.aowl` re-exports them
    src/plugin/pluginhooksevents.aowl     the closure hooks the server's call sites use (grow, redstone, spawn change, console command, broadcast,
                                          tick start/end, load, packet received); `gPacketSentHook` is in net/java/javamod.aowl (`writePacketFor`)
    src/plugin/pluginwireevents.aowl      `installEventHooks`: fills those hooks (and `CommandServer.fireSpawnChange`) with the conversions below
    src/plugin/wit/witeventsblock.aowl    `toWasm` / `fromWasm` / `fire...` for the six block events (typed; witeventsplayer2.aowl keeps the string-typed break and place the player path uses)
    src/plugin/wit/witeventsworld.aowl    SpawnChangeEvent
    src/plugin/wit/witeventsserver.aowl   packet received/sent (payload only, `unknown` packet case: PARTIAL), command, broadcast, load, tick start/end
    src/plugin/wit/witargs.aowl           `OwnedArg`, `ConsumedArgsResource`

Fired from: crop random tick (`BlockGrowEvent`), pressure plate (`BlockRedstoneEvent`), `/setworldspawn` (`SpawnChangeEvent`), console line
(`ServerCommandEvent`), `/say` and `/me` (`ServerBroadcastEvent`), the ticker, the start of the accept loop (`ServerLoadEvent`), `handlePlayPacket`
(`PacketReceivedEvent`) and `writePacketFor` (`PacketSentEvent`). Not fired, as upstream: `BlockBurnEvent`, `BlockCanBuildEvent`, `ChunkLoad`/`ChunkSave`
(`ChunkSend` is fired through javamod.aowl's `gChunkSendHook`, set by pluginwireevents.aowl). Test: `wit/witeventsblocktest` (conversions against known values and a host with no plugin; no component handles
these events in a test), `wit/witargstest`.
