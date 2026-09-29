## Round-trip smoke test for poi.nim, run via `nimony c -r src/world/poitest.nim`.

import std/assertions
import std/syncio
import tick
import poi

proc main() =
  var region = newPoiRegion()
  assert not region.dirty

  region.add(newPortalEntry(blockPos(10, 64, -5)))
  region.add(PoiEntry(x: 10, y: 70, z: -5, poiType: "minecraft:home", freeTickets: 3))
  region.add(PoiEntry(x: 300, y: 64, z: 300, poiType: "minecraft:meeting", freeTickets: 1))
  assert region.dirty
  assert region.getAll().len == 3

  # Same chunk (10>>4 == 0, -5>>4 == -1), different chunk for the third.
  let (found0, chunk0) = region.getChunkData(0, -1)
  assert found0
  assert chunk0.dataVersion == 3955
  # y=64 -> section 4, y=70 -> section 4 too (70 shr 4 == 4).
  assert chunk0.sectionKeys.len == 1
  assert chunk0.sections[0].records.len == 2

  let (found1, chunk1) = region.getChunkData(18, 18)
  assert found1
  assert chunk1.sections[0].records.len == 1
  assert chunk1.sections[0].records[0].poiType == "minecraft:meeting"

  let (foundEmpty, _) = region.getChunkData(999, 999)
  assert not foundEmpty

  # NBT round-trip: build -> parse -> compare.
  let nbt = buildChunkNbt(chunk0)
  let back = parseChunkNbt(nbt)
  assert back.dataVersion == chunk0.dataVersion
  assert back.sectionKeys == chunk0.sectionKeys
  assert back.sections.len == chunk0.sections.len
  assert back.sections[0].valid == chunk0.sections[0].valid
  assert back.sections[0].records.len == chunk0.sections[0].records.len
  # Records may come back in a different order than added (both are just
  # "the two entries in this chunk"); check membership rather than order.
  var sawPortal = false
  var sawHome = false
  for r in back.sections[0].records:
    if r.poiType == PoiTypeNetherPortal and r.x == 10 and r.y == 64 and r.z == -5:
      sawPortal = true
    if r.poiType == "minecraft:home" and r.freeTickets == 3:
      sawHome = true
  assert sawPortal
  assert sawHome

  assert region.remove(blockPos(10, 64, -5))
  assert region.getAll().len == 2
  assert not region.remove(blockPos(10, 64, -5))  # already gone

  region.markClean()
  assert not region.dirty

  echo "poi.nim: all checks passed"

main()
