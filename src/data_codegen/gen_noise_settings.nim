## Generates src/generated/noise_settings.nim from the upstream reference's
## worldgen/noise_settings datapack JSON files.
## Port of upstream/tools/pumpkin-codegen/src/noise_settings.rs
##
## Scope note: upstream's full struct also carries `aquifers`,
## `material_rule`, `surface_rule` (all raw/untyped `serde_json::Value` even
## on the Rust side - opaque noise-function graphs, not simple data) and
## `spawn_target` (a `Vec` of biome-placement parameter points, in either a
## structured or a keyed-noise-map JSON shape). All four are deferred here,
## same call as gen_dimension.nim made for cosmetic dimension attributes -
## this generator ports the tractable, load-bearing shape fields only:
## sea level, default block/fluid names, the Y-bounds/cell-size "noise"
## sub-object (`GenerationShapeConfigStruct` upstream), and
## `legacy_random_source`. All 7 real files use the plain-string form of
## `default_block`/`default_fluid` (verified against every one), so the
## alternate `{"Name":.., "Properties":..}` structured form isn't handled -
## if a future asset update introduces it, this generator will need that
## branch added.

import std/[json, paths, syncio, strutils]
import codegenutil

type NoiseSettingsEntry = object
  name: string
  seaLevel: int32
  defaultBlockName: string
  defaultFluidName: string
  legacyRandomSource: bool
  minY: int32
  height: int32
  sizeHorizontal: uint8
  sizeVertical: uint8

proc blockRefName(node: JsonNode): string =
  ## Mirrors `BlockStateCodecStruct`: a plain string is the common case;
  ## fall back to a `Name` field for the structured form even though no
  ## real asset currently uses it, so this doesn't silently misparse if one
  ## shows up later.
  result = ""
  if node.kind == JString:
    result = node.getStr()
  else:
    for k, v in node.pairs():
      if k == "Name":
        result = v.getStr()

proc loadNoiseSettings(name: string, path: Path): NoiseSettingsEntry {.noinit.} =
  var tree = parseFile($path)
  let root = root(tree)
  result = NoiseSettingsEntry()
  result.name = "minecraft:" & name
  result.sizeHorizontal = 1
  result.sizeVertical = 2
  for key, val in root.pairs():
    case key
    of "sea_level": result.seaLevel = int32(val.getInt())
    of "default_block": result.defaultBlockName = blockRefName(val)
    of "default_fluid": result.defaultFluidName = blockRefName(val)
    of "legacy_random_source": result.legacyRandomSource = val.getBool()
    of "noise":
      for k2, v2 in val.pairs():
        case k2
        of "min_y": result.minY = int32(v2.getInt())
        of "height": result.height = int32(v2.getInt())
        of "size_horizontal": result.sizeHorizontal = uint8(v2.getInt())
        of "size_vertical": result.sizeVertical = uint8(v2.getInt())
        else: discard
    else:
      discard

proc escapeNim(s: string): string =
  result = "\""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    else: result.add(c)
  result.add("\"")

proc main() =
  let dir = path("../upstream-ref/assets/datapack/data/minecraft/worldgen/noise_settings")
  let stems = listJsonStems(dir)
  var entries: seq[NoiseSettingsEntry] = @[]
  for i in 0 ..< stems.len:
    entries.add(loadNoiseSettings(stems[i][0], stems[i][1]))

  var src = "## Generated from upstream's worldgen/noise_settings datapack JSON.\n"
  src.add("## Port of upstream/tools/pumpkin-codegen/src/noise_settings.rs (shape fields only - see gen_noise_settings.nim).\n\n")
  src.add("type NoiseSettings* = object\n")
  src.add("  name*: string\n")
  src.add("  seaLevel*: int32\n")
  src.add("  defaultBlockName*: string\n")
  src.add("  defaultFluidName*: string\n")
  src.add("  legacyRandomSource*: bool\n")
  src.add("  minY*: int32\n")
  src.add("  height*: int32\n")
  src.add("  sizeHorizontal*: uint8\n")
  src.add("  sizeVertical*: uint8\n\n")

  for e in entries:
    let constName = toShoutySnakeCase(e.name.split(':')[^1])
    src.add("const " & constName & "* = NoiseSettings(\n")
    src.add("  name: " & escapeNim(e.name) & ",\n")
    src.add("  seaLevel: " & $e.seaLevel & "'i32,\n")
    src.add("  defaultBlockName: " & escapeNim(e.defaultBlockName) & ",\n")
    src.add("  defaultFluidName: " & escapeNim(e.defaultFluidName) & ",\n")
    src.add("  legacyRandomSource: " & $e.legacyRandomSource & ",\n")
    src.add("  minY: " & $e.minY & "'i32,\n")
    src.add("  height: " & $e.height & "'i32,\n")
    src.add("  sizeHorizontal: " & $e.sizeHorizontal & "'u8,\n")
    src.add("  sizeVertical: " & $e.sizeVertical & "'u8,\n")
    src.add(")\n\n")

  src.add("proc allNoiseSettings*(): seq[NoiseSettings] =\n")
  src.add("  @[\n")
  for e in entries:
    src.add("    " & toShoutySnakeCase(e.name.split(':')[^1]) & ",\n")
  src.add("  ]\n\n")

  src.add("proc noiseSettingsFromName*(name: string): (bool, NoiseSettings) =\n")
  src.add("  case name\n")
  for e in entries:
    src.add("  of " & escapeNim(e.name) & ", " & escapeNim(e.name.split(':')[^1]) & ":\n")
    src.add("    (true, " & toShoutySnakeCase(e.name.split(':')[^1]) & ")\n")
  src.add("  else:\n")
  src.add("    (false, NoiseSettings())\n")

  try:
    writeFile("src/generated/noise_settings.nim", src)
  except ErrorCode as e:
    echo "write failed: " & $e
  echo "wrote src/generated/noise_settings.nim (", entries.len, " noise settings)"

main()
