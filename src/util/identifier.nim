## Port of upstream/util/src/identifier.rs
##
## Skipped: `from_static`/`parse_static`/`vanilla_static`/`static` and
## the `unsafe` `slice_bytes_to_str_unchecked` helper they use - these exist
## in Rust purely so an `Identifier` can be built in a `const fn` (no heap
## alloc, usable in const contexts). Nimony's `string` is always a normal
## heap-backed value and there's no const/runtime split to preserve here, so
## `new`/`parse`/`vanilla`/`serverNs` (the runtime paths) cover the same
## ground. Also skipped: `serde` (de)serialize impls and the
## `codecs::FlatTryFrom` integration - ported once codecs is.

const
  VanillaNamespace* = "minecraft"
  ServerNamespace* = "server"

type
  Identifier* = object
    namespace: string
    path: string

  IdentifierErrorKind* = enum
    iekInvalidNamespace
    iekInvalidPath

  IdentifierError* = object
    kind*: IdentifierErrorKind
    ## The identifier that failed validation (Rust's `InvalidNamespace(Identifier)`
    ## / `InvalidPath(Identifier)` carry the offending value; kept the same way).
    identifier*: Identifier

  IdentifierResult* = object
    case isOk*: bool
    of true:
      value*: Identifier
    of false:
      error*: IdentifierError

proc isValidNamespace*(namespace: string): bool =
  for ch in namespace:
    let ok = (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'z') or
             ch == '-' or ch == '_' or ch == '.'
    if not ok:
      return false
  true

proc isValidPath*(path: string): bool =
  for ch in path:
    let ok = (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'z') or
             ch == '-' or ch == '_' or ch == '.' or ch == '/'
    if not ok:
      return false
  true

proc isValidChar*(c: char): bool =
  (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or
    c == '-' or c == '_' or c == '.' or c == '/' or c == ':'

proc validateIdentifier(identifier: sink Identifier): IdentifierResult =
  if not isValidNamespace(identifier.namespace):
    return IdentifierResult(isOk: false,
      error: IdentifierError(kind: iekInvalidNamespace, identifier: identifier))
  if not isValidPath(identifier.path):
    return IdentifierResult(isOk: false,
      error: IdentifierError(kind: iekInvalidPath, identifier: identifier))
  IdentifierResult(isOk: true, value: identifier)

proc validateIdentifierPath(identifier: sink Identifier): IdentifierResult =
  if not isValidPath(identifier.path):
    return IdentifierResult(isOk: false,
      error: IdentifierError(kind: iekInvalidPath, identifier: identifier))
  IdentifierResult(isOk: true, value: identifier)

proc newIdentifier*(namespace, path: string): IdentifierResult =
  validateIdentifier(Identifier(namespace: namespace, path: path))

proc vanilla*(path: string): IdentifierResult =
  newIdentifier(VanillaNamespace, path)

proc serverNs*(path: string): IdentifierResult =
  newIdentifier(ServerNamespace, path)

proc parse*(identifier: string): IdentifierResult =
  ## Splits on the first `:`. No colon (or a colon at position 0) implies the
  ## vanilla namespace, matching `Identifier::parse`.
  var colonIdx = -1
  for i, ch in identifier:
    if ch == ':':
      colonIdx = i
      break
  if colonIdx < 0:
    newIdentifier(VanillaNamespace, identifier)
  elif colonIdx == 0:
    newIdentifier(VanillaNamespace, identifier[1 .. ^1])
  else:
    newIdentifier(identifier[0 ..< colonIdx], identifier[colonIdx+1 .. ^1])

proc withPath*(id: sink Identifier, path: string): IdentifierResult =
  validateIdentifierPath(Identifier(namespace: id.namespace, path: path))

proc prefixPath*(id: sink Identifier, prefix: string): IdentifierResult =
  validateIdentifierPath(Identifier(namespace: id.namespace, path: prefix & id.path))

proc suffixPath*(id: sink Identifier, suffix: string): IdentifierResult =
  validateIdentifierPath(Identifier(namespace: id.namespace, path: id.path & suffix))

proc namespace*(id: Identifier): string {.inline.} = id.namespace
proc path*(id: Identifier): string {.inline.} = id.path

proc view*(id: Identifier): (string, string) {.inline.} =
  (id.namespace, id.path)

proc isVanilla*(id: Identifier): bool {.inline.} =
  id.namespace == VanillaNamespace

proc isServerNs*(id: Identifier): bool {.inline.} =
  id.namespace == ServerNamespace

proc `$`*(id: Identifier): string =
  id.namespace & ":" & id.path

proc `==`*(a, b: Identifier): bool {.inline.} =
  a.namespace == b.namespace and a.path == b.path
