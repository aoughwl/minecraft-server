#!/bin/sh
# Builds an aowlmony plugin so the server can load it.
#
#   sh tools/build_plugin.sh <plugin folder>        e.g.  sh tools/build_plugin.sh plugins/hello-world
#
# The folder holds main.aowl (and any other modules it imports). main.aowl imports pluginsdk (plugin_sdk/pluginsdk.aowl), defines
# handlers and registers them at its top level. The engine finds a program's entry procedures in its main module, so the build
# compiles a COPY of the folder with three lines added to the end of main.aowl (start, event and stop, which hand over to the SDK);
# your file is not touched and its line numbers do not move.
#
# The build is `aowlmony check`, which writes the typed artifact of every module; they are copied to <folder>/.plugin/live/ and the
# file <folder>/.plugin/main.txt names the main module's. The server loads that, and reloads the plugin when main.txt changes (hot
# reload), so build while the server runs to see the new version.
#
# AOWLMONY      the compiler (default: ../toolchain/aowlmony/root/bin/aowlmony.exe next to this repository)
set -e
DIR="$1"
[ -n "$DIR" ] && [ -f "$DIR/main.aowl" ] || { echo "usage: build_plugin.sh <plugin folder holding main.aowl>"; exit 2; }
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
DIR="$(cd "$DIR" && pwd -W 2>/dev/null || pwd)"
AOWLMONY="${AOWLMONY:-$HERE/../toolchain/aowlmony/root/bin/aowlmony.exe}"
export PATH="/c/msys64/ucrt64/bin:$PATH"
OUT="$DIR/.plugin"
NC="$OUT/nc"
SRC="$OUT/src"
rm -rf "$NC" "$SRC"
mkdir -p "$NC" "$SRC" "$OUT/live"
# the plugin's own files (not the dot folders), with the entries added to main.aowl
for f in "$DIR"/*; do
  cp -r "$f" "$SRC/"
done
cat >> "$SRC/main.aowl" <<'GLUE'

# ---- added by tools/build_plugin.sh: the entry procedures the engine calls
proc start*() = startPlugin()
proc event*() = dispatchEvent()
proc stop*() = stopPlugin()
GLUE
"$AOWLMONY" check -f --nimcache:"$NC" -p:"$HERE/plugin_sdk" -p:"$SRC" "$SRC/main.aowl"
MAIN="$(ls "$NC"/*.build.nif 2>/dev/null | head -1)"
[ -n "$MAIN" ] || { echo "build failed: no build marker in $NC"; exit 1; }
STEM="$(basename "$MAIN" .build.nif)"
[ -f "$NC/$STEM.s.nif" ] || { echo "build failed: no typed artifact for the main module ($STEM)"; exit 1; }
rm -f "$OUT/live"/*.nif
cp "$NC"/*.s.nif "$NC"/*.s.idx.nif "$NC"/*.s.deps.nif "$OUT/live/"
echo "$STEM.s.nif" > "$OUT/main.txt"
rm -rf "$NC" "$SRC"
echo "built $DIR (main module $STEM.s.nif, $(ls "$OUT/live"/*.s.nif | wc -l) modules)"
