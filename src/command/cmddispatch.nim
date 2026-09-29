## Command-tree dispatch: walks a `StringReader` against a `Tree`
## (cmdtree.nim) and, on success, runs the matched node's command.
## Port of upstream/command/src/node/dispatcher.rs (~1277 lines).
##
## In its own module mostly for size/organization, not strictly required:
## while isolating a Nimony compiler crash that surfaced while writing
## this file (internal AssertionDefect, `derefs.nim`
## `checkForDangerousLocations`, `fnType.isParamsTag`), splitting the
## dispatch procs out of cmdtree.nim was one of several changes tried
## together and the crash appeared gone afterward - but the real,
## minimally-reproduced cause (filed as feedback) turned out to be
## `cmdtree.nim`'s `meetsRequirements` iterating a `seq[proc(...)
## {.closure.}]` field with `for req in ...: req(source)`, which crashes
## the compiler regardless of which module it's in; rewriting it as an
## indexed `while` loop (see `cmdtree.nim`) was the actual fix. The split
## is harmless and kept for file-size hygiene, but isn't load-bearing.
##
## Dispatch algorithm: upstream's Brigadier-derived `parse`/`execute` does
## real backtracking - if a child matches syntactically but a *later*
## sibling further down the string fails to parse, try the next matching
## child at this level before giving up (this is what lets literal and
## argument children coexist at one branch point, e.g. `/data get
## <literal:block>` vs `/data get <argument:entity>`). This port
## reproduces that: `parseNode` tries every child in order, on a child's
## failure resets the reader to before that child was tried and moves on,
## and only fails the whole branch if every child fails.

import string_reader, cmderrors, argtype, cmdsource, cmdtree

proc findArgSeq*(args: seq[ParsedArg], name: string): (bool, ArgValue) =
  for a in args:
    if a.name == name:
      return (true, a.value)
  (false, ArgValue(kind: avkString, stringVal: ""))

proc findArg*(d: DispatchResult, name: string): (bool, ArgValue) =
  findArgSeq(d.args, name)

proc parseNode(t: Tree, nodeIdx: int, r: var StringReader, source: CommandSource,
               argsSoFar: seq[ParsedArg]): CmdResult[DispatchResult] =
  let node = t.nodes[nodeIdx]
  var target = nodeIdx
  if node.redirect >= 0:
    target = node.redirect

  # A node with children and no command of its own must consume a
  # separator space before trying to match a child (matches upstream's
  # `StringReader::skip` between path segments); the root has no leading
  # separator to skip.
  if nodeIdx != RootIndex:
    let (peekHas, peekChar) = peek(r)
    if peekHas and peekChar == ' ':
      skip(r)
    elif t.nodes[target].children.len > 0 and canReadByte(r):
      # A non-space character where a separator was expected: this
      # branch cannot continue (e.g. "gamemodesurvival" instead of
      # "gamemode survival").
      return cmdErr[DispatchResult](cekExpectedSymbol, "Expected whitespace to end one argument, but found trailing data")

  if not canReadByte(r):
    # End of input at this node: if it's executable, we're done;
    # otherwise this branch fails (a literal/argument requires more).
    if t.nodes[target].command != nil and meetsRequirements(t.nodes[target], source):
      return cmdOk[DispatchResult](DispatchResult(args: argsSoFar, node: target))
    return cmdErr[DispatchResult](cekExpectedSymbol, "Incomplete command")

  for childIdx in t.nodes[target].children:
    let child = t.nodes[childIdx]
    if not meetsRequirements(child, source):
      continue
    let startCursor = r.cursor()
    case child.kind
    of nkLiteral, nkCommand:
      let word = readUnquotedString(r)
      if word.len == 0 or toLowerAscii(word) != child.literalLowercase:
        r.setCursor(startCursor)
        continue
      let sub = parseNode(t, childIdx, r, source, argsSoFar)
      if sub.isOk:
        return sub
      r.setCursor(startCursor)
    of nkArgument:
      let pr = parse(child.argType, r)
      if not pr.isOk:
        r.setCursor(startCursor)
        continue
      var nextArgs = argsSoFar
      nextArgs.add(ParsedArg(name: child.argName, value: pr.value))
      let sub = parseNode(t, childIdx, r, source, nextArgs)
      if sub.isOk:
        return sub
      r.setCursor(startCursor)
    of nkRoot:
      discard # a root never appears as a child

  # No child matched. If this node itself is executable and there's
  # nothing left unconsumed that a child needed, upstream would already
  # have returned above (canReadByte was true, so there IS trailing
  # input) - so this is a genuine failure.
  cmdErr[DispatchResult](cekExpectedSymbol, "Incorrect argument for command")

proc dispatch*(t: Tree, input: string, source: CommandSource): CmdResult[DispatchResult] =
  ## Parses `input` against the tree starting at the root and, on success,
  ## runs the matched node's `command` (upstream's `parse` + `execute`
  ## combined, since this port has no separate "parse now, execute later"
  ## consumer). Returns the executor's own `CmdResult[int32]` result value
  ## wrapped back into a `DispatchResult` isn't quite right for a direct
  ## return type match, so this returns the parse result; call
  ## `executeCommand` for the run-it convenience wrapper below.
  var r = newStringReader(input)
  parseNode(t, RootIndex, r, source, @[])

proc executeCommand*(t: Tree, input: string, source: CommandSource): CmdResult[int32] =
  let pr = dispatch(t, input, source)
  if not pr.isOk:
    return cmdErr[int32](pr.error.kind, pr.error.message)
  let node = t.nodes[pr.value.node]
  if node.command == nil:
    return cmdErr[int32](cekExpectedSymbol, "Node has no command to execute")
  let execResult = node.command(source, pr.value.args)
  var rv: ReturnValue
  if execResult.isOk:
    rv = ReturnValue(kind: rvkSuccess, successValue: execResult.value)
  else:
    rv = ReturnValue(kind: rvkFailure)
  callResult(source, rv)
  execResult
