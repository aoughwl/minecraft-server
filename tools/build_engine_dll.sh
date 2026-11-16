#!/bin/sh
# Builds aoe_engine.dll, the aoughwl engine as a DLL the server's plugin host (src/plugin/engine) loads at run time.
#
#   sh tools/build_engine_dll.sh [engine checkout] [outdir]
#
# The engine checkout (default ../aoughwl-engine) must have its static library built first:
#   sh <engine>/tools/build_embed_lib.sh <engine>/build/embed        (about two minutes)
# Output: <outdir>/aoe_engine.dll (default <engine>/build/dll). Put that folder on PATH, or copy the DLL next to the
# server executable. The engine is a separate DLL on purpose: linked into the server executable it would share symbols with
# the server's own runtime.
set -e
ENGINE="${1:-$(cd "$(dirname "$0")/../../aoughwl-engine" && pwd)}"
OUT="${2:-$ENGINE/build/dll}"
export PATH="/c/msys64/ucrt64/bin:$PATH"
LIB="$ENGINE/build/embed/libaoughwl_embed.a"
[ -f "$LIB" ] || { echo "missing $LIB: build the engine's embed library first (tools/build_embed_lib.sh)"; exit 2; }
mkdir -p "$OUT"
gcc -O1 -shared -o "$OUT/aoe_engine.dll" -Wl,--whole-archive "$LIB" -Wl,--no-whole-archive -Wl,--export-all-symbols \
  $(cat "$ENGINE/build/embed/link.flags")
echo "built $OUT/aoe_engine.dll"
