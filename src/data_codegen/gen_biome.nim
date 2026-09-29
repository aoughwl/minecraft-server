## Generates src/generated/biome.nim from the upstream reference's biome
## datapack JSON files.
## Port of upstream/tools/pumpkin-codegen/src/biome.rs
##
## Scope note: upstream's `Biome` also carries `spawners`/`spawn_costs`
## (natural mob-spawn tables, themselves sometimes nested inside an
## `attributes."minecraft:gameplay/natural_mob_spawns"` override - see
## `apply_natural_mob_spawns` in biome.rs), the full `attributes` map
## (cosmetic/gameplay overrides keyed by tag, values of arbitrary shape),
## and `effects` (water/sky/fog color etc., client-rendering data). All of
## that is real work with its own edge cases (a `count` field that's either
## a bare int or a `{type, min_inclusive, max_inclusive}` uniform-provider
## object, same shape dimension.rs's `monster_spawn_light_level` has) and
## isn't needed for src/world/biomeparam.nim's climate-parameter math, so
## it's deferred here - this generator ports has_precipitation/temperature/
## downfall/temperature_modifier/carvers/features only. There is no `id`
## field in the source JSON (registry ids come from registry.rs's ordering,
## already captured separately in src/generated/registry_data.nim's
## `worldgen/biome` entries) - biomeFromName below is name-keyed, not
## id-keyed, matching what biomeparam.nim actually needs (a biome's climate
## data by name, not a numeric id).

import std/[json, paths, strutils, syncio]
import codegenutil

type BiomeEntry = object
  name: string
  hasPrecipitation: bool
  temperature: float
  downfall: float
  temperatureModifier: string
  carvers: seq[string]
  features: seq[string]

proc readCarvers(root: JsonNode): seq[string] =
  ## Port of biome.rs's `deserialize_carvers`: the JSON value is either a
  ## bare string or a list of strings; absent -> empty.
  result = @[]
  for k, v in root.pairs():
    if k == "carvers":
      case v.kind
      of JString:
        result.add(v.getStr())
      of JArray:
        for item in v.items():
          result.add(item.getStr())
      else:
        discard

proc readFeatures(root: JsonNode): seq[string] =
  ## Upstream's `features: Vec<Vec<String>>` is a list of per-step feature
  ## lists; flattened here (step boundaries aren't needed for climate math,
  ## and preserving them would need a seq[seq[string]] literal, itself a
  ## `const`-fold risk already hit elsewhere in this port with large seqs).
  result = @[]
  for k, v in root.pairs():
    if k == "features":
      for step in v.items():
        for item in step.items():
          result.add(item.getStr())

proc loadBiome(name: string, path: Path): BiomeEntry {.noinit.} =
  var tree = parseFile($path)
  let root = root(tree)
  result = BiomeEntry(name: "minecraft:" & name, temperatureModifier: "")
  for key, val in root.pairs():
    case key
    of "has_precipitation": result.hasPrecipitation = val.getBool()
    of "temperature": result.temperature = val.getFloat()
    of "downfall": result.downfall = val.getFloat()
    of "temperature_modifier": result.temperatureModifier = val.getStr()
    else: discard
  result.carvers = readCarvers(root)
  result.features = readFeatures(root)

proc escapeNim(s: string): string =
  result = "\""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    else: result.add(c)
  result.add("\"")

proc seqLit(items: seq[string]): string =
  result = "@["
  for i, it in items:
    if i > 0: result.add(", ")
    result.add(escapeNim(it))
  result.add("]")

proc main() =
  let dir = path("../upstream-ref/assets/datapack/data/minecraft/worldgen/biome")
  let stems = listJsonStems(dir)
  var entries: seq[BiomeEntry] = @[]
  for i in 0 ..< stems.len:
    entries.add(loadBiome(stems[i][0], stems[i][1]))

  var src = "## Generated from upstream's worldgen/biome datapack JSON.\n"
  src.add("## Port of upstream/tools/pumpkin-codegen/src/biome.rs (climate fields only - see gen_biome.nim).\n\n")
  src.add("type Biome* = object\n")
  src.add("  name*: string\n")
  src.add("  hasPrecipitation*: bool\n")
  src.add("  temperature*: float32\n")
  src.add("  downfall*: float32\n")
  src.add("  temperatureModifier*: string\n")
  src.add("  carvers*: seq[string]\n")
  src.add("  features*: seq[string]\n\n")

  proc constNameOf(e: BiomeEntry): string =
    toShoutySnakeCase(e.name.split(':')[^1])

  for e in entries:
    src.add("let " & constNameOf(e) & "* = Biome(\n")
    src.add("  name: " & escapeNim(e.name) & ",\n")
    src.add("  hasPrecipitation: " & $e.hasPrecipitation & ",\n")
    src.add("  temperature: " & $e.temperature & "'f32,\n")
    src.add("  downfall: " & $e.downfall & "'f32,\n")
    src.add("  temperatureModifier: " & escapeNim(e.temperatureModifier) & ",\n")
    src.add("  carvers: " & seqLit(e.carvers) & ",\n")
    src.add("  features: " & seqLit(e.features) & ",\n")
    src.add(")\n\n")

  src.add("proc allBiomes*(): seq[Biome] =\n")
  src.add("  @[\n")
  for e in entries:
    src.add("    " & constNameOf(e) & ",\n")
  src.add("  ]\n\n")

  src.add("proc biomeFromName*(name: string): (bool, Biome) =\n")
  src.add("  case name\n")
  for e in entries:
    src.add("  of " & escapeNim(e.name) & ", " & escapeNim(e.name.split(':')[^1]) & ":\n")
    src.add("    (true, " & constNameOf(e) & ")\n")
  src.add("  else:\n")
  src.add("    (false, Biome())\n")

  try:
    writeFile("src/generated/biome.nim", src)
  except ErrorCode as e:
    echo "write failed: " & $e
  echo "wrote src/generated/biome.nim (", entries.len, " biomes)"

main()
