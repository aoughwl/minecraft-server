## A minimal in-memory registry of connected players.
## Stands in for upstream's `Server.players`/`Server.get_all_players()`
## (a `DashMap<uuid::Uuid, Arc<Player>>` under a real tokio server) -
## NOT the full async multi-client server (that's still correctly
## deferred pending a concurrency-model decision, same as everywhere
## else in this port). This is the "minimal but real" data-model half,
## following `src/server/world/worldstub.nim`'s precedent: a plain
## `seq[Player]` with lookup-by-uuid/lookup-by-name/broadcast, enough
## for `src/server/command/`'s remaining ~20 files that specifically
## need "a player/world registry" per that directory's README, without
## inventing fake networking.

import entity/entity

type
  PlayerRegistry* = ref object
    players*: seq[Player]

proc newPlayerRegistry*(): PlayerRegistry =
  PlayerRegistry(players: @[])

proc addPlayer*(r: PlayerRegistry, p: Player) =
  r.players.add(p)

proc removePlayerByUuid*(r: PlayerRegistry, uuid: string) =
  var kept: seq[Player] = @[]
  for p in r.players:
    if p.livingEntity.entity.entityUuid != uuid:
      kept.add(p)
  r.players = kept

proc findByUuid*(r: PlayerRegistry, uuid: string): nil Player =
  ## `nil` if not found - matching `cmdsource.nim`'s `player*: nil Player`
  ## field shape (Nimony `ref object`s are non-nilable by default; a
  ## proc returning "or None" needs the same explicit `nil T` upstream's
  ## `Option<&T>` maps to elsewhere in this port).
  for p in r.players:
    if p.livingEntity.entity.entityUuid == uuid:
      return p
  nil

proc findByName*(r: PlayerRegistry, name: string): nil Player =
  for p in r.players:
    if p.gameProfileName == name:
      return p
  nil

proc allPlayers*(r: PlayerRegistry): seq[Player] =
  r.players

proc broadcast*(r: PlayerRegistry, sendFn: proc(p: Player, message: string) {.closure.}, message: string) =
  ## `sendFn` is the caller's actual network-send hook (nonexistent in
  ## this port yet); kept as a parameter rather than a field on `Player`
  ## itself so this module stays free of any transport assumption.
  for p in r.players:
    sendFn(p, message)
