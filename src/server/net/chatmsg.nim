## The plain-data/pure-logic slice of net/chat/mod.rs's secure-chat model.
## Port of upstream's net/chat/mod.rs (432 lines).
##
## `send_to_player` (the packet-construction/player-mutation tail of
## `OutgoingChatMessage`) is NOT ported here - it needs `Player`,
## `CPlayerChatMessage`/`SText` packet types, and a signature-cache/
## chat-session model that don't exist in this port yet. Everything above
## that - the filter mask, the signed-message link/body, the message
## itself, and the disguised-vs-player outgoing-message split - is pure
## data and logic, ported in full.
##
## No `TextComponent` type exists anywhere in this port yet (see the main
## README's `pumpkin-util` entry); every `TextComponent` field here is a
## plain `string` instead, matching the convention already used in
## src/command/cmdsource.nim and src/plugin_api/eventdata.nim.

import ../../protocol/bitset

type
  FilterMaskKind* = enum
    fmkPassThrough
    fmkFullyFiltered
    fmkPartiallyFiltered

  FilterMask* = object
    case kind*: FilterMaskKind
    of fmkPassThrough, fmkFullyFiltered: discard
    of fmkPartiallyFiltered: bits*: BitSet

proc passThroughMask*(): FilterMask {.inline.} =
  FilterMask(kind: fmkPassThrough)

proc fullyFilteredMask*(): FilterMask {.inline.} =
  FilterMask(kind: fmkFullyFiltered)

proc partiallyFilteredMask*(bits: sink BitSet): FilterMask {.inline.} =
  FilterMask(kind: fmkPartiallyFiltered, bits: bits)

proc isPassThrough*(m: FilterMask): bool {.inline.} = m.kind == fmkPassThrough
proc isFullyFiltered*(m: FilterMask): bool {.inline.} = m.kind == fmkFullyFiltered
proc isEmpty*(m: FilterMask): bool {.inline.} = m.isPassThrough()

proc apply*(m: FilterMask, text: string): (bool, string) =
  ## `(found, filtered)` in place of Rust's `Option<String>` - `found`
  ## false means "fully filtered", matching `None`.
  case m.kind
  of fmkPassThrough:
    (true, text)
  of fmkFullyFiltered:
    (false, "")
  of fmkPartiallyFiltered:
    var outStr = newString(text.len)
    for i in 0 ..< text.len:
      if m.bits.getBit(i):
        outStr[i] = '#'
      else:
        outStr[i] = text[i]
    (true, outStr)

# --- SignedMessageLink -------------------------------------------------

type
  PlayerUuid* = (uint64, uint64)
    ## Matches src/protocol/uuid.nim's (hi, lo) wire-shape convention.

const NilUuid*: PlayerUuid = (0'u64, 0'u64)

type
  SignedMessageLink* = object
    index*: int32
    sender*: PlayerUuid
    sessionId*: PlayerUuid

proc unsignedLink*(sender: PlayerUuid): SignedMessageLink {.inline.} =
  SignedMessageLink(index: 0, sender: sender, sessionId: NilUuid)

proc newSignedMessageLink*(index: int32, sender, sessionId: PlayerUuid): SignedMessageLink {.inline.} =
  SignedMessageLink(index: index, sender: sender, sessionId: sessionId)

# --- SignedMessageBody ---------------------------------------------------

type
  SignedMessageBody* = object
    content*: string
    timeStamp*: int64
    salt*: int64
    lastSeen*: seq[seq[byte]]

proc unsignedBody*(content: string): SignedMessageBody {.inline.} =
  SignedMessageBody(content: content, timeStamp: 0, salt: 0, lastSeen: @[])

proc newSignedMessageBody*(content: string, timeStamp, salt: int64,
    lastSeen: sink seq[seq[byte]]): SignedMessageBody {.inline.} =
  SignedMessageBody(content: content, timeStamp: timeStamp, salt: salt, lastSeen: lastSeen)

# --- PlayerChatMessage ---------------------------------------------------

type
  PlayerChatMessage* = object
    link*: SignedMessageLink
    hasSignature*: bool
    signature*: seq[byte]
    signedBody*: SignedMessageBody
    hasUnsignedContent*: bool
    unsignedContent*: string
    filterMask*: FilterMask

