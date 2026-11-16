#!/bin/sh
# Runs the plugin manager's test (src/plugin/enginemanagertest.aowl): builds the test plugins, prepares a scratch directory with
# plugins/echo (aowlmony) and plugins/jsone.js (JavaScript), and runs the test there.
#
#   sh tools/test_engine_plugins.sh [path to the built enginemanagertest.exe]
#
# Build the test first:  aowlmony c ... -p:src -p:src/plugin src/plugin/enginemanagertest.aowl  (see the commands in the commit that added it)
# aoe_engine.dll (tools/build_engine_dll.sh) must be on PATH.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
EXE="${1:-C:/m/mgr.exe}"
SCRATCH="${SCRATCH:-$HERE/../mgr_scratch}"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/plugins"
cp -r "$HERE/tests/engine_plugins/echo" "$SCRATCH/plugins/echo"
cp "$HERE/tests/engine_plugins/jsone.js" "$SCRATCH/plugins/jsone.js"
sh "$HERE/tools/build_plugin.sh" "$SCRATCH/plugins/echo"
cd "$SCRATCH"
"$EXE"
