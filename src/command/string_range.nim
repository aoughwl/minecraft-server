## A byte-index range into a command string.
## Port of upstream/command/src/context/string_range.rs

type
  StringRange* = object
    start*: int
    `end`*: int

proc between*(start, `end`: int): StringRange {.inline.} =
  StringRange(start: start, `end`: `end`)

proc at*(pos: int): StringRange {.inline.} =
  between(pos, pos)

proc encompass*(a, b: StringRange): StringRange {.inline.} =
  between(min(a.start, b.start), max(a.`end`, b.`end`))

proc substringSlice*(r: StringRange, s: string): string {.inline.} =
  ## Port of `substring_slice`. Rust's is a zero-copy `&str` slice;
  ## Nimony's `string` has no borrow-slicing story as cheap as that, so
  ## this copies - fine at command-parsing scale (short strings, once per
  ## argument), unlike the hot-path NBT/protocol code elsewhere in this
  ## port where that tradeoff was called out as worth revisiting.
  s[r.start ..< r.`end`]

proc isEmptyRange*(r: StringRange): bool {.inline.} =
  r.start == r.`end`

proc len*(r: StringRange): int {.inline.} =
  r.`end` - r.start
