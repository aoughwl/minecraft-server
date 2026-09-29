## Verifies gen_recipes.nim's output against a few hand-checked real
## recipe files. Actually run via `nimony c -r`, not just `nimony check`.

import std/[syncio, assertions]
import ../generated/recipes

# acacia_boat.json: crafting_shaped, key "#" -> acacia_planks, pattern
# ["# #", "###"], result minecraft:acacia_boat x1, no group/category set
# in source -> defaults rcMisc/"".
block:
  var found = false
  for r in shapedRecipes:
    if r.id == "acacia_boat":
      found = true
      assert r.pattern == @["# #", "###"]
      assert r.keyChars == @['#']
      assert r.keyIngredients.len == 1
      assert r.keyIngredients[0].kind == rikSimple
      assert r.keyIngredients[0].name == "minecraft:acacia_planks"
      assert r.result.id == "minecraft:acacia_boat"
      assert r.result.count == 1
      assert r.category == rcMisc
  assert found, "acacia_boat shaped recipe not found"

# acacia_button.json: crafting_shapeless, category redstone, group
# wooden_button, ingredients [acacia_planks], result acacia_button x1.
block:
  var found = false
  for r in shapelessRecipes:
    if r.id == "acacia_button":
      found = true
      assert r.category == rcRedstone
      assert r.group == "wooden_button"
      assert r.ingredients.len == 1
      assert r.ingredients[0].name == "minecraft:acacia_planks"
      assert r.result.id == "minecraft:acacia_button"
  assert found, "acacia_button shapeless recipe not found"

# baked_potato.json: smelting, category food, cookingtime 200 (matches
# the explicit source value, which happens to equal the default too),
# experience 0.35, ingredient potato, result baked_potato.
block:
  var found = false
  for r in cookingRecipes:
    if r.id == "baked_potato":
      found = true
      assert r.kind == crkSmelting
      assert r.category == rcFood
      assert r.cookingTime == 200
      assert r.experience > 0.349'f32 and r.experience < 0.351'f32
      assert r.ingredient.name == "minecraft:potato"
      assert r.result.id == "minecraft:baked_potato"
  assert found, "baked_potato smelting recipe not found"

# Sanity: matches() resolves rikSimple/rikOneOf correctly, and rikTagged
# is honestly false (no tag registry ported yet).
block:
  let ing = RecipeIngredient(kind: rikSimple, name: "minecraft:stick")
  assert matches(ing, "minecraft:stick")
  assert not matches(ing, "minecraft:stone")

  let oneOf = RecipeIngredient(kind: rikOneOf, options: @["minecraft:oak_log", "minecraft:spruce_log"])
  assert matches(oneOf, "minecraft:spruce_log")
  assert not matches(oneOf, "minecraft:birch_log")

  let tagged = RecipeIngredient(kind: rikTagged, name: "#minecraft:planks")
  assert not matches(tagged, "minecraft:oak_planks")

echo "recipes.nim: shaped=" & $shapedRecipes.len & " shapeless=" & $shapelessRecipes.len &
  " cooking=" & $cookingRecipes.len & " stonecutting=" & $stonecutterRecipes.len
echo "all recipe spot-checks passed"
