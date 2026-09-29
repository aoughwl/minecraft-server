## Block-state-id resolution: given a block name and a set of property
## name/value pairs, compute the concrete numeric state id (and the
## reverse: decode a state id back into property values). Built on
## `src/generated/blockprops.nim` (mixed-radix offsets, generated from
## upstream's real `properties.json`/`blocks.json` - see that file's own
## doc comment for the algorithm). This is the piece `on_place`-style
## block handlers need and that was missing when `logs.rs`/`chain.rs`/
## `end_rod.rs`/`end_portal_frame.rs`/`glazed_terracotta.rs` were found
## genuinely blocked (see src/server/block/README.md).
##
## Deliberately NOT ported here (out of scope, same cut gen_block.nim/
## gen_blockprops.nim already made): the full per-state `states[]` array
## (collision/outline shapes, opacity, luminance, ...) - only the id <->
## property-values mapping.

import ../../generated/blockprops

type
  StateResult* = object
    case ok*: bool
    of true:
      stateId*: int
    of false:
      discard

  PropsResult* = object
    case ok*: bool
    of true:
      values*: seq[(string, string)]  ## (propertyName, value), one per property.
    of false:
      discard

proc valueIndex(def: BpPropDef, value: string): int =
  for i, v in def.values:
    if v == value:
      return i
  -1

proc resolveStateId*(blockName: string, values: seq[(string, string)]): StateResult =
  ## Given a block's registration name (no `minecraft:` prefix, matching
  ## `src/generated/blockdata.nim`'s convention) and a set of
  ## (propertyName, value) pairs, compute the concrete state id.
  ## Missing properties fall back to the block's real default value for
  ## that property (decoded from `defaultStateId`, not just index 0) -
  ## same fallback a caller omitting an argument would expect from
  ## upstream's `Default` trait impls.
  let (found, info) = bpBlockByName(blockName)
  if not found:
    return StateResult(ok: false)
  var offset = 0
  for propRef in info.props:
    let (pfound, propDef) = bpPropByHash(propRef.hashKey)
    if not pfound:
      return StateResult(ok: false)
    var idx = -1
    for i in 0 ..< values.len:
      if values[i][0] == propDef.name:
        idx = valueIndex(propDef, values[i][1])
        break
    if idx < 0:
      # Not supplied (or supplied but unrecognized): fall back to the
      # block's real default, decoded the same way statePropValues does.
      let defOffset = info.defaultStateId - info.firstStateId
      let variantCount = propDef.values.len
      if variantCount == 0 or propRef.multiplier == 0:
        return StateResult(ok: false)
      idx = (defOffset div propRef.multiplier) mod variantCount
    offset += idx * propRef.multiplier
  StateResult(ok: true, stateId: info.firstStateId + offset)

proc statePropValues*(blockName: string, stateId: int): PropsResult =
  ## Reverse of `resolveStateId`: decode a state id back into its
  ## (propertyName, value) pairs for this block.
  let (found, info) = bpBlockByName(blockName)
  if not found:
    return PropsResult(ok: false)
  let offset = stateId - info.firstStateId
  if offset < 0:
    return PropsResult(ok: false)
  var values: seq[(string, string)] = @[]
  for propRef in info.props:
    let (pfound, propDef) = bpPropByHash(propRef.hashKey)
    if not pfound:
      return PropsResult(ok: false)
    let variantCount = propDef.values.len
    if variantCount == 0 or propRef.multiplier == 0:
      return PropsResult(ok: false)
    let idx = (offset div propRef.multiplier) mod variantCount
    if idx < 0 or idx >= variantCount:
      return PropsResult(ok: false)
    values.add((propDef.name, propDef.values[idx]))
  PropsResult(ok: true, values: values)

proc defaultStateId*(blockName: string): (bool, int) =
  ## Convenience: a block's default state id (e.g. a log placed with no
  ## explicit orientation), straight from the generated table.
  let (found, info) = bpBlockByName(blockName)
  if found: (true, info.defaultStateId) else: (false, 0)

proc isStateOfBlock*(blockName: string, stateId: int): bool =
  ## Port of upstream's `Block::from_state_id(id).eq(args.block)` check
  ## (e.g. `end_rod.rs`'s "is my neighbor also an end rod" test) -
  ## whether `stateId` falls within `blockName`'s own contiguous state-id
  ## range. `BpBlocks` is emitted in ascending `firstStateId` order (see
  ## `src/data_codegen/gen_blockprops.nim`), so a block's range is
  ## `[firstStateId, nextBlock.firstStateId)`, or unbounded-above for the
  ## table's last entry.
  let (found, info) = bpBlockByName(blockName)
  if not found or stateId < info.firstStateId:
    return false
  for i, b in BpBlocks:
    if b.name == blockName:
      if i + 1 < BpBlocks.len:
        return stateId < BpBlocks[i + 1].firstStateId
      return true
  false
