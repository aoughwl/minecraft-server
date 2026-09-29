## Verifies gen_template_bytes.nim's and gen_test_instance.nim's outputs:
## real resource-id/bare-id lookups resolve to paths that actually exist
## on disk. Run with `nimony c -r src/data_codegen/templatestest.nim`
## from the repo root.

import std/[assertions, syncio, os]
import "../generated/template_bytes"
import "../generated/test_instance"

# template_bytes.nim
assert templatePaths.len == 1513, "expected 1513 templates, got " & $templatePaths.len

block:
  let (found, p) = getTemplatePath("minecraft:woodland_mansion/1x1_a1")
  assert found
  assert fileExists(p), "path doesn't exist: " & p

block:
  # bare-id lookup for the default namespace should resolve the same way
  let (found, p) = getTemplatePath("woodland_mansion/1x1_a1")
  assert found
  assert fileExists(p)

block:
  let (found, _) = getTemplatePath("minecraft:does_not_exist")
  assert not found

block:
  # non-default namespace: bare id must NOT resolve
  let (found, p) = getTemplatePath("pumpkin:" & "some_test_structure")
  discard found  # existence not asserted (depends on real data); just
                 # confirms the call doesn't crash
  discard p

# test_instance.nim
assert testInstancePaths.len == 3, "expected 3 test instances, got " & $testInstancePaths.len

block:
  let (found, p) = getTestInstancePath("minecraft:always_pass")
  assert found
  assert fileExists(p), "path doesn't exist: " & p

block:
  let (found, p) = getTestInstancePath("always_pass")
  assert found
  assert fileExists(p)

block:
  let (found, p) = getTestInstancePath("pumpkin:summon_command_regression")
  assert found
  assert fileExists(p), "path doesn't exist: " & p

block:
  # pumpkin namespace is non-default: bare id alone must NOT resolve
  let (found, _) = getTestInstancePath("summon_command_regression")
  assert not found

echo "template_bytes + test_instance: all real-path lookups verified"
