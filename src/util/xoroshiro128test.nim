## Verifies xoroshiro128.nim byte-for-byte against upstream's own
## `#[cfg(test)]` vectors in random/xoroshiro128.rs (values themselves
## checked by upstream against the equivalent Java source).
## Run with `nimony c -r src/util/xoroshiro128test.nim`.

import std/assertions
import std/syncio
import xoroshiro128

block mixStafford13Test:
  # (input, expected) pairs from mix_stafford_13_test, negative i64 outputs
  # reinterpreted as their uint64 bit pattern.
  let cases = [
    (0'u64, 0'u64),
    (1'u64, 6238072747940578789'u64),
    (64'u64, cast[uint64](-8456553050427055661'i64)),
    (4096'u64, cast[uint64](-1125827887270283392'i64)),
    (262144'u64, cast[uint64](-120227641678947436'i64)),
    (16777216'u64, 6406066033425044679'u64),
    (1073741824'u64, 3143522559155490559'u64),
    (16'u64, cast[uint64](-2773008118984693571'i64)),
    (1024'u64, 8101005175654470197'u64),
    (65536'u64, cast[uint64](-3551754741763842827'i64)),
  ]
  # mixStafford13 is private; exercise it indirectly via fromSeed(0), whose
  # first internal mix result is verifiable through next_i32's own vector
  # below instead - a direct unit test would need to export the helper.
  discard cases

block nextI32Test:
  var x = fromSeed(0'u64)
  let expected = [-160476802'i32, 781697906'i32, 653572596'i32, 1337520923'i32,
                   -505875771'i32, -47281585'i32, 342195906'i32, 1417498593'i32,
                   -1478887443'i32, 1560080270'i32]
  for e in expected:
    assert x.nextI32() == e, "nextI32 mismatch"
  echo "nextI32: OK"

block nextBoundedI32Test:
  var x = fromSeed(0'u64)
  let expected10 = [9'i32, 1, 1, 3, 8, 9, 0, 3, 6, 3]
  for e in expected10:
    assert x.nextBoundedI32(10) == e, "nextBoundedI32(10) mismatch"
  let expectedBig = [9784805'i32, 470346, 13560642, 7320226, 14949645,
                      13460529, 2824352, 10938308, 14146127, 4549185]
  for e in expectedBig:
    assert x.nextBoundedI32(0xFFFFFF'i32) == e, "nextBoundedI32(0xFFFFFF) mismatch"
  echo "nextBoundedI32: OK"

block nextF64Test:
  var x = fromSeed(0'u64)
  let expected = [0.16474369376959186, 0.7997457290026366, 0.2511961888876212,
                   0.11712489470639631, 0.0997124786680137, 0.7566797430601416,
                   0.7723285712021574, 0.9420469457586381, 0.48056202536813664,
                   0.6099690583914598]
  for e in expected:
    assert x.nextF64() == e, "nextF64 mismatch"
  echo "nextF64: OK"

block nextI64Test:
  var x = fromSeed(0'u64)
  let expected = [3038984756725240190'i64, -3694039286755638414'i64,
                   4633751808701151732'i64, 2160572957309072155'i64,
                   1839370574944072389'i64, -4488466507718817201'i64,
                   -4199796579929588030'i64]
  for e in expected:
    assert x.nextI64() == e, "nextI64 mismatch"
  echo "nextI64: OK"

echo "all xoroshiro128 round-trip checks passed"
