## Port of tools/pumpkin-codegen/src/block.rs's property-permutation half -
## the piece gen_block.nim's doc comment explicitly scoped OUT. Reads
## assets/properties.json (124 property definitions, keyed by a stable
## `hash_key`) and assets/blocks.json's per-block `properties` (a list of
## those hashes, in a fixed order) + `states` (that block's contiguous
## state-id range, one entry per property-value combination), and computes
## the same mixed-radix offset upstream's generator does:
##
##   for a block's properties, in the order they're listed:
##     multiplier[last]  = 1
##     multiplier[i]     = multiplier[i+1] * variantCount(property[i+1])
##   stateId = states[0].id + sum(valueIndex[i] * multiplier[i])
##
## (upstream builds `multiplier` by iterating `block.properties.iter().rev()`
## and multiplying as it goes - same result, reversed construction order.)
## This lets `resolveStateId`/`statePropValues` in blockprops.nim compute or
## decode a state id from/to real property values, without generating the
## full `states[]` array upstream keeps (collision shapes, opacity, etc. -
## still out of scope, undisturbed from gen_block.nim's original cut).

import std/[json, syncio, algorithm, tables]
import codegenutil

type
  PropKind = enum
    pkBool
    pkInt
    pkEnum

  PropDef = object
    hashKey: int
    name: string        ## `serialized_name` - the JSON/property-string name.
    kind: PropKind
    values: seq[string]  ## Bool: ["true","false"]. Int: ["0".."N"]. Enum: real names.

  BlockPropRef = object
    hash: int
    multiplier: int

  BlockEntry = object
    name: string
    firstStateId: int
    defaultStateId: int
    props: seq[BlockPropRef]

proc readProperties(path: string): seq[PropDef] =
  var tree = parseFile(path)
  result = @[]
  for elem in items(tree.root()):
    var p = PropDef(hashKey: 0, name: "", kind: pkBool, values: @[])
    var minInt = 0
    var maxInt = 0
    for k, v in elem.pairs():
      case k
      of "hash_key": p.hashKey = int(v.getInt())
      of "serialized_name": p.name = v.getStr()
      of "type":
        case v.getStr()
        of "boolean": p.kind = pkBool
        of "int": p.kind = pkInt
        of "enum": p.kind = pkEnum
        else: discard
      of "min": minInt = int(v.getInt())
      of "max": maxInt = int(v.getInt())
      of "values":
        if p.kind == pkEnum or v.kind() == JArray:
          p.values = @[]
          for it in items(v):
            p.values.add(it.getStr())
      else: discard
    if p.kind == pkBool:
      p.values = @["true", "false"]
    elif p.kind == pkInt:
      p.values = @[]
      var i = minInt
      while i <= maxInt:
        p.values.add($i)
        i += 1
    result.add(p)

var blockHashesTmp: seq[seq[int]] = @[]

proc readBlockPropRefs(path: string): seq[BlockEntry] =
  var tree = parseFile(path)
  let obj = tree.root()
  result = @[]
  for topKey, topVal in obj.pairs():
    if topKey != "blocks":
      continue
    for elem in items(topVal):
      var name = ""
      var defaultStateId = 0
      var firstStateId = -1
      var hashes: seq[int] = @[]
      for k, v in elem.pairs():
        case k
        of "name": name = v.getStr()
        of "default_state_id": defaultStateId = int(v.getInt())
        of "properties":
          hashes = @[]
          for it in items(v):
            hashes.add(int(it.getInt()))
        of "states":
          # states[] is emitted in ascending id order in the real asset;
          # the first entry's id is this block's state-id range start.
          for it in items(v):
            for sk, sv in it.pairs():
              if sk == "id":
                let sid = int(sv.getInt())
                if firstStateId < 0 or sid < firstStateId:
                  firstStateId = sid
        else: discard
      if firstStateId < 0:
        firstStateId = defaultStateId
      result.add(BlockEntry(name: name, firstStateId: firstStateId,
                             defaultStateId: defaultStateId, props: @[]))
      # hashes recorded on the entry itself for the multiplier pass below;
      # stash them via a side table keyed by index since BlockEntry.props
      # isn't populated until multipliers are known.
      blockHashesTmp.add(hashes)

