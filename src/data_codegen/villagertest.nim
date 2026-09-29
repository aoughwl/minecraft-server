## Verifies gen_villager.nim's output against real source JSON. Run with
## `nimony c -r src/data_codegen/villagertest.nim`.

import std/[syncio, assertions]
import "../generated/villager"

let profs = allVillagerProfessions()
assert profs.len == 15

var farmerIdx = -1
for i, p in profs:
  if p.name == "farmer":
    farmerIdx = i
assert farmerIdx >= 0
let farmer = profs[farmerIdx]
assert farmer.translate == "entity.minecraft.villager.farmer"
assert farmer.requestedItems == @["minecraft:wheat", "minecraft:wheat_seeds", "minecraft:beetroot_seeds", "minecraft:bone_meal"]
assert farmer.workSound == "minecraft:entity.villager.work_farmer"

var noneIdx = -1
for i, p in profs:
  if p.name == "none":
    noneIdx = i
assert profs[noneIdx].workSound == "" # upstream has no work_sound for "none"

let types = villagerTypeNames()
assert types.len == 7
assert villagerTypeNamespace("desert") == "minecraft:desert"
assert villagerTypeNamespace("nonexistent") == ""

echo "villager: all checks passed"
