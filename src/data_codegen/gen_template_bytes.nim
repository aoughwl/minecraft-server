## Generates src/generated/template_bytes.nim: a lookup table from
## resource id (and, for the default "minecraft" namespace, the bare id
## too) to the real on-disk path of the structure `.nbt` template it
## names.
## Port of tools/pumpkin-codegen/src/template_bytes.rs.
##
## Upstream embeds every template's raw bytes at Rust compile time via
## `include_bytes!`, so the shipped binary needs no asset files on disk.
## Embedding ~1500 binary `.nbt` files as Nimony byte-literal seqs would
## be a huge amount of generated source for comparatively little value
## right now (this port has no consumer of structure data yet), and risks
## the same "large const seq is slow/awkward to typecheck" friction
## `sound.nim`'s 1991-entry table already showed at a smaller scale. This
## generator instead emits a path lookup table; a future consumer reads
## the `.nbt` file at runtime via the recorded path. Re-visit
## byte-embedding only if a build that must run without the `assets/`
## tree alongside it is actually needed.
##
## Previously deferred as "needing unbounded-depth multi-pack recursion" -
## on closer reading that's just bounded recursive directory walking, the
## same shape several other generators (registry.rs, painting_variant.rs)
## already handle; the earlier assessment under-triaged it, same as
## mob_variant.rs/villager.rs turned out to be tractable on a second look.
##
## Run with `nimony c -r src/data_codegen/gen_template_bytes.nim` from the
## repo root.

import std/[syncio, paths, dirs, algorithm, tables, strutils]
import codegenutil

const VanillaPackRoot = "../upstream-ref/assets/datapack"
const ContainerDir = "../upstream-ref/assets/tests/datapacks"
const DefaultNamespace = "minecraft"

type
  TemplateEntry = object
    resourceId: string
    bareId: string
    isDefault: bool
    relPath: string

proc toForwardSlashes(s: string): string =
  ## Windows path separators break a Nimony string literal unless escaped;
  ## forward slashes work fine and are what every other path constant in
  ## this codegen suite already uses.
  result = newString(s.len)
  for i, c in s:
    result[i] = (if c == '\\': '/' else: c)

proc baseName(p: Path): string =
  var base = $p
  let slashIdx = max(lastIndexOf(base, '/'), lastIndexOf(base, '\\'))
  if slashIdx >= 0:
    base = base[(slashIdx + 1) .. ^1]
  base

proc listDirSorted(dir: Path): seq[(string, Path, bool)] =
  ## (name, fullPath, isDir), sorted by name - mirrors every upstream
  ## generator's `fs::read_dir(...).sort_by_key(file_name)` dance.
  var entries: seq[(string, Path, bool)] = @[]
  try:
    for kind, entryPath in walkDir(dir):
      entries.add((baseName(entryPath), entryPath, kind == pcDir))
  except ErrorCode:
    discard  # missing/unreadable dir - upstream's container_dir.is_dir() guard
             # does the same thing, just via a check instead of a caught error.
  entries.sort(proc(a, b: (string, Path, bool)): int = cmp(a[0], b[0]))
  entries

