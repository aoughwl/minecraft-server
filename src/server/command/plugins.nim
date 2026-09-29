## The `/plugins` command.
## Port of upstream/pumpkin/src/command/commands/plugins.rs
##
## `CommandSource` gained `pluginsProc*: proc(): seq[PluginInfo] {.closure.}`
## standing in for `server.plugin_manager.active_plugins()` - no
## `Server`/`PluginManager` type exists in this port yet (the WASM
## plugin-host bridge is a separate, documented gap - see
## `src/plugin_runtime/README.md`/`src/host_bindings/README.md`). `nil`
## reports an empty plugin list. Not ported: permission-registry
## registration, and the colored/hover-tooltip feedback (`NamedColor`/
## `HoverEvent`, needs the unported `text` module - plain
## comma-separated names stand in).

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  PluginsDescription* = "Lists all plugins loaded on the server."
  PluginsPermission* = "pumpkin:command.plugins"

proc pluginsExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let plugins = if source.pluginsProc != nil: source.pluginsProc() else: @[]
  if plugins.len == 0:
    sendMessage(source, "No plugins are loaded on the server.")
  else:
    var names = ""
    for i, p in plugins:
      if i > 0:
        names.add(", ")
      names.add(p.name)
    sendMessage(source, "Plugins (" & $plugins.len & "): " & names)
  cmdOk[int32](1'i32)

proc registerPlugins*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "plugins", executable = true)
  setCommand(t, cmdNode, pluginsExecute)
