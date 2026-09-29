## Actually runs gen_noise_settings.nim against the real assets and
## verifies its output, following this suite's "run it, don't eyeball the
## string" bar.

import std/[syncio, osproc, assertions, strutils]

var runCode = -1
var runOutput = ""
try:
  let (output, code) = execCmdEx(r"C:\Users\savant\nimony\bin\nimony.exe c -r src\data_codegen\gen_noise_settings.nim")
  runOutput = output
  runCode = code
except ErrorCode:
  discard
echo runOutput
assert runCode == 0, "gen_noise_settings.nim failed to run"

var checkOutput = ""
var checkCode = -1
try:
  let checkCmd = execCmdEx(r"C:\Users\savant\nimony\bin\nimony.exe check src\generated\noise_settings.nim")
  checkOutput = checkCmd[0]
  checkCode = checkCmd[1]
except ErrorCode:
  discard
assert checkCode == 0, "generated noise_settings.nim failed nimony check: " & checkOutput

var src = ""
try:
  src = readFile("src/generated/noise_settings.nim")
except ErrorCode:
  discard
assert src.find("seaLevel: 63'i32") >= 0, "overworld sea level mismatch"
assert src.find("minY: -64'i32") >= 0, "overworld minY mismatch"
assert src.find("height: 384'i32") >= 0, "overworld height mismatch"
assert src.find("defaultBlockName: \"minecraft:netherrack\"") >= 0, "nether default block mismatch"
assert src.find("seaLevel: 0'i32") >= 0, "end sea level mismatch"

echo "noise_settings generator: real values verified (overworld, nether, end)"
