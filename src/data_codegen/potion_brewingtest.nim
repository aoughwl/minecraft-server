## Verifies src/generated/potion_brewing.nim's real data, run via
## `nimony c -r`. Spot-checked against the actual source JSON:
## `lingering_potion_awkward_blaze_powder.json` (the first alphabetically,
## matching upstream's own path-sort order).

import std/[assertions, syncio]
import ../generated/potion_brewing

let recipes = allBrewingRecipes()
assert recipes.len == 279, "expected 279 real brewing recipes, got " & $recipes.len

let first = recipes[0]
assert first.fromItem == "lingering_potion"
assert first.fromPotion == "awkward"
assert first.ingredient == "blaze_powder"
assert first.toItem == "lingering_potion"
assert first.toPotion == "strength"

## Every recipe's fields should be non-empty (a parse failure on a
## missing key would leave one blank rather than fail loudly, per
## parseBrewingRecipe's `if found: ... else: ""` fallback - catch that
## here rather than trust the generator silently).
for r in recipes:
  assert r.fromItem.len > 0, "empty fromItem in a recipe"
  assert r.fromPotion.len > 0, "empty fromPotion in a recipe"
  assert r.ingredient.len > 0, "empty ingredient in a recipe"
  assert r.toItem.len > 0, "empty toItem in a recipe"
  assert r.toPotion.len > 0, "empty toPotion in a recipe"

echo "potion_brewing: all checks passed (" & $recipes.len & " recipes)"
