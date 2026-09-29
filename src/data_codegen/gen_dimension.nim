## Generates src/generated/dimension.nim from the upstream reference's
## dimension_type datapack JSON files.
## Port of upstream/tools/pumpkin-codegen/src/dimension.rs
##
## Scope note: upstream's `Dimension` struct also carries an `attributes`
## sub-object (visual/audio/gameplay cosmetics: sky/fog/cloud color, ambient
## sound/music, bed-sleep rules) built from ~15 optional nested JSON paths.
## That's real work with its own edge cases (color hex parsing, a nested
## bed_rule object) and is client-rendering/cosmetic rather than core world
## logic, so it's deferred here - this generator ports the essential
## world-shape fields only (skylight/ceiling, Y bounds, coordinate scale,
## infiniburn/timelines tags). `monster_spawn_light_level` is an
## `IntProvider` (upstream's `value_to_int_provider`, itself unported) -
## stored here as the raw JSON text rather than parsed, so no data is lost,
## just not yet structured.

import std/[json, paths, strutils, syncio]
import codegenutil

type DimEntry = object
  name: string
  hasSkylight: bool
  hasCeiling: bool
  hasEnderDragonFight: bool
  ambientLight: float
  coordinateScale: float
  minY: int
  height: int
  logicalHeight: int
  infiniburn: string
  monsterSpawnBlockLightLimit: int
  monsterSpawnLightLevelJson: string
  fixedTime: int64
  hasFixedTime: bool
  timelines: string

proc normalizeNamespace(s: string): string =
  if s.len > 0 and (':' in s):
    s
  else:
    "minecraft:" & s

proc loadDimension(name: string, path: Path): DimEntry {.noinit.} =
  var tree = parseFile($path)
  let root = root(tree)
  # {.noinit.} (needed below to satisfy the "cannot prove initialized"
  # check on this loop-filled object) skips Nimony's usual zero-init, so
  # every field needs an explicit default here even when the JSON key is
  # expected to always be present - a real bug this exact gap produced on
  # the first pass: fixedTime held uninitialized memory garbage for
  # overworld.json (which has no "fixed_time" key), not 0.
  result = DimEntry()
  result.name = normalizeNamespace(name)
  var fixedTimeSet = false
  var hasFixedTimeExplicit = false
  var hasFixedTimeVal = false
  for key, val in root.pairs():
    case key
    of "has_skylight": result.hasSkylight = val.getBool()
    of "has_ceiling": result.hasCeiling = val.getBool()
    of "has_ender_dragon_fight": result.hasEnderDragonFight = val.getBool()
    of "ambient_light": result.ambientLight = val.getFloat()
    of "coordinate_scale": result.coordinateScale = val.getFloat()
    of "min_y": result.minY = val.getInt()
    of "height": result.height = val.getInt()
    of "logical_height": result.logicalHeight = val.getInt()
    of "infiniburn": result.infiniburn = normalizeNamespace(val.getStr())
    of "monster_spawn_block_light_limit": result.monsterSpawnBlockLightLimit = val.getInt()
    of "monster_spawn_light_level":
      # Structured minimally rather than via a generic JsonNode stringifier
      # (none is available in Nimony's std/json): the two shapes upstream's
      # IntProvider actually takes here are a bare int or a
      # {"type":"minecraft:uniform","min_inclusive":_,"max_inclusive":_}
      # object; capture whichever applies as plain text.
      if val.kind == JInt:
        result.monsterSpawnLightLevelJson = "const:" & $val.getInt()
      else:
        var kindStr, minStr, maxStr: string
        for k2, v2 in val.pairs():
          case k2
          of "type": kindStr = v2.getStr()
          of "min_inclusive": minStr = $v2.getInt()
          of "max_inclusive": maxStr = $v2.getInt()
          else: discard
        result.monsterSpawnLightLevelJson = kindStr & ":" & minStr & ".." & maxStr
    of "fixed_time":
      if val.kind != JNull:
        result.fixedTime = val.getInt()
        fixedTimeSet = true
    of "has_fixed_time":
      if val.kind != JNull:
        hasFixedTimeExplicit = true
        hasFixedTimeVal = val.getBool()
    of "timelines":
      if val.kind != JNull:
        result.timelines = normalizeNamespace(val.getStr())
    else:
      discard
  result.hasFixedTime =
    if hasFixedTimeExplicit: hasFixedTimeVal
    else: fixedTimeSet

