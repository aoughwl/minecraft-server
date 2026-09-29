## Port of pumpkingmc/crates/pumpkin-config/src/world.rs

import chunk, lighting

const DefaultAutosaveTicks* = 6000'u64 ## 5 minutes at 20 TPS.

type
  LevelConfig* = object
    chunk*: ChunkConfig
    lighting*: LightingEngineConfig
    autosaveTicks*: uint64

proc defaultLevelConfig*(): LevelConfig =
  LevelConfig(
    chunk: defaultChunkConfig(),
    lighting: defaultLightingEngineConfig(),
    autosaveTicks: DefaultAutosaveTicks,
  )
