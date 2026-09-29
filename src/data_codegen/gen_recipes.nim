## Generator for crafting/cooking/stonecutting recipes.
## Port of upstream/tools/pumpkin-codegen/src/recipes.rs, scoped to the
## common recipe types (crafting_shaped, crafting_shapeless, smelting,
## blasting, smoking, campfire_cooking, stonecutting) - these cover the
## overwhelming majority of the ~1763 real recipe files. Deliberately NOT
## ported this pass: crafting_transmute, crafting_decorated_pot,
## smithing_transform, smithing_trim, and the crafting_special_* family
## (banner duplicate, book cloning, firework assembly, map extending,
## item repair, shield decoration, dye, imbue) - each is a special-cased
## Java-side algorithm, not data-driven, so "porting" them here would mean
## fabricating fields with no real source; they need their own pass once
## src/inventory/crafting.nim grows real slot-matching logic to call them
## from. Recipe ids are the JSON filename stems, matching upstream's
## `fs::read_dir` + `file_stem()` (NOT the unused `generate_recipe_id`
## helper in the same upstream file, which nothing actually calls for the
## id passed to `to_tokens_with_id`).

import std/[syncio, json, paths, dirs, strutils]
import codegenutil

type
  RawRecipe = object
    id: string
    typ: string
    node: JsonNode

proc collectRecipeFiles(dir: Path): seq[(string, Path)] =
  ## Two-pass (collect paths, then read) per the established house rule:
  ## nesting readFile inside try inside walkDir breaks C-codegen.
  listJsonStems(dir)

proc readRawRecipes(dir: Path): seq[RawRecipe] =
  result = @[]
  for (stem, path) in collectRecipeFiles(dir):
    var tree = parseFile($path)
    let obj = root(tree)
    var typ = ""
    for k, v in obj.pairs():
      if k == "type":
        typ = v.getStr()
    result.add(RawRecipe(id: stem, typ: typ, node: obj))

proc ingredientLit(n: JsonNode): string =
  ## Emits a `RecipeIngredient(...)` literal from a JSON ingredient value,
  ## which upstream's `RecipeIngredientTypes` deserializes from either a
  ## plain string (item id, or `#namespace:tag` for a tag reference) or an
  ## array of alternative item ids.
  case n.kind
  of JString:
    let s = n.getStr()
    if s.len > 0 and s[0] == '#':
      "RecipeIngredient(kind: rikTagged, name: " & escape(s) & ")"
    else:
      "RecipeIngredient(kind: rikSimple, name: " & escape(s) & ")"
  of JArray:
    var opts = "@["
    var first = true
    for elem in n:
      if not first: opts.add(", ")
      opts.add(escape(elem.getStr()))
      first = false
    opts.add("]")
    "RecipeIngredient(kind: rikOneOf, options: " & opts & ")"
  else:
    "RecipeIngredient(kind: rikSimple, name: \"minecraft:air\")"

proc resultLit(n: JsonNode): string =
  var id = "minecraft:air"
  var count = 1
  for k, v in n.pairs():
    case k
    of "id": id = v.getStr()
    of "count": count = int(v.getInt())
  "RecipeResult(id: " & escape(id) & ", count: " & $count & "'u8)"

proc categoryConst(n: JsonNode): string =
  for k, v in n.pairs():
    if k == "category":
      case v.getStr()
      of "equipment": return "rcEquipment"
      of "building": return "rcBuilding"
      of "redstone": return "rcRedstone"
      of "food": return "rcFood"
      of "blocks": return "rcBlocks"
      else: return "rcMisc"
  "rcMisc"

proc groupLit(n: JsonNode): string =
  for k, v in n.pairs():
    if k == "group":
      return escape(v.getStr())
  "\"\""

proc buildShaped(id: string, n: JsonNode): string =
  var keyChars = "@["
  var keyIngs = "@["
  var firstKey = true
  var patternLit = "@["
  var firstPattern = true
  var resultL = "RecipeResult(id: \"minecraft:air\", count: 1'u8)"
  var showNotif = true
  for k, v in n.pairs():
    case k
    of "key":
      for ck, cv in v.pairs():
        if not firstKey:
          keyChars.add(", ")
          keyIngs.add(", ")
        keyChars.add("'" & ck & "'")
        keyIngs.add(ingredientLit(cv))
        firstKey = false
    of "pattern":
      for row in v:
        if not firstPattern: patternLit.add(", ")
        patternLit.add(escape(row.getStr()))
        firstPattern = false
    of "result":
      resultL = resultLit(v)
    of "show_notification":
      showNotif = v.getBool()
    else: discard
  keyChars.add("]")
  keyIngs.add("]")
  patternLit.add("]")
  "ShapedRecipe(id: " & escape(id) & ", category: " & categoryConst(n) &
    ", group: " & groupLit(n) & ", showNotification: " & $showNotif &
    ", keyChars: " & keyChars & ", keyIngredients: " & keyIngs &
    ", pattern: " & patternLit & ", result: " & resultL & ")"

