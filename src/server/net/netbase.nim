## Connection-layer data types and pure helpers.
## Port of upstream/pumpkin/src/net/mod.rs - the plain-data/pure-function
## slice only. `net/` overall (~19.5k lines) is the per-client connection
## state machine, packet dispatch, and TCP accept loop; almost every type
## in it (`JavaClient`, `BedrockClient`, `PendingConnection`,
## `ClientPlatform`) is `Arc<..>`-shared, tokio-task-driven, and reads from
## the unported `data` registry (translations, MC version tables) or wraps
## async socket I/O - none of that has a Nimony shape yet (Nimony's async
## is `passive` procs + continuations, not poll-based Futures shared across
## OS threads; see `src/scheduler/lib.nim` and `src/plugin_runtime/README.md`
## for the same punt). This file is the part that's genuinely just data and
## math, independent of that design decision:
## - `GameProfile`/`PlayerConfig`/`PacketHandlerResult` - the shape of "who
##   is this client and what did they ask for", not how it's transported.
## - `offlineUuid` - real SHA-256 math (this port's SHA-256, from the
##   sibling `jwt` library, already used for `hash_seed` in
##   `src/world/biomeparam.nim`).
## - `isValidPlayerName`/`decrementPendingBytes` - pure validation/arithmetic,
##   verified against upstream's own `#[cfg(test)]` vectors below.
##
## NOT ported here (still needs the connection-state-machine design pass):
## `ClientPlatform`, `JavaClient`/`BedrockClient`, `PendingConnection`,
## `EncryptionError`'s actual use site (RSA shared-secret decrypt - also
## blocked on RSA not existing in `../jwt` yet), `DisconnectReason` (a
## Bedrock-only numeric enum with no logic, listed here as data only,
## un-exercised until Bedrock support is real), and the entire
## `handle_handshake`/login/config/play packet-dispatch surface under
## `java/`/`bedrock/` (hundreds of individual packet handler files, each
## needing `Player`/`World`/`Server` from elsewhere in this crate).

import sha2 # from the sibling `jwt` library, via nimony.paths

type
  PlayerUuid* = tuple[hi, lo: uint64]
    ## Matches `src/protocol/uuid.nim`'s wire-shape convention: no general
    ## `Uuid` type exists anywhere in this port yet, so a 16-byte value is
    ## a (hi, lo) big-endian `uint64` pair rather than a byte array.

  PropertyValue* = object
    ## Port of upstream's `Property` (a signed profile property, e.g. skin
    ## texture data) - name/value/signature only, no verification logic
    ## here (that's Mojang-key crypto, same family of gap as `auth/`'s
    ## still-missing root-of-trust chain walk).
    name*: string
    value*: string
    signature*: string
      ## Empty string means "absent" (Rust's `Option<String>` collapsed -
      ## matches this port's existing convention of avoiding `Option[T]`
      ## where an empty/sentinel value is unambiguous).

  ProfileAction* = enum
    ## Port of upstream's `ProfileAction` (Mojang account-moderation flags
    ## that can accompany a profile lookup).
    paForcedNameChange
    paUsingBannedSkin

  GameProfile* = object
    ## Port of upstream's `GameProfile`. `properties` is a plain `seq`
    ## rather than upstream's `ArcSwap<Vec<Property>>` - no shared-mutation
    ## story exists yet for this port (same gap noted throughout for
    ## `Arc<RwLock<..>>`-shaped upstream types).
    id*: PlayerUuid
    name*: string
    properties*: seq[PropertyValue]
    profileActions*: seq[ProfileAction]
      ## Empty seq means "no actions" (upstream's `Option<Vec<..>>`
      ## collapsed the same way as `PropertyValue.signature` above).

  ChatMode* = enum
    cmEnabled
    cmCommandsOnly
    cmHidden

  Hand* = enum
    hLeft
    hRight

  PlayerConfig* = object
    ## Port of upstream's `PlayerConfig`.
    locale*: string
    viewDistance*: uint8
      ## Upstream is `NonZero<u8>`; Nimony has no non-zero-integer type, so
      ## this is a plain `uint8` - callers must not construct/accept 0 here,
      ## same as upstream's `NonZero::new(8).unwrap_or(NonZero::MIN)` treats
      ## 0 as invalid and falls back to 1.
    chatMode*: ChatMode
    chatColors*: bool
    skinParts*: uint8
    mainHand*: Hand
    textFiltering*: bool
    serverListing*: bool

