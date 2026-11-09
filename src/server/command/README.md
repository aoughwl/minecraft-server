# src/server/command

The slash commands, one file per upstream `pumpkin/src/command/commands/*.rs`. The library they use is in
`src/command`; `src/command/lib.aowl` says which module holds which upstream file.

Each command is on the system upstream has it on: `register(dispatcher, registry)` for a brigadier command,
`initCommandTree()` for one on the older tree that the dispatcher falls back to. `default_dispatcher.aowl` is
`commands/mod.rs`, and registers what exists so far.

## Hooks

Commands never touch `Server`, `World` or `Player`. They call the `{.closure.}` fields of `CommandServer`,
`CommandWorld`, `CommandPlayer` and `CommandEntity` in `src/command/cmdsource.aowl`. The code owning the real types
fills those in. A nil field is treated as the empty answer, so a test sets only the hooks it looks at.

## Testing

Tests build a dispatcher, set hooks with closures that record what happened, and run real input through
`executeInput` or `dispatch`. `cmdtestutil.aowl` holds the shared setup.

Keep test bodies inside procs. A closure capturing a `var` of a module-level `block` gets its own zeroed copy in this
compiler, so it reads the wrong value and its writes are lost; the failures look like command bugs.

`reload.aowl` and `returncmd.aowl` have no file in the pinned upstream tree.

## Not ported

`python tools/port_status.py --missing pumpkin | grep commands/` is the list.