proc scanStructureDir(dir: Path, namespace: string): seq[TemplateEntry] =
  ## Iterative (not recursive) directory walk, returning its findings by
  ## value rather than writing into a `var Table[...]` out-parameter.
  ##
  ## A `var Table[...]` out-param was tried first (both a recursive and
  ## this same iterative shape) and hit a real, reproducible Nimony bug:
  ## `results.len` grows correctly on every write *inside* the callee (an
  ## instrumented run showed it climbing 1, 2, 3, ... past 30 as files
  ## were found), but the caller sees only the FIRST write once the proc
  ## returns - every later mutation is silently lost across the call
  ## boundary, even though nothing at the type level suggests `var Table`
  ## shouldn't alias the caller's variable the way `var seq`/`var string`
  ## do elsewhere in this codebase. Documented in NIMONY-COMPILER-BUGS.md.
  ## Returning a plain `seq[TemplateEntry]` and letting the caller build
  ## its own table sidesteps it entirely.
  result = @[]
  var stack: seq[(Path, string)] = @[(dir, "")]
  while stack.len > 0:
    let (curDir, prefix) = stack.pop()
    for (name, entryPath, isDir) in listDirSorted(curDir):
      if isDir:
        let newPrefix = if prefix.len == 0: name else: prefix & "/" & name
        stack.add((entryPath, newPrefix))
        continue
      var lower = name
      for i in 0 ..< lower.len:
        if lower[i] >= 'A' and lower[i] <= 'Z':
          lower[i] = char(ord(lower[i]) + 32)
      if not lower.endsWith(".nbt"):
        continue
      let stem = name[0 ..< (name.len - 4)]
      let templateName = if prefix.len == 0: stem else: prefix & "/" & stem
      let resourceId = namespace & ":" & templateName
      result.add(TemplateEntry(
        resourceId: resourceId,
        bareId: templateName,
        isDefault: namespace == DefaultNamespace,
        relPath: toForwardSlashes($entryPath)))

proc main() =
  var packs: seq[(string, Path)] = @[("vanilla", path(VanillaPackRoot))]
  var embeddedPackNames: seq[string] = @["vanilla"]
  for (id, fullPath, isDir) in listDirSorted(path(ContainerDir)):
    if isDir:
      packs.add((id, fullPath))
      embeddedPackNames.add(id)

  var results = initTable[string, TemplateEntry]()
  for (_, packPath) in packs:
    let dataDir = packPath / path("data")
    for (namespace, nsDir, isDir) in listDirSorted(dataDir):
      if not isDir: continue
      let structDir = nsDir / path("structure")
      for e in scanStructureDir(structDir, namespace):
        results[e.resourceId] = e

  var keys: seq[string] = @[]
  for k in results.keys:
    keys.add(k)
  keys.sort(proc(a, b: string): int = cmp(a, b))

  var output = "## Generated by src/data_codegen/gen_template_bytes.nim - do not edit by hand.\n"
  output.add("## Maps a structure template's resource id (and, for the default\n")
  output.add("## \"minecraft\" namespace, its bare id too) to the real on-disk path of\n")
  output.add("## its `.nbt` file. See this generator's doc comment for why paths are\n")
  output.add("## recorded rather than the bytes being embedded.\n\n")
  output.add("type\n")
  output.add("  TemplatePathEntry* = object\n")
  output.add("    resourceId*: string\n")
  output.add("    bareId*: string\n")
  output.add("    isDefault*: bool\n")
  output.add("    relPath*: string\n\n")
  output.add("let templatePaths*: seq[TemplatePathEntry] = @[\n")
  for k in keys:
    var e: TemplateEntry
    try:
      e = results[k]
    except ErrorCode:
      continue  # unreachable: k came from results.keys itself
    output.add("  TemplatePathEntry(resourceId: \"" & e.resourceId &
      "\", bareId: \"" & e.bareId & "\", isDefault: " & $e.isDefault &
      ", relPath: \"" & e.relPath & "\"),\n")
  output.add("]\n\n")
  output.add("proc getTemplatePath*(id: string): (bool, string) =\n")
  output.add("  for e in templatePaths:\n")
  output.add("    if e.resourceId == id or (e.isDefault and e.bareId == id):\n")
  output.add("      return (true, e.relPath)\n")
  output.add("  (false, \"\")\n\n")
  output.add("let allEmbeddedDatapackNames*: seq[string] = @[\n")
  for p in embeddedPackNames:
    output.add("  \"" & p & "\",\n")
  output.add("]\n")

  try:
    writeFile("src/generated/template_bytes.nim", output)
    echo "wrote src/generated/template_bytes.nim: ", keys.len,
      " templates across ", embeddedPackNames.len, " packs"
  except ErrorCode as e:
    echo "write failed: " & $e

main()
