## Smoke test for src/generated/entity_type.nim - run with
## `nimony c -r src/data_codegen/entity_typetest.nim`.
import std/[assertions, syncio]
import "../generated/entity_type"

let all = allEntityTypes()
assert all.len == 161, "expected 161 entity types, got " & $all.len

let (foundOrb, orb) = entityTypeByName("experience_orb")
assert foundOrb
assert orb.id == 50'u16
assert orb.mob == false
assert orb.dimensionW == 0.5'f32
assert orb.dimensionH == 0.5'f32

let (foundMarker, marker) = entityTypeByName("marker")
assert foundMarker
assert marker.dimensionW == 0.0'f32
assert marker.dimensionH == 0.0'f32

let (foundSnowball, snowball) = entityTypeByName("snowball")
assert foundSnowball
assert snowball.dimensionW == 0.25'f32
assert snowball.eyeHeight == 0.2125'f32

let (foundMissing, _) = entityTypeByName("not_a_real_entity")
assert not foundMissing

echo "entity_type generator: all checks passed"
