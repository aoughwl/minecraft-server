#!/usr/bin/env python3
"""Build and run every `*test.aowl` under the given folders of src/, each with its own cache.

    python tools/run_tests.py [-j N] [--list-failed] util nbt codecs

Exit status is the number of failures. A test passes when it builds and exits 0.
"""
import concurrent.futures as cf
import os
import shutil
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
jobs = 4
if '-j' in args:
    i = args.index('-j')
    jobs = int(args[i + 1])
    del args[i:i + 2]
root = os.environ.get('AOWLMONY_ROOT', os.path.join(os.path.dirname(here), 'toolchain', 'aowlmony', 'root'))
aowl = os.path.join(root, 'bin', 'aowlmony.exe')
env = dict(os.environ)
env['PATH'] = r'C:\msys64\ucrt64\bin;' + env.get('PATH', '')
os.chdir(here)

tests = []
for folder in args or ['.']:
    for dirpath, _, names in os.walk(os.path.join('src', folder)):
        tests += [os.path.join(dirpath, n).replace(os.sep, '/') for n in names if n.endswith('test.aowl')]
tests.sort()
work = tempfile.mkdtemp(prefix='s', dir=os.environ.get('SRVTEST_TMP', 'C:/m'))  # a short path keeps hexer's final command line under Windows' 32KB limit


def one(item):
    i, t = item
    cache = os.path.join(work, 'c%d' % i)
    exe = os.path.join(work, 't%d.exe' % i)
    cmd = [aowl, 'c', '--cc:gcc', '--nimcache:' + cache, '-o:' + exe, '-p:src', '-p:' + os.path.dirname(t),
           '-p:../jwt/src', t]
    try:
        for attempt in range(4):
            b = subprocess.run(cmd, capture_output=True, text=True, errors='replace', env=env, timeout=1500)
            # The root's nimcache_static is rewritten by any build on the machine, so the link can miss it.
            if os.path.exists(exe) or 'nimcache_static' not in b.stdout + b.stderr:
                break
        if not os.path.exists(exe):
            lines = [l for l in (b.stdout + b.stderr).splitlines() if 'rror' in l]
            return t, 'BUILD', (lines[0] if lines else (b.stdout + b.stderr)[-200:])[:200]
        r = subprocess.run([exe], capture_output=True, text=True, errors='replace', cwd=here, env=env, timeout=600)
        if r.returncode != 0:
            return t, 'RUN %d' % r.returncode, (r.stdout + r.stderr)[-200:].replace('\n', ' | ')
        return t, 'ok', ''
    except subprocess.TimeoutExpired:
        return t, 'TIMEOUT', ''
    finally:
        shutil.rmtree(cache, ignore_errors=True)


bad = 0
with cf.ThreadPoolExecutor(jobs) as ex:
    for t, verdict, note in ex.map(one, enumerate(tests)):
        if verdict != 'ok':
            bad += 1
            print('%-8s %s\n         %s' % (verdict, t, note))
shutil.rmtree(work, ignore_errors=True)
print('%d tests, %d failed' % (len(tests), bad))
sys.exit(min(bad, 125))
