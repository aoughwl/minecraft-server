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

type
  MapColorEntry* = object
    id*: int
    name*: string
    col*: int
    r*, g*, b*: int

proc readMapColors*(path: string): seq[MapColorEntry] =
  ## Port of `serde_json::from_str::<Vec<MapColorEntry>>(...)` for
  ## map_colors.json's `[{id,name,col,hex,rgb:[r,g,b]}, ...]` shape.
  ## `JsonNode` has no `[]` field-index operator in Nimony's std/json - only
  ## `items`/`pairs` iterators - so object field lookup means scanning
  ## `pairs()` for the matching key.
  var tree = parseFile(path)
  let arr = root(tree)
  result = @[]
  for elem in arr:
    var entry = MapColorEntry(id: 0, name: "", col: 0, r: 0, g: 0, b: 0)
    for key, val in elem.pairs():
      case key
      of "id": entry.id = int(val.getInt())
      of "name": entry.name = val.getStr()
      of "col": entry.col = int(val.getInt())
      of "rgb":
        var rgbVals: seq[int] = @[]
        for v in val.items():
          rgbVals.add(int(v.getInt()))
        entry.r = rgbVals[0]
        entry.g = rgbVals[1]
        entry.b = rgbVals[2]
      else: discard
    result.add(entry)

proc toShoutySnakeCase*(s: string): string =
  ## Port of `heck::ToShoutySnakeCase`.
  result = toUpperAscii(s).replace("-", "_").replace(" ", "_")

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
