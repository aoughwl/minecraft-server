## The `/seed` command.
## Port of upstream/pumpkin/src/command/commands/seed.rs
##
## Not ported: permission-registry registration, and the click-to-copy/
## hover-text/colored feedback (`create_copy_on_click_text` builds a
## `TextComponent` with a `ClickEvent::CopyToClipboard` and a hover
## tooltip - needs the unported `text` module's click/hover event types;
## a plain string with the seed value stands in). `context.world().level.seed`
## has no equivalent here yet - see `CommandSource.getSeedProc`'s doc
## comment in cmdsource.nim.

import ../../command/cmdtree, ../../command/cmdsource, ../../command/cmderrors

const
  SeedDescription* = "Displays the world seed."
  SeedPermission* = "minecraft:command.seed"

proc seedExecute(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] =
  let seed = getSeed(source)
  sendMessage(source, "Seed: [" & $seed & "]")
  cmdOk[int32](int32(seed)) ## upstream: `seed as i32`, a truncating cast

proc registerSeed*(t: var Tree) =
  let cmdNode = addLiteral(t, RootIndex, "seed", executable = true)
  setCommand(t, cmdNode, seedExecute)
