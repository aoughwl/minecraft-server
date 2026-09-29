## Generated from upstream's worldgen/noise_settings datapack JSON.
## Port of upstream/tools/pumpkin-codegen/src/noise_settings.rs (shape fields only - see gen_noise_settings.nim).

type NoiseSettings* = object
  name*: string
  seaLevel*: int32
  defaultBlockName*: string
  defaultFluidName*: string
  legacyRandomSource*: bool
  minY*: int32
  height*: int32
  sizeHorizontal*: uint8
  sizeVertical*: uint8

const AMPLIFIED* = NoiseSettings(
  name: "minecraft:amplified",
  seaLevel: 63'i32,
  defaultBlockName: "minecraft:stone",
  defaultFluidName: "minecraft:water",
  legacyRandomSource: false,
  minY: -64'i32,
  height: 384'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

const CAVES* = NoiseSettings(
  name: "minecraft:caves",
  seaLevel: 32'i32,
  defaultBlockName: "minecraft:stone",
  defaultFluidName: "minecraft:water",
  legacyRandomSource: true,
  minY: -64'i32,
  height: 192'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

const END* = NoiseSettings(
  name: "minecraft:end",
  seaLevel: 0'i32,
  defaultBlockName: "minecraft:end_stone",
  defaultFluidName: "minecraft:air",
  legacyRandomSource: true,
  minY: 0'i32,
  height: 128'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

const FLOATING_ISLANDS* = NoiseSettings(
  name: "minecraft:floating_islands",
  seaLevel: -64'i32,
  defaultBlockName: "minecraft:stone",
  defaultFluidName: "minecraft:water",
  legacyRandomSource: true,
  minY: 0'i32,
  height: 256'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

const LARGE_BIOMES* = NoiseSettings(
  name: "minecraft:large_biomes",
  seaLevel: 63'i32,
  defaultBlockName: "minecraft:stone",
  defaultFluidName: "minecraft:water",
  legacyRandomSource: false,
  minY: -64'i32,
  height: 384'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

const NETHER* = NoiseSettings(
  name: "minecraft:nether",
  seaLevel: 32'i32,
  defaultBlockName: "minecraft:netherrack",
  defaultFluidName: "minecraft:lava",
  legacyRandomSource: true,
  minY: 0'i32,
  height: 128'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

const OVERWORLD* = NoiseSettings(
  name: "minecraft:overworld",
  seaLevel: 63'i32,
  defaultBlockName: "minecraft:stone",
  defaultFluidName: "minecraft:water",
  legacyRandomSource: false,
  minY: -64'i32,
  height: 384'i32,
  sizeHorizontal: 1'u8,
  sizeVertical: 2'u8,
)

proc allNoiseSettings*(): seq[NoiseSettings] =
  @[
    AMPLIFIED,
    CAVES,
    END,
    FLOATING_ISLANDS,
    LARGE_BIOMES,
    NETHER,
    OVERWORLD,
  ]

proc noiseSettingsFromName*(name: string): (bool, NoiseSettings) =
  case name
  of "minecraft:amplified", "amplified":
    (true, AMPLIFIED)
  of "minecraft:caves", "caves":
    (true, CAVES)
  of "minecraft:end", "end":
    (true, END)
  of "minecraft:floating_islands", "floating_islands":
    (true, FLOATING_ISLANDS)
  of "minecraft:large_biomes", "large_biomes":
    (true, LARGE_BIOMES)
  of "minecraft:nether", "nether":
    (true, NETHER)
  of "minecraft:overworld", "overworld":
    (true, OVERWORLD)
  else:
    (false, NoiseSettings())
