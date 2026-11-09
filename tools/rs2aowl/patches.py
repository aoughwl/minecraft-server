"""Hand corrections to the translator's output, reapplied on each regeneration: rel path -> [(old, new)]."""
GATE = '''import ../../blockprelude

type
  GateProps* = object
    ## `T: RedstoneGateBlockProperties`: the repeater's and the comparator's properties, by name.
    values: seq[(string, string)]

proc gatePropsOf*(stateId: BlockStateId; blockRef: Block): GateProps =
  ## `T::from_state_id`
  let (has, dyn) = blockRef.properties(stateId)
  if not has:
    rustPanic(blockRef.name & " has no properties")
  GateProps(values: dyn.toProps())

proc gatePropsDefault*(blockRef: Block): GateProps = gatePropsOf(blockRef.defaultState.id, blockRef)

proc isPowered*(self: GateProps): bool =
  for entry in self.values:
    if entry[0] == "powered":
      return entry[1] == "true"
  false

proc getFacing*(self: GateProps): HorizontalFacing =
  for entry in self.values:
    if entry[0] == "facing":
      return HorizontalFacing.fromValue(entry[1])
  rustPanic("no facing")

proc setFacing*(self: var GateProps; facing: HorizontalFacing) =
  for i in 0 ..< self.values.len:
    if self.values[i][0] == "facing":
      self.values[i] = ("facing", facing.toValue())

proc toStateId*(self: GateProps; blockRef: Block): BlockStateId =
  blockRef.fromProperties(self.values).toStateId(blockRef)
'''

