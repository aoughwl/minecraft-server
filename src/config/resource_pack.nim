## Port of pumpkingmc/crates/pumpkin-config/src/resource_pack.rs

import whitelist  # for the shared `Uuid` stub type

type
  JavaResourcePackConfig* = object
    enabled*: bool
    url*: string
    sha1*: string
    promptMessage*: string
    force*: bool

  BedrockPack* = object
    uuid*: Uuid
    version*: string
    size*: uint64
    downloadUrl*: string
    contentKey*: string
    subPackName*: string
    contentId*: string
    hasScripts*: bool
    addonPack*: bool
    rtxEnabled*: bool

  BedrockResourcePackConfig* = object
    enabled*: bool
    force*: bool
    packs*: seq[BedrockPack]

  ResourcePackConfig* = object
    java*: JavaResourcePackConfig
    bedrock*: BedrockResourcePackConfig

proc defaultJavaResourcePackConfig*(): JavaResourcePackConfig =
  JavaResourcePackConfig(enabled: false, url: "", sha1: "", promptMessage: "", force: false)

proc defaultBedrockResourcePackConfig*(): BedrockResourcePackConfig =
  BedrockResourcePackConfig(enabled: false, force: false, packs: @[])

proc defaultResourcePackConfig*(): ResourcePackConfig =
  ResourcePackConfig(
    java: defaultJavaResourcePackConfig(),
    bedrock: defaultBedrockResourcePackConfig(),
  )
