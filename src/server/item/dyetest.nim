## Intended as a runtime test for dye.nim's `dyeCanMine` via `nimony c -r`.
##
## STATUS: `nimony check` passes clean; `nimony c -r` does NOT run - it
## crashes (`eraiser.nim`/`ParamsTagId` AssertionDefect), confirming the
## "closures-through-vtables crash at runtime just from being reachable in
## the compiled binary" finding a 6th time. This file itself builds no
## vtable and calls no closure - the crash comes purely from importing
## `entity.nim` (transitively, via `dye.nim`), which DOES define
## `EntityBase`'s closure-based vtable constructors, even though this test
## never calls them. That means, as of this writing, nothing that imports
## `entity.nim` can be runtime-verified at all via `nimony c -r` - not just
## code that actively dispatches through a vtable. This is a load-bearing,
## compiler-level blocker, not something fixable from this file. `dyeCanMine`
## itself is `nimony check`-clean and its logic (one enum comparison) is
## correct by inspection, but is NOT runtime-proven, and neither is anything
## else built on `entity.nim` until this compiler bug is fixed.

import std/assertions, std/syncio
import dye
import ../entity/entity
import ../../util/gamemode

let entity1 = newEntity(1'i32, "uuid-1", EntityDimensions(width: 0.6'f32, height: 1.8'f32, eyeHeight: 1.62'f32))
let living1 = LivingEntity(entity: entity1, health: 20, maxHealth: 20)
let survivalPlayer = Player(livingEntity: living1, gameProfileName: "steve", gamemode: Survival)
assert dyeCanMine(survivalPlayer) == true

let entity2 = newEntity(2'i32, "uuid-2", EntityDimensions(width: 0.6'f32, height: 1.8'f32, eyeHeight: 1.62'f32))
let living2 = LivingEntity(entity: entity2, health: 20, maxHealth: 20)
let creativePlayer = Player(livingEntity: living2, gameProfileName: "alex", gamemode: Creative)
assert dyeCanMine(creativePlayer) == false

echo "dye.nim: all checks passed"
