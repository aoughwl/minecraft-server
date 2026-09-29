## Server-side plugin event data model.
## Port of upstream/plugin-api/src/events/*.rs's `Data` shapes, whose real
## field types are defined not in those .rs wrapper files (each is a
## ~20-line `FromIntoEvent` impl with no fields of its own) but in the WIT
## interface at upstream/pumpkin-plugin-wit/v0.1/event.wit, which the
## upstream build compiles into the `wit::...::EventData` records these
## wrappers convert to/from.
##
## This does NOT replace the WASM-guest plugin transport (still
## undecided - see src/host_bindings/README.md and
## src/plugin_runtime/README.md for the replacement paths). It gives the
## port a genuine, usable server-side event-data model independent of
## that transport: something server code can construct and pass to an
## event bus once one exists, whichever transport eventually delivers it
## to a plugin.
##
## Field-type choices, since WIT's `player`/`text-component` are opaque
## *resource* handles (host-side objects with methods), not plain
## records, so there's no faithful 1:1 struct to copy:
## - `player: player` (a WIT resource) becomes `PlayerUuid` (from
##   src/server/net/netbase.nim) - a plain identifier, not the resource
##   handle or a full `Entity`/`Player` reference. This is deliberate: a
##   real `Player`/`Entity` reference would pull in src/server/entity/
##   transitively, which currently makes ANY importing module
##   unverifiable at runtime (see entity/README.md's finding that mere
##   transitive import of entity.nim triggers the closure-vtable crash,
##   independent of whether vtable code actually runs). Event data is
##   exactly the kind of plain, frequently-constructed value type that
##   shouldn't carry that cost - callers that need the live Player look it
##   up by this id.
## - `text-component`/`*-message: text-component` fields (a builder
##   resource with formatting/hover/click methods, defined across
##   text.wit) become plain `string` (the flat text, no formatting).
##   TODO: replace with a real TextComponent type once upstream's
##   `pumpkin-util::text` module (skipped so far, see util's README) is
##   ported.
## - `position: position` becomes `Vector3[float64]` (src/util/vector3.nim).
## - `game-mode` becomes `GameMode` (src/util/gamemode.nim).

import ../server/net/netbase
import ../util/vector3
import ../util/gamemode
import ../world/tick  # BlockPos stand-in (see its doc comment)

type
  PlayerJoinEventData* = object
    player*: PlayerUuid
    joinMessage*: string
    cancelled*: bool

  PlayerLeaveEventData* = object
    player*: PlayerUuid
    leaveMessage*: string
    cancelled*: bool

  PlayerTeleportEventData* = object
    player*: PlayerUuid
    fromPosition*: Vector3[float64]
    toPosition*: Vector3[float64]
    cancelled*: bool

  PlayerGamemodeChangeEventData* = object
    player*: PlayerUuid
    previousGamemode*: GameMode
    newGamemode*: GameMode
    cancelled*: bool

  PlayerToggleSneakEventData* = object
    player*: PlayerUuid
    isSneaking*: bool
    cancelled*: bool

  PlayerMoveEventData* = object
    player*: PlayerUuid
    fromPosition*: Vector3[float64]
    toPosition*: Vector3[float64]
    cancelled*: bool

  PlayerChatEventData* = object
    ## `signature: option<list<u8>>` becomes an empty seq for "none",
    ## matching the seq-as-option convention already used elsewhere in
    ## this port (e.g. src/nbt/ has no separate Option type either).
    player*: PlayerUuid
    message*: string
    recipients*: seq[PlayerUuid]
    signature*: seq[byte]
    cancelled*: bool

  BlockPlaceEventData* = object
    ## `block-placed`/`block-placed-against` are `string` in the WIT
    ## record (presumably a resource-location-formatted block id) rather
    ## than a resolved block-state reference, so this stays a plain
    ## string here too rather than reaching for the still-mostly-unported
    ## block registry.
    player*: PlayerUuid
    blockPlaced*: string
    blockPlacedAgainst*: string
    blockPos*: BlockPos
    canBuild*: bool
    cancelled*: bool
