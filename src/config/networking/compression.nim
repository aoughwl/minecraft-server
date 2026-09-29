## Port of pumpkingmc/crates/pumpkin-config/src/networking/compression.rs

type
  CompressionInfo* = object
    threshold*: uint32
    level*: uint32

  CompressionConfig* = object
    enabled*: bool
    info*: CompressionInfo

proc defaultCompressionInfo*(): CompressionInfo =
  CompressionInfo(threshold: 256'u32, level: 4'u32)

proc defaultCompressionConfig*(): CompressionConfig =
  CompressionConfig(enabled: true, info: defaultCompressionInfo())
