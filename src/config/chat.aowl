## Port of upstream/config/src/chat.rs

import std/options

type
  AntiSpamConfig* = object
    enabled*: bool
    spamThreshold*: uint32
    chatSpamThresholdSeconds*: Option[uint32]
    commandSpamThresholdSeconds*: Option[uint32]
    messageCost*: uint32
    decayPerTick*: uint32
    opsBypass*: bool

  ChatConfig* = object
    format*: string
    antiSpam*: AntiSpamConfig

proc saturatingMul20(v: uint32): uint32 {.inline.} =
  ## Port of `seconds.saturating_mul(20)`.
  let big = uint64(v) * 20'u64
  if big > uint64(uint32.high): uint32.high else: uint32(big)

proc chatThresholdTicks*(a: AntiSpamConfig): uint32 =
  if a.chatSpamThresholdSeconds.isSome:
    saturatingMul20(a.chatSpamThresholdSeconds.get())
  else:
    a.spamThreshold

proc commandThresholdTicks*(a: AntiSpamConfig): uint32 =
  if a.commandSpamThresholdSeconds.isSome:
    saturatingMul20(a.commandSpamThresholdSeconds.get())
  else:
    a.spamThreshold

proc defaultAntiSpamConfig*(): AntiSpamConfig =
  AntiSpamConfig(
    enabled: true,
    spamThreshold: 200'u32,
    chatSpamThresholdSeconds: none[uint32](),
    commandSpamThresholdSeconds: none[uint32](),
    messageCost: 20'u32,
    decayPerTick: 1'u32,
    opsBypass: true,
  )

proc defaultChatConfig*(): ChatConfig =
  ChatConfig(format: "<{DISPLAYNAME}> {MESSAGE}", antiSpam: defaultAntiSpamConfig())
