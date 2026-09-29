## Native (dynamically-loaded-library) plugin loader.
## Ported from the upstream reference implementation's plugin/loader/mod.rs
## (the `LoaderError` enum + `PLUGIN_API_VERSION`) and plugin/loader/native.rs
## (`NativePluginLoader`).
##
## Only the plain-data/logic half is ported here: the error type, the API
## version constant, and `canLoad`'s file-extension check. The actual dynamic
## library load + symbol lookup (`Library::new`, `library.get::<...>(name)`)
## needs Nimony's C-backend dynlib FFI (`{.dynlib.}`/`loadLib`/`symAddr`,
## standard Nim-family features that should exist since the C backend can
## already link against system libraries - not yet investigated for this
## port) plus a real decision on the async load/unload signature (upstream
## returns a boxed future; no async model has been chosen anywhere in this
## port yet - see src/scheduler/'s and src/plugin_runtime/'s reports for the
## same open question). `loadPlugin`/`unloadPlugin` are therefore left as
## unimplemented stubs with a clear TODO rather than faked.

const
  PluginApiVersion* = 2'u32
  PluginDir* = "./plugins"

type
  LoaderErrorKind* = enum
    lekLibraryLoad
    lekMetadataMissing
    lekEntrypointMissing
    lekApiVersionMissing
    lekApiVersionMismatch
    lekInitializationFailed
    lekRuntimeError
    lekInvalidLoaderData

  LoaderError* = object
    kind*: LoaderErrorKind
    msg*: string

proc libraryLoad*(reason: string): LoaderError =
  LoaderError(kind: lekLibraryLoad, msg: "Failed to load library: " & reason)

proc metadataMissing*(): LoaderError =
  LoaderError(kind: lekMetadataMissing, msg: "Missing plugin metadata")

proc entrypointMissing*(): LoaderError =
  LoaderError(kind: lekEntrypointMissing, msg: "Missing plugin entrypoint")

proc apiVersionMissing*(): LoaderError =
  LoaderError(kind: lekApiVersionMissing, msg: "Plugin is missing the API version symbol")

proc apiVersionMismatch*(pluginVersion, serverVersion: uint32): LoaderError =
  LoaderError(kind: lekApiVersionMismatch,
    msg: "Plugin was built for an incompatible API version (" & $pluginVersion &
      "); this server expects " & $serverVersion &
      ". Please rebuild it against this build.")

proc initializationFailed*(reason: string): LoaderError =
  LoaderError(kind: lekInitializationFailed, msg: "Plugin initialization failed: " & reason)

proc runtimeError*(reason: string): LoaderError =
  LoaderError(kind: lekRuntimeError, msg: "Runtime error: " & reason)

proc invalidLoaderData*(): LoaderError =
  LoaderError(kind: lekInvalidLoaderData, msg: "Invalid loader data")

type
  LoaderResult*[T] = object
    case isOk*: bool
    of true: value*: T
    of false: error*: LoaderError

proc ok*[T](value: sink T): LoaderResult[T] =
  LoaderResult[T](isOk: true, value: value)

proc errRes*[T](e: LoaderError): LoaderResult[T] =
  LoaderResult[T](isOk: false, error: e)

proc lowerAscii(s: string): string =
  result = s
  for i in 0 ..< result.len:
    let c = result[i]
    if c >= 'A' and c <= 'Z':
      result[i] = char(ord(c) + 32)

proc extensionOf(path: string): string =
  ## Returns the file extension without the leading dot, or "" if none.
  var dot = -1
  for i in countdown(path.len - 1, 0):
    let c = path[i]
    if c == '.':
      dot = i
      break
    if c == '/' or c == '\\':
      break
  if dot < 0:
    ""
  else:
    path[dot + 1 ..< path.len]

proc canLoad*(path: string, isWindows: bool, isMacos: bool): bool =
  ## Port of `NativePluginLoader::can_load`. Upstream branches on
  ## `cfg!(target_os = ...)` at compile time; this port takes the platform
  ## as a parameter instead, since which OS's convention to check is a
  ## caller/build concern, not something to hardcode into library logic.
  let ext = lowerAscii(extensionOf(path))
  if isWindows: ext == "dll"
  elif isMacos: ext == "dylib"
  else: ext == "so"

proc canUnload*(isWindows: bool): bool =
  ## Windows locks DLLs, so upstream reports them as non-unloadable there.
  not isWindows

# TODO: loadPlugin(path)/unloadPlugin(handle) - the actual dynamic-library
# load, PUMPKIN_API_VERSION/METADATA/plugin-entrypoint symbol lookups, and
# their async wrapping - are not implemented. Needs: (1) Nimony's dynlib FFI
# investigated for this port, (2) a chosen async/concurrency model for the
# load/unload signature, matching the same open question in
# src/scheduler/README.md and src/plugin_runtime/README.md.
