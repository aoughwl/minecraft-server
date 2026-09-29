## Scheduler ownership domains.
## Port of pumpkingmc/crates/pumpkin-scheduler/src/domain.rs

type
  WorldDomainId* = object
    value: uint64
  RegionDomainId* = object
    value: uint64
  EntityDomainId* = object
    value: uint64
  ExternalDomainId* = object
    value: uint64

proc newWorldDomainId*(value: uint64): WorldDomainId {.inline.} = WorldDomainId(value: value)
proc get*(id: WorldDomainId): uint64 {.inline.} = id.value

proc newRegionDomainId*(value: uint64): RegionDomainId {.inline.} = RegionDomainId(value: value)
proc get*(id: RegionDomainId): uint64 {.inline.} = id.value

proc newEntityDomainId*(value: uint64): EntityDomainId {.inline.} = EntityDomainId(value: value)
proc get*(id: EntityDomainId): uint64 {.inline.} = id.value

proc newExternalDomainId*(value: uint64): ExternalDomainId {.inline.} = ExternalDomainId(value: value)
proc get*(id: ExternalDomainId): uint64 {.inline.} = id.value

type
  ExecutionDomainKind* = enum
    ## Identifies the scheduler owner responsible for executing a unit of
    ## work. A domain serializes task polls. Tasks may interleave whenever
    ## they suspend; submission order does not imply completion order or
    ## transaction isolation. Only Global admission is currently
    ## implemented upstream.
    edGlobal   ## Server-wide work with no narrower owner yet; also the
               ## fallback for work spanning several worlds/regions/entities.
    edWorld    ## One complete world/dimension: lifecycle, weather, time,
               ## cross-region coordination within that world.
    edRegion   ## One independently schedulable world region: chunk ticks,
               ## block entities, scheduled block work, spawning.
    edEntity   ## One movable player/entity: ticks, movement, combat, AI,
               ## vehicles, lifecycle. Ownership must transfer/invalidate
               ## before teleport/dimension-change/mount/despawn continues.
    edExternal ## Scheduler-visible work owned outside normal game-state
               ## domains (an external integration/completion source
               ## participating in parking and wakeup - not a replacement
               ## for Tokio-equivalent socket/filesystem I/O).

  ExecutionDomain* = object
    case kind*: ExecutionDomainKind
    of edGlobal: discard
    of edWorld: worldId*: WorldDomainId
    of edRegion: regionId*: RegionDomainId
    of edEntity: entityId*: EntityDomainId
    of edExternal: externalId*: ExternalDomainId

proc globalDomain*(): ExecutionDomain {.inline.} = ExecutionDomain(kind: edGlobal)
proc worldDomain*(id: WorldDomainId): ExecutionDomain {.inline.} = ExecutionDomain(kind: edWorld, worldId: id)
proc regionDomain*(id: RegionDomainId): ExecutionDomain {.inline.} = ExecutionDomain(kind: edRegion, regionId: id)
proc entityDomain*(id: EntityDomainId): ExecutionDomain {.inline.} = ExecutionDomain(kind: edEntity, entityId: id)
proc externalDomain*(id: ExternalDomainId): ExecutionDomain {.inline.} = ExecutionDomain(kind: edExternal, externalId: id)