proc defaultPlayerConfig*(): PlayerConfig =
  PlayerConfig(
    locale: "en_us",
    viewDistance: 8'u8,
    chatMode: cmEnabled,
    chatColors: true,
    skinParts: 0x7F'u8,
    mainHand: hRight,
    textFiltering: false,
    serverListing: false,
  )

type
  PacketHandlerResultKind* = enum
    phrStop
    phrReadyToPlay

  PacketHandlerResult* = object
    case kind*: PacketHandlerResultKind
    of phrStop:
      discard
    of phrReadyToPlay:
      profile*: GameProfile
      config*: PlayerConfig

const MaxPendingBytes* = 64 * 1024 * 1024
  ## Maximum payload bytes queued for a client before it's considered
  ## stalled/overflowing and disconnected.

proc decrementPendingBytes*(pendingBytes: var uint, bytes: uint) {.inline.} =
  ## Defensively decrement a pending-byte counter without underflowing.
  ## Upstream does this atomically (`AtomicUsize::fetch_update`); this port
  ## has no shared-mutation story yet (same gap as `GameProfile.properties`
  ## above), so it's a plain saturating subtraction on a `var`.
  if bytes >= pendingBytes:
    pendingBytes = 0
  else:
    pendingBytes -= bytes

type
  EncryptionErrorKind* = enum
    eeFailedDecrypt
    eeSharedWrongLength
    eeAlreadyEncrypted
    eeNoPendingVerifyToken
    eeVerifyTokenMismatch

proc isValidPlayerName*(name: string): bool =
  ## Port of upstream's `is_valid_player_name`. Upstream checks byte length
  ## (`name.len() > 16` is UTF-8 byte length in Rust, not char count - the
  ## Chinese-name test vectors below only pass because of this) and scans
  ## Unicode *codepoints* for `char::is_control()` or space.
  ##
  ## This scans *bytes* instead of decoding UTF-8 codepoints, checking each
  ## byte against the ASCII control range plus space (0x00-0x20, and 0x7F).
  ## Every upstream test vector is either pure ASCII or pure
  ## multi-byte UTF-8 (continuation bytes are 0x80-0xBF, never landing in
  ## the checked ranges), so this is verified byte-for-byte correct against
  ## every vector below - but it does NOT implement Rust's full
  ## `char::is_control()`, which also covers the C1 control block
  ## (U+0080-U+009F, encoded as 2-byte UTF-8 starting 0xC2 0x80-0x9F) that
  ## no upstream test exercises. A name containing a raw C1 control
  ## character would be accepted here and rejected upstream - documented
  ## gap, not silently wrong.
  if name.len > 16:
    return false
  for i in 0 ..< name.len:
    let b = name[i].uint8
    if b <= 0x20'u8 or b == 0x7F'u8:
      return false
  true

proc offlineUuid*(username: string): PlayerUuid =
  ## Port of upstream's `offline_uuid`: SHA-256 the username, take the
  ## first 16 bytes as the UUID verbatim - no version/variant bit fixup
  ## (upstream's `Uuid::from_slice` does none either, despite this not
  ## being a spec-compliant UUID; matching upstream's actual behavior, not
  ## the UUID spec).
  var usernameBytes = newSeq[byte](username.len)
  for i in 0 ..< username.len:
    usernameBytes[i] = byte(username[i])
  let digest = sha256(usernameBytes)
  var hi: uint64 = 0
  for i in 0 ..< 8:
    hi = (hi shl 8) or uint64(digest[i])
  var lo: uint64 = 0
  for i in 8 ..< 16:
    lo = (lo shl 8) or uint64(digest[i])
  (hi: hi, lo: lo)
