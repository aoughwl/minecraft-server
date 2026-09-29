## Verifies src/generated/bedrock_creative.nim's real data, run via
## `nimony c -r`. Spot-checked against the real source JSON: the first
## creative group (`itemGroup.name.planks`, category `construction`,
## icon `minecraft:oak_planks` -> real runtime item id 5).

import std/[assertions, syncio]
import ../generated/bedrock_creative

let groups = creativeGroups()
let entries = creativeEntries()

assert groups.len == 124, "expected 124 real creative groups, got " & $groups.len
assert entries.len == 1980, "expected 1980 real creative entries, got " & $entries.len

let first = groups[0]
assert first.category == 1, "expected 'construction' category to map to 1"
assert first.name == "itemGroup.name.planks"
assert first.iconItemId == 5'i16, "expected oak_planks' real runtime item id (5)"

## Every entry's groupIndex should reference a real group.
for e in entries:
  assert e.groupIndex < uint32(groups.len), "entry references an out-of-range group index"

echo "bedrock_creative: all checks passed (" & $groups.len & " groups, " & $entries.len & " entries)"