proc esc(s: string): string =
  result = ""
  for ch in s:
    if ch == '"' or ch == '\\':
      result.add('\\')
    result.add(ch)

proc main() =
  let props = readProperties("../upstream-ref/assets/properties.json")
  var propByHash = initTable[int, PropDef]()
  for p in props:
    propByHash[p.hashKey] = p

  var blocks = readBlockPropRefs("../upstream-ref/assets/blocks.json")

  # Second pass: compute each block's per-property multiplier from its
  # hash list (recorded in blockHashesTmp, same index order as `blocks`),
  # mirroring upstream's reverse-iteration accumulation.
  for i in 0 ..< blocks.len:
    let hashes = blockHashesTmp[i]
    var refs = newSeq[BlockPropRef](hashes.len)
    var multiplier = 1
    var j = hashes.len - 1
    while j >= 0:
      let hash = hashes[j]
      let (found, pd) = (propByHash.hasKey(hash), propByHash.getOrDefault(hash))
      let variantCount = if found: pd.values.len else: 1
      refs[j] = BlockPropRef(hash: hash, multiplier: multiplier)
      multiplier *= variantCount
      j -= 1
    blocks[i].props = refs

  var s = "## Generated by src/data_codegen/gen_blockprops.nim from\n"
  s.add("## assets/properties.json + assets/blocks.json's properties/states\n")
  s.add("## fields. See gen_blockprops.nim's doc comment for the\n")
  s.add("## mixed-radix offset algorithm this mirrors from upstream.\n\n")
  s.add("type\n")
  s.add("  BpPropDef* = object\n")
  s.add("    name*: string\n    values*: seq[string]\n\n")
  s.add("  BpPropRef* = object\n")
  s.add("    hashKey*: int\n    multiplier*: int\n\n")
  s.add("  BpBlockInfo* = object\n")
  s.add("    name*: string\n    firstStateId*: int\n    defaultStateId*: int\n")
  s.add("    props*: seq[BpPropRef]\n\n")

  s.add("let BpProps*: seq[BpPropDef] = @[\n")
  for p in props:
    s.add("  BpPropDef(name: \"" & esc(p.name) & "\", values: @[")
    for i, v in p.values:
      if i > 0: s.add(", ")
      s.add("\"" & esc(v) & "\"")
    s.add("]),  # hash " & $p.hashKey & "\n")
  s.add("]\n\n")
  s.add("let BpPropHashes*: seq[int] = @[")
  for i, p in props:
    if i > 0: s.add(", ")
    s.add($p.hashKey)
  s.add("]\n\n")

  s.add("proc bpPropByHash*(hash: int): (bool, BpPropDef) =\n")
  s.add("  for i in 0 ..< BpPropHashes.len:\n")
  s.add("    if BpPropHashes[i] == hash: return (true, BpProps[i])\n")
  s.add("  (false, BpPropDef())\n\n")

  s.add("let BpBlocks*: seq[BpBlockInfo] = @[\n")
  for b in blocks:
    s.add("  BpBlockInfo(name: \"" & esc(b.name) & "\", firstStateId: " &
          $b.firstStateId & ", defaultStateId: " & $b.defaultStateId &
          ", props: @[")
    for i, r in b.props:
      if i > 0: s.add(", ")
      s.add("BpPropRef(hashKey: " & $r.hash & ", multiplier: " & $r.multiplier & ")")
    s.add("]),\n")
  s.add("]\n\n")

  s.add("proc bpBlockByName*(name: string): (bool, BpBlockInfo) =\n")
  s.add("  for b in BpBlocks:\n    if b.name == name: return (true, b)\n")
  s.add("  (false, BpBlockInfo())\n")

  try:
    writeFile("../minecraft-server/src/generated/blockprops.nim", s)
  except ErrorCode as e:
    echo "writeFile failed: " & $e
  echo "wrote " & $blocks.len & " blocks, " & $props.len & " property defs"

main()
