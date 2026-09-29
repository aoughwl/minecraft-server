## The brigadier-style command tree: nodes (root/literal/command/argument)
## and the builders that assemble a tree. Dispatch (walking a
## `StringReader` against the tree) lives in cmddispatch.nim - split out
## as a Nimony-compiler-crash workaround, see that file's doc comment.
## Port of upstream/command/src/node/{mod,tree}.rs (~1.5k lines; the
## 1277-line dispatcher.rs is cmddispatch.nim).
##
## Design decisions (this is the crate's central design pass, flagged as
## deferred in `lib.nim` until the `ArgumentType`/`CommandSource` pair was
## settled - see argtype.nim/cmdsource.nim for that half):
##
## - Upstream's `Tree` is a slab/arena (`Vec` of nodes addressed by
##   `NodeId`/`GlobalNodeId` index, not `Rc`/`Arc` parent-child pointers) -
##   this port keeps that shape exactly (`nodes: seq[CommandNode]`,
##   `children: seq[int]` per node), which conveniently also sidesteps the
##   known Nimony bug where a self-recursive `ref T` field inside a `case`
##   object of type `T` fails C-codegen despite passing `nimony check`
##   (nodes never hold a `ref CommandNode` to each other, only indices).
## - `Command<S>` (`Arc<dyn CommandExecutor<S>>`) becomes a `{.closure.}`
##   proc field, same vtable pattern as `ArgumentType`.
## - `Requirements<S>`/`Requirement<S>` (a `Vec` of boxed predicates)
##   becomes a `seq` of `{.closure.}` predicate procs - directly portable,
##   no trait object needed since Nimony closures already erase their
##   environment.
## - `RedirectModifier`/`Redirection`/forking (multi-source redirects, used
##   by things like `/execute as @a run ...`) are NOT ported in this pass -
##   real forking needs a working multi-`CommandSource` execution model
##   this port doesn't have a design for yet. A node can still `redirect`
##   to another node by index for the simple single-target case; the
##   `RedirectModifier::Custom`/fork-to-many path is a documented gap.
## - Ambiguity detection (`find_ambiguities`/`AmbiguityConsumer`, used to
##   warn plugin/command authors about overlapping argument-node names at
##   registration time, not at dispatch time) is skipped - it's a
##   diagnostic nicety, not required for parse/execute correctness.
## - Suggestions (tab-complete) are entirely out of scope, matching
##   argtype.nim's scope note.

import string_reader, cmderrors, argtype, cmdsource

type
  NodeKind* = enum
    nkRoot
    nkLiteral   ## a non-executable literal (doesn't `Command`) path segment
    nkCommand   ## a literal path segment that CAN be executed here
    nkArgument

  ParsedArg* = object
    name*: string
    value*: ArgValue

  CommandNode* = object
    kind*: NodeKind
    literal*: string          ## nkLiteral/nkCommand: the exact text to match
    literalLowercase*: string ## for case-insensitive literal matching
    argName*: string          ## nkArgument: the name bound in CommandContext
    argType*: ArgumentType    ## nkArgument only
    children*: seq[int]       ## indices into the owning Tree's `nodes`
    requirements*: seq[proc(source: CommandSource): bool {.closure.}]
    command*: proc(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.} ## nil unless this node is runnable
    redirect*: int             ## -1 = none; else index to redirect to (simple case only)

  Tree* = object
    nodes*: seq[CommandNode]  ## nodes[0] is always the root

proc newTree*(): Tree =
  result = Tree(nodes: @[])
  result.nodes.add(CommandNode(kind: nkRoot, children: @[], requirements: @[], redirect: -1))

const RootIndex* = 0

proc meetsRequirements*(node: CommandNode, source: CommandSource): bool =
  ## NOTE: written as an indexed `while` rather than `for req in
  ## node.requirements`, which crashes the Nimony compiler (internal
  ## AssertionDefect, `derefs.nim`'s `checkForDangerousLocations`) when
  ## iterating a `seq[proc(...) {.closure.}]` field and calling an
  ## element - filed as feedback; this is the confirmed workaround.
  var i = 0
  while i < node.requirements.len:
    let req = node.requirements[i]
    if req != nil and not req(source):
      return false
    inc i
  true

proc addChild(t: var Tree, parent: int, node: CommandNode): int =
  let idx = t.nodes.len
  t.nodes.add(node)
  t.nodes[parent].children.add(idx)
  idx

proc addLiteral*(t: var Tree, parent: int, literal: string, executable = false): int =
  ## Port of `literal(name)` node-builder use: `executable` marks this as
  ## upstream's `NodeMetadata::Command` (a literal that's also a valid
  ## command by itself, e.g. `/spawn` with no further arguments) vs.
  ## `::Literal` (a path segment that must be followed by more nodes,
  ## e.g. the `gamemode` in `/gamemode survival`).
  addChild(t, parent, CommandNode(
    kind: (if executable: nkCommand else: nkLiteral),
    literal: literal,
    literalLowercase: toLowerAscii(literal),
    children: @[],
    requirements: @[],
    redirect: -1,
  ))

proc addArgument*(t: var Tree, parent: int, name: string, argType: ArgumentType): int =
  addChild(t, parent, CommandNode(
    kind: nkArgument,
    argName: name,
    argType: argType,
    children: @[],
    requirements: @[],
    redirect: -1,
  ))

proc setCommand*(t: var Tree, node: int, executor: proc(source: CommandSource, args: seq[ParsedArg]): CmdResult[int32] {.closure.}) =
  t.nodes[node].command = executor
  if t.nodes[node].kind == nkLiteral:
    t.nodes[node].kind = nkCommand

proc addRequirement*(t: var Tree, node: int, req: proc(source: CommandSource): bool {.closure.}) =
  t.nodes[node].requirements.add(req)

proc setRedirect*(t: var Tree, node: int, target: int) =
  t.nodes[node].redirect = target

proc toLowerAscii*(s: string): string =
  result = newString(s.len)
  for i, c in s:
    if c >= 'A' and c <= 'Z':
      result[i] = char(ord(c) + 32)
    else:
      result[i] = c

type
  DispatchResult* = object
    ## What a successful walk to an executable node collected along the
    ## way - upstream's `CommandContext` (minus the parts needing
    ## `RedirectModifier`/nested-context chaining, out of scope here).
    args*: seq[ParsedArg]
    node*: int
