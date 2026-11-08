## Port of upstream/util/src/gamemode.rs

type
  GameMode* = enum
    Survival = 0
    Creative = 1
    Adventure = 2
    Spectator = 3

const Values* = [Survival, Creative, Adventure, Spectator]

proc toStr*(g: GameMode): string =
  case g
  of Survival: "Survival"
  of Creative: "Creative"
  of Adventure: "Adventure"
  of Spectator: "Spectator"

proc name*(g: GameMode): string =
  case g
  of Survival: "survival"
  of Creative: "creative"
  of Adventure: "adventure"
  of Spectator: "spectator"

proc gameModeFromI32*(value: int32): (bool, GameMode) =
  case value
  of 0: (true, Survival)
  of 1: (true, Creative)
  of 2: (true, Adventure)
  of 3: (true, Spectator)
  else: (false, Survival)

proc gameModeFromI8*(value: int8): (bool, GameMode) =
  gameModeFromI32(int32(value))

proc gameModeFromU8*(value: uint8): (bool, GameMode) =
  gameModeFromI32(int32(value))

proc parseGameMode*(s: string): (bool, GameMode) =
  case s
  of "survival": (true, Survival)
  of "creative": (true, Creative)
  of "adventure": (true, Adventure)
  of "spectator": (true, Spectator)
  else: (false, Survival)