proc buildShapeless(id: string, n: JsonNode): string =
  var ings = "@["
  var first = true
  var resultL = "RecipeResult(id: \"minecraft:air\", count: 1'u8)"
  for k, v in n.pairs():
    case k
    of "ingredients":
      for elem in v:
        if not first: ings.add(", ")
        ings.add(ingredientLit(elem))
        first = false
    of "result":
      resultL = resultLit(v)
    else: discard
  ings.add("]")
  "ShapelessRecipe(id: " & escape(id) & ", category: " & categoryConst(n) &
    ", group: " & groupLit(n) & ", ingredients: " & ings &
    ", result: " & resultL & ")"

proc buildCooking(id, kindConst: string, n: JsonNode, defaultTime: int): string =
  var ingLit = "RecipeIngredient(kind: rikSimple, name: \"minecraft:air\")"
  var cookingTime = defaultTime
  var experience = 0.0
  var resultL = "RecipeResult(id: \"minecraft:air\", count: 1'u8)"
  for k, v in n.pairs():
    case k
    of "ingredient": ingLit = ingredientLit(v)
    of "cookingtime": cookingTime = int(v.getInt())
    of "experience": experience = v.getFloat()
    of "result": resultL = resultLit(v)
    else: discard
  "CookingRecipe(id: " & escape(id) & ", kind: " & kindConst &
    ", category: " & categoryConst(n) & ", group: " & groupLit(n) &
    ", ingredient: " & ingLit & ", cookingTime: " & $cookingTime &
    "'i32, experience: " & $experience & "'f32, result: " & resultL & ")"

proc buildStonecutting(id: string, n: JsonNode): string =
  var ingLit = "RecipeIngredient(kind: rikSimple, name: \"minecraft:air\")"
  var resultL = "RecipeResult(id: \"minecraft:air\", count: 1'u8)"
  for k, v in n.pairs():
    case k
    of "ingredient": ingLit = ingredientLit(v)
    of "result": resultL = resultLit(v)
    else: discard
  "StonecutterRecipe(id: " & escape(id) & ", group: " & groupLit(n) &
    ", ingredient: " & ingLit & ", result: " & resultL & ")"

