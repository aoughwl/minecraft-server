#!/usr/bin/env python3
"""Runs every src/data_codegen/gen_*.aowl generator from the repo root, in parallel, and reports failures.

    python src/data_codegen/regen_all.py [--compiler PATH] [--cache DIR] [--jobs N] [name...]

Without names it runs all. A name is a generator without its gen_ prefix and .aowl suffix.
The compiler defaults to $AOWLMONY_BIN, then `aowlmony` on PATH. The cache directory defaults to
$AOWLMONY_CACHE, then build/codegen under the repo root; each generator gets its own subdirectory, since a
shared cache fails falsely. gcc must be on PATH, or give its directory in $AOWLMONY_GCC_DIR.
"""
import argparse
import concurrent.futures
import glob
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Not run without being named: gen_wit documents why nothing is generated, and these read inputs the pinned tree
# does not have (see README.md), so their outputs stay as they were checked in. Running one with no input would
# overwrite its output with an empty table. Generators still reading assets/datapack are skipped the same way.
SKIP = {
    "wit", "decorated_pot_pattern", "dye_color", "map_color", "map_decoration", "context_provider",
    "template_bytes", "test_instance",
}


def reads_missing_input(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return "assets/datapack" in f.read()


def run_one(name, args):
    source = "src/data_codegen/gen_%s.aowl" % name
    cache = os.path.join(args.cache, "c_" + name)
    exe = os.path.join(args.cache, "gen_" + name + ".exe" if os.name == "nt" else "gen_" + name)
    cmd = [args.compiler, "c", "-r", "--cc:gcc", "--nimcache:" + cache, "-o:" + exe,
           "-p:src", "-p:src/data_codegen", "-p:../jwt/src", "-p:../compress/src", "-p:../compress", source]
    env = dict(os.environ)
    gcc = os.environ.get("AOWLMONY_GCC_DIR")
    if gcc:
        env["PATH"] = gcc + os.pathsep + env.get("PATH", "")
    proc = subprocess.run(cmd, cwd=REPO, env=env, capture_output=True, text=True, errors="replace")
    return name, proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", default=os.environ.get("AOWLMONY_BIN", "aowlmony"))
    parser.add_argument("--cache", default=os.environ.get("AOWLMONY_CACHE", os.path.join(REPO, "build", "codegen")))
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    args.cache = os.path.abspath(args.cache)
    os.makedirs(args.cache, exist_ok=True)

    skipped = []
    if args.names:
        names = args.names
    else:
        names = []
        for path in sorted(glob.glob(os.path.join(REPO, "src", "data_codegen", "gen_*.aowl"))):
            if path.endswith("test.aowl"):
                continue
            name = os.path.basename(path)[len("gen_"):-len(".aowl")]
            if name in SKIP or reads_missing_input(path):
                skipped.append(name)
            else:
                names.append(name)

    failed = []
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(run_one, name, args) for name in names]
        for future in concurrent.futures.as_completed(futures):
            name, code, output = future.result()
            print("%-30s %s" % (name, "ok" if code == 0 else "FAILED (exit %d)" % code), flush=True)
            if code != 0:
                failed.append(name)
                print(output[-3000:], flush=True)

    print("%d ran, %d failed, %d skipped" % (len(names), len(failed), len(skipped)))
    if skipped:
        print("skipped, no input in the pinned tree: " + ", ".join(skipped))
    if failed:
        print("failed: " + ", ".join(sorted(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
