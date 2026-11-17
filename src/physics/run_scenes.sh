#!/bin/sh
# Builds and runs the deterministic physics scene suite (src/physics/scenetest.aowl) against its golden numbers.
#
#   sh src/physics/run_scenes.sh            build + run, exit code 0 = ALL PASS
#   TOOLCHAIN=<dir with aowlmony.exe>       override the compiler location
#
# Recipe: own nimcache C:/m/scene, exe C:/m/scene.exe (deleted before the build so a failed build cannot run a stale exe),
# no build.lock (small build, ~30 s), msys64 gcc first on PATH. Never touches a running server or game.
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../toolchain/aowlmony/root/bin}"
EXE=C:/m/scene.exe
export PATH="/c/msys64/ucrt64/bin:$PATH"
rm -f "$EXE"
cd "$HERE" || exit 2
"$TOOLCHAIN/aowlmony.exe" c --cc:gcc --nimcache:C:/m/scene -o:"$EXE" -p:src src/physics/scenetest.aowl || { echo "BUILD FAILED"; exit 2; }
[ -f "$EXE" ] || { echo "BUILD FAILED: no exe"; exit 2; }
"$EXE"
