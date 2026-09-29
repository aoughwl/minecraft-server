## Exercises `codegenutil.genU16Bitset` (port of upstream's `bitsets.rs`
## codegen helper) directly - not against a JSON asset (it has none of its
## own; it's a shared builder other generators call with ids they already
## have), so this test builds a small id set by hand, generates the Nimony
## source, writes+compiles it, and checks the emitted `contains` proc
## against the expected membership - the same "actually run it, don't just
## eyeball the string" bar the rest of this codegen suite holds to.

import std/[syncio, osproc, strutils, assertions]
import codegenutil

let testIds = @[3'u16, 5'u16, 64'u16, 130'u16, 9'u16]

let src = genU16Bitset("testset", testIds)
let genFile = "bitsetgentmp.nim"
let genSrc = "import std/assertions\nimport std/syncio\n" & src & """

for id in 0'u16 .. 140'u16:
  let expected = id in @[3'u16, 5'u16, 64'u16, 130'u16, 9'u16]
  assert testsetContains(id) == expected, "mismatch at id " & $id
echo "bitset generator: all ids 0..140 match expected membership"
"""

var runCode = -1
var runOutput = ""
try:
  writeFile(genFile, genSrc)
  let (output, code) = execCmdEx(r"C:\Users\savant\nimony\bin\nimony.exe c -r bitsetgentmp.nim")
  runOutput = output
  runCode = code
except ErrorCode:
  discard

echo runOutput
assert runCode == 0, "generated bitset code failed to compile/run"
