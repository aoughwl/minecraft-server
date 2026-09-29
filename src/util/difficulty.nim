## Port of upstream/util/src/difficulty.rs

type
  Difficulty* = enum
    Peaceful = 0
    Easy = 1
    Normal = 2
    Hard = 3

proc name*(d: Difficulty): string =
  case d
  of Peaceful: "peaceful"
  of Easy: "easy"
  of Normal: "normal"
  of Hard: "hard"

proc translationKey*(d: Difficulty): string =
  case d
  of Peaceful: "options.difficulty.peaceful"
  of Easy: "options.difficulty.easy"
  of Normal: "options.difficulty.normal"
  of Hard: "options.difficulty.hard"

proc parseDifficulty*(s: string): (bool, Difficulty) =
  ## Port of `impl FromStr for Difficulty`. Returns `(false, _)` for
  ## `ParseDifficultyError` the way `resource.nim`'s `cast_` does for `None`.
  case s
  of "peaceful": (true, Peaceful)
  of "easy": (true, Easy)
  of "normal": (true, Normal)
  of "hard": (true, Hard)
  else: (false, Peaceful)
