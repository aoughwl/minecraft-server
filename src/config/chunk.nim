## Port of pumpkingmc/crates/pumpkin-config/src/chunk.rs

type
  Compression* = enum
    compGZip
    compZLib
    compLZ4
    compCustom

  ChunkCompression* = object
    algorithm*: Compression
    level*: uint32

  AnvilChunkConfig* = object
    compression*: ChunkCompression
    writeInPlace*: bool

  ChunkConfigKind* = enum
    cckAnvil
    cckLinear
    cckPump

  ChunkConfig* = object
    case kind*: ChunkConfigKind
    of cckAnvil: anvil*: AnvilChunkConfig
    of cckLinear: discard
    of cckPump: discard

proc defaultChunkCompression*(): ChunkCompression =
  ChunkCompression(algorithm: compLZ4, level: 6'u32)

proc defaultAnvilChunkConfig*(): AnvilChunkConfig =
  AnvilChunkConfig(compression: defaultChunkCompression(), writeInPlace: false)

proc defaultChunkConfig*(): ChunkConfig =
  ChunkConfig(kind: cckAnvil, anvil: defaultAnvilChunkConfig())
