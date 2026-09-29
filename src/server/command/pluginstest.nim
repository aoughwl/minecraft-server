## Exercises `/plugins` through a real Tree/dispatch walk. Same caveat
## as every other file in this directory: check-verified, not
## runtime-proven (NIMONY-COMPILER-BUGS.md #1).

import std/[assertions, syncio]
import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmddispatch
import plugins

proc hasSubstr(s, sub: string): bool =
  ## `std/strutils` has no substring `contains`/`find` in Nimony's
  ## stdlib - a plain scan is fine for this test's tiny strings.
  if sub.len == 0:
    return true
  for i in 0 .. s.len - sub.len:
    if s[i ..< i + sub.len] == sub:
      return true
  false

block noPluginsLoaded:
  var t = newTree()
  registerPlugins(t)
  let source = CommandSource() ## pluginsProc stays nil
  let r = executeCommand(t, "plugins", source)
  assert r.isOk, "expected /plugins to succeed with no plugins loaded"

var gLastMessage = ""

proc recordMessage(message: string) {.closure.} =
  gLastMessage = message

block pluginsLoaded:
  var t = newTree()
  registerPlugins(t)
  let source = CommandSource(
    sendMessageProc: recordMessage,
    pluginsProc: proc(): seq[PluginInfo] {.closure.} =
      @[
        PluginInfo(name: "aowlinventory", version: "1.0", authors: "savannt", description: "test"),
        PluginInfo(name: "aowleconomy", version: "2.0", authors: "savannt", description: "test"),
      ],
  )
  let r = executeCommand(t, "plugins", source)
  assert r.isOk, "expected /plugins to succeed"
  assert hasSubstr(gLastMessage, "2"), "expected the count in the message"
  assert hasSubstr(gLastMessage, "aowlinventory"), "expected the first plugin name in the message"
  assert hasSubstr(gLastMessage, "aowleconomy"), "expected the second plugin name in the message"

echo "plugins command tests: all checks passed"