proc main() =
  let recipes = readRawRecipes(path("../upstream-ref/assets/datapack/data/minecraft/recipe"))

  var shapedLits: seq[string] = @[]
  var shapelessLits: seq[string] = @[]
  var cookingLits: seq[string] = @[]
  var stonecuttingLits: seq[string] = @[]
  var skippedByType: seq[(string, int)] = @[]

  for r in recipes:
    case r.typ
    of "minecraft:crafting_shaped":
      shapedLits.add(buildShaped(r.id, r.node))
    of "minecraft:crafting_shapeless":
      shapelessLits.add(buildShapeless(r.id, r.node))
    of "minecraft:smelting":
      cookingLits.add(buildCooking(r.id, "crkSmelting", r.node, 200))
    of "minecraft:blasting":
      cookingLits.add(buildCooking(r.id, "crkBlasting", r.node, 100))
    of "minecraft:smoking":
      cookingLits.add(buildCooking(r.id, "crkSmoking", r.node, 100))
    of "minecraft:campfire_cooking":
      cookingLits.add(buildCooking(r.id, "crkCampfireCooking", r.node, 100))
    of "minecraft:stonecutting":
      stonecuttingLits.add(buildStonecutting(r.id, r.node))
    else:
      var found = false
      for i in 0 ..< skippedByType.len:
        if skippedByType[i][0] == r.typ:
          skippedByType[i][1] = skippedByType[i][1] + 1
          found = true
      if not found:
        skippedByType.add((r.typ, 1))

  var shapedBody = "@[\n"
  for i, s in shapedLits:
    shapedBody.add("  " & s & (if i < shapedLits.len - 1: ",\n" else: "\n"))
  shapedBody.add("]")

  var shapelessBody = "@[\n"
  for i, s in shapelessLits:
    shapelessBody.add("  " & s & (if i < shapelessLits.len - 1: ",\n" else: "\n"))
  shapelessBody.add("]")

  var cookingBody = "@[\n"
  for i, s in cookingLits:
    cookingBody.add("  " & s & (if i < cookingLits.len - 1: ",\n" else: "\n"))
  cookingBody.add("]")

  var stonecuttingBody = "@[\n"
  for i, s in stonecuttingLits:
    stonecuttingBody.add("  " & s & (if i < stonecuttingLits.len - 1: ",\n" else: "\n"))
  stonecuttingBody.add("]")

  var skipComment = "## Skipped recipe types this pass (counts): "
  for i, (t, n) in skippedByType:
    skipComment.add(t & "=" & $n)
    if i < skippedByType.len - 1: skipComment.add(", ")
  skipComment.add("\n")

  let output = "## Crafting/cooking/stonecutting recipe tables.\n" &
    "## Generated by gen_recipes.nim from upstream/assets/datapack/data/minecraft/recipe/*.json\n" &
    "## - do not edit by hand.\n" &
    skipComment & "\n" &
    "type\n" &
    "  RecipeCategory* = enum\n" &
    "    rcEquipment, rcBuilding, rcRedstone, rcMisc, rcFood, rcBlocks\n\n" &
    "  RecipeIngredientKind* = enum\n" &
    "    rikSimple, rikTagged, rikOneOf\n\n" &
    "  RecipeIngredient* = object\n" &
    "    case kind*: RecipeIngredientKind\n" &
    "    of rikSimple, rikTagged:\n" &
    "      name*: string\n" &
    "    of rikOneOf:\n" &
    "      options*: seq[string]\n\n" &
    "  RecipeResult* = object\n" &
    "    id*: string\n" &
    "    count*: uint8\n\n" &
    "  ShapedRecipe* = object\n" &
    "    id*: string\n" &
    "    category*: RecipeCategory\n" &
    "    group*: string\n" &
    "    showNotification*: bool\n" &
    "    keyChars*: seq[char]\n" &
    "    keyIngredients*: seq[RecipeIngredient]\n" &
    "    pattern*: seq[string]\n" &
    "    result*: RecipeResult\n\n" &
    "  ShapelessRecipe* = object\n" &
    "    id*: string\n" &
    "    category*: RecipeCategory\n" &
    "    group*: string\n" &
    "    ingredients*: seq[RecipeIngredient]\n" &
    "    result*: RecipeResult\n\n" &
    "  CookingRecipeKind* = enum\n" &
    "    crkSmelting, crkBlasting, crkSmoking, crkCampfireCooking\n\n" &
    "  CookingRecipe* = object\n" &
    "    id*: string\n" &
    "    kind*: CookingRecipeKind\n" &
    "    category*: RecipeCategory\n" &
    "    group*: string\n" &
    "    ingredient*: RecipeIngredient\n" &
    "    cookingTime*: int32\n" &
    "    experience*: float32\n" &
    "    result*: RecipeResult\n\n" &
    "  StonecutterRecipe* = object\n" &
    "    id*: string\n" &
    "    group*: string\n" &
    "    ingredient*: RecipeIngredient\n" &
    "    result*: RecipeResult\n\n" &
    "proc matches*(ing: RecipeIngredient, itemName: string): bool =\n" &
    "  ## `itemName` should be the full `minecraft:xxx` registry key. Tag\n" &
    "  ## matching (`rikTagged`) can't be resolved here - no tag membership\n" &
    "  ## table is ported yet - so it always returns false; callers that\n" &
    "  ## need real tag matching must special-case `ing.kind == rikTagged`\n" &
    "  ## against a real tag registry once one exists.\n" &
    "  case ing.kind\n" &
    "  of rikSimple: ing.name == itemName\n" &
    "  of rikTagged: false\n" &
    "  of rikOneOf: itemName in ing.options\n\n" &
    "let shapedRecipes* = " & shapedBody & "\n\n" &
    "let shapelessRecipes* = " & shapelessBody & "\n\n" &
    "let cookingRecipes* = " & cookingBody & "\n\n" &
    "let stonecutterRecipes* = " & stonecuttingBody & "\n"

  try:
    writeFile("src/generated/recipes.nim", output)
  except ErrorCode as e:
    echo "write failed: " & $e
  echo "wrote src/generated/recipes.nim (" & $shapedLits.len & " shaped, " &
    $shapelessLits.len & " shapeless, " & $cookingLits.len & " cooking, " &
    $stonecuttingLits.len & " stonecutting)"
  for (t, n) in skippedByType:
    echo "  skipped " & t & ": " & $n

main()
