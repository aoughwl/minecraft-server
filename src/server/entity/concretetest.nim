## Proves the two new concrete entity types actually work, split into what
## CAN be run today vs. what's blocked on the known closure-through-vtable
## runtime crash (see entity/README.md - confirmed independently twice
## already, `nimony check` passes, `nimony c -r` crashes in
## `eraiser.nim(128,3) 'fnType.tagEnum == ParamsTagId' [AssertionDefect]`).
##
## REFINED FINDING from isolating this file: the crash is NOT gated on
## actually calling through a `{.closure.}` vtable field. This file never
## calls `markerBaseOf`/`experienceOrbBaseOf` (the only procs that
## construct `EntityBase`'s closure fields) - it only constructs the plain
## `Entity`/`MarkerEntity`/`ExperienceOrbEntity` ref objects and checks
## plain fields - yet `nimony c -r` still crashes before printing
## anything, including before the very first `roundToOrbSize` check.
## `orbsizetest.nim` (same directory, zero import of `entity.nim`) proves
## `roundToOrbSize` itself is correct and runnable in isolation - the
## crash disappears entirely once nothing in the compiled binary reaches
## code that constructs `EntityBase`'s closure fields, even code that's
## never executed. That points at something in closure-lifting/lowering
## happening at whole-binary init or link time, not at the call site -
## useful detail for whoever fixes the underlying compiler bug, since it
## means the trigger is "closure-constructing code is reachable in the
## binary" not "closure-constructing code runs".

import std/syncio
import std/assertions
import entity, marker, experienceorb
import ../../nbt/tag
import ../../generated/entity_pose
import ../../generated/entity_type
import ../../util/vector3

proc realDims(name: string): EntityDimensions =
  ## Looks up real width/height/eyeHeight from `src/generated/entity_type.nim`
  ## instead of the ad-hoc guesses this file used before that table existed.
  let (found, et) = entityTypeByName(name)
  if found:
    EntityDimensions(width: et.dimensionW, height: et.dimensionH, eyeHeight: et.eyeHeight)
  else:
    EntityDimensions(width: 0.5'f32, height: 0.98'f32, eyeHeight: 0.0'f32)

var failures = 0

proc check(cond: bool, msg: string) =
  if not cond:
    echo "FAIL: " & msg
    inc failures
  else:
    echo "ok: " & msg

# --- roundToOrbSize: pure function, no vtable, safe to run today ----------

check(roundToOrbSize(10000'u32) == 2477'u32, "roundToOrbSize(10000) == 2477")
check(roundToOrbSize(2477'u32) == 2477'u32, "roundToOrbSize(2477) == 2477")
check(roundToOrbSize(2476'u32) == 1237'u32, "roundToOrbSize(2476) == 1237")
check(roundToOrbSize(5'u32) == 3'u32, "roundToOrbSize(5) == 3")
check(roundToOrbSize(2'u32) == 1'u32, "roundToOrbSize(2) == 1")
check(roundToOrbSize(0'u32) == 1'u32, "roundToOrbSize(0) == 1 (matches upstream's fallthrough, not a real spawn case)")

# Reference: splitting 100 xp should sum back to 100 across orb-sized chunks,
# matching what ExperienceOrbEntity.spawn's loop would produce.
block:
  var remaining = 100'u32
  var total = 0'u32
  var iterations = 0
  while remaining > 0'u32 and iterations < 100:
    let orb = roundToOrbSize(remaining)
    remaining -= orb
    total += orb
    inc iterations
  check(total == 100'u32, "orb-splitting loop over 100 xp sums back to 100")

# --- EntityBase construction/dispatch: compiles clean, not run at RUNTIME -
# via the vtable dispatch path due to the known closure/vtable crash. The
# construction and field-access below (not calling through the vtable
# procs) is still real signal that the types compose correctly.

let baseEntity = newEntity(1'i32, "00000000-0000-0000-0000-000000000001", realDims("marker"))
let markerEnt = newMarkerEntity(baseEntity)
check(markerEnt.entity.entityId == 1'i32, "MarkerEntity wraps its Entity correctly")
check(markerEnt.data.names.len == 0, "MarkerEntity starts with empty custom data")
check(markerEnt.entity.dimensions.width == 0.0'f32, "marker's real dimensions are 0x0 (invisible anchor)")

let orbEntity = newEntity(2'i32, "00000000-0000-0000-0000-000000000002", realDims("experience_orb"))
let orb = newExperienceOrbEntity(orbEntity, 37'u32)
check(orb.amount == 37'u32, "ExperienceOrbEntity carries its amount")
check(orb.orbAge == 0'u32, "ExperienceOrbEntity starts at age 0")

# NOT called here (documented, not silently skipped): markerBaseOf(markerEnt),
# experienceOrbBaseOf(orb), and any dispatch through the resulting
# EntityBase (getEntity/tick/writeNbt/damage/...) - those exercise
# {.closure.} vtable fields, which crash `nimony c -r` per the known
# compiler bug. entity.nim's own entitytest.nim already documents this in
# detail; re-confirming it here would just be the third repro of the same
# root cause, not new information.

if failures == 0:
  echo "all runnable concrete-entity checks passed (" & $6 & " orb-size checks + splitting + construction)"
else:
  echo $failures & " check(s) failed"
