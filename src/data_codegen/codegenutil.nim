## Shared helpers for the data-codegen generators, factored out of
## gen_sound_category.nim's proof-of-concept so later generators don't
## each reimplement `toPascalCase`/JSON-array reading.

import std/[json, strutils, algorithm, syncio, paths, dirs]

proc toPascalCase*(s: string): string =
  ## Port of `heck::ToPascalCase` as the upstream generators use it: splits
  ## on `_`/`-`/whitespace, uppercases each word's first letter, lowercases
  ## the rest, concatenates. Input is SCREAMING_SNAKE JSON values.
  result = ""
  var capitalizeNext = true
  for ch in s:
    if ch == '_' or ch == '-' or ch == ' ' or ch == '.':
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

proc lastIndexOf*(s: string, c: char): int =
  ## `rfind` isn't available in Nimony; scan backward by hand.
  result = -1
  var i = s.len - 1
  while i >= 0:
    if s[i] == c:
      return i
    dec i

proc stemOf*(p: Path): string =
  ## Filename minus directory and `.json` extension. `splitFile` isn't
  ## available.
  var base = $p
  let slashIdx = max(lastIndexOf(base, '/'), lastIndexOf(base, '\\'))
  if slashIdx >= 0:
    base = base[(slashIdx + 1) .. ^1]
  if base.endsWith(".json"):
    base = base[0 ..< (base.len - 5)]
  base

proc listJsonStems*(dir: Path): seq[(string, Path)] =
  ## Port of the `fs::read_dir(dir).../sort_by_key(file_name)` dance every
  ## per-directory generator (decorated_pot_pattern.rs, cat_variant.rs, and
  ## siblings) does before building its own `BTreeMap<String, _>` - since a
  ## `BTreeMap` iterates by key, the final emission order is alphabetical by
  ## stem either way, so collecting pre-sorted here is equivalent and
  ## reusable. Returns `(stem, fullPath)` pairs sorted by stem.
  var pairs: seq[(string, Path)] = @[]
  try:
    for kind, entryPath in walkDir(dir):
      if kind == pcFile and ($entryPath).endsWith(".json"):
        pairs.add((stemOf(entryPath), entryPath))
  except ErrorCode as e:
    echo "listJsonStems: walkDir failed: " & $e
  pairs.sort(proc(a, b: (string, Path)): int = cmp(a[0], b[0]))
  pairs

proc jsonStringField*(jsonPath: Path, key: string): string =
  ## Reads one top-level string field from a JSON object file.
  ## `JsonNode` has no `[]` field-index operator in Nimony's std/json -
  ## object field lookup means scanning `pairs()` for the matching key.
  var tree = parseFile($jsonPath)
  let obj = root(tree)
  result = ""
  for k, val in obj.pairs():
    if k == key:
      result = val.getStr()

proc jsonNestedStringField*(jsonPath: Path, outerKey, innerKey: string): string =
  ## Reads a string field one level deep (`obj[outerKey][innerKey]`), e.g.
  ## `description.translate`. Missing outer/inner keys or a non-string value
  ## yield "" (matching upstream's `.as_deref().unwrap_or("")` pattern for
  ## `Option<String>` fields).
  var tree = parseFile($jsonPath)
  let obj = root(tree)
  result = ""
  for k, val in obj.pairs():
    if k == outerKey:
      for ik, iv in val.pairs():
        if ik == innerKey:
          result = iv.getStr()

proc jsonBoolField*(jsonPath: Path, key: string, default: bool): bool =
  ## Reads a top-level bool field, or `default` if absent (matching
  ## upstream's `#[serde(default)]` on a `bool` field).
  var tree = parseFile($jsonPath)
  let obj = root(tree)
  result = default
  for k, val in obj.pairs():
    if k == key:
      result = val.getBool()

proc jsonFloatField*(jsonPath: Path, key: string, default: float): float =
  ## Reads a top-level numeric field as a float, or `default` if absent.
  var tree = parseFile($jsonPath)
  let obj = root(tree)
  result = default
  for k, val in obj.pairs():
    if k == key:
      result = val.getFloat()

proc jsonIntField*(jsonPath: Path, key: string, default: int): int =
  ## Reads a top-level integer field, or `default` if absent.
  var tree = parseFile($jsonPath)
  let obj = root(tree)
  result = default
  for k, val in obj.pairs():
    if k == key:
      result = int(val.getInt())

proc isAsciiDigit*(c: char): bool {.inline.} =
  c >= '0' and c <= '9'

proc readStringIntSeqMapSorted*(path: string): seq[(string, seq[int])] =
  ## Port of `serde_json::from_str::<BTreeMap<String, Box<[usize]>>>(...)` -
  ## a `BTreeMap` iterates in ascending key order, so this sorts by name to
  ## match upstream's emitted order exactly.
  var tree = parseFile(path)
  let obj = root(tree)
  var pairs: seq[(string, seq[int])] = @[]
  for key, val in obj.pairs():
    var nums: seq[int] = @[]
    for v in val.items():
      nums.add(int(v.getInt()))
    pairs.add((key, nums))
  pairs.sort(proc(a, b: (string, seq[int])): int =
    cmp(a[0], b[0]))
  pairs

proc jsonTryGet*(t: var JsonTree, key: string): (bool, JsonNode) =
  ## Safe replacement for `t{key}` when the key may be absent. Nimony's
  ## `std/json` `{}` operator returns a default-constructed `JsonNode()`
  ## on a missing key, and calling `.kind` (or almost anything else) on
  ## that default value crashes at runtime with an internal assertion
  ## failure - `nimony check` doesn't catch it, `nimony c -r` does. This
  ## walks the object's pairs itself and never constructs/touches that
  ## broken default value: the returned `JsonNode` is only meaningful
  ## when the `bool` is `true`. Reproduced standalone: `var n =
  ## JsonNode(); discard n.kind` alone crashes at runtime.
  var root = t.root
  if kind(root) != JObject:
    return (false, root)
  for k, v in pairs(root):
    if k == key:
      return (true, v)
  return (false, root)

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