proc main() =
  let dir = path("../upstream-ref/assets/datapack/data/minecraft/dimension_type")
  let stems = listJsonStems(dir)
  var entries: seq[DimEntry] = @[]
  for i in 0 ..< stems.len:
    let stem = stems[i][0]
    let path = stems[i][1]
    entries.add(loadDimension("minecraft:" & stem, path))

  var src = "## Generated from upstream's dimension_type datapack JSON.\n"
  src.add("## Port of upstream/tools/pumpkin-codegen/src/dimension.rs (core fields only - see gen_dimension.nim).\n\n")
  src.add("type Dimension* = object\n")
  src.add("  name*: string\n")
  src.add("  hasSkylight*: bool\n")
  src.add("  hasCeiling*: bool\n")
  src.add("  hasEnderDragonFight*: bool\n")
  src.add("  ambientLight*: float32\n")
  src.add("  coordinateScale*: float64\n")
  src.add("  minY*: int32\n")
  src.add("  height*: int32\n")
  src.add("  logicalHeight*: int32\n")
  src.add("  infiniburn*: string\n")
  src.add("  monsterSpawnBlockLightLimit*: uint8\n")
  src.add("  monsterSpawnLightLevelJson*: string\n")
  src.add("  fixedTime*: int64\n")
  src.add("  hasFixedTime*: bool\n")
  src.add("  timelines*: string\n\n")

  # Named constants, id = declaration order (sorted by stem, matching the
  # `entries.sort_by_key(|e| e.path())` upstream does before enumerate()).
  for i, e in entries:
    let constName = toShoutySnakeCase(e.name.split(':')[^1])
    src.add("const " & constName & "* = Dimension(\n")
    src.add("  name: " & escapeNim(e.name) & ",\n")
    src.add("  hasSkylight: " & $e.hasSkylight & ",\n")
    src.add("  hasCeiling: " & $e.hasCeiling & ",\n")
    src.add("  hasEnderDragonFight: " & $e.hasEnderDragonFight & ",\n")
    src.add("  ambientLight: " & $e.ambientLight & "'f32,\n")
    src.add("  coordinateScale: " & $e.coordinateScale & "'f64,\n")
    src.add("  minY: " & $e.minY & "'i32,\n")
    src.add("  height: " & $e.height & "'i32,\n")
    src.add("  logicalHeight: " & $e.logicalHeight & "'i32,\n")
    src.add("  infiniburn: " & escapeNim(e.infiniburn) & ",\n")
    src.add("  monsterSpawnBlockLightLimit: " & $e.monsterSpawnBlockLightLimit & "'u8,\n")
    src.add("  monsterSpawnLightLevelJson: " & escapeNim(e.monsterSpawnLightLevelJson) & ",\n")
    src.add("  fixedTime: " & $e.fixedTime & "'i64,\n")
    src.add("  hasFixedTime: " & $e.hasFixedTime & ",\n")
    src.add("  timelines: " & escapeNim(e.timelines) & ",\n")
    src.add(")\n\n")

  src.add("proc allDimensions*(): seq[Dimension] =\n")
  src.add("  @[\n")
  for e in entries:
    src.add("    " & toShoutySnakeCase(e.name.split(':')[^1]) & ",\n")
  src.add("  ]\n\n")

  src.add("proc dimensionFromName*(name: string): (bool, Dimension) =\n")
  src.add("  case name\n")
  for e in entries:
    src.add("  of " & escapeNim(e.name) & ", " & escapeNim(e.name.split(':')[^1]) & ":\n")
    src.add("    (true, " & toShoutySnakeCase(e.name.split(':')[^1]) & ")\n")
  src.add("  else:\n")
  src.add("    (false, Dimension())\n")

  try:
    writeFile("src/generated/dimension.nim", src)
  except ErrorCode as e:
    echo "write failed: " & $e
  echo "wrote src/generated/dimension.nim (", entries.len, " dimensions)"

proc escapeNim(s: string): string =
  result = "\""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    else: result.add(c)
  result.add("\"")

main()
