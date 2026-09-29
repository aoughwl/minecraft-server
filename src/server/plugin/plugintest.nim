## Real behavior test for the plugin module's ported pieces - run via
## `nimony c -r src/server/plugin/plugintest.nim`. No `entity.nim` import,
## so unaffected by the closures-through-vtables runtime crash (see
## NIMONY-COMPILER-BUGS.md) - this actually proves the logic, not just
## checks it.

import std/[syncio, assertions]
import permissions, native

# --- permissions.nim ---

block:
  let (found, desc) = getPermissionDescription(NetworkTcpConnect)
  assert found
  assert desc == "Allows the plugin to initiate TCP connections."

block:
  let (found, desc) = getPermissionDescription(SysEnvPrefix & "PATH")
  assert found
  assert desc == "Allows the plugin to read specific environment variables."

block:
  let (found, _) = getPermissionDescription("not.a.real.permission")
  assert not found

# --- native.nim ---

assert canLoad("plugins/foo.dll", isWindows = true, isMacos = false)
assert not canLoad("plugins/foo.so", isWindows = true, isMacos = false)
assert canLoad("plugins/foo.DYLIB", isWindows = false, isMacos = true) # case-insensitive
assert canLoad("plugins/foo.so", isWindows = false, isMacos = false)
assert not canLoad("plugins/foo", isWindows = false, isMacos = false) # no extension
assert canLoad("plugins/foo.tar.so", isWindows = false, isMacos = false) # last extension wins

assert canUnload(isWindows = false)
assert not canUnload(isWindows = true)

let err = apiVersionMismatch(1'u32, PluginApiVersion)
assert err.kind == lekApiVersionMismatch
assert PluginApiVersion == 2'u32

echo "plugin module (permissions + native loader logic): all checks passed"
