## Generic JSON -> NBT value converter, used by gen_registry.nim.
## Port of registry.rs's local `json_to_nbt_tag` closure.
##
## Rust matches on `serde_json::Value`'s 6 variants directly. Nimony's
## `std/json` JsonNode has the same shape (JNull/JBool/JInt/JFloat/JString/
## JArray/JObject - note JInt/JFloat are split where serde_json's Number
## is one variant tested with `as_i64`/`as_f64`), so this is a close
## structural match, not a reinterpretation.

import std/json
import "../nbt/tag"
import "../nbt/nbtbase"

proc jsonToNbtTag*(v: JsonNode): NbtTag =
  case v.kind
  of JNull:
    NbtTag(kind: ntkEnd)
  of JBool:
    NbtTag(kind: ntkByte, byteVal: (if v.getBool(): 1'i8 else: 0'i8))
  of JInt:
    let i = v.getInt()
    if i >= int64(int32.low) and i <= int64(int32.high):
      NbtTag(kind: ntkInt, intVal: int32(i))
    else:
      NbtTag(kind: ntkLong, longVal: i)
  of JFloat:
    NbtTag(kind: ntkDouble, doubleVal: v.getFloat())
  of JString:
    NbtTag(kind: ntkString, stringVal: v.getStr())
  of JArray:
    var list: seq[NbtTag] = @[]
    for item in v.items:
      list.add(jsonToNbtTag(item))
    NbtTag(kind: ntkList, listVal: list)
  of JObject:
    var compound = newCompound()
    for key, val in v.pairs():
      put(compound, key, jsonToNbtTag(val))
    NbtTag(kind: ntkCompound, compoundVal: compound)