PATCHES = {
    'blocks/redstone/comparator.aowl': [
        ("      else:\n        R2A_NONE\n    let blockLevel", "      else:\n        none[uint8]()\n    let blockLevel"),
        ("re:(?s)    let t\\d+ = asType\\(entity\\.castAny\\(\\), ItemFrameEntity\\)\n.*?    if \\(not \\(itemframe\\.getFacing\\(\\) == direction\\)\\):\n", '''    let frameFacing = entity.itemFrameFacing0
    if frameFacing == nil:
      continue
    if (not (frameFacing() == direction)):
'''),
        ("level = some(itemframe.getAnalogOutput())", "level = some((let frameOutput = entity.itemFrameOutput0; frameOutput()))"),
    ],
    'blocks/redstone/redstone_wire.aowl': [
        ("  let t1 = block:\n    case args.direction\n    of BlockDirection.Up:\n      return args.stateId\n    of BlockDirection.Down:\n      return getRegulatedSides(wire, args.world, args.position).toStateId(args.block0)\n",
         "  if args.direction == BlockDirection.Up:\n    return args.stateId\n  if args.direction == BlockDirection.Down:\n    return getRegulatedSides(wire, args.world, args.position).toStateId(args.block0)\n  let t1 = block:\n    case args.direction\n    of BlockDirection.Up, BlockDirection.Down:\n      rustPanic(\"handled above\")\n"),
        ("if (not (wire == newWire)):", "if (not (wire.toIndex() == newWire.toIndex())):"),
    ],
    'blocks/redstone/repeater.aowl': [
        ("    if (props1.delay == 4):\n      1\n", "    if (props1.delay == 4):\n      1'u8\n"),
    ],
    'blocks/redstone/pressure_plate/weighted.aowl': [
        ("len0.min(weight)", "min(len0, int(weight))"),
        ("weight.min(len01)", "min(int(weight), len01)"),
        ("/ weight)", "div int(weight))"),
    ],
    'blocks/redstone/abstract_redstone_gate.aowl': [
        ('import ../../blockprelude\n', GATE),
        ('T.fromStateId(', 'gatePropsOf('),
        ('T.defaultFor(', 'gatePropsDefault('),
    ],
    'blocks/redstone/turbo.aowl': [
        ("  var heading: R2A_MANUAL_type\n", "  var heading: int\n"),
        ("self.nodes[upd1.index].neighbors.get()[0 ..< 24].tryInto().get()", "self.nodes[upd1.index].neighbors.get()"),
        ("let neighbors: array[24, NodeId] =", "let neighbors ="),
        ("  for neighborId in neighbors[0 ..< 4]:\n", "  for q in 0 ..< 4:\n    let neighborId = neighbors[q]\n"),
        ("  var wirePower = 0\n", "  var wirePower = 0'u8\n"),
        ("  var blockPower = 0\n", "  var blockPower = 0'u8\n"),
        ("nodeCache: initTable()", "nodeCache: initTable[int64, NodeId]()"),
        ("nodeCache*: Table[BlockPos, NodeId]", "nodeCache*: Table[int64, NodeId]"),
        ("self.nodeCache.containsKey(neighborPos)", "self.nodeCache.hasKey(neighborPos.asLong())"),
        ("self.nodeCache[neighborPos]", "self.nodeCache.getOrDefault(neighborPos.asLong())"),
        ("turbo.nodeCache.insert(pos, nodeId)", "turbo.nodeCache[pos.asLong()] = nodeId"),
        ("self.nodeCache.insert(neighborPos, nodeId)", "self.nodeCache[neighborPos.asLong()] = nodeId"),
        ("updateQueue: @[@[], @[], @[]]", "updateQueue: @[newSeq[NodeId](), newSeq[NodeId](), newSeq[NodeId]()]"),
        ("var neighborsVisited = @[]", "var neighborsVisited: seq[bool] = @[]"),
        ("var neighborNodes = @[]", "var neighborNodes: seq[NodeId] = @[]"),
        ("var neighbors = @[]", "var neighbors: seq[NodeId] = @[]"),
        ("for neighborPos in neighbors[0 ..< 24]:", "for neighborPos in neighbors:"),
        ("  var cx = 0\n", "  var cx = 0'i32\n"),
        ("  var cz = 0\n", "  var cz = 0'i32\n"),
    ],
    'blocks/redstone/rails/common.aowl': [
        ("var connectedTowards = @[]", "var connectedTowards: seq[HorizontalFacing] = @[]"),
        ("      R2A_NONE\n  let railLeaningDirection", "      none[HorizontalFacing]()\n  let railLeaningDirection"),
    ],
    'blocks/redstone/pressure_plate/plate.aowl': [
        ("re:(?s)  var combined = @\\[\\]\n.*?collect\\(\\)\n", '''  result = tagBlockIds(Block_MINECRAFT_WOODEN_PRESSURE_PLATES)
  for id in tagBlockIds(Block_MINECRAFT_STONE_PRESSURE_PLATES):
    result.add(id)
'''),
    ],
    'blocks/redstone/bell.aowl': [
        ('ringBell(args.position, args.world, R2A_NONE)', 'ringBell(args.position, args.world, none[HorizontalFacing]())'),
        ('ringBell(args.position, args.world, args.hit.face.toHorizontalFacing())', 'ringBell(args.position, args.world, toOpt(args.hit.face.toHorizontalFacing()))'),
        ('''  var blockFace: R2A_MANUAL_type
  var facing: R2A_MANUAL_type
  (blockFace, facing) = getPlacementFace(''', '''  let (blockFace, facing) = getPlacementFace('''),
    ],
    'blocks/redstone/redstonemod.aowl': [
        ("var maxPower = 0\n", "var maxPower = 0'u8\n"),
    ],
    'blocks/redstone/tripwire_hook.aowl': [
        ('(-1), R2A_NONE)', '(-1), none[BlockStateId]())'),
        ('wiresProps[int(k)] = R2A_NONE', 'wiresProps[int(k)] = none[TripwireProperties]()'),
        ('R2A_MANUAL("repeat 42")', 'newSeq[Option[TripwireProperties]](42)'),
        ('startHookPos.offsetDir(startHookProps.facing.toOffset(), k)', 'startHookPos.offsetDir(startHookProps.facing.toOffset(), int32(k))'),
        ('startHookPos.offsetDir(startHookProps.facing.toOffset(), j)', 'startHookPos.offsetDir(startHookProps.facing.toOffset(), int32(j))'),
        ('startHookPos.offsetDir(startHookProps.facing.toOffset(), l)', 'startHookPos.offsetDir(startHookProps.facing.toOffset(), int32(l))'),
    ],
    'blocks/redstone/pressure_plate/pressure_platemod.aowl': [
        ("re:(?s)    let t\\d+ = block:\n      let t\\d+ = world\\.server\n.*?    let nextOutput = t\\d+\n", """    # `BlockRedstoneEvent` is not fired: no plugin hears of it from here yet.
    let nextOutput = calcOutput
"""),
    ],
    'entities/daylight_detector.aowl': [
        ("world.dimension.hasSkylight", "world.dimension.hasSkylight"),
        ("  let level = world.level\n", ""),
        ("(((float32(timeOfDay) / 24000.0)) - 0.25)", "(((float32(timeOfDay) / 24000.0'f32)) - 0.25'f32)"),
        ("(sunAngleFraction * ((PI * 2.0)))", "(sunAngleFraction * (float32(PI) * 2.0'f32))"),
        ("""    if (cosAngle < 0.0):
      # night time = ~11 darkness
      uint8(((abs(cosAngle) * 11.0)))
    else:
      0
""", """    if (cosAngle < 0.0'f32):
      # night time = ~11 darkness
      uint8(((abs(cosAngle) * 11.0'f32)))
    else:
      0'u8
"""),
        ("level.lightEngine.getSkyLightLevel(level, blockPos)", "world.getSkyLightLevel(blockPos)"),
        ("power = (15 - power)", "power = (15'u8 - power)"),
        ("elif (power > 0):", "elif (power > 0'u8):"),
        ("""      if (sunAngleRadians < PI):
        0.0
      else:
        (PI * 2.0)
""", """      if (sunAngleRadians < float32(PI)):
        0.0'f32
      else:
        (float32(PI) * 2.0'f32)
"""),
        ("* 0.2)", "* 0.2'f32)"),
        ("clamp(power, 0, 15)", "clamp(power, 0'u8, 15'u8)"),
    ],
}
