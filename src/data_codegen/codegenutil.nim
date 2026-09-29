## Shared helpers for the data-codegen generators, factored out of
## gen_sound_category.nim's proof-of-concept so later generators don't
## each reimplement `toPascalCase`/JSON-array reading.

import std/[json, strutils, algorithm, syncio]

proc toPascalCase*(s: string): string =
  ## Port of `heck::ToPascalCase` as the upstream generators use it: splits
  ## on `_`/`-`/whitespace, uppercases each word's first letter, lowercases
  ## the rest, concatenates. Input is SCREAMING_SNAKE JSON values.
  result = ""
  var capitalizeNext = true
  for ch in s:
    if ch == '_' or ch == '-' or ch == ' ':
      capitalizeNext = true
    elif capitalizeNext:
      result.add(toUpperAscii(ch))
      capitalizeNext = false
    else:
      result.add(toLowerAscii(ch))

proc readStringArray*(path: string): seq[string] =
  ## Port of `serde_json::from_str::<Vec<String>>(...)`.
  var tree = parseFile(path)
  let arr = root(tree)
  result = @[]
  for elem in arr:
    result.add(elem.getStr())

proc readIntIntMapSorted*(path: string): seq[(int, int)] =
  ## Port of `serde_json::from_str::<BTreeMap<uN, uN>>(...)` - JSON object
  ## keys are always strings, so this parses each key back to an int; a
  ## `BTreeMap<uN, _>` iterates in ascending numeric key order.
  var tree = parseFile(path)
  let obj = root(tree)
  var pairs: seq[(int, int)] = @[]
  for key, val in obj.pairs():
    var keyInt = 0
    try:
      keyInt = parseInt(key)
    except ErrorCode as e:
      echo "bad int key '" & key & "': " & $e
    pairs.add((keyInt, int(val.getInt())))
  pairs.sort(proc(a, b: (int, int)): int =
    cmp(a[0], b[0]))
  pairs

proc readStringIntMapSorted*(path: string): seq[(string, int)] =
  ## Port of `serde_json::from_str::<BTreeMap<String, uN>>(...)` - a
  ## `BTreeMap` iterates in ascending key order, so this sorts by name to
  ## match upstream's emitted variant order exactly.
  var tree = parseFile(path)
  let obj = root(tree)
  var pairs: seq[(string, int)] = @[]
  for key, val in obj.pairs():
    pairs.add((key, int(val.getInt())))
  pairs.sort(proc(a, b: (string, int)): int =
    cmp(a[0], b[0]))
  pairs