const SystemSender*: PlayerUuid = NilUuid
  ## `MESSAGE_EXPIRES_AFTER_SERVER`/`_CLIENT` (5min/7min Durations) aren't
  ## ported - nothing in this port tracks message expiry yet; add as plain
  ## second counts (300/420) when a real chat-session timeout is wired up.

proc systemMessage*(content: string): PlayerChatMessage =
  PlayerChatMessage(
    link: unsignedLink(SystemSender),
    hasSignature: false, signature: @[],
    signedBody: unsignedBody(content),
    hasUnsignedContent: false, unsignedContent: "",
    filterMask: passThroughMask())

proc unsignedMessage*(sender: PlayerUuid, content: string): PlayerChatMessage =
  PlayerChatMessage(
    link: unsignedLink(sender),
    hasSignature: false, signature: @[],
    signedBody: unsignedBody(content),
    hasUnsignedContent: false, unsignedContent: "",
    filterMask: passThroughMask())

proc signedContent*(m: PlayerChatMessage): string {.inline.} = m.signedBody.content

proc decoratedContent*(m: PlayerChatMessage): string {.inline.} =
  if m.hasUnsignedContent: m.unsignedContent else: m.signedContent()

proc timestamp*(m: PlayerChatMessage): int64 {.inline.} = m.signedBody.timeStamp
proc salt*(m: PlayerChatMessage): int64 {.inline.} = m.signedBody.salt
proc sender*(m: PlayerChatMessage): PlayerUuid {.inline.} = m.link.sender
proc isSystem*(m: PlayerChatMessage): bool {.inline.} = m.sender() == SystemSender
proc hasSignatureFrom*(m: PlayerChatMessage, profileId: PlayerUuid): bool {.inline.} =
  m.hasSignature and m.sender() == profileId
proc isFullyFiltered*(m: PlayerChatMessage): bool {.inline.} = m.filterMask.isFullyFiltered()

proc withUnsignedContent*(m: sink PlayerChatMessage, content: string): PlayerChatMessage =
  ## Upstream drops `unsigned_content` when it's byte-identical to the
  ## signed content (no point carrying a duplicate).
  result = m
  if content == result.signedBody.content:
    result.hasUnsignedContent = false
    result.unsignedContent = ""
  else:
    result.hasUnsignedContent = true
    result.unsignedContent = content

proc removeUnsignedContent*(m: sink PlayerChatMessage): PlayerChatMessage =
  result = m
  result.hasUnsignedContent = false
  result.unsignedContent = ""

proc filter*(m: PlayerChatMessage, mask: FilterMask): PlayerChatMessage =
  result = m
  result.filterMask = mask

proc filterByBool*(m: PlayerChatMessage, filtered: bool): PlayerChatMessage =
  m.filter(if filtered: m.filterMask else: passThroughMask())

proc removeSignature*(m: PlayerChatMessage): PlayerChatMessage =
  result = m
  result.signedBody = unsignedBody(m.signedContent())
  result.link = unsignedLink(m.sender())
  result.hasSignature = false
  result.signature = @[]

# --- OutgoingChatMessage ---------------------------------------------------

type
  OutgoingKind* = enum
    ockDisguised
    ockPlayer

  OutgoingChatMessage* = object
    case kind*: OutgoingKind
    of ockDisguised: content*: string
    of ockPlayer: message*: PlayerChatMessage

proc createOutgoing*(message: sink PlayerChatMessage): OutgoingChatMessage =
  if message.isSystem():
    OutgoingChatMessage(kind: ockDisguised, content: message.decoratedContent())
  else:
    OutgoingChatMessage(kind: ockPlayer, message: message)

proc outgoingContent*(o: OutgoingChatMessage): string =
  case o.kind
  of ockDisguised: o.content
  of ockPlayer: o.message.decoratedContent()

# send_to_player: NOT ported. Needs `Player` (chat_session/signature_cache
# state, try_enqueue_packet_editioned), `CPlayerChatMessage`/`SText`
# packet types, and `pumpkin_data::translation` - none exist in this port
# yet. Once `Player` gets a chat-session model, this is the call site to
# build against upstream's actual field/method names.
