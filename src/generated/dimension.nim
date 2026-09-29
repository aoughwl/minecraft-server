## Generated from upstream's dimension_type datapack JSON.
## Port of upstream/tools/pumpkin-codegen/src/dimension.rs (core fields only - see gen_dimension.nim).

type Dimension* = object
  name*: string
  hasSkylight*: bool
  hasCeiling*: bool
  hasEnderDragonFight*: bool
  ambientLight*: float32
  coordinateScale*: float64
  minY*: int32
  height*: int32
  logicalHeight*: int32
  infiniburn*: string
  monsterSpawnBlockLightLimit*: uint8
  monsterSpawnLightLevelJson*: string
  fixedTime*: int64
  hasFixedTime*: bool
  timelines*: string

const OVERWORLD* = Dimension(
  name: "minecraft:overworld",
  hasSkylight: true,
  hasCeiling: false,
  hasEnderDragonFight: false,
  ambientLight: 0.0'f32,
  coordinateScale: 1.0'f64,
  minY: -64'i32,
  height: 384'i32,
  logicalHeight: 384'i32,
  infiniburn: "#minecraft:infiniburn_overworld",
  monsterSpawnBlockLightLimit: 0'u8,
  monsterSpawnLightLevelJson: "minecraft:uniform:0..7",
  fixedTime: 0'i64,
  hasFixedTime: false,
  timelines: "#minecraft:in_overworld",
)

const OVERWORLD_CAVES* = Dimension(
  name: "minecraft:overworld_caves",
  hasSkylight: true,
  hasCeiling: true,
  hasEnderDragonFight: false,
  ambientLight: 0.0'f32,
  coordinateScale: 1.0'f64,
  minY: -64'i32,
  height: 384'i32,
  logicalHeight: 384'i32,
  infiniburn: "#minecraft:infiniburn_overworld",
  monsterSpawnBlockLightLimit: 0'u8,
  monsterSpawnLightLevelJson: "minecraft:uniform:0..7",
  fixedTime: 0'i64,
  hasFixedTime: false,
  timelines: "#minecraft:in_overworld",
)

const THE_END* = Dimension(
  name: "minecraft:the_end",
  hasSkylight: true,
  hasCeiling: false,
  hasEnderDragonFight: true,
  ambientLight: 0.25'f32,
  coordinateScale: 1.0'f64,
  minY: 0'i32,
  height: 256'i32,
  logicalHeight: 256'i32,
  infiniburn: "#minecraft:infiniburn_end",
  monsterSpawnBlockLightLimit: 0'u8,
  monsterSpawnLightLevelJson: "const:15",
  fixedTime: 0'i64,
  hasFixedTime: true,
  timelines: "#minecraft:in_end",
)

const THE_NETHER* = Dimension(
  name: "minecraft:the_nether",
  hasSkylight: false,
  hasCeiling: true,
  hasEnderDragonFight: false,
  ambientLight: 0.1'f32,
  coordinateScale: 8.0'f64,
  minY: 0'i32,
  height: 256'i32,
  logicalHeight: 128'i32,
  infiniburn: "#minecraft:infiniburn_nether",
  monsterSpawnBlockLightLimit: 15'u8,
  monsterSpawnLightLevelJson: "const:7",
  fixedTime: 0'i64,
  hasFixedTime: true,
  timelines: "#minecraft:in_nether",
)

proc allDimensions*(): seq[Dimension] =
  @[
    OVERWORLD,
    OVERWORLD_CAVES,
    THE_END,
    THE_NETHER,
  ]

proc dimensionFromName*(name: string): (bool, Dimension) =
  case name
  of "minecraft:overworld", "overworld":
    (true, OVERWORLD)
  of "minecraft:overworld_caves", "overworld_caves":
    (true, OVERWORLD_CAVES)
  of "minecraft:the_end", "the_end":
    (true, THE_END)
  of "minecraft:the_nether", "the_nether":
    (true, THE_NETHER)
  else:
    (false, Dimension())
