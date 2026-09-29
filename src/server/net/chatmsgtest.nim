## Exercises chatmsg.nim's pure logic for real - `nimony c -r`, not just
## `nimony check`. No `entity.nim` import, so this is genuine proof, not
## affected by the closures-through-vtables crash (NIMONY-COMPILER-BUGS.md #1).

import std/[syncio, assertions]
import chatmsg
import ../../protocol/bitset

# FilterMask.apply
block:
  let (foundPass, textPass) = passThroughMask().apply("hello")
  assert foundPass and textPass == "hello"

  let (foundFull, _) = fullyFilteredMask().apply("hello")
  assert not foundFull

  var bits = newBitSet()
  bits.setBit(1, true)
  bits.setBit(3, true)
  let (foundPartial, textPartial) = partiallyFilteredMask(bits).apply("hello")
  assert foundPartial
  assert textPartial == "h#l#o", "got: " & textPartial

# SignedMessageLink / SignedMessageBody
block:
  let sender: PlayerUuid = (1'u64, 2'u64)
  let link = unsignedLink(sender)
  assert link.index == 0
  assert link.sender == sender
  assert link.sessionId == NilUuid

  let body = unsignedBody("hi")
  assert body.content == "hi"
  assert body.timeStamp == 0
  assert body.salt == 0
  assert body.lastSeen.len == 0

# PlayerChatMessage
block:
  let sender: PlayerUuid = (5'u64, 6'u64)
  let msg = unsignedMessage(sender, "hello world")
  assert msg.sender() == sender
  assert not msg.isSystem()
  assert msg.signedContent() == "hello world"
  assert msg.decoratedContent() == "hello world"
  assert not msg.hasSignature
  assert not msg.isFullyFiltered()

  let sysMsg = systemMessage("server says hi")
  assert sysMsg.isSystem()
  assert sysMsg.sender() == SystemSender

  # withUnsignedContent: identical content is dropped
  let sameContent = msg.withUnsignedContent("hello world")
  assert not sameContent.hasUnsignedContent

  let diffContent = msg.withUnsignedContent("HELLO WORLD (decorated)")
  assert diffContent.hasUnsignedContent
  assert diffContent.decoratedContent() == "HELLO WORLD (decorated)"

  let cleared = diffContent.removeUnsignedContent()
  assert not cleared.hasUnsignedContent
  assert cleared.decoratedContent() == "hello world"

  # filterByBool
  var withMask = msg
  withMask.filterMask = fullyFilteredMask()
  let filteredOn = withMask.filterByBool(true)
  assert filteredOn.isFullyFiltered()
  let filteredOff = withMask.filterByBool(false)
  assert not filteredOff.isFullyFiltered()

  # removeSignature
  var signed = msg
  signed.hasSignature = true
  signed.signature = @[1'u8, 2, 3]
  let unsigned = signed.removeSignature()
  assert not unsigned.hasSignature
  assert unsigned.signature.len == 0
  assert unsigned.signedContent() == msg.signedContent()

# OutgoingChatMessage
block:
  let sysMsg = systemMessage("welcome")
  let outSys = createOutgoing(sysMsg)
  assert outSys.kind == ockDisguised
  assert outgoingContent(outSys) == "welcome"

  let playerMsg = unsignedMessage((9'u64, 10'u64), "player says hi")
  let outPlayer = createOutgoing(playerMsg)
  assert outPlayer.kind == ockPlayer
  assert outgoingContent(outPlayer) == "player says hi"

echo "chatmsg: all checks passed"
