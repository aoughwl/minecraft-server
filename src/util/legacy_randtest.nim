## Verifies legacy_rand.nim against nbt/util's own Rust unit
## test vectors (legacy_rand.rs's `#[cfg(test)] mod test`), byte-for-byte -
## this file's whole purpose is deterministic world-gen, so "compiles" means
## nothing without this. Run with `nimony c -r src/util/legacy_randtest.nim`.
import std/assertions, std/syncio
import legacy_rand

block next_i32:
  var r = fromSeed(0)
  let expected = [-1155484576'i32, -723955400, 1033096058, -1690734402, -1557280266,
                   1327362106, -1930858313, 502539523, -1728529858, -938301587]
  for e in expected:
    assert nextI32(r) == e

block next_bounded_i32:
  var r = fromSeed(0)
  let expected = [0'i32, 13, 4, 2, 5, 8, 11, 6, 9, 14]
  for e in expected:
    assert nextBoundedI32(r, 0xf) == e

  var r2 = fromSeed(0)
  for i in 0 ..< 10:
    assert nextBoundedI32(r2, 1) == 0'i32

  var r3 = fromSeed(0)
  let expected3 = [1'i32, 1, 0, 1, 1, 0, 1, 0, 1, 1]
  for e in expected3:
    assert nextBoundedI32(r3, 2) == e

block next_inbetween_i32:
  var r = fromSeed(0)
  let expected = [1'i32, 5, 2, 12, 12, 6, 12, 10, 4, 3]
  for e in expected:
    assert nextInbetweenI32(r, 1, 12) == e

block next_inbetween_exclusive_i32:
  var r = fromSeed(0)
  let expected = [1'i32, 7, 9, 6, 7, 3, 3, 7, 3, 1]
  for e in expected:
    assert nextInbetweenI32Exclusive(r, 1, 12) == e

block next_f64:
  var r = fromSeed(0)
  let expected = [0.730967787376657, 0.24053641567148587, 0.6374174253501083,
                   0.5504370051176339, 0.5975452777972018, 0.3332183994766498,
                   0.3851891847407185, 0.984841540199809, 0.8791825178724801,
                   0.9412491794821144]
  for e in expected:
    assert nextF64(r) == e

block next_f32:
  var r = fromSeed(0)
  let expected = [0.73096776'f32, 0.831441'f32, 0.24053639'f32, 0.6063452'f32,
                   0.6374174'f32, 0.30905056'f32, 0.550437'f32, 0.1170066'f32,
                   0.59754527'f32, 0.7815346'f32]
  for e in expected:
    assert nextF32(r) == e

block next_i64:
  var r = fromSeed(0)
  let expected = [-4962768465676381896'i64, 4437113781045784766, -6688467811848818630,
                   -8292973307042192125, -7423979211207825555, 6146794652083548235,
                   7105486291024734541, -279624296851435688, -2228689144322150137,
                   -1083761183081836303]
  for e in expected:
    assert nextI64(r) == e

block next_bool:
  var r = fromSeed(0)
  let expected = [true, true, false, true, true, false, true, false, true, true]
  for e in expected:
    assert nextBool(r) == e

block next_gaussian:
  var r = fromSeed(0)
  let expected = [0.8025330637390305, -0.9015460884175122, 2.080920790428163,
                   0.7637707684364894, 0.9845745328825128, -1.6834122587673428,
                   -0.027290262907887285, 0.11524570286202315, -0.39016704137993774,
                   -0.643388813126449]
  for e in expected:
    assert nextGaussian(r) == e

block next_triangular:
  var r = fromSeed(0)
  let expected = [124.52156858525856, 104.34902101162372, 113.2163439160276,
                   70.01738222704547, 96.89666691951828, 107.30284075808541,
                   106.16817675813144, 79.11264482608078, 73.96721613927062,
                   81.72419521080646]
  for e in expected:
    assert nextTriangular(r, 100.0, 50.0) == e

block split:
  var r0 = fromSeed(0)
  assert nextI64(r0) == -4962768465676381896'i64

  var r1 = fromSeed(0)
  let splitter1 = newSplitter(r1)
  assert splitter1.seed == cast[uint64](-4962768465676381896'i64)
  var randA = splitString(splitter1, "minecraft:offset")
  assert nextI32(randA) == 103436829'i32

  var origRand = fromSeed(0)
  var newRand = split(origRand)
  let splitter2 = newSplitter(newRand)

  var rand1 = splitString(splitter2, "TEST STRING")
  assert nextI32(rand1) == -1170413697'i32

  var rand2 = splitU64(splitter2, 10)
  assert nextI32(rand2) == -1157793070'i32

  var rand3 = splitPos(splitter2, 1, 11, -111)
  assert nextI32(rand3) == -1213890343'i32

  assert nextI32(origRand) == 1033096058'i32
  assert nextI32(newRand) == -888301832'i32

echo "legacy_rand: all upstream test vectors matched"
