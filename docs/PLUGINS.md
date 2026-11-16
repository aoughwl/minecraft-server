# Plugins

Server plugins run on the **aoughwl engine**: a plugin is a program in **aowlmony** or **JavaScript** that the server loads from
`plugins/`. It listens to events, adds commands, schedules work and acts on players. The engine only runs programs; the plugin
manager (`src/plugin/pluginmanager.aowl`) is the server's own, and finds, loads, unloads and reloads them.

## A plugin in aowlmony

One file, `main.aowl`. Define handlers and register them at the top level. The handler's **parameter type** says which event it is for.

```nim
import pluginsdk

proc greet(e: var JoinEvent) =
  discard e.player.tell("Welcome, " & e.player.name & "!")

proc chatRules(e: var ChatEvent) =
  if e.message == "!ping":
    discard e.player.tell("pong!")
    e.cancel()                         # the server will not broadcast it
  else:
    e.message = e.message & " <3"      # rewrite what is broadcast

proc noTnt(e: var BlockPlaceEvent) =
  if e.blockName == "minecraft:tnt": e.cancel()

proc hello(c: var CommandContext) =
  c.reply("Hello, " & c.sender.name & "!")

registerEvent(greet)
registerEvent(chatRules)
registerEvent(noTnt)
command("hello", "Say hello", 0, hello)
```

Build it, and the server loads it (and reloads it every time you build again):

```
sh tools/build_plugin.sh plugins/my-plugin
```

`examples/hello-world` shows nearly everything.

## A plugin in JavaScript

`main.js`. There is no import: the server puts the SDK in front of your code. JavaScript has no static types to read, so the event
type is the first argument, the way Bukkit's `registerEvent` names the event class.

```js
on(JoinEvent, function (e) { e.player.tell("Welcome, " + e.player.name + "!"); });

on(ChatEvent, function (e) {
  if (e.message == "!ping") { e.player.tell("pong!"); e.cancel(); }
  else e.message += " <3";
});

on(BlockPlaceEvent, function (e) { if (e.blockName == "minecraft:tnt") e.cancel(); });

command("hello", "Say hello", 0, function (c) { c.reply("Hello, " + c.sender.name + "!"); });
```

All JavaScript plugins share one program (the engine runs one JavaScript program per process), each in its own scope; loading or
unloading one restarts that program, which runs the others' `onEnable` again. `examples/hello-world-js` is a small one.

## The API, in both languages

| | aowlmony | JavaScript |
|---|---|---|
| listen to an event | `registerEvent(handler)` (type from the parameter) | `on(EventType, handler)` |
| the event | a typed object: `e.player`, `e.message`, `e.x`, `e.cancelled` | an object with the same fields |
| cancel / change it | `e.cancel()`, `e.message = ...`, `e.amount = ...` | `e.cancel()`, `e.message = ...` |
| a command | `command(name, description, level, handler)` | `command(name, description, level, fn)` |
| in a command | `c.sender`, `c.isConsole`, `c.args`, `c.rawArgs`, `c.arg(i)`, `c.intArg(i)`, `c.floatArg(i)`, `c.restFrom(i)`, `c.reply(text)`, `c.fail(text)` | the same names (`c.numberArg(i)` for a number) |
| a player | `p.tell(text)`, `p.kick(reason)`, `p.teleport(x, y, z)`, `p.setGamemode(mode)`, `p.pos()`, `p.isOnline()`, `playerNamed(name)` | the same methods, `server.player(name)` |
| the server | `log(text)`, `broadcast(text)`, `onlineCount()` | `server.log`, `server.broadcast`, `server.onlineCount()` |
| run later | `after(ticks, handler)`, `every(ticks, handler)`, with data: `after(ticks, data, handler)`, `cancelTask(id)` | `after(ticks, fn, data)`, `every(...)`, `cancelTask(id)` |
| the world (overworld) | `blockAt(x, y, z)`, `setBlock(x, y, z, name)`, `worldTime()`, `setWorldTime(ticks)` | `server.blockAt(x, y, z)`, `server.setBlock(x, y, z, name)`, `server.time()`, `server.setTime(ticks)` |
| inventory | `p.give(item, count)`, `p.itemCount(item)`, `p.setFood(level)` | the same |
| an entity (by the id an event gives; overworld) | `entityHealth(id)`, `setEntityHealth(id, h)`, `entityPos(id)`, `teleportEntity(id, x, y, z)`, `setEntityOnFire(id, seconds)`, `removeEntity(id)` | `server.entityHealth(id)`, `server.setEntityHealth(id, h)`, `server.entityPos(id)`, `server.teleportEntity(id, x, y, z)`, `server.removeEntity(id)` |
| start and stop | `onEnable(handler)`, `onDisable(handler)` | `onEnable(fn)`, `onDisable(fn)` |

Command level 0 lets anyone use it; 1 to 4 an operator of at least that level. 20 ticks make a second.

## Events

72 event types: everything the server fires, with the Bukkit equivalent of each, and the list of Bukkit events the server does not (yet)
have a firing site for, are in **`docs/EVENTS.md`**.

## Managing plugins

* `aoe_engine.dll` must be on the DLL path (next to the server executable, or on `PATH`); `tools/build_engine_dll.sh` builds it. A server
  without it starts and simply runs no plugins.
* `/plugins` lists the loaded plugins; `/plugin list | load <name> | unload <name> | reload <name> | hotreload enable|disable` (level 3).
* **Hot reload:** every two seconds the server looks at each plugin's files; a changed plugin is reloaded and a new one is loaded.
* Unloading a plugin runs its `onDisable` handlers and removes its commands, tasks and event subscriptions.

## Under the hood

* An aowlmony plugin is compiled together with three added procedures (`start`, `event`, `stop`) that hand over to the SDK, because the
  engine finds a program's entries in its main module. `tools/build_plugin.sh` does that on a copy; your file is not touched.
* The engine's interpreter cannot give the host a runtime string directly, so `pluginsdk` talks in integers and reads text back; you never see it.
* The raw interface (host calls by name, plain `on_player_chat` functions in JavaScript) still exists underneath and is documented in the
  source of `src/plugin/engine/engineplugins.aowl`; the SDKs are the way to write plugins.

## Limits

* Plugins run **interpreted** (no native image yet).
* Registrations happen at the top level of the plugin; create tasks in a handler or `onEnable`, not at the top level.
* A plugin sees the events in `docs/EVENTS.md` and the calls above. Blocks and the time of the overworld can be read and set, other worlds, entities (beyond the damage, death, spawn and remove events),
  scoreboards, boss bars, forms and recipes are not exposed.
